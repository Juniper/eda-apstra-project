#!/bin/bash

# Nutanix Event Notification Service Deployment Script
# This script deploys the Nutanix EDA service using either Docker or Kubernetes
# with automatic AWX password extraction and user-guided configuration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_header() {
    echo -e "${PURPLE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}  $1${NC}"
    echo -e "${PURPLE}════════════════════════════════════════════════════════════════${NC}"
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_question() {
    echo -e "${CYAN}[INPUT]${NC} $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES_DIR="$(dirname "$SCRIPT_DIR")/files"

# Default port/namespace values
DEFAULT_NUTANIX_PORT="9440"
DEFAULT_AWX_PORT="80"
DEFAULT_NAMESPACE="default"

# Apstra version → Juniper Nutanix Plugin version mapping
#   Apstra 6.0  →  Plugin 6.0.0  →  event-notification-service:6.0.0
#   Apstra 6.1  →  Plugin 6.1.0  →  event-notification-service:6.1.0

print_header "Nutanix Event Notification Service Deployment"

echo "This script will help you deploy the Nutanix Event Notification Service"
echo "using either Docker containers or Kubernetes pods."
echo ""
echo "AWX/Ansible Tower configuration will be automatically detected from the"
echo "running AWX instance in the 'aap' namespace."
echo ""

# ── Apstra version selection ──────────────────────────────────────────────────
print_question "Which Apstra version are you running?"
echo "  1. Apstra 6.0  →  Juniper Nutanix Plugin 6.0.0"
echo "  2. Apstra 6.1  →  Juniper Nutanix Plugin 6.1.0"
echo ""
read -p "Enter your choice (1 or 2): " APSTRA_VER_CHOICE

case $APSTRA_VER_CHOICE in
    1)
        APSTRA_VERSION="6.0"
        PLUGIN_VERSION="6.0.0"
        ;;
    2)
        APSTRA_VERSION="6.1"
        PLUGIN_VERSION="6.1.0"
        ;;
    *)
        print_error "Invalid choice. Please run the script again."
        exit 1
        ;;
esac

SELECTED_IMAGE="event-notification-service:${PLUGIN_VERSION}"
# The image inside the tgz may carry a different name/tag pattern
# (e.g. apstra-nutanix-event-service:6.1.0-2.0.0-x86_64). The load helpers
# below search for any apstra-nutanix OR event-notification-service tag and
# re-tag it to SELECTED_IMAGE so the deployment manifests stay consistent.
PLUGIN_TGZ="juniper-nutanix-plugin-${PLUGIN_VERSION}.tgz"
print_status "Apstra version : $APSTRA_VERSION"
print_status "Plugin image   : $SELECTED_IMAGE"
echo ""

# ── Deployment method selection ──────────────────────────────────────────────
print_question "Choose deployment method:"
echo "  1. Docker Container (Standalone)"
echo "  2. Kubernetes Pods (Cluster)"
echo ""
read -p "Enter your choice (1 or 2): " DEPLOY_METHOD

case $DEPLOY_METHOD in
    1)
        DEPLOYMENT_TYPE="docker"
        print_status "Selected: Docker Container deployment"
        ;;
    2)
        DEPLOYMENT_TYPE="kubernetes"
        print_status "Selected: Kubernetes Pods deployment"
        ;;
    *)
        print_error "Invalid choice. Please run the script again."
        exit 1
        ;;
esac
echo ""

# Check prerequisites
print_status "Checking prerequisites..."

# kubectl is always required (for AWX password + K8s deployment)
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster"
    print_error "Please ensure kubectl is properly configured"
    exit 1
fi

# Docker is required only for Docker deployment path
if [ "$DEPLOYMENT_TYPE" == "docker" ]; then
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed or not in PATH"
        print_error "Install with: sudo apt-get install -y docker.io"
        exit 1
    fi
    if ! docker ps &> /dev/null; then
        print_error "Cannot run Docker commands. Please check Docker daemon and permissions."
        print_status "If Docker was just installed, add your user to the docker group and re-login:"
        print_status "  sudo usermod -aG docker \$USER  # then log out and back in"
        print_status "Or run this script with: sg docker ./deploy_nutanix_service.sh"
        exit 1
    fi
fi

print_success "Prerequisites check passed"

# Extract AWX admin password from installed AWX
print_status "Extracting AWX admin password from cluster..."

# Check if AWX secret exists in aap namespace
if ! kubectl get secret -n aap | grep -q "ansible-awx-admin-password"; then
    print_error "AWX admin password secret not found in 'aap' namespace"
    print_error "Please ensure AWX is properly installed"
    exit 1
