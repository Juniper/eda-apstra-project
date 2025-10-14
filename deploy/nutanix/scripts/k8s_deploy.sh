#!/bin/bash

# Interactive Kubernetes Single Node Deployment Script using Kubespray
# Based on: https://github.com/Juniper/eda-apstra-project/blob/main/tests/upstream/README.md

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER_HOME="$(eval echo ~$USER)"
VENV_DIR="$USER_HOME/k8s-venv"
KUBESPRAY_DIR="$USER_HOME/kubespray"
SELECTED_IP=""

# Logging function
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

# Function to select IP address
select_ip_address() {
    log "Detecting available IP addresses..."
    
    # Get all IP addresses (excluding loopback)
    local ips=($(ip addr show | grep -E 'inet [0-9]' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1))
    
    if [ ${#ips[@]} -eq 0 ]; then
        log_error "No IP addresses found"
        return 1
    elif [ ${#ips[@]} -eq 1 ]; then
        SELECTED_IP="${ips[0]}"
        log "Only one IP address found: $SELECTED_IP"
        return 0
    fi
    
    echo
    log_info "Multiple IP addresses detected:"
    for i in "${!ips[@]}"; do
        local ip="${ips[$i]}"
        local interface=$(ip addr show | grep -B2 "$ip/" | grep "^[0-9]" | awk '{print $2}' | sed 's/://')
        echo "  $((i+1))) $ip ($interface)"
    done
    
    echo
    while true; do
        read -p "Select IP address for Kubernetes installation (1-${#ips[@]}): " choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#ips[@]} ]; then
            SELECTED_IP="${ips[$((choice-1))]}"
            log "Selected IP address: $SELECTED_IP"
            break
        else
            log_error "Invalid selection. Please enter a number between 1 and ${#ips[@]}"
        fi
    done
    
    return 0
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for Kubernetes deployment..."
    
    local errors=0
    
    # Check CPU cores
    cpu_cores=$(nproc)
    log_info "CPU cores: $cpu_cores"
    if [ "$cpu_cores" -lt 2 ]; then
        log_error "Minimum 2 CPU cores required. Found: $cpu_cores"
        ((errors++))
    else
        log "✓ CPU cores requirement met"
    fi
    
    # Check RAM
    ram_gb=$(free -g | awk '/^Mem:/{print $2}')
    log_info "RAM: ${ram_gb}GB"
    if [ "$ram_gb" -lt 4 ]; then
        log_error "Minimum 4GB RAM required. Found: ${ram_gb}GB"
        ((errors++))
    else
        log "✓ RAM requirement met"
    fi
    
    # Check disk space
    disk_space_gb=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    log_info "Available disk space: ${disk_space_gb}GB"
    if [ "$disk_space_gb" -lt 20 ]; then
        log_warning "Recommended 20GB disk space. Found: ${disk_space_gb}GB"
        log_warning "You may encounter issues with a smaller disk. Continue anyway? (y/N)"
        read -p "Proceed with limited disk space? " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Deployment cancelled due to insufficient disk space"
            ((errors++))
        else
            log "⚠ Proceeding with limited disk space"
        fi
    else
        log "✓ Disk space requirement met"
    fi
    
    # Check and install Python
    if command -v python3 &> /dev/null; then
        python_version=$(python3 -c "import sys; print('.'.join(map(str, sys.version_info[:2])))")
        log_info "Python version: $python_version"
        if python3 -c "import sys; exit(0 if sys.version_info >= (3, 10) else 1)"; then
            log "✓ Python 3.10+ requirement met"
        else
            log_error "Python 3.10+ required. Found: $python_version"
            log_warning "You may need to install a newer Python version manually"
            ((errors++))
        fi
    else
        log_warning "Python 3 not found. Installing python3..."
        if [ "$EUID" -eq 0 ] || sudo -v 2>/dev/null; then
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y python3 python3-venv
            elif command -v yum &> /dev/null; then
                sudo yum install -y python3 python3-venv
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y python3 python3-venv
            else
                log_error "Cannot install Python3 automatically. Package manager not supported."
                ((errors++))
                return 1
            fi
            
            # Verify installation
            if command -v python3 &> /dev/null; then
                python_version=$(python3 -c "import sys; print('.'.join(map(str, sys.version_info[:2])))")
                log "✓ Python3 installed successfully. Version: $python_version"
            else
                log_error "Failed to install Python3"
                ((errors++))
            fi
        else
            log_error "Python3 not found and no sudo access to install it"
            ((errors++))
        fi
    fi
    
    # Check and install python3-venv package
    log_info "Checking python3-venv availability..."
    test_venv_dir="/tmp/test_venv_$$"
    venv_available=false
    
    # Try to create a test virtual environment
    if python3 -m venv "$test_venv_dir" &> /dev/null; then
        venv_available=true
        rm -rf "$test_venv_dir" 2>/dev/null
        log "✓ python3-venv is available"
    else
        rm -rf "$test_venv_dir" 2>/dev/null
        log_warning "python3-venv package not working properly. Installing required packages..."
        
        if [ "$EUID" -eq 0 ] || sudo -v 2>/dev/null; then
            if command -v apt-get &> /dev/null; then
                # Install both python3-venv and python3-pip to ensure ensurepip works
                sudo apt-get update && sudo apt-get install -y python3-venv python3-pip
            elif command -v yum &> /dev/null; then
                sudo yum install -y python3-venv python3-pip
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y python3-venv python3-pip
            else
                log_error "Cannot install python3-venv automatically. Package manager not supported."
                log_error "Please install python3-venv manually using your package manager"
                ((errors++))
                return 1
            fi
            
            # Verify installation by testing venv creation again
            if python3 -m venv "$test_venv_dir" &> /dev/null; then
                rm -rf "$test_venv_dir" 2>/dev/null
                log "✓ python3-venv installed and working correctly"
                venv_available=true
            else
                rm -rf "$test_venv_dir" 2>/dev/null
                log_error "Failed to install or configure python3-venv properly"
                ((errors++))
            fi
        else
            log_error "python3-venv not working and no sudo access to install it"
            log_error "Please run: sudo apt install python3-venv python3-pip"
            ((errors++))
        fi
    fi
    
    # Check and install Git
    if command -v git &> /dev/null; then
        git_version=$(git --version | cut -d' ' -f3)
        log_info "Git version: $git_version"
        log "✓ Git is available"
    else
        log_warning "Git not found. Installing git..."
        if [ "$EUID" -eq 0 ] || sudo -v 2>/dev/null; then
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y git
            elif command -v yum &> /dev/null; then
                sudo yum install -y git
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y git
            else
                log_error "Cannot install Git automatically. Package manager not supported."
                ((errors++))
                return 1
            fi
            
            # Verify installation
            if command -v git &> /dev/null; then
                git_version=$(git --version | cut -d' ' -f3)
                log "✓ Git installed successfully. Version: $git_version"
            else
                log_error "Failed to install Git"
                ((errors++))
            fi
        else
            log_error "Git not found and no sudo access to install it"
            ((errors++))
        fi
    fi
    
    # Check and install pip
    if command -v pip3 &> /dev/null; then
        pip_version=$(pip3 --version | cut -d' ' -f2)
        log_info "Pip version: $pip_version"
        log "✓ Pip is available"
    else
        log_warning "Pip3 not found. Installing pip3..."
        if [ "$EUID" -eq 0 ] || sudo -v 2>/dev/null; then
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y python3-pip
            elif command -v yum &> /dev/null; then
                sudo yum install -y python3-pip
            elif command -v dnf &> /dev/null; then
                sudo dnf install -y python3-pip
            else
                log_error "Cannot install pip3 automatically. Package manager not supported."
                ((errors++))
                return 1
            fi
            
            # Verify installation
            if command -v pip3 &> /dev/null; then
                pip_version=$(pip3 --version | cut -d' ' -f2)
                log "✓ Pip3 installed successfully. Version: $pip_version"
            else
                log_error "Failed to install pip3"
                ((errors++))
            fi
        else
            log_error "Pip3 not found and no sudo access to install it"
            ((errors++))
        fi
    fi
    
    # Check if running as root or with sudo capabilities
    if [ "$EUID" -eq 0 ]; then
        log "✓ Running with root privileges"
    elif sudo -n true 2>/dev/null; then
        log "✓ Passwordless sudo already configured"
    elif groups | grep -q sudo; then
        log_warning "User is in sudo group but passwordless sudo is not configured"
        log_warning "For seamless Kubernetes deployment, passwordless sudo is recommended"
        echo
        read -p "Do you want to configure passwordless sudo for this user? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Configuring passwordless sudo..."
            
            # Create sudoers file for the user
            sudo_rule="$USER ALL=(ALL) NOPASSWD:ALL"
            sudoers_file="/etc/sudoers.d/$USER"
            
            if echo "$sudo_rule" | sudo tee "$sudoers_file" > /dev/null; then
                sudo chmod 440 "$sudoers_file"
                log "✓ Passwordless sudo configured successfully"
                
                # Verify the configuration
                if sudo -n true 2>/dev/null; then
                    log "✓ Passwordless sudo verification successful"
                else
                    log_warning "Passwordless sudo configuration may not be active yet"
                    log_warning "You may need to start a new shell session"
                fi
            else
                log_error "Failed to configure passwordless sudo"
                log_error "You may need to configure it manually or provide password during deployment"
            fi
        else
            log_warning "Passwordless sudo not configured - you'll be prompted for password during deployment"
        fi
    else
        log_error "Root privileges or sudo access required"
        ((errors++))
    fi
    
    if [ $errors -gt 0 ]; then
        log_error "Prerequisites check failed with $errors error(s). Please resolve them before proceeding."
        return 1
    else
        log "✓ All prerequisites met!"
        return 0
    fi
}

# Function to create virtual environment
create_virtual_environment() {
    log "Creating Python virtual environment..."
    
    if [ -d "$VENV_DIR" ]; then
        log_warning "Virtual environment already exists. Removing it..."
        rm -rf "$VENV_DIR"
    fi
    
    # Create the parent directory if it doesn't exist
    mkdir -p "$(dirname "$VENV_DIR")"
    
    python3 -m venv "$VENV_DIR"
    
    if [ ! -f "$VENV_DIR/bin/activate" ]; then
        log_error "Failed to create virtual environment at $VENV_DIR"
        return 1
    fi
    
    source "$VENV_DIR/bin/activate"
    
    # Verify we're in the virtual environment
    if [ -z "$VIRTUAL_ENV" ]; then
        log_error "Failed to activate virtual environment"
        return 1
    fi
    
    log_info "Virtual environment created at: $VENV_DIR"
    log_info "Virtual environment activated: $VIRTUAL_ENV"
    
    # Upgrade pip
    pip install --upgrade pip
    
    log "✓ Virtual environment created and activated!"
}

# Function to clone Kubespray
clone_kubespray() {
    log "Step 1: Cloning Kubespray repository..."
    
    if [ -d "$KUBESPRAY_DIR" ]; then
        log_warning "Kubespray directory already exists. Removing it..."
        rm -rf "$KUBESPRAY_DIR"
    fi
    
    cd "$USER_HOME"
    git clone https://github.com/kubernetes-sigs/kubespray.git
    cd kubespray
    
    # Get the latest release tag
    log_info "Fetching latest release information..."
    latest_tag=$(git describe --tags $(git rev-list --tags --max-count=1))
    log_info "Latest release found: $latest_tag"
    
    log "Checking out latest release: $latest_tag..."
    git checkout $latest_tag
    
    log "✓ Kubespray cloned successfully with latest version: $latest_tag!"
}

# Function to install requirements
install_requirements() {
    log "Step 2: Installing required tools and dependencies..."
    
    cd "$KUBESPRAY_DIR"
    
    # Ensure we're in the virtual environment
    if [ ! -f "$VENV_DIR/bin/activate" ]; then
        log_error "Virtual environment not found at $VENV_DIR"
        return 1
    fi
    
    source "$VENV_DIR/bin/activate"
    
    # Verify we're in the virtual environment
    if [ -z "$VIRTUAL_ENV" ]; then
        log_error "Failed to activate virtual environment"
        return 1
    fi
    
    log_info "Using virtual environment: $VIRTUAL_ENV"
    
    # Install requirements
    pip install -r requirements.txt
    
    log "✓ Requirements installed successfully!"
}

# Function to create inventory
create_inventory() {
    log "Step 3: Creating inventory for single node cluster..."
    
    cd "$KUBESPRAY_DIR"
    
    # Create inventory directory
    cp -rfp inventory/sample inventory/mycluster
    
    # Enable kubectl and kubeconfig localhost in kubespray configuration
    log "Enabling kubectl localhost in kubespray configuration..."
    sed -i 's/# kubeconfig_localhost: false/kubeconfig_localhost: true/' inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
    sed -i 's/# kubectl_localhost: false/kubectl_localhost: true/' inventory/mycluster/group_vars/k8s_cluster/k8s-cluster.yml
    log "✓ Kubespray localhost configuration updated!"
    
    log "✓ Inventory created successfully!"
}

# Function to configure hosts
configure_hosts() {
    log "Step 4: Configuring hosts.yaml for single node deployment..."
    
    cd "$KUBESPRAY_DIR"
    
    # Get the current hostname and use selected IP
    local hostname=$(hostname)
    local ip_address="$SELECTED_IP"
    
    log_info "Hostname: $hostname"
    log_info "Selected IP Address: $ip_address"
    
    # Create hosts.yaml for single node
    cat > inventory/mycluster/hosts.yaml << EOF
all:
  hosts:
    $hostname:
      ansible_host: $ip_address
      ansible_user: $USER
      ansible_connection: local
      ansible_become: true
      ansible_become_method: sudo
      ip: $ip_address
      access_ip: $ip_address
  children:
    kube_control_plane:
      hosts:
        $hostname:
    kube_node:
      hosts:
        $hostname:
    etcd:
      hosts:
        $hostname:
    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:
    calico_rr:
      hosts: {}
EOF
    
    log "✓ hosts.yaml configured for single node deployment!"
    log_info "Configuration created for node: $hostname ($ip_address)"
}

# Function to setup SSH
setup_ssh() {
    log "Step 5: Setting up SSH key authentication..."
    
    local ssh_dir="$HOME/.ssh"
    
    # Create .ssh directory if it doesn't exist
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    
    # Check if SSH key exists
    if [ ! -f "$ssh_dir/id_rsa" ]; then
        log "Generating SSH key pair..."
        ssh-keygen -t rsa -b 4096 -f "$ssh_dir/id_rsa" -N ""
    else
        log "SSH key already exists"
    fi
    
    # Add key to authorized_keys for localhost
    if [ ! -f "$ssh_dir/authorized_keys" ] || ! grep -q "$(cat $ssh_dir/id_rsa.pub)" "$ssh_dir/authorized_keys"; then
        log "Adding SSH key to authorized_keys..."
        cat "$ssh_dir/id_rsa.pub" >> "$ssh_dir/authorized_keys"
        chmod 600 "$ssh_dir/authorized_keys"
    else
        log "SSH key already in authorized_keys"
    fi
    
    # Test SSH connection
    log "Testing SSH connection to localhost..."
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 localhost "echo 'SSH connection successful'" || {
        log_error "SSH connection test failed"
        return 1
    }
    
    log "✓ SSH setup completed successfully!"
}

# Function to run cluster deployment
deploy_cluster() {
    log "Step 6: Running Kubernetes cluster deployment..."
    
    cd "$KUBESPRAY_DIR"
    
    # Ensure we're in the virtual environment
    if [ ! -f "$VENV_DIR/bin/activate" ]; then
        log_error "Virtual environment not found at $VENV_DIR"
        return 1
    fi
    
    source "$VENV_DIR/bin/activate"
    
    # Verify we're in the virtual environment
    if [ -z "$VIRTUAL_ENV" ]; then
        log_error "Failed to activate virtual environment"
        return 1
    fi
    
    log_info "Using virtual environment: $VIRTUAL_ENV"
    log "Starting Ansible playbook for cluster deployment..."
    log_warning "This process may take 15-30 minutes..."
    
    # Check if we need to handle sudo authentication
    if ! sudo -n true 2>/dev/null; then
        log_warning "Sudo password is required for Ansible to configure the system"
        log_info "You have two options:"
        log_info "1. Run the deployment with --ask-become-pass (you'll be prompted for sudo password)"
        log_info "2. Configure passwordless sudo for your user (recommended for automation)"
        echo
        read -p "Do you want to proceed with password prompt? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Running with sudo password prompt..."
            ansible-playbook -i inventory/mycluster/hosts.yaml --ask-become-pass cluster.yml
        else
            log_error "Deployment cancelled. To enable passwordless sudo, run:"
            log_error "echo '$USER ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/$USER"
            return 1
        fi
    else
        log_info "Passwordless sudo detected, proceeding without password prompt"
        ansible-playbook -i inventory/mycluster/hosts.yaml cluster.yml
    fi
    
    log "✓ Cluster deployment completed!"
}

# Function to label nodes
label_nodes() {
    log "Step 7: Labeling single node for scheduling..."
    
    local hostname=$(hostname)
    
    # Wait for kubectl to be available
    log "Waiting for kubectl to be available..."
    local retries=0
    while [ $retries -lt 30 ]; do
        if command -v kubectl &> /dev/null && kubectl get nodes &> /dev/null; then
            break
        fi
        sleep 10
        ((retries++))
        log_info "Waiting for kubectl... ($retries/30)"
    done
    
    if [ $retries -eq 30 ]; then
        log_error "kubectl not available after waiting"
        return 1
    fi
    
    # Setup kubectl config for user (fallback if kubespray localhost didn't work)
    if [ ! -f ~/.kube/config ]; then
        log "Setting up kubectl configuration for user (fallback)..."
        mkdir -p ~/.kube
        sudo cp /etc/kubernetes/admin.conf ~/.kube/config
        sudo chown $(id -u):$(id -g) ~/.kube/config
        chmod 600 ~/.kube/config
        log "✓ Kubectl configuration completed!"
    else
        log "✓ Kubectl configuration already exists (created by kubespray)!"
    fi
    
    # Remove taint from control plane node to allow scheduling
    log "Removing taint from control plane node to allow pod scheduling..."
    kubectl taint nodes $hostname node-role.kubernetes.io/control-plane- || true
    kubectl taint nodes $hostname node-role.kubernetes.io/master- || true
    
    # Add worker label
    log "Adding worker role label..."
    kubectl label nodes $hostname node-role.kubernetes.io/worker=worker --overwrite
    
    log "✓ Node labeling completed!"
}

# Function to verify installation
verify_installation() {
    log "Verifying Kubernetes installation..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found in PATH"
        return 1
    fi
    
    # Check cluster status
    log "Checking cluster status..."
    kubectl get nodes
    kubectl get pods --all-namespaces
    
    # Check if node is ready
    if kubectl get nodes | grep -q "Ready"; then
        log "✓ Kubernetes cluster is running and ready!"
        return 0
    else
        log_error "Kubernetes cluster is not ready"
        return 1
    fi
}

# Function to display completion message
display_completion() {
    log "🎉 Kubernetes single node deployment completed successfully!"
    echo
    log_info "Cluster Information:"
    echo "- Node: $(hostname)"
    echo "- IP: $SELECTED_IP"
    echo "- Kubectl config: ~/.kube/config"
    echo "- Kubespray artifacts: $KUBESPRAY_DIR/inventory/mycluster/artifacts/ (if generated)"
    echo
    log_info "Useful commands:"
    echo "- Check nodes: kubectl get nodes"
    echo "- Check pods: kubectl get pods --all-namespaces"
    echo "- Check services: kubectl get services --all-namespaces"
    echo
    log_info "Virtual environment location: $VENV_DIR"
    log_info "To activate virtual environment: source $VENV_DIR/bin/activate"
}

# Function to cleanup on error
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up..."
    
    # Optionally remove created directories
    read -p "Do you want to remove created directories? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        [ -d "$KUBESPRAY_DIR" ] && rm -rf "$KUBESPRAY_DIR"
        [ -d "$VENV_DIR" ] && rm -rf "$VENV_DIR"
        log "Cleanup completed."
    fi
}

# Main function
main() {
    echo "================================================="
    echo "  Kubernetes Single Node Deployment Script"
    echo "  Using Kubespray (Latest Version)"
    echo "================================================="
    echo
    
    # Ask user if they want to proceed
    echo "This script will deploy a single-node Kubernetes cluster using Kubespray."
    echo "The deployment will:"
    echo "- Check system prerequisites"
    echo "- Create a Python virtual environment"
    echo "- Download and configure Kubespray (latest version)"
    echo "- Deploy Kubernetes with all components on this single node"
    echo
    
    read -p "Do you want to proceed with Kubernetes single node deployment? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user."
        exit 0
    fi
    
    echo
    log "Starting Kubernetes single node deployment..."
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Execute deployment steps
    check_prerequisites || exit 1
    
    select_ip_address || exit 1
    
    create_virtual_environment || exit 1
    
    clone_kubespray || exit 1
    
    install_requirements || exit 1
    
    create_inventory || exit 1
    
    configure_hosts || exit 1
    
    setup_ssh || exit 1
    
    deploy_cluster || exit 1
    
    label_nodes || exit 1
    
    verify_installation || exit 1
    
    display_completion
    
    log "🚀 Deployment completed successfully!"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi