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

echo "=== Complete AWX Configuration Script ==="
echo "This script will:"
echo "1. Configure Kubernetes RBAC"
echo "2. Clone the repository and role"
echo "3. Prompt for configuration values"
echo "4. Configure AWX automatically"
echo

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

# Function to clone repository and prepare role
clone_and_prepare_repo() {
    echo "Cloning repository and preparing role..."
    
    # Clean up any existing work directory
    rm -rf $WORK_DIR
    mkdir -p $WORK_DIR
    
    # Clone the repository
    git clone -b $REPO_BRANCH $REPO_URL $WORK_DIR/repo
    echo "✓ Repository cloned to $WORK_DIR/repo"
    
    # Check if role exists
    if [[ ! -d "$WORK_DIR/repo/build/$ROLE_NAME" ]]; then
        echo "ERROR: Role $ROLE_NAME not found in repository"
        exit 1
    fi
    
    echo "✓ Role $ROLE_NAME found in repository"
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
    
    # Execution Environment
    echo
    echo "Execution Environment:"
    read -p "Execution Environment Image URL [s-artifactory.juniper.net/atom-docker/ee/apstra-ee:0.1.32]: " EE_IMAGE_URL
    EE_IMAGE_URL=${EE_IMAGE_URL:-s-artifactory.juniper.net/atom-docker/ee/apstra-ee:0.1.32}
    
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
    if ansible-playbook deploy-awx-playbook.yml -v; then
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