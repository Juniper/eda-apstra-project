Ansible Role: apstra-ntx-awx-configure
=========

This role helps to configure AWX (Ansible Automation Platform) on Kubernetes for Apstra EDA integration with Nutanix.

Requirements
------------

This role requires:
- Ansible 2.15 or higher
- Kubernetes cluster with kubectl configured
- AWX deployed and running
- Kubernetes RBAC configured (use configure_awx.sh script)

Prerequisites
------------

Before running this role, you must:

1. **Deploy Kubernetes cluster:**
   ```bash
   ./k8s_deploy.sh
   ```

2. **Deploy AWX:**
   ```bash
   ./awx_deploy.sh
   ```

3. **Configure Kubernetes RBAC and extract certificates:**
   ```bash
   ./configure_awx.sh
   ```

4. **Run the configuration playbook:**
   ```bash
   cd /home/ubuntu/eda-apstra-project/build
   ansible-playbook deploy-awx-playbook.yml
   ```

Role Variables
--------------
Please change the variables in [file](../apstra-ntx-awx-configure/vars/main.yml).

| Variable                       | Required | Type                      | Comments                                                                        |
|--------------------------------|----------|---------------------------|---------------------------------------------------------------------------------|
| organization_name              | yes      | String                    | Name of the organization in AWX                                                 |
| project_url                    | yes      | String                    | URL for the project where Playbooks and Rulebooks are available                 |
| project_scm_branch             | yes      | String                    | SCM branch for the project                        |
| apstra_blueprint_name          | yes      | String                    | Name of the Apstra blueprint for Nutanix integration     |
| kubernetes_host                | yes      | String                    | Host address for Kubernetes API server eg. https://localhost:6443              |
| awx_host     | yes      | String                    | AWX controller URL eg. http://localhost:30080                                  |
| awx_username | yes      | String                    | AWX controller username (default: admin)                                       |
| awx_password | yes      | String                    | AWX controller password                                                         |
| execution_environment_image_url| yes      | String                    | URL where image for Execution environment is pushed           |
| eda_controller_host            | yes      | String                    | AWX EDA controller URL eg. http://localhost:30081                              |
| eda_controller_username        | yes      | String                    | AWX EDA controller username (default: admin)                                   |
| eda_controller_password        | yes      | String                    | AWX EDA controller password                                                     |
| controller_api                 | yes      | String                    | API endpoint of AWX controller eg. http://localhost:30080/api/controller/      |
| decision_environment_image_url | yes      | String                    | URL where image for Decision environment is pushed           |
| apstra_api_url                 | yes      | String                    | URL for the Apstra API                            |
| apstra_username                | yes      | String                    | Username for Apstra                               |
| apstra_password                | yes      | String                    | Password for Apstra (sensitive)                   |

**Note**
Store all the sensitive information like passwords directly in vars/main.yml for development, or use Ansible vault for production environments.


Files
------------
kubernetes-ca.crt and kubernetes-sa.crt are certificate files [here](../apstra-ntx-awx-configure/files) that will be automatically populated by the role from the Kubernetes service account.

| Name                           | Required to Change | Comments                                                                                                     |
|--------------------------------|--------------------|--------------------------------------------------------------------------------------------------------------|
| cred_injector_config.json      | No                 | This file requires to create Apstra credential types in AWX.                                                |
| cred_input_config.json         | No                 | This file requires to create Apstra credential types in AWX.                                                |
| kubernetes-ca.crt              | Auto-generated     | Certificate Authority data for Kubernetes Cluster (auto-extracted from service account).                   |
| kubernetes-sa.crt              | Auto-generated     | API authentication certificate of Service Account for Kubernetes (auto-extracted).                         |

**Note**
If you are not aware how to obtain, Certificate Autority data and API authentication bearer token, you may read [this](https://developers.redhat.com/articles/2023/06/26/how-deploy-apps-k8s-cluster-automation-controller#install_and_configure_ansible_automation_platform) article.

Please encrypt these files using Ansible vault as best practice.

Example Playbook
----------------

An example of how to use this role. You can run [playbook](../apstra-eda-build.yaml) to configure Ansible Automation Platform.

```yaml
---
- name: Configure Ansible Automation Platform for Apstra EDA
  hosts: localhost
  gather_facts: false
  roles:
    - role: apstra-aap-configure
```

License
-------

BSD

Author Information
------------------
Name: Pratik Dave 
Email: pratikd@juniper.net