fi

AWX_ADMIN_PASSWORD=$(kubectl get secret ansible-awx-admin-password -n aap -o jsonpath='{.data.password}' | base64 -d)
if [ -z "$AWX_ADMIN_PASSWORD" ]; then
    print_error "Failed to extract AWX admin password"
    exit 1
fi

print_success "AWX admin password extracted successfully"

# ── Image availability check + auto-load ─────────────────────────────────────
# Helper: prompt for tgz path, validate, return in $PLUGIN_TGZ_PATH
_prompt_for_plugin_tgz() {
    echo ""
    print_status "The Nutanix plugin image needs to be downloaded from the Juniper Support portal:"
    print_status "  URL  : https://support.juniper.net/support/downloads/?p=apstra"
    print_status "  Under: 'Juniper Nutanix Plugin'"
    print_status "  File : juniper-nutanix-plugin-${PLUGIN_VERSION}.tgz  (~63 MB)"
    echo ""
    read -p "$(echo -e "${CYAN}[INPUT]${NC} Enter full path to juniper-nutanix-plugin-${PLUGIN_VERSION}.tgz: ")" PLUGIN_TGZ_PATH
    if [[ -z "$PLUGIN_TGZ_PATH" ]]; then
        print_error "No path provided."
        exit 1
    fi
    if [[ ! -f "$PLUGIN_TGZ_PATH" ]]; then
        print_error "File not found: $PLUGIN_TGZ_PATH"
        exit 1
    fi
}

# Helper: load tgz into Docker daemon and (re)tag to SELECTED_IMAGE
_load_image_docker() {
    print_status "Loading image into Docker daemon..."
    if file "$PLUGIN_TGZ_PATH" | grep -qi "gzip\|compressed"; then
        zcat "$PLUGIN_TGZ_PATH" | docker load
    else
        docker load -i "$PLUGIN_TGZ_PATH"
    fi
    # Re-tag to the expected name if loaded under a different tag
    if ! docker image inspect "$SELECTED_IMAGE" &>/dev/null; then
        local loaded_tag
        loaded_tag=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "event-notification-service" | head -1)
        if [[ -n "$loaded_tag" && "$loaded_tag" != "$SELECTED_IMAGE" ]]; then
            docker tag "$loaded_tag" "$SELECTED_IMAGE"
            print_success "Re-tagged $loaded_tag → $SELECTED_IMAGE"
        fi
    fi
}

# Helper: load tgz into containerd k8s.io namespace and (re)tag to SELECTED_IMAGE
_load_image_containerd() {
    print_status "Loading image into containerd (k8s.io namespace)..."
    if file "$PLUGIN_TGZ_PATH" | grep -qi "gzip\|compressed"; then
        zcat "$PLUGIN_TGZ_PATH" | sudo ctr -n k8s.io images import -
    else
        sudo ctr -n k8s.io images import "$PLUGIN_TGZ_PATH"
    fi
    # Re-tag to the canonical short name. The tgz may contain either:
    #   event-notification-service:X.Y.Z
    #   apstra-nutanix-event-service:X.Y.Z-...
    if ! sudo ctr -n k8s.io images ls 2>/dev/null | grep -q "^event-notification-service:${PLUGIN_VERSION}"; then
        local loaded_tag
        loaded_tag=$(sudo ctr -n k8s.io images ls 2>/dev/null \
            | grep -E "event-notification-service|apstra-nutanix" \
            | awk '{print $1}' | head -1)
        if [[ -n "$loaded_tag" ]]; then
            sudo ctr -n k8s.io images tag "$loaded_tag" "$SELECTED_IMAGE"
            print_success "Re-tagged $loaded_tag → $SELECTED_IMAGE"
        fi
    fi
    # Kubelet resolves bare image names to docker.io/library/<name> internally.
    # Tag with the full docker.io/library prefix so IfNotPresent lookup succeeds.
    sudo ctr -n k8s.io images tag "$SELECTED_IMAGE" "docker.io/library/${SELECTED_IMAGE}" 2>/dev/null || true
    print_success "Also tagged as docker.io/library/${SELECTED_IMAGE} (required by kubelet)"
}

print_status "Checking Nutanix plugin image availability ($SELECTED_IMAGE)..."

if [ "$DEPLOYMENT_TYPE" == "docker" ]; then
    if ! docker image inspect "$SELECTED_IMAGE" &>/dev/null; then
        print_warning "Image '$SELECTED_IMAGE' not found in Docker daemon."
        _prompt_for_plugin_tgz
        _load_image_docker
        if ! docker image inspect "$SELECTED_IMAGE" &>/dev/null; then
            print_error "Image still not found after load. Check the tgz file."
            exit 1
        fi
    fi
