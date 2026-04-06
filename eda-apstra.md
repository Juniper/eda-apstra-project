
Juniper Apstra RedHat OpenShift Integration Guide

IN THIS GUIDE
- About This Guide
- Overview
- Before You Start
- Download and Installation of Environments
- Install Ansible Automation Platform on OpenShift
- Automation Execution
- Decision Automation
- Ansible Automation Platform
- Verification and Testing

---

## About This Guide

This guide explains how to use OpenShift 4.17 and Red Hat Ansible Automation Platform 2.5 to automate workflows, streamline decision-making, and activate rulebooks to use for Juniper Apstra event-driven automation (EDA). This document also explains how to install and use Ansible Automation Platform with Automation Decisions and Automation Execution, and set up the environment to optimize the platform's features.

---

## Overview

Juniper Apstra is now integrated with RedHat Ansible Event-Driven Automation (EDA). With this integration, Juniper Apstra supports Kubernetes SR-IOV (Single Root I/O Virtualization) traffic to automatically configure network fabric elements (VRFs, VLANs, and connectivity templates) in response to OpenShift resource lifecycle events. This functionality ensures a more responsive, efficient, and scalable infrastructure.

We support the Red Hat OpenShift Container Platform (RHOCP) 4.17 and Juniper Apstra using Red Hat Ansible Automation Platform 2.5.

### Integration Architecture

The following diagram illustrates the complete integration architecture:

- OpenShift cluster with master and worker nodes
- Required Operators that need to be Installed
- SR-IOV interfaces
- Apstra fabric integration

---

## Before You Start

### Prerequisites

Before you can automate workflows, streamline decision-making, and activate rulebooks, you need to make sure you have the following software installed and/or configured:

**Table 1: System Requirements**

| Component | Version | Purpose |
|---|---|---|
| OpenShift Container Platform | 4.17+ | Container orchestration platform |
| Red Hat Ansible Automation Platform | 2.5+ | Event-driven automation and execution |
| Juniper Apstra | 5.0, 5.1, or 6.0 | Network fabric management |
| Docker | 20.10+ (CE recommended) | Container image management |

### Required OpenShift Operators

The following operators must be installed and configured:

