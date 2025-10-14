# Nutanix Event Notification Service - Complete Deployment Guide

## Overview

This guide provides step-by-step instructions for deploying the complete Nutanix Event Notification Service ecosystem. The service monitors Nutanix infrastructure changes and automatically triggers Ansible AWX job templates for infrastructure automation.

**Two Deployment Paths Available:**

🏗️ **Path A: I have Kubernetes** - Use your existing Kubernetes cluster (single-node or multi-node)

🚀 **Path B: I need Kubernetes** - We'll install a single-node Kubernetes cluster for you using our automated script

**Note**: The automated Kubernetes installation (`k8s_deploy.sh`) creates a **single-node cluster only**. If you need a multi-node cluster, please install Kubernetes manually and use Path A.

## Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Nutanix AHV   │    │   Apstra DC     │    │   Kubernetes    │
│   Prism Central │◄───┤   Fabric        │◄───┤   Cluster       │
│                 │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    │ ┌─────────────┐ │
                                              │ │     AWX     │ │
┌─────────────────┐                          │ └─────────────┘ │
│ Event Service   │◄─────────────────────────┤ ┌─────────────┐ │
│ (Docker/K8s)    │                          │ │   Nutanix   │ │
│                 │                          │ │   Service   │ │
└─────────────────┘                          │ └─────────────┘ │
                                             └─────────────────┘
```

## Prerequisites

Before starting the deployment, ensure you have the following components installed and configured:

### 1. Infrastructure Requirements

#### Nutanix Environment
- ✅ **Nutanix AHV**: v.10.0.1.1 or later
- ✅ **Nutanix AOS**: 7.3.0.5 or later
- ✅ **Prism Central**: Deployed and accessible
- ✅ **Network Access**: Prism Central accessible via HTTPS (port 9440)
- ✅ **Credentials**: Admin user credentials for API access

#### Apstra Environment
- ✅ **Apstra Version**: 6.0 or 6.1
- ✅ **Day-0 Onboarding**: Complete (devices discovered, blueprints created)
- ✅ **Network Access**: Apstra server accessible via HTTPS (port 443)
- ✅ **Credentials**: Admin user credentials for API access
- ✅ **Blueprints**: At least one blueprint configured and committed

#### Kubernetes Environment
**Choose ONE of the following options:**

**Option A: Existing Kubernetes Cluster**
- ✅ **Kubernetes Version**: 1.31 or later
- ✅ **Cluster Type**: Single-node or multi-node (both supported)
- ✅ **kubectl**: Configured and connected to cluster
- ✅ **Storage**: Persistent volume support (local-path, NFS, or other)
- ✅ **Helm**: v3.0+ installed
- ✅ **Resources**: Minimum 4 CPU cores, 8GB RAM, 50GB storage

**Option B: No Kubernetes (We'll install it for you)**
- ✅ **Linux Server**: Ubuntu 20.04+, CentOS 8+, or RHEL 8+
- ✅ **Resources**: Minimum 2 CPU cores, 4GB RAM, 20GB storage
- ✅ **Root/Sudo Access**: Required for Kubernetes installation
- ✅ **Python**: 3.10+ (script will install if missing)
- ✅ **Internet Access**: Required to download Kubernetes components

### 2. Network Connectivity Requirements

All components must have network connectivity:

```
Kubernetes Cluster ←→ Nutanix Prism Central (port 9440)
Kubernetes Cluster ←→ Apstra Server (port 443)
Event Service ←→ AWX (via NodePort)
AWX ←→ Apstra Server (port 443)
```

### 3. Software Requirements

#### On Deployment Host

**For Existing Kubernetes Users:**
- ✅ **Git**: For cloning repositories
- ✅ **kubectl**: Kubernetes command-line tool (configured)
- ✅ **Helm**: Package manager for Kubernetes v3.0+
- ✅ **Docker**: (Optional) If deploying service as Docker container
- ✅ **Bash**: Shell environment for running scripts

**For New Kubernetes Installation:**
- ✅ **Git**: For cloning repositories  
- ✅ **Sudo Access**: Required for Kubernetes installation
- ✅ **Internet Access**: Required to download components
- ✅ **Bash**: Shell environment for running scripts
- ✅ **Python 3.10+**: (Script will install if missing)

**Note**: kubectl, Helm, and Docker will be installed automatically by the `k8s_deploy.sh` script.

### 4. Credentials Required

Prepare the following credentials:
- **Nutanix Prism Central**: Username/password with admin privileges
- **Apstra**: Username/password with admin privileges
- **Kubernetes**: kubectl access with cluster-admin privileges

---

## Deployment Steps

### Step 1: Prepare Environment

#### 1.1 Clone the Repository

```bash
# Clone the repository
git clone https://github.com/Juniper/eda-apstra-project.git
cd eda-apstra-project
git checkout nutanix
```

#### 1.2 Choose Your Kubernetes Setup

**Option A: I have Kubernetes already installed**

Skip to Step 1.3 to verify your existing cluster.

**Option B: I need to install Kubernetes**

Use our automated single-node Kubernetes installation:

```bash
cd deploy/nutanix/scripts/
chmod +x k8s_deploy.sh
./k8s_deploy.sh
```

The script will:
- ✅ Check system requirements (CPU, RAM, disk space)
- ✅ Install Python 3.10+ if missing
- ✅ Clone and setup Kubespray
- ✅ Create Python virtual environment
- ✅ Install Ansible and dependencies
- ✅ Configure single-node Kubernetes cluster
- ✅ Install kubectl and configure access
- ✅ Install local-path storage provisioner
- ✅ Install Helm package manager

**Installation Process:**
1. **System Check**: Verifies minimum requirements (2 CPU, 4GB RAM, 20GB disk)
2. **IP Selection**: Choose which network interface to use for Kubernetes
3. **Automated Setup**: ~15-30 minutes depending on internet speed
4. **Verification**: Confirms cluster is ready and accessible

**After installation completes:**
```bash
# Verify cluster is working
kubectl get nodes
kubectl get pods -A

