Ansible Role: apstra-aap-configure
=========

This role automates the configuration of **Red Hat Ansible Automation Platform (AAP) 2.5** components for Juniper Apstra Event-Driven Automation integration. It configures:

- **Automation Controller**: Job execution and workflow management
- **Event-Driven Ansible (EDA)**: Event monitoring and rulebook activation
- **Project Management**: Source control integration with playbooks and rulebooks
- **Credential Management**: Secure storage of API keys and certificates
- **Environment Configuration**: Decision and Execution Environment setup

## Prerequisites

### Software Requirements
- **Ansible**: 2.15 or higher
- **Python**: 3.8+ with required modules (`requests`, `kubernetes`)
- **OpenShift CLI**: `oc` command configured and authenticated
- **jq**: JSON processing tool for extracting certificate data

### Access Requirements
- **OpenShift Cluster**: Admin access to apply RBAC configurations
- **Ansible Automation Platform**: Admin access to both Controller and EDA components
- **Juniper Apstra**: API access with admin privileges
- **Container Registry**: Access to push/pull Decision and Execution Environment images

### Pre-Configuration Steps

Before running this role, ensure you have completed:

1. **RBAC Setup**: Applied the RBAC configurations from `../../rbac/` directory
2. **Docker Images**: Built and pushed Decision Environment and Execution Environment images
3. **Service Account**: Created the `aap` service account and secret in OpenShift

## Configuration Steps

### Step 1: Prepare Certificate and Token Files

The role requires OpenShift cluster certificate and service account token. Use these commands to automatically extract and save them:

```bash
# Navigate to the files directory
cd build/apstra-aap-configure/files/

# Extract the service account token
kubectl get secret aap -n aap -o json | jq '.data.token' | xargs | base64 --decode > openshift-sa.token

# Extract the cluster certificate authority data
kubectl get secret aap -n aap -o json | jq '.data["ca.crt"]' | xargs | base64 --decode > openshift-ca.crt
```

> **🔐 Security Note**: These files contain sensitive authentication data. Ensure proper file permissions (600) and avoid committing to public repositories.

#### Verify File Creation

```bash
# Verify files were created successfully
ls -la openshift-*.{token,crt}

# Check file contents (should not be empty)
wc -l openshift-sa.token openshift-ca.crt

# Validate token format (should be a long base64-like string)
head -c 50 openshift-sa.token && echo "..."
```

### Step 2: Configure Role Variables

Edit the variables file to match your environment:

```bash
# Edit the main configuration file
vi vars/main.yml
```

## Role Variables
--------------
Please change the variables in [file](../apstra-aap-configure/vars/main.yml).

| Variable                       | Required | Type                      | Comments                                                                        |
|--------------------------------|----------|---------------------------|---------------------------------------------------------------------------------|
| organization_name              | yes      | String                    | Name of the organization in Ansible Automation Plaform                          |
| project_url                    | yes      | String                    | URL for the project where Playbooks and Rulebooks are available                 |
| project_scm_branch             | yes      | String                    | SCM branch for the project                        |
| apstra_blueprint_name          | yes      | String                    | Name of the Apstra blueprint                      |
| openshift_host                 | yes      | String                    | Host address for OpenShift eg.https://api.ocpapstra-lab.englab.juniper.net:6443                        |
| automation_controller_host     | yes      | String                    | Ansible host controller URL. Go to opeators->Ansible Automation Platform->All Instances-> Automation Controller-> URL                                     |
| automation_controller_username | yes      | String                    | Ansible host controller Username. Go to opeators->Ansible Automation Platform->All Instances-> Automation Controller-> Username          |
| automation_controller_password | yes      | String                    | Ansible host controller URL. Go to opeators->Ansible Automation Platform->All Instances-> Automation Controller-> Password|
| execution_environment_image_url| yes      | String                    | URL where image for Execution environment is pushed           |
| eda_controller_host            | yes      | String                    | Ansible EDA controller URL. Go to opeators->Ansible Automation Platform->All Instances-> Automation EDA-> URL              |
| eda_controller_username        | yes      | String                    | Ansible EDA controller Username. Go to opeators->Ansible Automation Platform->All Instances-> Automation EDA-> Username                  |
| eda_controller_password        | yes      | String                    | Ansible EDA controller Password. Go to opeators->Ansible Automation Platform->All Instances-> Automation EDA-> Pasword      |
| controller_api                 | yes      | String                    | API endpoint of Ansible controller eg. https://aap.apps.ocpapstra-lab.englab.juniper.net/api/controller/"                   |
| decision_environment_image_url | yes      | String                    | URL where image for Decision environment is pushed           |
| apstra_api_url                 | yes      | String                    | URL for the Apstra API                            |
| apstra_username                | yes      | String                    | Username for Apstra                               |
| apstra_password                | yes      | String                    | Password for Apstra (sensitive)                   |

