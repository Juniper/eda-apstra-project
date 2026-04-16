#!/bin/bash

# configure_awx.sh - Complete AWX Configuration Script
# This script configures Kubernetes RBAC, clones the repo, prompts for config, and configures AWX

set -e

# Configuration
NAMESPACE="aap"
SERVICE_ACCOUNT="cicd"
REPO_URL="https://github.com/Juniper/eda-apstra-project.git"
REPO_BRANCH="nutanix"
WORK_DIR="/tmp/awx-config"
ROLE_NAME="apstra-ntx-awx-configure"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# EE image tag (same for Apstra 6.0 and 6.1)
EE_IMAGE_TAG="1.0.6"
EE_IMAGE_URL=""   # resolved by resolve_ee_image()

echo "=== Complete AWX Configuration Script ==="
echo "This script will:"
echo "1. Select Apstra version"
echo "2. Configure Kubernetes RBAC"
echo "3. Clone the repository and role"
echo "4. Prompt for configuration values"
echo "5. Configure AWX automatically"
echo

# Function to select Apstra version and derive EE image default
select_apstra_version() {
    echo
    echo "=== Apstra Version Selection ==="
    echo "Select the Apstra version you are running:"
    echo "  1. Apstra 6.0  →  EE image apstra-ee:1.0.6"
    echo "  2. Apstra 6.1  →  EE image apstra-ee:1.0.6"
    echo
    read -p "Enter your choice (1 or 2): " APSTRA_VER_CHOICE

    case $APSTRA_VER_CHOICE in
        1)
            APSTRA_VERSION="6.0"
            EE_IMAGE_TAG="1.0.6"
            ;;
        2)
            APSTRA_VERSION="6.1"
            EE_IMAGE_TAG="1.0.6"
            ;;
        *)
            echo "ERROR: Invalid choice. Please run the script again."
            exit 1
            ;;
    esac

    echo "✓ Apstra version : $APSTRA_VERSION"
    echo "✓ EE image tag   : apstra-ee:${EE_IMAGE_TAG}"
}

# Function to resolve EE image — check containerd, offer to load from local tgz
resolve_ee_image() {
    local desired_tag="apstra-ee:${EE_IMAGE_TAG}"

    echo
    echo "=== Execution Environment Image ==="
    echo "Required local image tag: $desired_tag"
    echo

    # Check if the canonical short tag already exists in containerd k8s.io namespace.
    # The loaded image may have originally been tagged with a registry prefix
    # (e.g. s-artifactory.juniper.net/atom-docker/ee/apstra-ee:1.0.6).
    # We always normalise to the short tag so AWX never needs registry access.
    local existing
    existing=$(sudo ctr -n k8s.io images ls 2>/dev/null | grep "apstra-ee" | awk '{print $1}')

    if echo "$existing" | grep -qx "$desired_tag"; then
        EE_IMAGE_URL="$desired_tag"
        echo "✓ Image '$desired_tag' already present in containerd — using it."
        return 0
    fi

    # Image is present under a different tag (e.g. long registry prefix) — just re-tag it.
    if [[ -n "$existing" ]]; then
        local first_tag
        first_tag=$(echo "$existing" | head -1)
        echo "Found existing apstra-ee image: $first_tag"
        echo "Re-tagging to short local name: $desired_tag"
        sudo ctr -n k8s.io images tag "$first_tag" "$desired_tag"
        EE_IMAGE_URL="$desired_tag"
        echo "✓ EE image ready: $EE_IMAGE_URL"
        return 0
    fi

    # Not loaded at all — ask user for the .tgz file.
    echo "Image not found in containerd."
    echo
    echo "You need the pre-built EE image .tgz file (Docker save format)."
    echo "Download it from: https://support.juniper.net/support/downloads/?p=apstra"
    echo "  → Section: 'Apstra Ansible Execution Environment'"
    echo "  → File:    apstra-ee-x86_64-${EE_IMAGE_TAG}.image.tgz"
    echo
    read -p "Enter full path to the EE image .tgz file: " EE_TGZ_PATH

    if [[ -z "$EE_TGZ_PATH" ]]; then
        echo "ERROR: No path provided. Cannot continue without the EE image."
        exit 1
    fi

    if [[ ! -f "$EE_TGZ_PATH" ]]; then
        echo "ERROR: File not found: $EE_TGZ_PATH"
        exit 1
    fi

    # Docker-save archives are gzip-compressed — ctr import needs a raw tar stream.
    echo "Loading image into containerd (k8s.io namespace)..."
    if file "$EE_TGZ_PATH" | grep -qi "gzip\|compressed"; then
        zcat "$EE_TGZ_PATH" | sudo ctr -n k8s.io images import -
    else
        sudo ctr -n k8s.io images import "$EE_TGZ_PATH"
    fi

    # Detect whatever tag was loaded (may carry a registry prefix such as
    # s-artifactory.juniper.net/atom-docker/ee/apstra-ee:X.Y.Z)
    local loaded_tag
    loaded_tag=$(sudo ctr -n k8s.io images ls 2>/dev/null | grep "apstra-ee" | awk '{print $1}' | head -1)

    if [[ -z "$loaded_tag" ]]; then
        echo "ERROR: Image load appeared to succeed but no apstra-ee tag found in containerd."
        echo "Check with: sudo ctr -n k8s.io images ls | grep apstra-ee"
        exit 1
    fi

    echo "✓ Loaded tag: $loaded_tag"

    # Always create the short local tag — this is what AWX will reference.
    # No registry hostname means no external network call, even if pull policy
    # is not 'missing'.
    if [[ "$loaded_tag" != "$desired_tag" ]]; then
        sudo ctr -n k8s.io images tag "$loaded_tag" "$desired_tag"
        echo "✓ Re-tagged as: $desired_tag  (original registry tag discarded from AWX config)"
    fi

    EE_IMAGE_URL="$desired_tag"
    echo "✓ EE image ready: $EE_IMAGE_URL"
}

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo "ERROR: kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Test kubectl connectivity
    if ! kubectl cluster-info &> /dev/null; then
        echo "ERROR: kubectl cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    echo "✓ kubectl is available and connected to cluster"
}