- **Red Hat Ansible Automation Platform Operator**
  - Provides Automation Controller and Event-Driven Ansible
  - Enables rulebook activation and job execution
  - For step-by-step installation instructions, see [Install Ansible Automation Platform on OpenShift](#install-ansible-automation-platform-on-openshift) in this guide.

- **Kubernetes NMState Operator**
  - Manages network interface configuration
  - Required for LLDP neighbor discovery
  - For more information, see Installation Guide.

- **OpenShift SR-IOV Network Operator**
  - Enables high-performance networking for workloads
  - For more information, see Installation Guide

- **(Optional) OpenShift Virtualization**
  - Required only if deploying virtual machines
  - Enables KubeVirt functionality

### Infrastructure Requirements

**OpenShift Cluster:**
- Master Nodes: Minimum three bare metal hosts
- Worker Nodes: Minimum of three bare metal hosts
- Each worker must have at least one SR-IOV-capable NIC (Intel E810 or XXV710)
- Each worker needs a separate NIC for management and default Kubernetes networking

See https://docs.redhat.com/en/documentation/openshift_container_platform/4.11/html/installing/installing-on-baremetal for information on how to install an OpenShift Cluster on bare metal hosts.

**Network Infrastructure:**
- Leaf Switches: Minimum of two Juniper QFX5120 or QFX5130 devices
- Spine Switches: Minimum of one Juniper QFX5210 or QFX5220 device
- Apstra Management: One host with external connectivity to switch management network

**Docker Registry:**
- Container registry accessible from the management node
- Used for Decision Environment and Execution Environment images
- Can be OpenShift internal registry or external registry (e.g., Juniper Artifactory)

### Management Node Requirements

A dedicated management node is required for image preparation, cluster management, and running the AAP configuration playbook.

- **Supported OS:** Debian 12 (bookworm), RHEL 8/9, Ubuntu 22.04+ (Debian 12 verified)
- **Architecture:** x86_64 (amd64)
- **Minimum free disk space:** 10 GB (container images are ~500 MB each)
- **Required tools:**

  | Tool | Minimum Version | Install Reference |
  |---|---|---|
  | Docker CE | 20.10+ | Debian: https://docs.docker.com/engine/install/debian/ / RHEL: https://docs.docker.com/engine/install/rhel/ |
  | OpenShift CLI (`oc`) | 4.6+ | https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/ |
  | `kubectl` | 1.28+ | https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/ |
  | `git` | 2.30+ | `apt install git` or `yum install git` |
  | `ansible` | 2.14+ with `awx.awx` and `ansible.eda` collections | https://docs.ansible.com/ansible/latest/installation_guide/ |

  > **Note:** `oc create token` requires oc v4.11+. On older versions of `oc`, use `kubectl create token` instead.

- **Verify installed tools:**

  ```bash
  docker version
  oc version
  kubectl version --client
  git version
  ansible --version
  ansible-galaxy collection list | grep -E "awx|eda"
  ```

- **Network connectivity required to:**
  - OpenShift cluster API endpoint
  - Container registry (accessible from the management node) for image push
  - Juniper Support portal for downloading images
  - All AAP component hostnames (Gateway, Controller, EDA, Hub) — resolve via DNS or `/etc/hosts`

### Network Access Requirements for Management Node

- Access to the Juniper public Git repository that contains the automation project files:
  - **(Required)** https://github.com/Juniper/eda-apstra-project
  - **(Optional)** https://github.com/Juniper/apstra-ansible-collection — Customize the solution, playbooks, and learn how to use modules with Apstra Ansible.
  - **(Optional)** https://github.com/Juniper/k8s.eda — Explains how to use the Kubernetes event source for Ansible. Also, you can use this repository to run events for other resources.

### Notes

- Juniper Apstra EDA only recognizes objects that are labeled with `type=eda`.
- We require that you set Projects, Credentials, Apstra Blueprint name, and Rulebook Activations to run Juniper Apstra EDA as described in this guide.

---

## Download and Installation of Environments

IN THIS SECTION
- Download and Install the Decision Environment
- Download and Install the Execution Environment

Follow these steps to download and install your Execution and Decision environments.

### Container Registry Authentication

Before loading and pushing images, authenticate to your container registry:

```bash
docker login <your-registry-hostname>
# Enter your registry credentials when prompted
```

### Download and Install the Decision Environment on Management Node

1. Navigate to the Juniper Support portal (https://support.juniper.net/support/downloads/?p=apstra).
2. Go to **Application Tools**.
3. Download the image that matches your version of Apstra and the architecture of the server you're using — for example, `juniper-k8s-de-x86_64-6.0.0.image.tgz`.
4. Load and tag the Decision Environment image:

   a. Load the image (it loads pre-tagged as `juniper-k8s-de:6.0.0`):

      ```bash
      docker load --input juniper-k8s-de-x86_64-6.0.0.image.tgz
      ```

      Verify the loaded image name:

      ```bash
      docker images | grep juniper-k8s-de
      ```

   b. Tag the image for the target registry:

      ```bash
      docker tag juniper-k8s-de:6.0.0 <your-registry>/juniper-k8s-de-x86_64-6.0.0:latest
      ```

   c. Push the image to the registry:

      ```bash
      docker push <your-registry>/juniper-k8s-de-x86_64-6.0.0:latest
      ```

### Download and Install the Execution Environment

1. Navigate to the Juniper Support portal (https://support.juniper.net/support/downloads/?p=apstra).
2. Go to **Application Tools**.
3. Download the image that matches your version of Apstra and the architecture of the server you're using — for example, `apstra-ee-x86_64-6.0.0.image.tgz`.
4. Load and tag the Execution Environment:

   a. Load the image (it loads pre-tagged as `apstra-ee:6.0.0`):

      ```bash
      docker load --input apstra-ee-x86_64-6.0.0.image.tgz
      ```

      Verify the loaded image name:

      ```bash
      docker images | grep apstra-ee
      ```

   b. Tag the image for the target registry:

      ```bash
      docker tag apstra-ee:6.0.0 <your-registry>/apstra-ee-x86_64-6.0.0:latest
      ```

   c. Push the image to the registry:

      ```bash
      docker push <your-registry>/apstra-ee-x86_64-6.0.0:latest
      ```

---

## Install Ansible Automation Platform on OpenShift

IN THIS SECTION
- Prerequisites
- Step 1 — Create the Namespace and OperatorGroup
- Step 2 — Configure the Red Hat Registry Pull Secret
- Step 3 — Create the Operator Subscription
- Step 4 — Approve the InstallPlan
- Step 5 — Deploy the AnsibleAutomationPlatform CR
- Step 6 — Verify the Installation
- Step 7 — Retrieve Admin Credentials

Follow these steps to install the Ansible Automation Platform (AAP) Operator on your OpenShift cluster and deploy an AAP instance. The verified version used in this guide is AAP **2.5** (Operator CSV `aap-operator.v2.5.0-0.1737675968`, Controller `4.6.7`).

> **Before you begin:** You must be logged in to the OpenShift cluster as a `cluster-admin` user.
> ```bash
> oc login https://api.<cluster-domain>:6443 -u kubeadmin
> oc whoami   # must return cluster-admin
> ```

### Prerequisites

- OpenShift cluster is running and healthy
- The `nfs-client` StorageClass (or your preferred RWX-capable StorageClass) is available:
  ```bash
  oc get storageclass
  ```
- Your cluster global pull secret includes credentials for `registry.redhat.io` (required to pull Red Hat images):
  ```bash
  oc get secret pull-secret -n openshift-config \
    -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | python3 -m json.tool | grep registry.redhat.io
  ```
  If `registry.redhat.io` is missing, add it via the OpenShift console under **Cluster Settings → Global Pull Secret**, or contact your Red Hat account team for registry credentials.

### Step 1 — Create the Namespace and OperatorGroup

Create the `aap` namespace and an `OperatorGroup` that scopes the operator to that namespace:

```bash
cat <<'EOF' | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: aap
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: aap-operatorgroup
  namespace: aap
spec:
  targetNamespaces:
    - aap
EOF
```

Verify the namespace and OperatorGroup are created:

```bash
oc get namespace aap
oc get operatorgroup -n aap
```

### Step 2 — Configure the Red Hat Registry Pull Secret

The operator pods must pull images from `registry.redhat.io`. Copy the cluster-level pull secret into the `aap` namespace:

```bash
oc get secret pull-secret -n openshift-config \
  -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d > /tmp/dockerconfig.json

oc create secret generic redhat-operators-pull-secret \
  --from-file=operator=/tmp/dockerconfig.json \
  -n aap
```

Verify the secret was created:

```bash
oc get secret redhat-operators-pull-secret -n aap
```

### Step 3 — Create the Operator Subscription

Create a `Subscription` object pointing to the `stable-2.5` channel in the Red Hat operator catalog. Setting `installPlanApproval: Manual` with a pinned `startingCSV` ensures you install the exact tested version and do not auto-upgrade:

```bash
cat <<'EOF' | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ansible-automation-platform-operator
  namespace: aap
spec:
  channel: stable-2.5
  installPlanApproval: Manual
  name: ansible-automation-platform-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  startingCSV: aap-operator.v2.5.0-0.1737675968
EOF
```

> **Note:** The `startingCSV` value `aap-operator.v2.5.0-0.1737675968` is the verified CSV for AAP 2.5 (platform version `2.5.20250115`, Controller `4.6.7`). A newer CSV may be available in the catalog. To use the latest available 2.5 version, omit the `startingCSV` field, or check the available CSVs with:
> ```bash
> oc get packagemanifest ansible-automation-platform-operator -n openshift-marketplace \
>   -o jsonpath='{.status.channels[?(@.name=="stable-2.5")].currentCSV}'
> ```

Verify the Subscription is created:

```bash
oc get subscription -n aap
```

### Step 4 — Approve the InstallPlan

Because `installPlanApproval` is set to `Manual`, the operator will not install until you explicitly approve the generated `InstallPlan`.

**Wait for the InstallPlan to appear** (typically 15–30 seconds):

```bash
oc get installplan -n aap
```

**Approve the pending InstallPlan:**

```bash
INSTALL_PLAN=$(oc get installplan -n aap \
  -o jsonpath='{.items[?(@.spec.approved==false)].metadata.name}')
echo "Approving InstallPlan: $INSTALL_PLAN"

oc patch installplan "$INSTALL_PLAN" -n aap \
  --type merge --patch '{"spec":{"approved":true}}'
```

**Wait for the operator CSV to reach `Succeeded` phase** (typically 3–5 minutes):

```bash
watch oc get csv -n aap
```

Expected output when ready:

```
NAME                               DISPLAY                       VERSION              PHASE
aap-operator.v2.5.0-0.1737675968   Ansible Automation Platform   2.5.0+0.1737675968   Succeeded
```

> **Important:** Do not proceed to Step 5 until the CSV shows `Succeeded`. If it remains in `Installing` for more than 10 minutes, check operator pod logs:
> ```bash
> oc logs -n aap -l app.kubernetes.io/name=aap-gateway-operator -c manager
> ```

### Step 5 — Deploy the AnsibleAutomationPlatform CR

Create the top-level `AnsibleAutomationPlatform` custom resource. The operator uses this single CR to automatically provision all sub-components: Automation Controller, Automation Hub, Event-Driven Ansible (EDA), PostgreSQL, and Redis.

```bash
cat <<'EOF' | oc apply -f -
apiVersion: aap.ansible.com/v1alpha1
kind: AnsibleAutomationPlatform
metadata:
  name: aap
  namespace: aap
spec:
  api:
    log_level: INFO
    replicas: 1
  database:
    postgres_data_volume_init: false
    postgres_storage_class: nfs-client      # Replace with your StorageClass if different
  image_pull_policy: Always
  no_log: true
  redis_mode: standalone
  route_tls_termination_mechanism: Edge
EOF
```

> **StorageClass note:** The `postgres_storage_class` value must match a StorageClass available in your cluster. The Automation Hub file storage PVC (100 Gi, RWX) and the Redis data PVC (1 Gi, RWO) are also automatically created using this storage class.

**Monitor deployment progress:**

```bash
# Watch the top-level AAP CR status conditions
watch oc get ansibleautomationplatform aap -n aap

# Watch all pods starting up (full deployment takes 5–15 minutes)
watch oc get pods -n aap
```

The operator provisions resources in this order:

1. PostgreSQL 15 StatefulSet (`aap-postgres-15`)
2. Redis StatefulSet (`aap-redis`)
3. Gateway deployment (`aap-gateway`)
4. `AutomationController` sub-CR and pods (`aap-controller-task`, `aap-controller-web`)
5. `AutomationHub` sub-CR and pods (`aap-hub-api`, `aap-hub-content`, `aap-hub-web`, `aap-hub-worker`)
6. `EDA` sub-CR and pods (`aap-eda-api`, `aap-eda-activation-worker`, `aap-eda-default-worker`, `aap-eda-scheduler`, `aap-eda-event-stream`)

### Step 6 — Verify the Installation

**Verify all pods are Running:**

```bash
oc get pods -n aap
```

All pods must show `Running` status. The expected pods and their container counts are:

| Pod | Containers | Expected Status |
|---|---|---|
| `aap-postgres-15-0` | 1/1 | Running |
| `aap-redis-0` | 1/1 | Running |
| `aap-gateway-*` | 2/2 | Running |
| `aap-controller-task-*` | 4/4 | Running |
| `aap-controller-web-*` | 3/3 | Running |
| `aap-hub-api-*` | 1/1 | Running |
| `aap-hub-content-*` (×2) | 1/1 | Running |
| `aap-hub-web-*` | 1/1 | Running |
| `aap-hub-worker-*` | 1/1 | Running |
| `aap-hub-redis-*` | 1/1 | Running |
| `aap-eda-api-*` | 3/3 | Running |
| `aap-eda-activation-worker-*` (×2) | 1/1 | Running |
| `aap-eda-default-worker-*` (×2) | 1/1 | Running |
| `aap-eda-scheduler-*` (×2) | 1/1 | Running |
| `aap-eda-event-stream-*` | 2/2 | Running |

**Verify the AAP CR shows a successful reconciliation:**

```bash
oc get ansibleautomationplatform aap -n aap \
  -o jsonpath='{.status.conditions}' | python3 -m json.tool
```

Look for `"type": "Successful"` with `"status": "True"`.

**Verify the deployed versions match:**

```bash
# Platform version (expected: 2.5.20250115)
oc get ansibleautomationplatform aap -n aap -o jsonpath='{.status.version}'; echo

# Automation Controller version (expected: 4.6.7)
oc get automationcontroller aap-controller -n aap -o jsonpath='{.status.version}'; echo
```

**Verify routes are created:**

```bash
oc get routes -n aap
```

Four routes are expected:

| Route | URL Pattern |
|---|---|
| Gateway (main entry point) | `https://aap-aap.apps.<cluster-domain>` |
| Automation Controller | `https://aap-controller-aap.apps.<cluster-domain>` |
| Automation Hub | `https://aap-hub-aap.apps.<cluster-domain>` |
| Event-Driven Ansible | `https://aap-eda-aap.apps.<cluster-domain>` |

### Step 7 — Retrieve Admin Credentials

The operator auto-generates admin passwords and stores them in secrets within the `aap` namespace. Retrieve them as follows:

```bash
# Gateway / Platform admin password
oc get secret aap-admin-password -n aap \
  -o jsonpath='{.data.password}' | base64 -d; echo

# Automation Controller admin password
oc get secret aap-controller-admin-password -n aap \
  -o jsonpath='{.data.password}' | base64 -d; echo

# Automation Hub admin password
oc get secret aap-hub-admin-password -n aap \
  -o jsonpath='{.data.password}' | base64 -d; echo

# EDA admin password
oc get secret aap-eda-admin-password -n aap \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

The default admin username for all components is `admin`.

Log in to the Gateway URL (`https://aap-aap.apps.<cluster-domain>`) with username `admin` and the Gateway admin password to confirm AAP is fully operational before proceeding to the next section.

---

## Automation Execution

### Create OpenShift or Kubernetes API Bearer Token Credentials

You can create OpenShift or Kubernetes API Bearer token credential types. These credential types enable you to create instance groups that point to a Kubernetes or OpenShift container. You can also use these credentials to access an OpenShift cluster from your automation jobs by using a service account.

Follow these steps to create a service account and generate the required token and CA certificate:

**Step 1: Create a service account in the AAP namespace**

```bash
oc create serviceaccount aap-access -n aap
```

**Step 2: Bind the cluster-admin role to the service account**

```bash
oc adm policy add-cluster-role-to-user cluster-admin system:serviceaccount:aap:aap-access
```

**Step 3: Generate a long-lived token**

> **Note:** Use `kubectl create token` even if `oc` is available, as older versions of `oc` (< 4.11) do not support the `create token` subcommand.

```bash
kubectl create token aap-access -n aap --duration=8760h > \
  eda-apstra-project/build/apstra-aap-configure/files/openshift-sa.token
```

**Step 4: Export the cluster CA certificate**

```bash
kubectl config view --raw \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' \
  | base64 -d > eda-apstra-project/build/apstra-aap-configure/files/openshift-ca.crt
```



For more information about how to create an OpenShift or Kubernetes API Bearer Token credential, see [OpenShift or Kubernetes API Bearer Token](https://docs.ansible.com/automation-controller/latest/html/userguide/credentials.html#openshift-or-kubernetes-api-bearer-token).

---

## Decision Automation

IN THIS SECTION
- Prerequisites
- Configure SR-IOV Nodes
- Mappings of OpenShift Objects with Apstra Objects

### Prerequisites

Before configuring SR-IOV nodes, verify that the Kubernetes NMState Operator and the SR-IOV Network Operator are installed and running in your cluster.

**Verify the Kubernetes NMState Operator:**

```bash
# Check the operator CSV is Succeeded
oc get csv -n openshift-nmstate | grep nmstate

# Check the NMState CR exists and handler pods are running
oc get NMState
oc get pods -n openshift-nmstate
```

Expected output:

```
NAME                                               DISPLAY                       VERSION              PHASE
kubernetes-nmstate-operator.4.17.0-202501301304   Kubernetes NMState Operator   4.17.0-202501301304  Succeeded
```

All `nmstate-handler-*` pods must show `Running`. One handler pod runs on each node.

**Verify the SR-IOV Network Operator:**

```bash
# Check the operator CSV is Succeeded
oc get csv -n openshift-sriov-network-operator | grep sriov

# Check the SriovOperatorConfig exists and operator pods are running
oc get SriovOperatorConfig -n openshift-sriov-network-operator
oc get pods -n openshift-sriov-network-operator
```

Expected output:

```
NAME                                         DISPLAY                 VERSION              PHASE
sriov-network-operator.v4.17.0-202501230004  SR-IOV Network Operator 4.17.0-202501230004  Succeeded
```

The `network-resources-injector-*` and `operator-webhook-*` pods must show `Running`.

> **If either operator is not installed**, refer to the [Required OpenShift Operators](#required-openshift-operators) section and install them before continuing.

### Configure SR-IOV Nodes

#### Enable LLDP on SR-IOV Nodes

Follow these steps to use NMState to enable LLDP on your SR-IOV nodes.

1. Identify the SR-IOV interfaces on each worker node (the interfaces connected to Apstra-managed leaf switches). Create and apply a `NodeNetworkConfigurationPolicy` YAML file with those interface names:

   ```yaml
   apiVersion: nmstate.io/v1
   kind: NodeNetworkConfigurationPolicy
   metadata:
     name: lldp-node-policy
   spec:
     nodeSelector:
       node-role.kubernetes.io/worker: ""
     maxUnavailable: 3
     desiredState:
       interfaces:
         - name: <interface-name-1>
           type: ethernet
           lldp:
             enabled: true
         - name: <interface-name-2>
           type: ethernet
           lldp:
             enabled: true
   ```

   ```bash
   oc apply -f lldp-node-policy.yaml
   ```

2. Verify LLDP neighbors are visible. Issue the following command and confirm that leaf switch neighbors appear under each interface:

   ```bash
   oc get NodeNetworkState <nodeName> -o json | jq -r '.status.currentState.interfaces[] | select(.lldp.neighbors | length > 0) | "interface: \(.name)", (.lldp.neighbors[][] | select(.type==5) | "  system-name: \(.["system-name"])"), (.lldp.neighbors[][] | select(.type==2) | "  port-id: \(.["port-id"])"), ""'
   ```

   Expected output:

   ```
   interface: <interface-name-1>
     system-name: <leaf-switch-hostname>
     port-id: <switch-port>

   interface: <interface-name-2>
     system-name: <leaf-switch-hostname>
     port-id: <switch-port>
   ```

   > **Important:** Only interfaces that show LLDP neighbors connected to Apstra-managed leaf switches can be used for SR-IOV virtual networks and connectivity templates. Pods deployed on interfaces without LLDP neighbors will cause the `create-connectivity-template` automation job to fail. Verify per-node LLDP connectivity before proceeding.

#### Apply SR-IOV Network Node Policy

Create an SR-IOV network node policy to specify the SR-IOV network device configuration. The API object for the policy is part of the `sriovnetwork.openshift.io` API group.

Create a separate policy YAML file for each SR-IOV physical function (interface) you want to expose as virtual functions. Use the following template:

```yaml
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetworkNodePolicy
metadata:
  name: <interface-name>-policy
  namespace: openshift-sriov-network-operator
spec:
  deviceType: netdevice
  isRdma: false
  needVhostNet: true
  nicSelector:
    pfNames:
      - <interface-name>
  nodeSelector:
    feature.node.kubernetes.io/network-sriov.capable: "true"
  numVfs: 4
  priority: 99
  resourceName: <interface-name>_vfs
```

Replace `<interface-name>` with the actual interface name (e.g., `ens801f1`). The `resourceName` will be used when requesting SR-IOV resources in pod/deployment specs (e.g., `openshift.io/ens801f1_vfs`).

Apply the policy:

```bash
oc apply -f sriov-policy-<interface-name>.yaml
```

Verify the policy is applied and synced across nodes:

```bash
oc get SriovNetworkNodeState -n openshift-sriov-network-operator
```

Wait until the `syncStatus` shows `Succeeded` for all worker nodes before proceeding.

See [Configuring an SR-IOV Network Device](https://docs.openshift.com/container-platform/4.17/networking/hardware_networks/configuring-sriov-device.html) for detailed information on each field in the SR-IOV network node policy.

### Mappings of OpenShift Objects with Apstra Objects

The following table highlights what you can expect while creating various OpenShift objects.

**Table 2: Mappings of OpenShift Objects with Apstra Objects**

| OpenShift Object | Apstra Object | Description |
|---|---|---|
| Project | Routing Zones (VRF) | Creating/Deleting a project will create Routing Zones (VRF) in Apstra. |
| SriovNetwork | Virtual Networks (VNET) | Creating/Deleting a SriovNetwork will create Virtual Networks (VNET) in Apstra. |
| Pod | Connectivity Template | Creating a pod on a VNET creates a connectivity template automatically in Apstra. The pod is mapped to the respective nodes and ports in the connectivity templates dynamically. |

---

## Ansible Automation Platform

IN THIS SECTION
- Ansible Role: apstra-aap-configure
- Role Variables
- Files
- Configuring Ansible Automation Platform

### Ansible Role: apstra-aap-configure

You can use Ansible Role to configure Ansible Automation Controller (Ansible Tower) and Ansible Decisions (event-driven Ansible) for Juniper Apstra EDA.

### Role Variables

| Variable | Required | Type | Comments |
|---|---|---|---|
| `organization_name` | yes | String | Name of the organization in Ansible Automation Platform |
| `project_url` | yes | String | URL for the project where Playbooks and Rulebooks are available |
| `project_scm_branch` | yes | String | SCM branch for the project |
| `apstra_blueprint_name` | yes | String | Name of the Apstra blueprint (must match exactly as it appears in Apstra) |
| `kubernetes_host` | yes | String | Kubernetes/OpenShift API server URL, e.g., `https://api.<cluster-domain>:6443` |
| `automation_controller_host` | yes | String | Ansible Automation Controller URL. Go to Operators → Ansible Automation Platform → All Instances → Automation Controller → URL |
| `automation_controller_username` | yes | String | Automation Controller username |
| `automation_controller_password` | yes | String | Automation Controller password |
| `execution_environment_image_url` | yes | String | Full image URL for the Execution Environment pushed to your registry (including tag), e.g., `<your-registry>/apstra-ee-x86_64-6.0.0:latest` |
| `eda_controller_host` | yes | String | Ansible EDA controller URL. Go to Operators → Ansible Automation Platform → All Instances → Automation EDA → URL |
| `eda_controller_username` | yes | String | Ansible EDA controller username |
| `eda_controller_password` | yes | String | Ansible EDA controller password |
| `controller_api` | yes | String | API endpoint of Ansible controller, e.g., `https://aap-<name>.apps.<cluster-domain>/api/controller/` |
| `decision_environment_image_url` | yes | String | Full image URL for the Decision Environment pushed to your registry (including tag), e.g., `<your-registry>/juniper-k8s-de-x86_64-6.0.0:latest` |
| `apstra_api_url` | yes | String | URL for the Apstra API, e.g., `https://<apstra-host>/api` |
| `apstra_username` | yes | String | Username for Apstra |
| `apstra_password` | yes | String | Password for Apstra (sensitive — consider using Ansible Vault) |

### Files

The following files in `build/apstra-aap-configure/files/` must be present before running the playbook. Only the two token/certificate files require action — they are generated in the [Create OpenShift or Kubernetes API Bearer Token Credentials](#create-openshift-or-kubernetes-api-bearer-token-credentials) section. The JSON credential config files are static and must not be modified.

| Name | Action Required | Comments |
|---|---|---|
| `openshift-ca.crt` | **Yes** — generate using Step 4 in the Bearer Token section | Cluster CA certificate for OpenShift authentication |
| `openshift-sa.token` | **Yes** — generate using Step 3 in the Bearer Token section | Service account bearer token for OpenShift authentication |
| `cred_injector_config.json` | No — do not modify | Static template used by the playbook to create Apstra credential types in AAP |
| `cred_input_config.json` | No — do not modify | Static template used by the playbook to create Apstra credential types in AAP |

### Configuring Ansible Automation Platform

Follow these steps to configure Ansible Automation Platform for Juniper Apstra EDA.

**Step 1: Clone the automation project**

```bash
git clone https://github.com/Juniper/eda-apstra-project.git
cd eda-apstra-project/build
```

**Step 2: Populate the variables file**

Edit `apstra-aap-configure/vars/main.yml` with the values for your environment. Use the commands below to retrieve each required value:

**`kubernetes_host`:**
```bash
kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}'; echo
```

**`automation_controller_host`:**
```bash
echo "https://$(oc get route aap-controller -n aap -o jsonpath='{.spec.host}')/"
```

**`automation_controller_password`:**
```bash
oc get secret aap-controller-admin-password -n aap -o jsonpath='{.data.password}' | base64 -d; echo
```

**`eda_controller_host`:**
```bash
echo "https://$(oc get route aap-eda -n aap -o jsonpath='{.spec.host}')/"
```

**`eda_controller_password`:**
```bash
oc get secret aap-eda-admin-password -n aap -o jsonpath='{.data.password}' | base64 -d; echo
```

**`controller_api`:**
```bash
echo "https://$(oc get route aap -n aap -o jsonpath='{.spec.host}')/api/controller/"
```

**`execution_environment_image_url`** and **`decision_environment_image_url`** — Use the full image URLs (including tag) from the registry push steps in [Download and Installation of Environments](#download-and-installation-of-environments).

**`apstra_api_url`** — `https://<apstra-host>/api`

**`apstra_blueprint_name`**, **`apstra_username`**, **`apstra_password`** — Use the blueprint name, username, and password from your Apstra instance.

**Step 3: Copy credential files**

Ensure the following files are in place (generated in the Bearer Token section):

```bash
ls apstra-aap-configure/files/openshift-ca.crt
ls apstra-aap-configure/files/openshift-sa.token
```

**Step 4: Resolve AAP hostnames**

Verify that all AAP component hostnames are resolvable from the management node:

```bash
curl -sk https://aap-controller-<name>.apps.<cluster-domain>/api/v2/ping/
```

If they are not resolvable via DNS, add the router/ingress IP to `/etc/hosts`:

```bash
echo "<ingress-ip>  aap-<name>.apps.<cluster-domain>  aap-controller-<name>.apps.<cluster-domain>  aap-eda-<name>.apps.<cluster-domain>  aap-hub-<name>.apps.<cluster-domain>" >> /etc/hosts
```

**Step 5: Run the configuration playbook**

```bash
cd eda-apstra-project/build
ansible-playbook apstra-eda-build.yaml \
  -e "@apstra-aap-configure/vars/main.yml" \
  -v
```

---

## Verification and Testing

Follow these steps to verify and test the Juniper Apstra RedHat OpenShift Integration end-to-end.

> **Before you begin:** Ensure the EDA rulebook activation is running in the `aap` namespace, the Automation Controller is accessible, and the Apstra blueprint is deployed with the correct name matching `apstra_blueprint_name` in `vars/main.yml`.

Sample YAML files are available at https://github.com/Juniper/eda-apstra-project/tree/main/tests

### Step 1 — Apply SR-IOV Node Policies

Apply one policy per SR-IOV interface you intend to use:

```bash
oc apply -f sriov-policy-<interface-name>.yaml
```

Verify all nodes reach `syncStatus: Succeeded`:

```bash
oc get SriovNetworkNodeState -n openshift-sriov-network-operator
```

**Table: Expected AAP Job Sequence**

| Step | OpenShift Object Applied | AAP Job Template Triggered | Expected Result |
|---|---|---|---|
| 1 | SR-IOV Node Policies | (none — no EDA trigger) | Policies synced across nodes |
| 2 | Project (with `type=eda` label) | `create-vrf` | Routing Zone created in Apstra |
| 3 | SriovNetwork (with `type=eda` label) | `create-vnet` | Virtual Network created in Apstra |
| 4 | Deployment/Pod (on SR-IOV network) | `create-connectivity-template` | Connectivity Template created and node port mapped |

### Step 2 — Create a Project (Routing Zone / VRF)

The Project object must carry the `type=eda` label and an `apstra.juniper.net/vrf` annotation listing the VRF name(s) to create in Apstra.

```yaml
# project.yaml
apiVersion: project.openshift.io/v1
kind: Project
metadata:
  name: <namespace>
  labels:
    type: eda
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
    security.openshift.io/scc.podSecurityLabelSync: "false"
  annotations:
    apstra.juniper.net/vrf: '[
      {
        "vrfName": "<vrf-name>"
      }
    ]'
```

```bash
oc apply -f project.yaml
```

Verify the `create-vrf` job is triggered and succeeds in Automation Controller, and that the Routing Zone appears in Apstra under the configured blueprint.

### Step 3 — Create SR-IOV Networks (Virtual Networks / VNETs)

Each SriovNetwork must carry the `type=eda` label, the `pfname` label (physical function interface name), and an `apstra.juniper.net/vnet` annotation.

```yaml
# sriov-vn1.yaml
apiVersion: sriovnetwork.openshift.io/v1
kind: SriovNetwork
metadata:
  name: sriovnet-<vnet-name>
  namespace: openshift-sriov-network-operator
  labels:
    type: eda
    pfname: <interface-name>
  annotations:
    apstra.juniper.net/vnet: '[
      {
        "vnetName": "<vnet-name>",
        "vrfName": "<vrf-name>"
      }
    ]'
spec:
  ipam: |
    {
      "type": "host-local",
      "subnet": "<subnet-cidr>",
      "rangeStart": "<ip-range-start>",
      "rangeEnd": "<ip-range-end>",
      "gateway": "<gateway-ip>",
      "routes": [
        {
          "dst": "<other-subnet-cidr>",
          "gw": "<gateway-ip>"
        }
      ]
    }
  networkNamespace: <namespace>
  resourceName: <interface-name>_vfs
  vlan: <vlan-id>
```

```bash
oc apply -f sriov-vn1.yaml
oc apply -f sriov-vn2.yaml
```

Verify `create-vnet` jobs succeed for each SriovNetwork, and that Virtual Networks appear in Apstra.

### Step 4 — Deploy SR-IOV Workloads (Connectivity Templates)

Deploy pods or deployments that request SR-IOV resources. The deployment must:

- Carry `type=eda` label and `apstra.juniper.net/ep` annotation
- Request the correct SR-IOV resource via `openshift.io/<resourceName>`
- Use `nodeSelector` to pin pods to a node where the interface has an LLDP neighbor on an Apstra-managed leaf switch

> **Important:** Before deploying, verify that the target node's SR-IOV interface has LLDP neighbors:
> ```bash
> oc get NodeNetworkState <node-name> -o yaml | grep -A5 "neighbors"
> ```
> If the interface shows no LLDP neighbors, select a different node or interface. Deploying on an interface with no LLDP neighbors will cause the `create-connectivity-template` job to fail.

```yaml
# deployment-vn1.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vn1-deployment
  namespace: <namespace>
  labels:
    type: eda
    vnet: <vnet-name>
spec:
  replicas: 1
  selector:
    matchLabels:
      type: eda
      vnet: <vnet-name>
  template:
    metadata:
      name: vn1-deployment
      labels:
        type: eda
        vnet: <vnet-name>
      annotations:
        apstra.juniper.net/ep: '[{"vnetName": "<vnet-name>"}]'
        k8s.v1.cni.cncf.io/networks: '[
          {
            "name": "sriovnet-<vnet-name>",
            "namespace": "<namespace>",
            "interface": "ext0"
          }
        ]'
    spec:
      containers:
        - name: iperf3
          image: centos/tools
          command: ["/bin/bash", "-c", "--"]
          args: ["while true; do sleep 300000; done;"]
```

> **Tip:** If your cluster has some worker nodes without LLDP neighbors on Apstra-managed leaf switches, add a `nodeSelector` under `spec` to pin the pod to a known-good node:
> ```yaml
>     spec:
>       nodeSelector:
>         kubernetes.io/hostname: <worker-node-name>
> ```

```bash
oc apply -f deployment-vn1.yaml
oc apply -f deployment-vn2.yaml
```

Verify `create-connectivity-template` jobs succeed, and that Connectivity Templates in Apstra show the correct node and port mappings.

### Step 5 — Verify End-to-End Connectivity

Verify the pods are running and have received IP addresses on their SR-IOV interfaces:

```bash
oc get pods -n <namespace> -o wide
oc exec -n <namespace> <pod-name> -- ip addr show ext0
```

Test cross-network connectivity (VNET1 pod to VNET2 pod):

```bash
# Get the ext0 IP of the vn2 pod
oc exec -n <namespace> <vn2-pod-name> -- ip addr show ext0

# Ping from vn1 pod to vn2 pod's ext0 IP
oc exec -n <namespace> <vn1-pod-name> -- ping -c 4 <vn2-ext0-ip>
```

Successful pings confirm that:
- SR-IOV virtual functions are correctly allocated
- VLANs and VNETs are configured in the Apstra fabric
- Connectivity templates are routing traffic between the virtual networks

---

RELATED DOCUMENTATION

Juniper Networks, the Juniper Networks logo, Juniper, and Junos are registered trademarks of Juniper Networks, Inc. in the United States and other countries. All other trademarks, service marks, registered marks, or registered service marks are the property of their respective owners. Juniper Networks assumes no responsibility for any inaccuracies in this document.

Juniper Networks reserves the right to change, modify, transfer, or otherwise revise this publication without notice. Copyright © 2026 Juniper Networks, Inc. All rights reserved.
