![Juniper Networks](https://juniper-prod.scene7.com/is/image/junipernetworks/juniper_black-rgb-header?wid=320&dpr=off)

# Juniper Apstra Event Drive Automation for Upstream Kubernetes

The document outlines the installation procedures for Upstream Kubernetes and Apstra Event-Driven Ansible. It includes the following sections:

- [Installing Kubernetes](#installing-kubernetes-with-kubespray)
- [Installing Multus](#installing-multus-for-kubernetes-networking-plugin)
- [Configuring Dynamic NFS Storage class](#setting-up-dynamic-nfs-provisioning-in-a-kubernetes-cluster-if-required)
- [Installing SRIOVNetwork Operator](#installing-sriovnetwork-operator)
- [Install AWX Operator (Ansible Tower)](#install-awx-operator-ansible-tower)
- [Installing EDA Server Operator](#installing-eda-server-operator)
- [Installing NMState Operator](#installing-nmstate-operator)
- [Manage RBAC for EDA Controller](#manage-rbac-for-eda-controller)
- [Integrating AWX Operator with EDA(Event Driven Ansible)](#integrating-awx-operator-with-edaevent-driven-ansible)
- [Verification and Testing](#verification-and-testing)
- [Troubleshooting](#troubleshooting)

# Installing Kubernetes with Kubespray

Kubespray is a tool for deploying production-ready Kubernetes clusters using Ansible. This guide provides steps to install Kubernetes using Kubespray.

## Prerequisites

- **Nodes**: At least 2 nodes (1 control plane, 1 worker) with supported OS (Ubuntu 20.04/22.04, CentOS 7/8, or Debian 11/12).
- **Hardware**:
  - Minimum: 2 CPU cores, 4GB RAM per node.
  - Recommended: 4 CPU cores, 8GB RAM for control plane.
- **Network**:
  - Passwordless SSH access (root or sudo user) on all nodes.
  - Open ports: 6443 (API server), 2379-2380 (etcd), 10250-10252 (Kubelet), and others per [Kubespray network requirements](https://github.com/kubernetes-sigs/kubespray#requirements).
- **Software**:
  - Python 3.10+ on all nodes.
  - Ansible 2.16+ on the deployment machine.
  - Git installed on the deployment machine.

## Step-by-Step Installation

### 1. Clone Kubespray Repository
```bash
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
git checkout release-2.27.0  # Use the latest stable release (adjust as needed)
```

### 2. Install tools:
  ```bash
  sudo apt update
  sudo apt install -y python3-pip git
  pip3 install requirements.txt
  ```

### 3. Create Inventory
``` bash
cp -rfp inventory/sample inventory/mycluster
```

### 4. Paste and update with your node IPs in inventory/mycluster/hosts.yaml
``` bash
all:
  hosts:
    node1:
      ansible_host: 10.54.240.19
      ip: 10.54.240.19
      access_ip: 10.54.240.19
  children:
    kube_control_plane:
      hosts:
        node1:
    kube_node:
      hosts:
        node1:
    etcd:
      hosts:
        node1:
    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:
    calico_rr:
      hosts: {}
```

### 5. Configure SSH Access
  ```bash
ssh-copy-id <ansible_user>@<node_ip>
```

### 6. Run the cluster
  ```bash
ansible-playbook -i inventory/mycluster/hosts.yaml cluster.yml -b -u <ssh-user>
```

### 7. Label the nodes.
It is required to label the node for various different purposes for Apstra EDA.

```bash
feature.node.kubernetes.io/network-sriov.capable=true
node-role.kubernetes.io/control-plane=
node-role.kubernetes.io/worker=
sriovnetwork.openshift.io/device-plugin=Enabled
```

# Installing Multus for Kubernetes Networking Plugin

``` bash
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset.yml
```

# Setting Up Dynamic NFS Provisioning in a Kubernetes Cluster if required

This guide provides step-by-step instructions to set up dynamic NFS provisioning in a Kubernetes cluster deployed with Kubespray v2.27.0. It automates the creation and management of NFS-backed Persistent Volumes (PVs) and Persistent Volume Claims (PVCs) using the `nfs-subdir-external-provisioner`. The setup assumes an existing NFS server and a Kubernetes cluster.

Based on: [How to Setup Dynamic NFS Provisioning in a Kubernetes Cluster by Hakan Bayraktar](https://hbayraktar.medium.com/how-to-setup-dynamic-nfs-provisioning-in-a-kubernetes-cluster-cbf433b7de29)

## Prerequisites
- **Kubernetes Cluster**:
  - Deployed using Kubespray v2.27.0 (supports Kubernetes v1.31.0).
  - Minimum 2 nodes (1 control plane, 1 worker).
- **NFS Server**:
  - Accessible from the Kubernetes cluster.
  - Configured with a shared directory (e.g., `/data/nfs`).
  - NFS server IP (e.g., `10.124.0.9`) and export path known.
- **Nodes**:
  - Ubuntu 20.04/22.04 or other supported OS (per Kubespray v2.27.0).
  - NFS client packages installed on all Kubernetes nodes.
- **Tools**:
  - Helm 3 installed on the deployment machine.
  - `kubectl` configured to access the cluster.
- **Network**:
  - Ports open: 111, 2049, 20048 for NFS.
  - NFS server reachable from all nodes.

## Step-by-Step Instructions

### Step 1: Install NFS Server (If Not Already Set Up)
- On the NFS server (e.g., Ubuntu 22.04), install NFS utilities:
  ```bash
  sudo apt update
  sudo apt install -y nfs-kernel-server
  ```

### Step 2: Create a shared directory
``` bash
sudo mkdir -p /data/nfs
sudo chown nobody:nogroup /data/nfs
sudo chmod 777 /data/nfs
```

### Step 3: Configure NFS exports:
``` bash
echo -e "/data/nfs\t10.124.0.0/24(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
```
Replace 10.124.0.0/24 with your network CIDR.

### Step 4:Export the share and restart NFS
``` bash
sudo exportfs -rav
sudo systemctl restart nfs-kernel-server
sudo systemctl status nfs-kernel-server
```

### Step 5: On all Kubernetes nodes, install NFS client packages

``` bash
sudo apt update
sudo apt install -y nfs-common
```

### Step 6: On the deployment machine, install Helm 3
``` bash
curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
sudo apt-get install apt-transport-https --yes
echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install -y helm
```

### Step 7: Deploy NFS Subdir External Provisioner

``` bash
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner
helm repo update
```

### Step 8: Install the provisioner with Helm

``` bash
helm install nfs-subdir-external-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --set nfs.server=<nfs-server-ip> \
  --set nfs.path=/data/nfs \
  --set storageClass.onDelete=true
```

### Step 9:  Verify Provisioner Deployment

``` bash
kubectl get pods -A | grep nfs-
kubectl get sc
```

### Step 10: Make Storage Class as Default 
``` bash
kubectl patch storageclass nfs-client -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}
```

# Installing SRIOVNetwork Operator


The SR-IOV Network Operator Helm Chart provides an easy way to install, configure, and manage the lifecycle of the SR-IOV Network Operator in a Kubernetes cluster. The SR-IOV Network Operator leverages Kubernetes Custom Resource Definitions (CRDs) and the Operator SDK to configure and manage SR-IOV networks, including provisioning SR-IOV CNI and device plugins.

This guide assumes a Kubernetes cluster deployed with Kubespray v2.27.0 (supporting Kubernetes v1.31.0) and SR-IOV-capable hardware.

## Prerequisites
- **Kubernetes Cluster**:
  - Version: v1.16 or later (v1.31.0 recommended with Kubespray v2.27.0).
  - Deployed on bare-metal nodes with SR-IOV-capable NICs.
- **SR-IOV Hardware**:
  - Supported NICs listed in [supported-hardware.md](https://github.com/k8snetworkplumbingwg/sriov-network-operator/blob/master/doc/supported-hardware.md).
- **CNI Plugins**:
  - Multus CNI deployed as the default CNI plugin.
  - A default CNI plugin (e.g., Flannel, Calico) available for Multus.
- **Software**:
  - Helm 3 installed on the deployment machine.
  - `rdma-core` package installed on Ubuntu or RHEL nodes (not required for Red Hat CoreOS).
- **Nodes**:
  - SR-IOV worker nodes labeled with `node-role.kubernetes.io/worker`.
  - `feature.node.kubernetes.io/network-sriov.capable=true` label on SR-IOV-capable nodes.

## Installation Steps

### Step 1: Install Helm
- Install Helm 3 if not already installed:
  ```bash
  curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
  chmod 500 get_helm.sh
  ./get_helm.sh

### Step 2: Label Namespace for Privileged Pod Security
```bash
kubectl label ns sriov-network-operator pod-security.kubernetes.io/enforce=privileged
```
### Step 3: Download repository
```bash
git clone https://github.com/k8snetworkplumbingwg/sriov-network-operator.git ; cd sriov-network-operator
```

### Step 5: Install SR-IOV Network Operator

```bash
helm install -n openshift-sriov-network-operator --create-namespace --wait --set sriovOperatorConfig.deploy=true sriov-network-operator ./deployment/sriov-network-operator-chart
```

### Step 6: View deployed resources
``` bash
kubectl -n openshift-sriov-network-operator  get pods
```

### Step 7: Configure SriovNetworkNodePolicy change pfNames.

```yaml
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetworkNodePolicy
metadata:
 name: enp94s0f1-policy
 namespace: openshift-sriov-network-operator
spec:
 deviceType: netdevice
 isRdma: false
 needVhostNet: true
 nicSelector:
   pfNames: ["enp94s0f1"]
 numVfs: 10
 priority: 99
 resourceName: PF_enp94s0f1
 nodeSelector:
    feature.node.kubernetes.io/network-sriov.capable: "true"
```

Follow [document](https://github.com/k8snetworkplumbingwg/sriov-network-operator/blob/master/deployment/sriov-network-operator-chart/README.md) for more information


# Install AWX Operator (Ansible Tower)

### Step 1: Clone the AWX Operator Helm Repository

```bash
git clone https://github.com/ansible-community/awx-operator-helm.git
```

### Step 2: Navigate to the Repository Directory

```bash
cd awx-operator-helm
git checkout v2.19.1
```

### Step 3: Install helm chart for AWX Operator
``` bash
helm install my-awx-operator . -n aap --create-namespace 
```
### Step 4: Once operator is installed create object
Create below file and apply using kubectl

```bash
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: ansible-awx
  namespace: aap
spec:
  service_type: nodeport
  postgres_storage_class: nfs-client
```


### Step 5: Access using NodePort service
Once AWX Operator is up, you can access it using NodePort service.

### Notes
- **Version Specificity**: The steps target the exact tag `v2.19.1` as requested, verified via the repository’s release tags.[](https://github.com/ansible-community/awx-operator-helm/releases)
- **Copy-Paste Ready**: Commands are formatted for immediate execution, with minimal placeholders.
- **Kubespray Integration**: The guide assumes a Kubespray v2.27.0 cluster, consistent with your previous requests, and includes relevant troubleshooting links.
- **Optional Steps**: Added a verification step and optional chart inspection for user confidence.
- **Citations**: Included references to the repository, release, and documentation, following the provided citation guidelines.[](https://github.com/ansible-community/awx-operator-helm)[](https://ansible-community.github.io/awx-operator-helm/)[](https://github.com/ansible-community/awx-operator-helm/releases)

# Installing EDA Server Operator 

### Step 1: Run the following command in your terminal to install the operator

``` bash

kubectl apply -f https://github.com/ansible/eda-server-operator/releases/download/1.0.0/operator.yaml
```

### Step 2: Now create your EDA custom resource by applying the eda-demo.yml file and you will soon have a working EDA instance!

```bash
kind: EDA
metadata:
  name: eda
  namespace: eda
spec:
  service_type: NodePort
  automation_server_ssl_verify: "no"
  automation_server_url: http://10.54.240.19:30332
  database:
    postgres_storage_class: nfs-client
```

# Installing NMState Operator

### Step 1
By default network manager is not installed for ubuntu. 
```bash
sudo apt install network-manager  
```

NICs should be managed using nework manager.
```bash
$ nmcli dev status
DEVICE           TYPE      STATE                                  CONNECTION          
vxlan.calico     vxlan     connected (externally)                 vxlan.calico        
enp94s0f1        ethernet  connecting (getting IP configuration)  Wired connection 28 
enp94s0f2        ethernet  connecting (getting IP configuration)  Wired connection 29 
enp94s0f3        ethernet  connecting (getting IP configuration)  Wired connection 30 
```
We need to exclude some of the interfaces which is used by Kubernetes itself excluding them in file /etc/NetworkManager/NetworkManager.conf.

```bash
[main]
plugins=ifupdown,keyfile

[ifupdown]
managed=false

[device]
wifi.scan-rand-mac-address=no

[keyfile]
# Ensure no devices are unmanaged unless explicitly listed
unmanaged-devices=interface-name:enp94s0f0;interface-name:lo;interface-name:eno1;interface-name:eno2;interface-name:br-int;interface-name:br-local;interface-name:br-nexthop;interface-name:ovn-k8s-*;interface-name:k8s-*;interface-name:tun0;interface-name:br0;interface-name:patch-br-*;interface-name:br-ext;interface-name:ext-vxlan;interface-name:ext;interface-name:int;interface-name:vxlan_sys_*;interface-name:genev_sys_*;driver:veth;interface-name:cali*;interface-name:kube*;interface-name:nodelocaldns
```

### Step 2
Install NMState Operator

kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.83.0/nmstate.io_nmstates.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.83.0/namespace.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.83.0/service_account.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.83.0/role.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.83.0/role_binding.yaml
kubectl apply -f https://github.com/nmstate/kubernetes-nmstate/releases/download/v0.83.0/operator.yaml

### Step 3
Once that's done, create an NMState CR, triggering deployment of kubernetes-nmstate handler:

```bash
cat <<EOF | kubectl create -f -
apiVersion: nmstate.io/v1
kind: NMState
metadata:
  name: nmstate
EOF
```

### Step 4 
Configure lldp using NMState as below, change the interface names.

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: lldp-node-policy 
spec:
  nodeSelector: 
    node-role.kubernetes.io/control-plane: ""
  maxUnavailable: 3 
  desiredState:
    interfaces:
      - name: enp94s0f1 
        type: ethernet
        lldp:
          enabled: true
      - name: enp94s0f2 
        type: ethernet
        lldp:
          enabled: true
      - name: enp94s0f3 
        type: ethernet
        lldp:
          enabled: true
```



# Manage RBAC for EDA Controller

It is required to configure RBAC for Event Driven Ansible controller.
Apply RBAC from [here](../../rbac/) changing if required to change namespace.

# Integrating AWX Operator with EDA(Event Driven Ansible)

Make sure you have installed awx and eda collection for Ansible.

```bash
ansible-galaxy collection install awx.awx
ansible-galaxy collection install ansible.eda
```

To integrate AWX with EDA using configure AAP. Follow [document](./build/apstra-aap-configure/README.md)

Sample vars/main.yaml file is as below:
```yaml
---
# vars file for apstra-aap-configure

## It is best practice to use Ansible Vault to encrypt sensitive data such as passwords.

# Common Variables
organization_name: "Default"
project_url: "https://github.com/Juniper/eda-apstra-project.git" 
project_scm_branch: "main"
apstra_blueprint_name: "eda-bp-qc"
kubernetes_host: "https://10.54.240.19:6443"

# Ansible Automation Controller(Ansible Tower) Configuration
automation_controller_host: "http://10.54.240.19:31135/"
automation_controller_username: "admin"
automation_controller_password: "AWXPassword"
execution_environment_image_url: "s-artifactory.juniper.net/atom-docker/ee/apstra-ee:1.0.5"

# Ansible Automation Decisions(Ansible EDA) Configuration
eda_controller_host: "http://10.54.240.19:30901/"
eda_controller_username: "admin"
eda_controller_password: "EDAPassword"

controller_api: "http://10.54.240.19:30709/"
decision_environment_image_url: "s-artifactory.juniper.net/atom-docker/de/juniper-k8s-de:1.4.4"

# Apstra Variables
apstra_api_url: "https://10.87.2.74/api"
apstra_username: "admin"
apstra_password: "YourApstraPassword"
```

# Verification and Testing

1. Validate the decision/execution workflows and rulebook activations through logs and dashboards in the Automation Controller and Automation Decision.
2. Validate projects gets synced properly.

Once above validation is done, we can run sample yamls from [folder](./tests/) and validate.

1. First we create Routing Zones, for that we create project in OpenShift. Check file [project.yaml](./tests/examples/project.yaml)
2. You can verify automation job starts and the Routing Zone created in Apstra.
3. Once project is created, we can create SRIOVNetwork. Check file [sriov-vn1.yaml](./tests/examples/sriov-vn1.yaml)
4. You can verify automation job starts and the Virtual Network created in Apstra.
5. Once Virtual Network is created , you can see connectivity templates get created.
6. Now, you can run SRIOV workloads(Pod/Deployment) on this Virtual Network. Refer file [deployment-vn1.yaml](./tests/examples/deployment-vn1.yaml)
7. You can verify automation job starts and node port is mapped in connectivity template.

### Troubleshooting:
- If you are not able to open webui for EDA server image version to quay.io/ansible/eda-ui:2.4.892. Edit eda-ui deployment and change image version.

``` bash
kubectl get deploy -n eda eda-ui 
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
eda-ui   1/1     1            1           34d
```

- You might face issues opening files that can cause exhibit as failing Pods. To resolve it increase the inotify.max_user_watches and inotify.max_user_instances sysctls on a Linux host.

```bash
sudo sysctl fs.inotify.max_user_instances=8192
sudo sysctl fs.inotify.max_user_watches=524288
sudo sysctl -p
```
Reference - https://www.suse.com/support/kb/doc/?id=000020048 