# Check storage class
kubectl get storageclass
```

#### 1.3 Verify Kubernetes Cluster (For Both Options)

```bash
# Check cluster status
kubectl cluster-info
kubectl get nodes

# Verify you have admin access
kubectl auth can-i '*' '*'

# Ensure you have a storage class
kubectl get storageclass
```

#### 1.4 Install Helm (if not installed)

```bash
# Check if Helm is installed
helm version

# If not installed, install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installation
helm version
```

### Step 2: Deploy AWX on Kubernetes

AWX (Ansible Automation Platform) must be deployed on Kubernetes regardless of how you plan to deploy the Nutanix service.

#### 2.1 Run AWX Deployment Script

Navigate to the scripts directory and run the AWX deployment script:

```bash
cd deploy/nutanix/scripts/
chmod +x awx_deploy.sh
./awx_deploy.sh
```

The script will:
- Check prerequisites (kubectl, helm)
- Detect available storage classes
- Deploy AWX operator using Helm
- Create AWX instance with persistent storage
- Wait for deployment to complete
- Display AWX access information

#### 2.2 Script Options

**Interactive Mode (Recommended):**
```bash
./awx_deploy.sh
```
The script will show available storage classes and let you choose.

**Automated Mode with Specific Storage:**
```bash
# Use local-path storage
STORAGE_CLASS_OVERRIDE=local-path ./awx_deploy.sh

# Use NFS storage
STORAGE_CLASS_OVERRIDE=nfs-client ./awx_deploy.sh
```

#### 2.3 Verify AWX Deployment

After successful deployment:

```bash
# Check AWX pods
kubectl get pods -n aap

# Check AWX service
kubectl get svc -n aap

# Get AWX admin password
kubectl get secret ansible-awx-admin-password -n aap -o jsonpath='{.data.password}' | base64 -d
```

**Expected Output:**
```
NAME                                           READY   STATUS    RESTARTS   AGE
ansible-awx-operator-controller-manager-xxx    1/1     Running   0          5m
ansible-awx-postgres-13-0                      1/1     Running   0          4m
ansible-awx-task-xxx                           4/4     Running   0          3m
ansible-awx-web-xxx                            3/3     Running   0          3m
```

#### 2.4 Access AWX Web Interface

Get the NodePort and access AWX:

```bash
# Get NodePort
kubectl get svc ansible-awx-service -n aap