**Security Best Practices:**
- Store all sensitive information (passwords, tokens) directly in `vars/main.yml`
- Ensure proper file permissions on the variables file (600 or 640)
- Never commit credentials to public version control repositories

### Variable Examples

```yaml
# Example vars/main.yml - configure all variables directly
organization_name: "Apstra-EDA-Organization"
project_url: "https://github.com/Juniper/eda-apstra-project.git"
project_scm_branch: "main"
apstra_blueprint_name: "apstra-eda-datacenter"
openshift_host: "https://api.cluster.example.com:6443"
automation_controller_host: "https://aap-controller.apps.cluster.example.com"
automation_controller_username: "admin"
automation_controller_password: "your-controller-password"
execution_environment_image_url: "registry.example.com/apstra-ee:1.0.1"
eda_controller_host: "https://eda-controller.apps.cluster.example.com"
eda_controller_username: "admin"
eda_controller_password: "your-eda-password"
controller_api: "https://aap-controller.apps.cluster.example.com/api/controller/"
decision_environment_image_url: "registry.example.com/juniper-k8s-de:1.4.4"
apstra_api_url: "https://apstra.example.com"
apstra_username: "admin"
apstra_password: "your-apstra-password"
```

## Required Files

The following files must be properly configured before running the role:

| File Name | Purpose | Source | Required Changes |
|-----------|---------|---------|------------------|
| `openshift-ca.crt` | **OpenShift Cluster CA Certificate** | Auto-generated via command | ✅ **Auto-populated** |
| `openshift-sa.token` | **Service Account Authentication Token** | Auto-generated via command | ✅ **Auto-populated** |
| `cred_injector_config.json` | **Apstra Credential Type Definition** | Pre-configured | ❌ **No changes needed** |
| `cred_input_config.json` | **Apstra Credential Input Schema** | Pre-configured | ❌ **No changes needed** |

### File Generation Commands

```bash
# Run these commands from build/apstra-aap-configure/files/ directory

# 1. Generate OpenShift service account token
kubectl get secret aap -n aap -o json | jq '.data.token' | xargs | base64 --decode > openshift-sa.token

# 2. Generate OpenShift cluster CA certificate  
kubectl get secret aap -n aap -o json | jq '.data["ca.crt"]' | xargs | base64 --decode > openshift-ca.crt

# 3. Verify files are correctly generated
echo "Token length: $(wc -c < openshift-sa.token) characters"
echo "Certificate lines: $(wc -l < openshift-ca.crt) lines"

# 4. Secure the files (recommended for production)
chmod 600 openshift-sa.token openshift-ca.crt
```

### File Validation

Verify the generated files contain valid data:

```bash
# Check token format (should be alphanumeric with dots and dashes)
if grep -qE '^[A-Za-z0-9._-]+$' openshift-sa.token; then
    echo "✅ Token format is valid"
else
    echo "❌ Token format is invalid"
fi

# Check certificate format (should start with -----BEGIN CERTIFICATE-----)
if grep -q "BEGIN CERTIFICATE" openshift-ca.crt; then
    echo "✅ Certificate format is valid"
else
    echo "❌ Certificate format is invalid"
fi
```

## File Details

### openshift-ca.crt
- **Purpose**: Validates the authenticity of the OpenShift API server
- **Source**: Extracted from the `aap` service account secret
- **Format**: PEM-encoded X.509 certificate
- **Security**: Can be stored in plain text (public certificate)

### openshift-sa.token  
- **Purpose**: Authenticates AAP with OpenShift API for resource monitoring
- **Source**: Extracted from the `aap` service account secret  
- **Format**: JWT token (base64-encoded string)
- **Security**: ⚠️ **Highly sensitive** - protect with proper file permissions (600)

### cred_injector_config.json
- **Purpose**: Defines custom credential type for Apstra API integration
- **Content**: Credential field definitions and validation rules
- **Modification**: No changes required - pre-configured for Apstra API

