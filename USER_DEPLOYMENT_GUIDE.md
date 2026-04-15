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
┌─────────────────┐                           │ └─────────────┘ │
│ Event Service   │◄─────────────────────────-┤ ┌─────────────┐ │
│ (Docker/K8s)    │                           │ │   Nutanix   │ │
│                 │                           │ │   Service   │ │
└─────────────────┘                           │ └─────────────┘ │
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
- ✅ **CPU Architecture**: x86-64-v2 or newer — required by AWX's PostgreSQL 15 container.
  Verify with: `grep -m1 flags /proc/cpuinfo | tr ' ' '\n' | grep -E 'sse4_1|sse4_2|ssse3|popcnt'` — all four must appear.
  > ⚠️ **QEMU/KVM VMs with CPU model `qemu64` or `QEMU Virtual CPU v2.5+` will fail** at the PostgreSQL
  > pod start-up with `Fatal glibc error: CPU does not support x86-64-v2`.
  > Fix in your hypervisor: set CPU model to **`host`** (pass-through) or at minimum **`Skylake-Client`** before deploying.

**Option B: No Kubernetes (We'll install it for you)**
- ✅ **Linux Server**: Ubuntu 20.04+, CentOS 8+, or RHEL 8+
- ✅ **Resources**: Minimum 2 CPU cores, 4GB RAM, 20GB storage
- ✅ **Root/Sudo Access**: Required for Kubernetes installation
- ✅ **Python**: 3.10+ (script will install if missing)
- ✅ **Internet Access**: Required to download Kubernetes components
- ✅ **CPU Architecture**: x86-64-v2 or newer (same requirement as Option A above)

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
- ✅ **Docker**: Required to load the Nutanix plugin image. Install with `sudo apt-get install -y docker.io` then add your user to the docker group: `sudo usermod -aG docker $USER` (re-login required)
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

## Build the Execution Environment (EE)

AWX requires an **Execution Environment** (EE) container image that bundles the Ansible collection and the Apstra SDK. The published image
`apstra-ee:1.0.5` ships `aos-sdk 0.1.0` (Apstra 5.1). To work with **Apstra 6.1**, you must rebuild the image with `aos-sdk 6.1.0` and
collection `1.0.6`.

> **Note:** You only need to do this once. After uploading the image to AWX, all job templates will use it automatically.

### EE Build Prerequisites

| Requirement | Version |
|---|---|
| Git | Any recent version |
| Docker | 20.10+ |
| Python | 3.11 |
| `ansible-builder` | 3.x (`pip install ansible-builder`) |
| Red Hat registry account | Required for base image — [register free at](https://access.redhat.com) |
| Juniper Support account | Required to download the Apstra SDK |

---

### EE Step 1: Clone the Apstra Ansible Collection

```bash
git clone https://github.com/Juniper/apstra-ansible-collection.git
cd apstra-ansible-collection
```

---

### EE Step 2: Download the Apstra SDK Wheel

The Apstra SDK (`aos_sdk`) is **not** on PyPI and is **not committed to this repository** — it must be downloaded from the Juniper Support portal and placed in `build/wheels/` **before** running any `make` targets.

> ⚠️ **Critical — do this before `make pipenv` or `make image`:**  
> If `build/wheels/` contains no SDK wheel, `make pipenv` automatically falls back to downloading
> `aos_sdk-0.1.0` (Apstra 5.1 SDK). That older SDK is **not compatible** with Apstra 6.0 / 6.1
> and will cause blueprint commit/unlock failures at runtime.

**Steps:**

1. Go to: **https://support.juniper.net/support/downloads/?p=apstra**
2. Under **"Application Tools"** locate **"Apstra Automation Python3 SDK"**.
3. Download the `.tar.gz` archive (e.g. `apstra-automation-python3-sdk-6.1.0.tar.gz`).
4. Extract the wheel file:

   ```bash
   tar -xzf apstra-automation-python3-sdk-*.tar.gz
   find . -name "aos_sdk-*.whl"
   ```

5. Create the `build/wheels/` directory and place the wheel there:

   ```bash
   mkdir -p apstra-ansible-collection/build/wheels/
   cp /path/to/aos_sdk-6.1.0-py3-none-any.whl apstra-ansible-collection/build/wheels/
   ```

6. Verify it is in place:

   ```bash
   ls apstra-ansible-collection/build/wheels/
   # Expected: aos_sdk-6.1.0-py3-none-any.whl
   ```

> **Offline / air-gapped:** If your Juniper SE has provided the wheel file directly, skip steps 1–4 and copy it straight to `build/wheels/`.

---

### EE Step 3: Set Up the Python Environment

> **Prerequisite:** The `aos_sdk-6.1.0-py3-none-any.whl` must already be in `build/wheels/` (Step 2 above).

The `make pipenv` target detects the highest-versioned `aos_sdk-*.whl` in `build/wheels/`, updates `Pipfile` to reference it, and installs all dependencies:

```bash
cd apstra-ansible-collection
make pipenv
```

This will:
- Install `pipenv` and `pre-commit` if missing
- Pick `aos_sdk-6.1.0-py3-none-any.whl` from `build/wheels/` automatically
- Update `Pipfile` to reference that wheel
- Install all Python dependencies

Confirm the correct wheel was selected in the `make pipenv` output:
```
Using aos_sdk wheel: aos_sdk-6.1.0-py3-none-any.whl
```
If you see `aos_sdk-0.1.0` here, the 6.1.0 wheel was not found — go back to Step 2.

---

### EE Step 4: Build the Collection Tarball

```bash
make build
```

This runs `ansible-galaxy collection build` and produces `juniper-apstra-1.0.6.tar.gz`.

---

### EE Step 5: Configure Red Hat Registry Credentials

`ansible-builder` pulls the base image `registry.redhat.io/ansible-automation-platform-25/ee-minimal-rhel8:1.0`.
Create a `.env` file in the repo root (it is git-ignored):

```bash
cat > .env << 'EOF'
RH_USERNAME=your-redhat-username
RH_PASSWORD=your-redhat-password
EOF
```

> **Tip:** If you already have a Red Hat service account token, use the token username/password from
> **https://access.redhat.com/terms-based-registry/**.

Optionally set `REGISTRY_URL` to push directly to Artifactory after the build:

```bash
echo "REGISTRY_URL=s-artifactory.juniper.net/atom-docker/ee" >> .env
```

---

### EE Step 6: Build the Image

```bash
# Loads .env automatically via pipenv
make image
```

What this does:
1. Copies `juniper-apstra-1.0.6.tar.gz` → `build/collections/juniper-apstra.tar.gz`
2. Runs `build/build_image.sh` which calls `ansible-builder build -f build/ee-builder.yml`
3. The builder:
   - Pulls the RH base image (requires `RH_USERNAME` / `RH_PASSWORD`)
   - Installs `aos_sdk-6.1.0` via the wheel copied into the image
   - Installs the `juniper.apstra 1.0.6` collection
   - Installs `kubernetes.core` and `community.general` collections
4. Tags the resulting image `apstra-ee:1.0.6`
5. Exports it as `apstra-ee-<platform>-1.0.6.image.tgz`
6. If `REGISTRY_URL` is set — pushes `apstra-ee:1.0.6` to your registry

**Build takes ~10–15 minutes** on first run (base image download + RPM installs).

> **Note for customizers:** The RH base image does not have `pip` on `PATH`. Any custom `RUN` steps in `ee-builder.yml` that install Python packages must use `python3 -m pip install` instead of bare `pip install`.

---

### EE Step 7: Verify the Built Image

```bash
docker run --rm apstra-ee:1.0.6 bash -c "
  pip show aos-sdk
  ansible-galaxy collection list juniper.apstra
"
```

Expected output:

```
Name: aos-sdk
Version: 6.1.0
...
Collection      Version
--------------- -------
juniper.apstra  1.0.6
```

---

### EE Step 8: Upload the Image to AWX

#### Option A — Push to a Registry and Configure AWX to Pull It

```bash
# Tag for your registry (if not done automatically by make image)
docker tag apstra-ee:1.0.6 s-artifactory.juniper.net/atom-docker/ee/apstra-ee:1.0.6

# Push
docker push s-artifactory.juniper.net/atom-docker/ee/apstra-ee:1.0.6
```

In AWX: **Administration → Execution Environments → Add**
- **Name:** `apstra-ee`
- **Image:** `s-artifactory.juniper.net/atom-docker/ee/apstra-ee:1.0.6`
- **Pull:** `Always`

#### Option B — Import the Exported `.tgz` Directly into the Node

```bash
# Copy the tgz to the Kubernetes node and import
scp apstra-ee-x86_64-1.0.6.image.tgz user@k8s-node:~
ssh user@k8s-node "docker load -i ~/apstra-ee-x86_64-1.0.6.image.tgz"
```

---

### EE Compatibility Matrix

| EE Image Tag | Collection | aos-sdk | Apstra Server |
|---|---|---|---|
| `apstra-ee:1.0.5` | 1.0.5 | 0.1.0 | 5.1.x |
| `apstra-ee:1.0.6` | 1.0.6 | 6.1.0 | 6.0 / 6.1 |

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

1. **Apstra Version** (new — selects the correct Execution Environment image):
   - `1` → Apstra 6.0  (EE image: `apstra-ee:1.0.6`)
   - `2` → Apstra 6.1  (EE image: `apstra-ee:1.0.6`)

2. **Apstra Configuration:**
   - Apstra server URL (e.g., `https://10.84.106.91`)
   - Username (admin or your Apstra user)
   - Password

3. **Kubernetes Configuration:**
   - Kubernetes API server URL (auto-detected)
   - Cluster configuration (auto-generated)

4. **Project Configuration:**
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

### Step 4: Download and Load the Nutanix Plugin Image

Before deploying the Nutanix Event Notification Service you must obtain the official container image from Juniper and make it available to Docker / the Kubernetes node. **The image is not pulled from a public registry — it must be loaded manually.**

#### 4.0 Identify Your Plugin Version

Choose the plugin package that matches your Apstra server version:

| Apstra Version | Plugin Package | Image Tag | ~Size |
|---|---|---|---|
| **6.0** | `juniper-nutanix-plugin-6.0.0.tgz` | `event-notification-service:6.0.0` | ~63 MB |
| **6.1** | `juniper-nutanix-plugin-6.1.0.tgz` | `event-notification-service:6.1.0` | ~63 MB |

All commands below show `<PLUGIN_VERSION>` as a placeholder — substitute `6.0.0` or `6.1.0` according to the table above.

#### 4.1 Download the Plugin Package

1. Open a browser and go to:  
   **https://support.juniper.net/support/downloads/?p=apstra**
2. Sign in with your Juniper support account.
3. Under **"Nutanix"** (or **"Juniper Nutanix Plugin"**), locate the release that matches your Apstra version:
   - Apstra **6.0** → **Juniper Nutanix Plugin 6.0.0**
   - Apstra **6.1** → **Juniper Nutanix Plugin 6.1.0** (released 08 Apr 2026, ~63 MB)
4. Download the `.tgz` archive (e.g. `juniper-nutanix-plugin-6.1.0.tgz`).
5. Download the associated **Checksums** file and verify integrity:

```bash
# Replace <PLUGIN_VERSION> with 6.0.0 or 6.1.0
sha256sum juniper-nutanix-plugin-<PLUGIN_VERSION>.tgz
# Compare output against the checksum listed on the download page
```

#### 4.2 Load the Image into Docker

```bash
# Replace <PLUGIN_VERSION> with your version (6.0.0 or 6.1.0)
docker load -i juniper-nutanix-plugin-<PLUGIN_VERSION>.tgz
```

Confirm the image was loaded and note the tag printed by Docker:

```bash
docker images | grep event-notification-service
# Expected output:
# event-notification-service   6.0.0   <image-id>   ...   (for Apstra 6.0)
# event-notification-service   6.1.0   <image-id>   ...   (for Apstra 6.1)
```

> **Note:** If the loaded tag differs from `event-notification-service:<PLUGIN_VERSION>`, re-tag it before proceeding:
> ```bash
> docker tag <loaded-name>:<loaded-tag> event-notification-service:<PLUGIN_VERSION>
> ```

#### 4.3 Make the Image Available on the Kubernetes Node (Kubernetes Deployment Only)

Kubernetes uses `containerd` as its container runtime (installed by `k8s_deploy.sh`). You must import the image directly into `containerd`'s `k8s.io` namespace — simply loading it into Docker is **not** sufficient for Kubernetes pods to find it.

**Option A — Import the tgz directly into containerd (recommended):**

```bash
# Replace <PLUGIN_VERSION> with 6.0.0 or 6.1.0
sudo ctr -n k8s.io images import juniper-nutanix-plugin-<PLUGIN_VERSION>.tgz
```

Verify the image is visible to containerd:

```bash
sudo ctr -n k8s.io images ls | grep event-notification-service
```

**Option B — Transfer from Docker daemon to containerd:**

```bash
# Replace <PLUGIN_VERSION> with 6.0.0 or 6.1.0
docker save event-notification-service:<PLUGIN_VERSION> | sudo ctr -n k8s.io images import -
```

#### 4.4 Verify the Image is Ready

```bash
# For Docker deployments — replace <PLUGIN_VERSION> with 6.0.0 or 6.1.0
docker inspect event-notification-service:<PLUGIN_VERSION> --format '{{.Id}}' | head -c 12

# For Kubernetes deployments — confirm containerd can see it
sudo crictl images | grep event-notification-service
# or
sudo ctr -n k8s.io images ls | grep event-notification-service
```

Once the image is available, proceed to Step 5.

---

### Step 5: Deploy Nutanix Event Notification Service

Now deploy the service that monitors Nutanix infrastructure and triggers AWX jobs.

#### 5.1 Run Nutanix Service Deployment Script

```bash
# Ensure you're in the scripts directory
cd deploy/nutanix/scripts/
chmod +x deploy_nutanix_service.sh
./deploy_nutanix_service.sh
```

The script will first ask which Apstra version you are running and will select the correct plugin image (`event-notification-service:6.0.0` or `event-notification-service:6.1.0`) automatically for the rest of the deployment.

#### 5.2 Deployment Options

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

#### 5.3 Configuration Input

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

#### 5.4 Monitor Deployment

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

### Step 6: Verify End-to-End Functionality

#### 6.1 Check Service Startup

Look for these messages in the service logs:

```
✅ All required configuration loaded from ConfigMap environment variables
✅ v3 Subnets API: X subnets available
✅ v3 VMs API: X VMs available
✅ Ansible Tower connection successful
👀 Starting v3 event monitoring...
🔍 Watching SUBNETS & VMS & VIRTUAL SWITCHES for: CREATION | MODIFICATION | DELETION
```

#### 6.2 Test Infrastructure Event Detection

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

#### 6.3 Verify AWX Job Execution

1. Login to AWX web interface
2. Go to Jobs tab
3. Verify that jobs are being triggered when infrastructure changes occur
4. Check job output for successful execution

### Step 7: Troubleshooting

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

**0. Nutanix Plugin Image Not Found:**
```bash
# deploy_nutanix_service.sh will error with, e.g.:
# "Image 'event-notification-service:6.1.0' not found in local Docker daemon."

# Fix: download and load the correct image for your Apstra version (see Step 4):
#   Apstra 6.0 → juniper-nutanix-plugin-6.0.0.tgz
#   Apstra 6.1 → juniper-nutanix-plugin-6.1.0.tgz

# Load into Docker (replace <PLUGIN_VERSION> with 6.0.0 or 6.1.0):
docker load -i juniper-nutanix-plugin-<PLUGIN_VERSION>.tgz
docker images | grep event-notification-service

# For Kubernetes node, also import into containerd:
sudo ctr -n k8s.io images import juniper-nutanix-plugin-<PLUGIN_VERSION>.tgz
sudo ctr -n k8s.io images ls | grep event-notification-service
```

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