else
    if ! sudo ctr -n k8s.io images ls 2>/dev/null | grep -q "event-notification-service:${PLUGIN_VERSION}"; then
        print_warning "Image '$SELECTED_IMAGE' not found in containerd."
        _prompt_for_plugin_tgz
        _load_image_containerd
        if ! sudo ctr -n k8s.io images ls 2>/dev/null | grep -q "event-notification-service:${PLUGIN_VERSION}"; then
            print_error "Image still not found after load. Check the tgz file."
            exit 1
        fi
    fi
fi
print_success "Nutanix plugin image ready: $SELECTED_IMAGE"

# Extract AWX service configuration from cluster
print_status "Extracting AWX service configuration..."

# Check if AWX service exists
if ! kubectl get svc -n aap ansible-awx-service &> /dev/null; then
    print_error "AWX service not found in 'aap' namespace"
    print_error "Please ensure AWX is properly installed"
    exit 1
fi

# Get AWX NodePort
AWX_NODEPORT=$(kubectl get svc -n aap ansible-awx-service -o jsonpath='{.spec.ports[0].nodePort}')
if [ -z "$AWX_NODEPORT" ]; then
    print_error "Failed to extract AWX NodePort"
    exit 1
fi

# Get Kubernetes node IP (where AWX is accessible)
K8S_NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
if [ -z "$K8S_NODE_IP" ]; then
    print_error "Failed to get Kubernetes node IP"
    exit 1
fi

# Set AWX connection details
AWX_HOST="$K8S_NODE_IP"
AWX_PORT="$AWX_NODEPORT"
AWX_USERNAME="admin"

print_success "AWX configuration auto-detected"
print_status "AWX accessible at: $AWX_HOST:$AWX_PORT"

echo ""
print_header "Configuration Input"

# Get Nutanix configuration
print_question "Enter Nutanix Prism Central IP address:"
read -p "Nutanix IP: " NUTANIX_IP
if [ -z "$NUTANIX_IP" ]; then
    print_error "Nutanix IP is required"
    exit 1
fi

print_question "Enter Nutanix Prism Central port (default: $DEFAULT_NUTANIX_PORT):"
read -p "Nutanix Port: " NUTANIX_PORT
NUTANIX_PORT=${NUTANIX_PORT:-$DEFAULT_NUTANIX_PORT}

print_question "Enter Nutanix username:"
read -p "Nutanix Username: " NUTANIX_USERNAME
if [ -z "$NUTANIX_USERNAME" ]; then
    print_error "Nutanix username is required"
    exit 1
fi

print_question "Enter Nutanix password:"
read -s -p "Nutanix Password: " NUTANIX_PASSWORD
echo ""
if [ -z "$NUTANIX_PASSWORD" ]; then
    print_error "Nutanix password is required"
    exit 1
fi

# For Kubernetes deployment, get namespace
if [ "$DEPLOYMENT_TYPE" == "kubernetes" ]; then
    print_question "Enter Kubernetes namespace (default: $DEFAULT_NAMESPACE):"
    read -p "Namespace: " K8S_NAMESPACE
    K8S_NAMESPACE=${K8S_NAMESPACE:-$DEFAULT_NAMESPACE}
fi

# Optional: Blueprint name
print_question "Enter Apstra Blueprint Name (optional, default: apstra-ntx-bp):"
read -p "Blueprint Name: " BLUEPRINT_NAME
BLUEPRINT_NAME=${BLUEPRINT_NAME:-apstra-ntx-bp}

echo ""
print_header "Deployment Configuration Summary"

echo "Deployment Type: $DEPLOYMENT_TYPE"
echo "Nutanix Prism Central: $NUTANIX_IP:$NUTANIX_PORT"
echo "Nutanix Username: $NUTANIX_USERNAME"
echo "AWX/Tower Host: $AWX_HOST:$AWX_PORT (Auto-detected)"
echo "AWX Username: $AWX_USERNAME (Auto-detected)"
echo "Blueprint Name: $BLUEPRINT_NAME"
if [ "$DEPLOYMENT_TYPE" == "kubernetes" ]; then
    echo "Kubernetes Namespace: $K8S_NAMESPACE"
fi

echo ""
print_question "Do you want to proceed with deployment? (y/N):"
read -p "Confirm: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    print_warning "Deployment cancelled by user"
    exit 0
fi

echo ""
print_header "Starting Deployment"