# Access AWX at: http://<your-node-ip>:<nodeport>
# Username: admin
# Password: (from step 2.3)
```

### Step 3: Configure AWX

Once AWX is deployed, configure it with Apstra credentials and job templates.

#### 3.1 Run AWX Configuration Script

```bash
# Ensure you're in the scripts directory
cd deploy/nutanix/scripts/
chmod +x configure_awx.sh
./configure_awx.sh
```

#### 3.2 Configuration Process

The script will prompt you for:

1. **Apstra Configuration:**
   - Apstra server URL (e.g., `https://10.84.106.91`)
   - Username (admin or your Apstra user)
   - Password

2. **Kubernetes Configuration:**
   - Kubernetes API server URL (auto-detected)
   - Cluster configuration (auto-generated)

3. **Project Configuration:**
   - Repository URL (defaults to this project)
   - Branch (defaults to 'nutanix')

#### 3.3 What the Script Does

The configuration script automatically:
- ✅ Creates Kubernetes RBAC (ServiceAccount, ClusterRole, ClusterRoleBinding)
- ✅ Clones the project repository
- ✅ Creates AWX credentials for Apstra and Kubernetes
- ✅ Creates AWX inventory and execution environment
- ✅ Creates AWX project pointing to your repository
- ✅ Creates job templates:
  - `create-vrf` (Security Zone creation)
  - `delete-vrf` (Security Zone deletion)
  - `create-vnet` (Virtual Network creation)
  - `delete-vnet` (Virtual Network deletion)
  - `create-connectivity-template` (Connectivity template)
  - `delete-connectivity-template` (Connectivity template deletion)

#### 3.4 Verify AWX Configuration

After configuration:

```bash
# Check if job templates were created
# Login to AWX web interface and verify:
# - Templates tab shows 6 job templates
# - Credentials tab shows Apstra and Kubernetes credentials
# - Projects tab shows eda-apstra-project
# - Inventories tab shows "Apstra Inventory"
```

### Step 4: Deploy Nutanix Event Notification Service

Now deploy the service that monitors Nutanix infrastructure and triggers AWX jobs.

#### 4.1 Run Nutanix Service Deployment Script

```bash
# Ensure you're in the scripts directory
cd deploy/nutanix/scripts/
chmod +x deploy_nutanix_service.sh
./deploy_nutanix_service.sh
```

#### 4.2 Deployment Options

The script will prompt you to choose:

**Option 1: Kubernetes Deployment (Recommended)**
- Deploys as Kubernetes pod
- Uses ConfigMaps and Secrets for configuration
- Automatic restart and health monitoring
- Better for production environments

**Option 2: Docker Container**
- Deploys as standalone Docker container
- Uses environment file for configuration
- Simpler for development/testing

#### 4.3 Configuration Input

The script will automatically detect AWX configuration and prompt for:

1. **Nutanix Configuration:**
   - Prism Central IP address
   - Port (default: 9440)
   - Username
   - Password

2. **Additional Settings:**
   - Kubernetes namespace (if using Kubernetes deployment)
   - Blueprint name (optional, default: apstra-ntx-bp)

**AWX configuration is automatically detected:**
- Host: Kubernetes node IP
- Port: AWX NodePort
- Username: admin
- Password: Extracted from AWX secret

#### 4.4 Monitor Deployment

**For Kubernetes Deployment:**
```bash
# Check pod status
kubectl get pods -l app=event-notification-service

# View logs
kubectl logs -f deployment/event-notification-service

# Check configuration
kubectl get configmap nutanix-eda-config -o yaml
kubectl get secret nutanix-eda-secrets -o yaml
```

**For Docker Deployment:**
```bash
# Check container status
docker ps | grep nutanix-event-service

# View logs
docker logs -f nutanix-event-service

# Check environment variables
docker exec nutanix-event-service env | grep NUTANIX
```

---

## Verification and Testing

### Step 5: Verify End-to-End Functionality

#### 5.1 Check Service Startup

Look for these messages in the service logs:

