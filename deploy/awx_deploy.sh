#!/bin/bash

# AWX Deployment Script for Kubernetes
# Deploys AWX using Helm chart with configurable storage support
#
# Usage:
#   ./awx_deploy.sh                              # Interactive mode (choose from available storage classes)
#   STORAGE_CLASS_OVERRIDE=nfs-client ./awx_deploy.sh   # Use specific storage class
#   STORAGE_CLASS_OVERRIDE=local-path ./awx_deploy.sh   # Use local-path storage class

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWX_NAMESPACE="aap"
AWX_INSTANCE_NAME="ansible-awx"
STORAGE_CLASS=""  # Will be set during deployment
HELM_REPO_NAME="awx-operator"
HELM_REPO_URL="https://ansible-community.github.io/awx-operator-helm/"

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if Kubernetes cluster is accessible
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log "✓ Prerequisites check passed!"
}

# Function to install Helm
install_helm() {
    if command -v helm &> /dev/null; then
        log "Helm is already installed: $(helm version --short)"
        return 0
    fi
    
    log "Installing Helm..."
    
    # Download and install helm
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
    
    log "✓ Helm installed successfully!"
}

# Function to check and setup storage class
setup_storage_class() {
    log "Checking storage class configuration..."
    
    # Check if user provided storage class via environment variable or command line
    if [ -n "${STORAGE_CLASS_OVERRIDE:-}" ]; then
        STORAGE_CLASS="$STORAGE_CLASS_OVERRIDE"
        log_info "Using user-specified storage class: $STORAGE_CLASS"
        
        # Verify the storage class exists
        if kubectl get storageclass "$STORAGE_CLASS" &>/dev/null; then
            log "✓ Storage class '$STORAGE_CLASS' found and will be used"
            return 0
        else
            log_error "Specified storage class '$STORAGE_CLASS' not found in cluster"
            exit 1
        fi
    fi
    
    # List available storage classes
    local available_storage_classes=$(kubectl get storageclass -o name 2>/dev/null | cut -d'/' -f2)
    
    if [ -n "$available_storage_classes" ]; then
        log_info "Available storage classes:"
        echo "$available_storage_classes" | while read sc; do
            local is_default=$(kubectl get storageclass "$sc" -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null)
            if [ "$is_default" = "true" ]; then
                echo "  - $sc (default)"
            else
                echo "  - $sc"
            fi
        done
        echo
        
        # Interactive storage class selection
        echo "Please choose an option:"
        echo "1) Use existing storage class"
        echo "2) Install local-path-provisioner (for local storage)"
        read -p "Enter your choice (1 or 2): " choice
        
        case $choice in
            1)
                echo "Available storage classes:"
                local sc_array=($available_storage_classes)
                for i in "${!sc_array[@]}"; do
                    echo "$((i+1))) ${sc_array[i]}"
                done
                read -p "Select storage class number: " sc_choice
                if [[ "$sc_choice" =~ ^[0-9]+$ ]] && [ "$sc_choice" -ge 1 ] && [ "$sc_choice" -le "${#sc_array[@]}" ]; then
                    STORAGE_CLASS="${sc_array[$((sc_choice-1))]}"
                    log_info "Selected storage class: $STORAGE_CLASS"
                else
                    log_error "Invalid selection"
                    exit 1
                fi
                ;;
            2)
                install_local_path_provisioner
                ;;
            *)
                log_error "Invalid choice"
                exit 1
                ;;
        esac
    else
        log_warning "No storage classes found. Installing local-path-provisioner..."
        install_local_path_provisioner
    fi
}

# Function to install local-path-provisioner
install_local_path_provisioner() {
    log "Installing local-path-provisioner for local storage..."
    
    # Create namespace
    kubectl create namespace local-path-storage --dry-run=client -o yaml | kubectl apply -f -
    
    # Install local-path-provisioner
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
    
    # Wait for deployment to be ready
    log "Waiting for local-path-provisioner to be ready..."
    kubectl wait --namespace local-path-storage \
        --for=condition=ready pod \
        --selector=app=local-path-provisioner \
        --timeout=300s
    
    # Set as default storage class
    kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    
    STORAGE_CLASS="local-path"
    log "✓ Local-path-provisioner installed and set as default storage class!"
}

# Function to setup Helm repository
setup_helm_repo() {
    log "Setting up AWX Operator Helm repository..."
    
    # Add helm repository
    helm repo add $HELM_REPO_NAME $HELM_REPO_URL
    helm repo update
    
    log "✓ Helm repository configured!"
}

# Function to create namespace
create_namespace() {
    log "Creating AWX namespace..."
    
    kubectl create namespace $AWX_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
    
    log "✓ Namespace '$AWX_NAMESPACE' created!"
}

# Function to install AWX Operator
install_awx_operator() {
    log "Installing AWX Operator..."
    
    # Check if operator is already installed
    if kubectl get deployment awx-operator-controller-manager -n $AWX_NAMESPACE &>/dev/null; then
        log_info "AWX Operator already exists, checking if it's ready..."
    else
        # Install AWX Operator using Helm
        helm upgrade --install awx-operator $HELM_REPO_NAME/awx-operator \
            --namespace $AWX_NAMESPACE \
            --create-namespace \
            --wait \
            --timeout=10m
    fi
    
    # Wait for operator to be ready with robust checking
    log "Waiting for AWX Operator to be ready..."
    
    local timeout=300
    local elapsed=0
    local sleep_interval=10
    
    while [ $elapsed -lt $timeout ]; do
        # Check if operator deployment exists
        if kubectl get deployment awx-operator-controller-manager -n $AWX_NAMESPACE &>/dev/null; then
            # Check if deployment is ready
            local ready_replicas=$(kubectl get deployment awx-operator-controller-manager -n $AWX_NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            local desired_replicas=$(kubectl get deployment awx-operator-controller-manager -n $AWX_NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
            
            if [ "$ready_replicas" = "$desired_replicas" ] && [ "$ready_replicas" != "0" ]; then
                # Double-check pods are actually running
                local running_pods=$(kubectl get pods -n $AWX_NAMESPACE -l "control-plane=controller-manager" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
                if [ "$running_pods" -gt 0 ]; then
                    log "✓ AWX Operator is ready!"
                    return 0
                fi
            fi
        fi
        
        log_info "Waiting for AWX Operator... ($elapsed/$timeout seconds)"
        sleep $sleep_interval
        elapsed=$((elapsed + sleep_interval))
    done
    
    log_error "AWX Operator failed to become ready within $timeout seconds"
    log_error "Deployment status:"
    kubectl get deployment awx-operator-controller-manager -n $AWX_NAMESPACE || echo "Deployment not found"
    log_error "Pod status:"
    kubectl get pods -n $AWX_NAMESPACE
    return 1
}

# Function to create AWX instance
create_awx_instance() {
    log "Creating AWX instance..."
    
    # Verify storage class exists before creating AWX instance
    if ! kubectl get storageclass "$STORAGE_CLASS" &>/dev/null; then
        log_error "Storage class '$STORAGE_CLASS' not found!"
        kubectl get storageclass
        return 1
    fi
    
    # Check if AWX instance already exists
    if kubectl get awx $AWX_INSTANCE_NAME -n $AWX_NAMESPACE &>/dev/null; then
        log_info "AWX instance '$AWX_INSTANCE_NAME' already exists"
    else
        # Create AWX custom resource
        log "Creating AWX custom resource..."
        cat <<EOF | kubectl apply -f -
---
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: $AWX_INSTANCE_NAME
  namespace: $AWX_NAMESPACE
spec:
  service_type: nodeport
  projects_persistence: true
  projects_storage_access_mode: ReadWriteOnce
  projects_storage_size: 8Gi
  projects_storage_class: $STORAGE_CLASS
  postgres_storage_class: $STORAGE_CLASS
  postgres_storage_requirements:
    requests:
      storage: 8Gi
EOF
        
        if [ $? -eq 0 ]; then
            log "✓ AWX instance '$AWX_INSTANCE_NAME' created successfully"
        else
            log_error "Failed to create AWX instance"
            return 1
        fi
    fi
    
    # Wait for AWX to be deployed
    log "Waiting for AWX deployment (this may take 5-10 minutes)..."
    
    local timeout=600
    local elapsed=0
    local sleep_interval=15
    local last_status_check=0
    
    while [ $elapsed -lt $timeout ]; do
        # Check PVCs first
        local pvc_count=$(kubectl get pvc -n $AWX_NAMESPACE --no-headers 2>/dev/null | grep "Bound" | wc -l || echo "0")
        
        # Get AWX-related pods (exclude operator and completed jobs)
        local awx_web_pods=$(kubectl get pods -n $AWX_NAMESPACE -l "app.kubernetes.io/name=${AWX_INSTANCE_NAME}-web" --no-headers 2>/dev/null | wc -l || echo "0")
        local awx_task_pods=$(kubectl get pods -n $AWX_NAMESPACE -l "app.kubernetes.io/name=${AWX_INSTANCE_NAME}-task" --no-headers 2>/dev/null | wc -l || echo "0")
        local postgres_pods=$(kubectl get pods -n $AWX_NAMESPACE -l "app.kubernetes.io/name=postgres-15" --no-headers 2>/dev/null | wc -l || echo "0")
        
        local running_web=$(kubectl get pods -n $AWX_NAMESPACE -l "app.kubernetes.io/name=${AWX_INSTANCE_NAME}-web" --no-headers 2>/dev/null | grep "Running" | wc -l || echo "0")
        local running_task=$(kubectl get pods -n $AWX_NAMESPACE -l "app.kubernetes.io/name=${AWX_INSTANCE_NAME}-task" --no-headers 2>/dev/null | grep "Running" | wc -l || echo "0")
        local running_postgres=$(kubectl get pods -n $AWX_NAMESPACE -l "app.kubernetes.io/name=postgres-15" --no-headers 2>/dev/null | grep "Running" | wc -l || echo "0")
        
        # Check if all expected components are running
        if [ "$pvc_count" -ge 2 ] && [ "$running_web" -ge 1 ] && [ "$running_task" -ge 1 ] && [ "$running_postgres" -ge 1 ]; then
            # Verify AWX service exists
            if kubectl get svc -n $AWX_NAMESPACE ${AWX_INSTANCE_NAME}-service &>/dev/null; then
                # Final check: ensure pods are actually ready, not just running
                local ready_web_pods=0
                local ready_task_pods=0
                
                # Check web pod readiness (count ready containers)
                if [ "$running_web" -gt 0 ]; then
                    ready_web_pods=$(kubectl get pods -n $AWX_NAMESPACE -l "app.kubernetes.io/name=${AWX_INSTANCE_NAME}-web" -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -c "True" || echo "0")
                fi
                
                # Check task pod readiness
                if [ "$running_task" -gt 0 ]; then
                    ready_task_pods=$(kubectl get pods -n $AWX_NAMESPACE -l "app.kubernetes.io/name=${AWX_INSTANCE_NAME}-task" -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -c "True" || echo "0")
                fi
                
                if [ "$ready_web_pods" -ge 1 ] && [ "$ready_task_pods" -ge 1 ]; then
                    log "✓ AWX instance deployed successfully!"
                    log_info "Final deployment status:"
                    echo "  - Web pods: $running_web running"
                    echo "  - Task pods: $running_task running" 
                    echo "  - PostgreSQL pods: $running_postgres running"
                    echo "  - PVCs bound: $pvc_count"
                    return 0
                fi
            fi
        fi
        
        # Show progress every 60 seconds
        if [ $((elapsed - last_status_check)) -ge 60 ]; then
            log_info "AWX deployment progress ($((elapsed/60))m $((elapsed%60))s elapsed):"
            echo "  - PVCs bound: $pvc_count/2"
            echo "  - Web pods: $running_web/$awx_web_pods running"
            echo "  - Task pods: $running_task/$awx_task_pods running"
            echo "  - PostgreSQL pods: $running_postgres/$postgres_pods running"
            last_status_check=$elapsed
        else
            log_info "AWX deployment in progress... ($((elapsed/60))m $((elapsed%60))s elapsed)"
        fi
        
        sleep $sleep_interval
        elapsed=$((elapsed + sleep_interval))
    done
    
    log_error "AWX deployment timed out after $((timeout/60)) minutes"
    log_error "Final status:"
    kubectl get pods -n $AWX_NAMESPACE
    kubectl get pvc -n $AWX_NAMESPACE
    kubectl get awx -n $AWX_NAMESPACE
    return 1
}

# Function to get AWX access information
get_awx_access_info() {
    log "Retrieving AWX access information..."
    
    # Get NodePort with error handling
    local nodeport=$(kubectl get svc -n $AWX_NAMESPACE ${AWX_INSTANCE_NAME}-service -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
    if [ -z "$nodeport" ]; then
        log_error "Could not retrieve NodePort for AWX service"
        kubectl get svc -n $AWX_NAMESPACE
        return 1
    fi
    
    # Get external IP or use local IP
    local external_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null)
    if [ -z "$external_ip" ]; then
        external_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
    fi
    
    if [ -z "$external_ip" ]; then
        log_error "Could not determine cluster IP address"
        kubectl get nodes -o wide
        return 1
    fi
    
    # Get admin password with retry logic
    local admin_password=""
    local password_attempts=0
    local max_password_attempts=10
    
    while [ $password_attempts -lt $max_password_attempts ]; do
        admin_password=$(kubectl get secret -n $AWX_NAMESPACE ${AWX_INSTANCE_NAME}-admin-password -o jsonpath="{.data.password}" 2>/dev/null | base64 --decode 2>/dev/null)
        
        if [ -n "$admin_password" ] && [ ${#admin_password} -gt 5 ]; then
            break
        fi
        
        log_info "Waiting for admin password secret to be created... (attempt $((password_attempts + 1))/$max_password_attempts)"
        sleep 10
        password_attempts=$((password_attempts + 1))
    done
    
    if [ -z "$admin_password" ]; then
        log_warning "Could not retrieve admin password automatically"
        admin_password="<check secret: kubectl get secret -n $AWX_NAMESPACE ${AWX_INSTANCE_NAME}-admin-password -o jsonpath='{.data.password}' | base64 -d>"
    fi
    
    echo
    log "🎉 AWX deployment completed successfully!"
    echo
    log_info "AWX Access Information:"
    echo "- URL: http://$external_ip:$nodeport"
    echo "- Username: admin"
    echo "- Password: $admin_password"
    echo
    log_info "Storage Information:"
    echo "- Storage Class: $STORAGE_CLASS"
    echo "- PostgreSQL Storage: 8Gi"
    echo "- Projects Storage: 8Gi"
    echo
    log_info "Useful commands:"
    echo "- Check AWX pods: kubectl get pods -n $AWX_NAMESPACE"
    echo "- Check AWX logs: kubectl logs -n $AWX_NAMESPACE deployment/${AWX_INSTANCE_NAME}-web"
    echo "- Access AWX service: kubectl get svc -n $AWX_NAMESPACE"
    echo "- Get admin password: kubectl get secret -n $AWX_NAMESPACE ${AWX_INSTANCE_NAME}-admin-password -o jsonpath='{.data.password}' | base64 -d"
}

# Function to verify deployment
verify_deployment() {
    log "Verifying AWX deployment..."
    
    # Check operator pods
    local operator_ready=$(kubectl get pods -n $AWX_NAMESPACE -l "control-plane=controller-manager" --no-headers 2>/dev/null | grep "Running" | wc -l)
    if [ "$operator_ready" -eq 0 ]; then
        log_error "AWX Operator is not running"
        kubectl get pods -n $AWX_NAMESPACE -l "control-plane=controller-manager"
        return 1
    fi
    
    # Check AWX pods (exclude completed jobs)
    local awx_pods=$(kubectl get pods -n $AWX_NAMESPACE -l "app.kubernetes.io/managed-by=awx-operator" --no-headers 2>/dev/null | grep -v "Completed" | wc -l)
    local running_awx_pods=$(kubectl get pods -n $AWX_NAMESPACE -l "app.kubernetes.io/managed-by=awx-operator" --no-headers 2>/dev/null | grep "Running" | wc -l)
    
    if [ "$awx_pods" -eq 0 ] || [ "$running_awx_pods" -lt 3 ]; then
        log_error "AWX pods are not running properly (expected ≥3, got $running_awx_pods running)"
        kubectl get pods -n $AWX_NAMESPACE
        return 1
    fi
    
    # Check AWX service
    if ! kubectl get svc -n $AWX_NAMESPACE ${AWX_INSTANCE_NAME}-service &>/dev/null; then
        log_error "AWX service not found"
        kubectl get svc -n $AWX_NAMESPACE
        return 1
    fi
    
    # Check AWX custom resource
    if ! kubectl get awx -n $AWX_NAMESPACE ${AWX_INSTANCE_NAME} &>/dev/null; then
        log_error "AWX custom resource not found"
        kubectl get awx -n $AWX_NAMESPACE
        return 1
    fi
    
    log "✓ AWX deployment verification passed!"
    log_info "Deployment summary:"
    echo "  - Operator pods: $operator_ready running"
    echo "  - AWX pods: $running_awx_pods running"
    return 0
}

# Function to cleanup on error
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up..."
    
    read -p "Do you want to remove AWX resources? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete namespace $AWX_NAMESPACE --ignore-not-found=true
        log "AWX resources cleaned up."
    fi
}

# Main function
main() {
    echo "================================================="
    echo "        AWX Deployment Script for Kubernetes"
    echo "================================================="
    echo
    
    # Set error trap
    trap cleanup_on_error ERR
    
    log "Starting AWX deployment process..."
    echo
    
    # Execute deployment steps
    check_prerequisites
    install_helm
    setup_storage_class
    setup_helm_repo
    create_namespace
    install_awx_operator
    create_awx_instance
    
    # Verify and display results
    if verify_deployment; then
        get_awx_access_info
    else
        log_error "Deployment verification failed"
        exit 1
    fi
    
    log "AWX deployment completed successfully! 🚀"
}

# Execute main function
main "$@"