# Function to get AWX connection details
get_awx_details() {
    echo "Getting AWX connection details from deployed instance..."
    
    # Get AWX service details
    AWX_NODEPORT=$(kubectl get service ansible-awx-service -n $NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
    if [[ -z "$AWX_NODEPORT" ]]; then
        echo "ERROR: Could not find AWX service. Make sure AWX is deployed in namespace '$NAMESPACE'"
        exit 1
    fi
    
    # Get cluster IP (assuming single node or using first node)
    CLUSTER_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    if [[ -z "$CLUSTER_IP" ]]; then
        echo "ERROR: Could not determine cluster IP"
        exit 1
    fi
    
    AWX_HOST="http://${CLUSTER_IP}:${AWX_NODEPORT}"
    AWX_USERNAME="admin"
    
    # Get AWX admin password
    AWX_PASSWORD=$(kubectl get secret ansible-awx-admin-password -n $NAMESPACE -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")
    if [[ -z "$AWX_PASSWORD" ]]; then
        echo "ERROR: Could not retrieve AWX admin password"
        exit 1
    fi
    
    echo "✓ AWX Details Retrieved:"
    echo "  Host: $AWX_HOST"
    echo "  Username: $AWX_USERNAME"
    echo "  Password: [Retrieved from Kubernetes secret]"
}

# Function to create namespace and RBAC
create_kubernetes_rbac() {
    echo "Creating Kubernetes RBAC configuration..."
    
    # Create namespace
    kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    echo "✓ Namespace $NAMESPACE created/updated"
    
    # Create service account
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $SERVICE_ACCOUNT
  namespace: $NAMESPACE
EOF
    echo "✓ Service account $SERVICE_ACCOUNT created/updated"
    
    # Create cluster role binding
    cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: $SERVICE_ACCOUNT-cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: $SERVICE_ACCOUNT
  namespace: $NAMESPACE
EOF
    echo "✓ Cluster role binding created/updated"
    
    # Create service account token secret
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: $SERVICE_ACCOUNT-token
  namespace: $NAMESPACE
  annotations:
    kubernetes.io/service-account.name: $SERVICE_ACCOUNT
type: kubernetes.io/service-account-token
EOF
    echo "✓ Service account token secret created/updated"
}

# Function to prepare role — use local repo if available, otherwise clone from GitHub
clone_and_prepare_repo() {
    echo "Preparing repository and role..."

    # Determine local repo root: this script lives at deploy/nutanix/scripts/configure_awx.sh
    # so the repo root is three levels up.
    local LOCAL_REPO
    LOCAL_REPO="$(cd "$SCRIPT_DIR/../../.." && pwd)"

    if [[ -d "$LOCAL_REPO/build/$ROLE_NAME" ]]; then
        echo "✓ Using local repository at: $LOCAL_REPO"
        rm -rf $WORK_DIR
        mkdir -p $WORK_DIR
        # Symlink so the rest of the script can reference $WORK_DIR/repo as before
        ln -s "$LOCAL_REPO" "$WORK_DIR/repo"
        echo "✓ Role $ROLE_NAME found in local repository"
    else
        echo "Local repository not found — cloning from GitHub..."
        rm -rf $WORK_DIR
        mkdir -p $WORK_DIR
        git clone -b $REPO_BRANCH $REPO_URL $WORK_DIR/repo
        echo "✓ Repository cloned to $WORK_DIR/repo"

        if [[ ! -d "$WORK_DIR/repo/build/$ROLE_NAME" ]]; then
            echo "ERROR: Role $ROLE_NAME not found in repository"
            exit 1
        fi
        echo "✓ Role $ROLE_NAME found in repository"
    fi
}

# Function to extract service account credentials
extract_kubernetes_credentials() {
    echo "Extracting Kubernetes service account credentials..."
    
    # Wait for token to be available
    for i in {1..30}; do
        TOKEN=$(kubectl get secret $SERVICE_ACCOUNT-token -n $NAMESPACE -o jsonpath='{.data.token}' 2>/dev/null || echo "")
        if [[ -n "$TOKEN" ]]; then
            echo "✓ Token is available"
            break
        fi
        echo "Waiting for token... (attempt $i/30)"
        sleep 2
    done
    
    if [[ -z "$TOKEN" ]]; then
        echo "ERROR: Token not available after 60 seconds"
        exit 1
    fi
    
    # Extract and save service account token
    kubectl get secret $SERVICE_ACCOUNT-token -n $NAMESPACE -o jsonpath='{.data.token}' | base64 -d > $WORK_DIR/repo/build/$ROLE_NAME/files/kubernetes-sa.token
    echo "✓ Service account token extracted"
    
    # Extract and save CA certificate
    kubectl get secret $SERVICE_ACCOUNT-token -n $NAMESPACE -o jsonpath='{.data.ca\.crt}' | base64 -d > $WORK_DIR/repo/build/$ROLE_NAME/files/kubernetes-ca.crt
    echo "✓ CA certificate extracted"
}

# Function to prompt user for configuration
prompt_for_configuration() {
    echo
    echo "=== Configuration Setup ==="
    echo "Please provide the following configuration details:"
    echo
    
    # Kubernetes host (derived from cluster)
    KUBERNETES_HOST="https://${CLUSTER_IP}:6443"
    
    # Apstra configuration
    echo "Apstra Configuration:"
    read -p "Apstra API URL (e.g., https://10.84.128.67/api): " APSTRA_API_URL
    read -p "Apstra Username [admin]: " APSTRA_USERNAME
    APSTRA_USERNAME=${APSTRA_USERNAME:-admin}
    read -s -p "Apstra Password: " APSTRA_PASSWORD
    echo

    echo
    echo "✓ Configuration collected"
}

# Function to update role variables
update_role_variables() {
    echo "Updating role variables..."
    
    cat > $WORK_DIR/repo/build/$ROLE_NAME/vars/main.yml <<EOF
---
# vars file for apstra-ntx-awx-configure

## It is best practice to use Ansible Vault to encrypt sensitive data such as passwords.

# Kubernetes Configuration
kubernetes_host: "$KUBERNETES_HOST"

# AWX Configuration
awx_host: "$AWX_HOST"
awx_username: "$AWX_USERNAME"
awx_password: "$AWX_PASSWORD"
execution_environment_image_url: "$EE_IMAGE_URL"

# Apstra Variables
apstra_api_url: "$APSTRA_API_URL"
apstra_username: "$APSTRA_USERNAME"
apstra_password: "$APSTRA_PASSWORD"
EOF
    
    echo "✓ Role variables updated"
}

# Function to run AWX configuration
configure_awx() {
    echo "Configuring AWX..."
    
    # Check if ansible-playbook is available
    if ! command -v ansible-playbook &> /dev/null; then
        echo "ERROR: ansible-playbook is not available. Please install Ansible."
        exit 1
    fi
    
    # Navigate to build directory and run playbook
    cd $WORK_DIR/repo/build
    
    # Run the playbook
    if ansible-playbook deploy-awx-playbook.yml -vv; then
        echo "✓ AWX configuration completed successfully"
    else
        echo "ERROR: AWX configuration failed"
        exit 1
    fi
}

# Function to display final summary
display_final_summary() {
    echo
    echo "=== AWX Configuration Complete ==="
    echo
    echo "AWX Details:"
    echo "  URL: $AWX_HOST"
    echo "  Username: $AWX_USERNAME"
    echo "  Password: $AWX_PASSWORD"
    echo
    echo "Apstra Integration:"
    echo "  API URL: $APSTRA_API_URL"
    echo "  Username: $APSTRA_USERNAME"
    echo
    echo "Files created:"
    echo "  - Kubernetes RBAC in namespace: $NAMESPACE"
    echo "  - Service account tokens and certificates"
    echo "  - AWX credentials and job templates"
    echo "  - Repository cloned to: $WORK_DIR/repo"
    echo
    echo "You can now access AWX and use the configured job templates for Apstra automation!"
}

# Main execution
main() {
    echo "Starting complete AWX configuration..."

    select_apstra_version
    resolve_ee_image
    check_kubectl
    get_awx_details
    create_kubernetes_rbac
    clone_and_prepare_repo
    extract_kubernetes_credentials
    prompt_for_configuration
    update_role_variables
    configure_awx
    display_final_summary
}

# Run main function
main