```
✅ All required configuration loaded from ConfigMap environment variables
✅ v3 Subnets API: X subnets available
✅ v3 VMs API: X VMs available
✅ Ansible Tower connection successful
👀 Starting v3 event monitoring...
🔍 Watching SUBNETS & VMS & VIRTUAL SWITCHES for: CREATION | MODIFICATION | DELETION
```

#### 5.2 Test Infrastructure Event Detection

**Create a test subnet in Nutanix:**

1. Login to Prism Central
2. Go to Network & Security → Virtual Private Clouds
3. Create a new subnet
4. Monitor the service logs for event detection

**Expected Log Output:**
```
🌐 SUBNET CREATED! (v3) 🌐
📅 Detection Time: 2025-10-14 15:30:00
🆔 Subnet UUID: xxxxx-xxxxx-xxxxx
📛 Name: test-subnet
🎯 Processing NETWORK CREATED event for Ansible automation
✅ Found job template 'create-vnet' with ID: X
🚀 Launching job template: create-vnet
✅ Job launched successfully!
   Job ID: X
   Job URL: http://x.x.x.x:xxxxx/#/jobs/X
```

#### 5.3 Verify AWX Job Execution

1. Login to AWX web interface
2. Go to Jobs tab
3. Verify that jobs are being triggered when infrastructure changes occur
4. Check job output for successful execution

### Step 6: Troubleshooting

#### Kubernetes Installation Issues

**1. Insufficient Resources:**
```bash
# If k8s_deploy.sh fails due to resources:
# Check current usage
free -h
df -h
nproc

# The script requires minimum: 2 CPU, 4GB RAM, 20GB disk
# For better performance, use: 4 CPU, 8GB RAM, 50GB disk
```

**2. Network Issues During Installation:**
```bash
# If download fails, check internet connectivity
ping -c 3 8.8.8.8

# If behind proxy, set proxy environment variables
export http_proxy=http://proxy-server:port
export https_proxy=http://proxy-server:port
```

**3. Python/Ansible Issues:**
```bash
# If Python installation fails, install manually
sudo apt-get update
sudo apt-get install -y python3 python3-venv python3-pip

# If Ansible fails, check virtual environment
source ~/k8s-venv/bin/activate
pip install --upgrade ansible
```

**4. Kubernetes Cluster Not Ready:**
```bash
# Check kubelet status
sudo systemctl status kubelet

# Check kubernetes pods
kubectl get pods -A

# If pods are failing, check logs
kubectl logs -n kube-system <pod-name>
```

#### Service-Specific Issues

**1. Service Cannot Connect to Nutanix:**
```bash
# Check network connectivity
kubectl exec deployment/event-notification-service -- curl -k https://PRISM-IP:9440/api/nutanix/v3/clusters

# Verify credentials
kubectl get secret nutanix-eda-secrets -o yaml
```

**2. Service Cannot Connect to AWX:**
```bash
# Check AWX service
kubectl get svc -n aap ansible-awx-service

# Test connectivity
kubectl exec deployment/event-notification-service -- curl http://AWX-IP:PORT/api/v2/ping/
```

**3. No Events Detected:**
```bash
# Check monitoring flags
kubectl exec deployment/event-notification-service -- env | grep MONITORING

# Verify Nutanix API access
kubectl logs deployment/event-notification-service | grep "API"
```

**4. AWX Jobs Not Triggering:**
```bash
# Check job templates exist
kubectl logs deployment/event-notification-service | grep "job template"

# Verify AWX credentials
kubectl logs deployment/event-notification-service | grep "Ansible Tower"
```

#### Recovery Procedures

**1. Restart Kubernetes Installation:**
```bash
# If k8s_deploy.sh fails, clean up and retry
sudo kubeadm reset -f
sudo rm -rf ~/.kube
rm -rf ~/k8s-venv ~/kubespray

# Then run the script again
./k8s_deploy.sh
```

**2. Reinstall AWX:**
```bash
# Remove AWX completely
helm uninstall ansible-awx -n aap
kubectl delete namespace aap

# Wait for cleanup, then redeploy
./awx_deploy.sh
```