if [ "$DEPLOYMENT_TYPE" == "docker" ]; then
    # Docker deployment
    print_status "Preparing Docker environment file..."
    
    # Create temporary environment file
    ENV_FILE="/tmp/nutanix-eda-docker.env"
    cat > "$ENV_FILE" << EOF
NUTANIX_PRISM_CENTRAL_IP=$NUTANIX_IP
NUTANIX_PRISM_CENTRAL_PORT=$NUTANIX_PORT
NUTANIX_USERNAME=$NUTANIX_USERNAME
NUTANIX_PASSWORD=$NUTANIX_PASSWORD
ANSIBLE_TOWER_HOST=$AWX_HOST
ANSIBLE_TOWER_PORT=$AWX_PORT
ANSIBLE_TOWER_USERNAME=$AWX_USERNAME
ANSIBLE_TOWER_PASSWORD=$AWX_ADMIN_PASSWORD
BLUEPRINT_NAME=$BLUEPRINT_NAME
EOF

    print_success "Environment file created: $ENV_FILE"
    
    print_status "Deploying Docker container..."
    
    # Stop existing container if running
    if docker ps -a --format '{{.Names}}' | grep -q "^nutanix-event-service$"; then
        print_warning "Stopping existing container..."
        docker stop nutanix-event-service || true
        docker rm nutanix-event-service || true
    fi
    
    # Run the container
    docker run -d \
        --name nutanix-event-service \
        --env-file "$ENV_FILE" \
        --restart unless-stopped \
        $SELECTED_IMAGE
    
    if [ $? -eq 0 ]; then
        print_success "Docker container deployed successfully!"
        print_status "Container name: nutanix-event-service"
        print_status "View logs: docker logs -f nutanix-event-service"
        print_status "Stop service: docker stop nutanix-event-service"
        
        # Show container status
        echo ""
        print_status "Container Status:"
        docker ps --filter name=nutanix-event-service --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
        
        # Show recent logs
        echo ""
        print_status "Recent logs (last 20 lines):"
        docker logs --tail 20 nutanix-event-service
    else
        print_error "Failed to deploy Docker container"
        exit 1
    fi
    
    # Clean up temporary file
    rm -f "$ENV_FILE"