### cred_input_config.json
- **Purpose**: Specifies input schema for Apstra credentials in AAP UI
- **Content**: Form field definitions for credential creation
- **Modification**: No changes required - matches Apstra API requirements

## Troubleshooting File Issues

### Token Extraction Failures

```bash
# If token extraction fails, check these prerequisites:
# 1. Verify the secret exists
kubectl get secret aap -n aap

# 2. Check secret has token data
kubectl describe secret aap -n aap

# 3. Verify jq is installed and working
echo '{"test": "value"}' | jq '.test'

# 4. Manual token extraction (if automated command fails)
kubectl get secret aap -n aap -o jsonpath='{.data.token}' | base64 -d > openshift-sa.token
```

### Certificate Extraction Failures

```bash
# If certificate extraction fails:
# 1. Verify CA certificate exists in secret
kubectl get secret aap -n aap -o jsonpath='{.data.ca\.crt}' | base64 -d > openshift-ca.crt

# 2. Alternative: Extract from cluster info
kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > openshift-ca.crt
```

**Note:**
If you encounter issues obtaining Certificate Authority data and API authentication tokens, refer to the [Red Hat OpenShift integration guide](https://developers.redhat.com/articles/2023/06/26/how-deploy-apps-k8s-cluster-automation-controller#install_and_configure_ansible_automation_platform).

## Execution Guide

### Step 3: Run the Configuration Playbook

Execute the role using the provided playbook:

```bash
# Navigate to the build directory
cd build/

# Run the configuration playbook
ansible-playbook apstra-eda-build.yaml
```

### Step 4: Verify Configuration

After successful execution, verify the configuration in AAP:

#### Automation Controller Verification
1. **Login** to Automation Controller: `https://<automation_controller_host>`
2. **Check Organization**: Verify organization `<organization_name>` exists
3. **Verify Project**: Confirm project sync status is **Successful**
4. **Check Credentials**: Ensure Apstra and OpenShift credentials are created
5. **Verify Execution Environment**: Confirm EE image is properly configured

#### Event-Driven Ansible Verification  
1. **Login** to EDA Controller: `https://<eda_controller_host>`
2. **Check Project**: Verify project is synced and rulebooks are detected
3. **Verify Decision Environment**: Confirm DE image is available
4. **Activate Rulebooks**: Enable rulebook activations for event monitoring

### Configuration Validation Commands

```bash
# Test OpenShift connectivity with generated token
curl -k -H "Authorization: Bearer $(cat files/openshift-sa.token)" \
     --cacert files/openshift-ca.crt \
     https://<openshift_host>/api/v1/namespaces

# Verify Apstra API connectivity
curl -k -u <apstra_username>:<apstra_password> \
     https://<apstra_api_url>/api/versions

# Check AAP project sync via API
curl -k -u <aap_username>:<aap_password> \
     https://<automation_controller_host>/api/v2/projects/
```

## Example Playbook

The provided playbook configures all necessary AAP components:

```yaml
---
- name: Configure Ansible Automation Platform for Apstra EDA
  hosts: localhost
  gather_facts: false
  vars_files:
    - apstra-aap-configure/vars/main.yml
  roles:
    - role: apstra-aap-configure


## Execution Options

### Development Environment
```bash
# Quick setup for testing (minimal validation)
ansible-playbook apstra-eda-build.yaml 

# Debug mode with verbose output
ansible-playbook apstra-eda-build.yaml -vvv
```



### 3. Verify Apstra Integration
- **Login** to Apstra UI
- **Check** for new security zones/VRFs created by automation
- **Monitor** connectivity template updates

## Common Configuration Issues

| Issue | Symptoms | Solution |
|-------|----------|----------|
| **Token Authentication Failed** | 401 Unauthorized errors | Regenerate token: `kubectl delete secret aap -n aap && kubectl apply -f ../../rbac/secret.yaml` |
| **Certificate Validation Failed** | SSL/TLS errors | Re-extract certificate: `kubectl get secret aap -n aap -o jsonpath='{.data.ca\.crt}' \| base64 -d > openshift-ca.crt` |
| **Project Sync Failed** | Git clone errors | Verify repository URL and branch in variables |
| **Image Pull Failed** | EE/DE unavailable | Check image URLs and registry authentication |
| **Apstra API Unreachable** | Connection timeout | Verify network connectivity and API URL |

License
-------

BSD

Author Information
------------------
Name: Pratik Dave 
Email: pratikd@juniper.net