**3. Reset Nutanix Service:**
```bash
# Kubernetes deployment
kubectl delete deployment event-notification-service
kubectl delete configmap nutanix-eda-config
kubectl delete secret nutanix-eda-secrets

# Docker deployment
docker stop nutanix-event-service
docker rm nutanix-event-service

# Then redeploy
./deploy_nutanix_service.sh
```

---

## Configuration Reference

### Default Configuration Values

The service uses sensible defaults when configuration is not specified:

```yaml
# Monitoring (all enabled by default)
MONITORING_CHECK_INTERVAL: "5"          # seconds
MONITORING_MONITOR_NETWORKS: "true"
MONITORING_MONITOR_VMS: "true"
MONITORING_MONITOR_VIRTUAL_SWITCHES: "true"

# Job Templates (default AWX job names)
JOB_TEMPLATE_NETWORK_CREATE: "create-vnet"
JOB_TEMPLATE_NETWORK_DELETE: "delete-vnet"
JOB_TEMPLATE_VIRTUAL_SWITCH_CREATE: "create-vrf"
JOB_TEMPLATE_VIRTUAL_SWITCH_DELETE: "delete-vrf"

# Ansible Settings (enabled by default)
ANSIBLE_ENABLED: "true"
ANSIBLE_MAX_RETRIES: "3"
ANSIBLE_RETRY_DELAY: "5"
```

### File Locations

```
eda-apstra-project/
├── deploy/nutanix/
│   ├── scripts/
│   │   ├── awx_deploy.sh           # AWX deployment
│   │   ├── configure_awx.sh        # AWX configuration
│   │   └── deploy_nutanix_service.sh # Service deployment
│   └── files/
│       ├── deployment.yaml         # Kubernetes deployment
│       ├── unified-configmap.yaml  # Configuration template
│       ├── unified-secret.yaml     # Secrets template
│       └── nutanix-eda-docker.env  # Docker environment template
└── playbooks/                      # Ansible playbooks for job templates
    ├── ntx-create-sz.yml           # Create security zone
    ├── ntx-delete-sz.yml           # Delete security zone
    ├── ntx-create-vnet.yml         # Create virtual network
    └── ntx-delete-vnet.yml         # Delete virtual network
```

---

## Maintenance and Operations

### Monitoring Service Health

```bash
# Kubernetes deployment
kubectl get pods -l app=event-notification-service
kubectl logs -f deployment/event-notification-service

# Docker deployment
docker ps | grep nutanix-event-service
docker logs -f nutanix-event-service
```

### Updating Configuration

**Kubernetes:**
```bash
# Update ConfigMap
kubectl edit configmap nutanix-eda-config

# Update Secret
kubectl edit secret nutanix-eda-secrets

# Restart deployment
kubectl rollout restart deployment event-notification-service
```

**Docker:**
```bash
# Update environment file and restart container
docker stop nutanix-event-service
docker rm nutanix-event-service
# Edit nutanix-eda-docker.env
docker run -d --name nutanix-event-service --env-file nutanix-eda-docker.env <image>
```

### Scaling (Kubernetes only)

```bash
# Scale to multiple replicas
kubectl scale deployment event-notification-service --replicas=2

# Update resource limits
kubectl edit deployment event-notification-service
```

---

## Support and Documentation

### Log Analysis

The service provides detailed logging for troubleshooting:
- Infrastructure event detection
- AWX job template execution
- Configuration loading
- API connectivity status

### Useful Commands

```bash
# Get service version
kubectl exec deployment/event-notification-service -- python -c "print('Service running')"

# Test configuration
kubectl exec deployment/event-notification-service -- python unified_config_manager.py

# Manual job trigger (for testing)
# Access AWX web interface and manually run job templates
```

---

## Conclusion

This guide provides a complete deployment workflow for the Nutanix Event Notification Service. The service will:

1. ✅ Monitor Nutanix infrastructure for changes
2. ✅ Detect network, VM, and virtual switch events
3. ✅ Automatically trigger corresponding AWX job templates
4. ✅ Execute Ansible playbooks to maintain Apstra configuration
5. ✅ Provide comprehensive logging and monitoring

For additional support or customization, refer to the project repository and documentation.