else
    # Kubernetes deployment
    print_status "Preparing Kubernetes manifests..."
    
    # Create temporary directory for manifests
    TEMP_DIR="/tmp/nutanix-k8s-deploy-$$"
    mkdir -p "$TEMP_DIR"
    
    # Prepare ConfigMap
    cp "$FILES_DIR/unified-configmap.yaml" "$TEMP_DIR/"
    sed -i "s/NUTANIX_PRISM_CENTRAL_IP: \".*\"/NUTANIX_PRISM_CENTRAL_IP: \"$NUTANIX_IP\"/" "$TEMP_DIR/unified-configmap.yaml"
    sed -i "s/NUTANIX_PRISM_CENTRAL_PORT: \".*\"/NUTANIX_PRISM_CENTRAL_PORT: \"$NUTANIX_PORT\"/" "$TEMP_DIR/unified-configmap.yaml"
    sed -i "s/NUTANIX_USERNAME: \".*\"/NUTANIX_USERNAME: \"$NUTANIX_USERNAME\"/" "$TEMP_DIR/unified-configmap.yaml"
    sed -i "s/ANSIBLE_TOWER_HOST: \".*\"/ANSIBLE_TOWER_HOST: \"$AWX_HOST\"/" "$TEMP_DIR/unified-configmap.yaml"
    sed -i "s/ANSIBLE_TOWER_PORT: \".*\"/ANSIBLE_TOWER_PORT: \"$AWX_PORT\"/" "$TEMP_DIR/unified-configmap.yaml"
    sed -i "s/ANSIBLE_TOWER_USERNAME: \".*\"/ANSIBLE_TOWER_USERNAME: \"$AWX_USERNAME\"/" "$TEMP_DIR/unified-configmap.yaml"
    sed -i "s/BLUEPRINT_NAME: \".*\"/BLUEPRINT_NAME: \"$BLUEPRINT_NAME\"/" "$TEMP_DIR/unified-configmap.yaml"
    sed -i "s/namespace: default/namespace: $K8S_NAMESPACE/" "$TEMP_DIR/unified-configmap.yaml"
    
    # Prepare Secret with encoded passwords
    NUTANIX_PASSWORD_B64=$(echo -n "$NUTANIX_PASSWORD" | base64 -w 0)
    AWX_PASSWORD_B64=$(echo -n "$AWX_ADMIN_PASSWORD" | base64 -w 0)
    
    cp "$FILES_DIR/unified-secret.yaml" "$TEMP_DIR/"
    sed -i "s/NUTANIX_PASSWORD: .*/NUTANIX_PASSWORD: $NUTANIX_PASSWORD_B64/" "$TEMP_DIR/unified-secret.yaml"
    sed -i "s/ANSIBLE_TOWER_PASSWORD: .*/ANSIBLE_TOWER_PASSWORD: $AWX_PASSWORD_B64/" "$TEMP_DIR/unified-secret.yaml"
    sed -i "s/namespace: default/namespace: $K8S_NAMESPACE/" "$TEMP_DIR/unified-secret.yaml"
    
    # Prepare Deployment
    cp "$FILES_DIR/deployment.yaml" "$TEMP_DIR/"
    sed -i "s/namespace: default/namespace: $K8S_NAMESPACE/" "$TEMP_DIR/deployment.yaml"
    # Patch image tag for selected Apstra version
    sed -i "s|image: event-notification-service:.*|image: $SELECTED_IMAGE|" "$TEMP_DIR/deployment.yaml"
    
    # Copy Service if exists
    if [ -f "$FILES_DIR/service.yaml" ]; then
        cp "$FILES_DIR/service.yaml" "$TEMP_DIR/"
        sed -i "s/namespace: default/namespace: $K8S_NAMESPACE/" "$TEMP_DIR/service.yaml"
    fi
    
    print_success "Kubernetes manifests prepared"
    
    # Create namespace if it doesn't exist
    if [ "$K8S_NAMESPACE" != "default" ]; then
        kubectl create namespace "$K8S_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
        print_status "Namespace '$K8S_NAMESPACE' ready"
    fi
    
    # Apply manifests
    print_status "Applying Kubernetes manifests..."
    
    kubectl apply -f "$TEMP_DIR/unified-configmap.yaml"
    print_status "ConfigMap applied"
    
    kubectl apply -f "$TEMP_DIR/unified-secret.yaml"
    print_status "Secret applied"
    
    kubectl apply -f "$TEMP_DIR/deployment.yaml"
    print_status "Deployment applied"
    
    if [ -f "$TEMP_DIR/service.yaml" ]; then
        kubectl apply -f "$TEMP_DIR/service.yaml"
        print_status "Service applied"
    fi
    
    # Wait for deployment to be ready
    print_status "Waiting for deployment to be ready..."
    kubectl wait --for=condition=available --timeout=120s deployment/event-notification-service -n "$K8S_NAMESPACE"
    
    if [ $? -eq 0 ]; then
        print_success "Kubernetes deployment completed successfully!"
        
        # Show deployment status
        echo ""
        print_status "Deployment Status:"
        kubectl get deployment event-notification-service -n "$K8S_NAMESPACE"
        
        echo ""
        print_status "Pod Status:"
        kubectl get pods -l app=event-notification-service -n "$K8S_NAMESPACE"
        
        # Show recent logs
        echo ""
        print_status "Recent logs (last 20 lines):"
        kubectl logs --tail 20 -l app=event-notification-service -n "$K8S_NAMESPACE"
        
        echo ""
        print_status "Useful commands:"
        echo "  View logs: kubectl logs -f deployment/event-notification-service -n $K8S_NAMESPACE"
        echo "  Check status: kubectl get pods -l app=event-notification-service -n $K8S_NAMESPACE"
        echo "  Delete deployment: kubectl delete -f $TEMP_DIR/deployment.yaml"
    else
        print_error "Deployment failed to become ready"
        print_status "Check deployment status: kubectl describe deployment event-notification-service -n $K8S_NAMESPACE"
        exit 1
    fi
    
    # Clean up temporary directory
    rm -rf "$TEMP_DIR"
fi

echo ""
print_header "Deployment Complete"

if [ "$DEPLOYMENT_TYPE" == "docker" ]; then
    print_success "Nutanix Event Notification Service is running as a Docker container"
    print_status "Monitor the service: docker logs -f nutanix-event-service"
else
    print_success "Nutanix Event Notification Service is running in Kubernetes"
    print_status "Monitor the service: kubectl logs -f deployment/event-notification-service -n $K8S_NAMESPACE"
fi

print_status "The service will monitor your Nutanix infrastructure and trigger AWX jobs automatically"
print_status "Check the logs to verify connectivity to Nutanix Prism Central and AWX"

echo ""
print_warning "Important: Keep your credentials secure and consider using proper secret management"
print_warning "For production deployments, review security settings and resource limits"