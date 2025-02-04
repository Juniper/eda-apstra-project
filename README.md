![Juniper Networks](https://juniper-prod.scene7.com/is/image/junipernetworks/juniper_black-rgb-header?wid=320&dpr=off)

# Juniper Apstra Event Drive Automation

## Overview
This project leverages **OpenShift 4.17** and **Red Hat Ansible Automation Platform 2.5** to automate workflows, streamline decision-making, and activate rulebooks. This document explains installation and use of Ansible Automation Platform with  Automation Decisions, Automation Execution Below is a step-by-step guide to setting up the environment and utilizing the platform's features effectively.

## Prerequisites
1. **OpenShift 4.17** environment set up and configured.
2. **Ansible Automation Platform 2.5** operator installed and configured.
3. **Kubernetes NMState** operator installed.
4. **OpenShift SR-IOV Network** operator installed.
5. Juniepr Apstra 5.0 or 5.1
6. Access to Juniper public Git repository containing the automation project files.

## Notes:

1. Objects which are labelled with type=eda will only be recongized by Apstra EDA.
2. It is required to set Projects, Credentials, Apstra Blueprint name and Rulebook Activations to run Apstra EDA as given in this document.
3. Docker images for decision environment and execution environment required to build before setting up the environment.


Useful documentation:
- [Automation Decisions](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/using_automation_decisions/index)
- [Automation Execution Configuration](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/configuring_automation_execution/index)
- [Installing NMState Operator](https://docs.openshift.com/container-platform/4.15/networking/k8s_nmstate/k8s-nmstate-about-the-k8s-nmstate-operator.html)
- [Installing SR-IOV Network Opeator](https://docs.openshift.com/container-platform/4.17/networking/hardware_networks/installing-sriov-operator.html#install-operator-web-console_installing-sriov-operator)

---

## Steps to Configure and Use Ansible Automation Platform

This project uses Automation Decisions and Automation Execusion for getting events and running ansible jobs respectively. This document describes how to configure both the tools for Juniper Apstra Event Driven Automation.

### Configuring Automation Execustion

#### 1. Creating Execution Environments

You can run Ansible automation in containers, like any other modern software application. Ansible uses container images known as Execution Environments (EE) that act as control nodes. 

To create Execution Envrionments container image follow the instructions from [here](https://github.com/Juniper/apstra-ansible-collection?tab=readme-ov-file#image-build)

Once container image is created and pushed to artifactory or similar location which is accessible by Ansible Automation Platform, follow below steps to create Execution Environment.

1. Naviagte to **Automation Controller**.
2. Go to Infrastructure.
3. Click on Execution Environments.
4. Click on Create Execution Environment.
5. Mention the Name, Image(created in step above), Pull Option, Organization(remains same for all the components)
6. Click on Create Execution Environment.

Check the sample configuration of tower [here](./tests/images/tower-ee-example.png)
Once Execution Environment is created, mention the name of the Execution Environment while creating templates.


#### 2. Creating Credentials
Credentials are essential for accessing external systems and running automation jobs. Follow these steps:

1. Navigate to **Automation Controller**.
2. Go to **Credentials** under the Resources section.
3. Click **Add** to create a new credential.
4. Fill in the following fields:
   - **Name**: A descriptive name for the credential.
   - **Type**: Select the appropriate credential type (e.g., Machine, GitHub Personal Access Token).
   - **Inputs**: Provide the required inputs based on the credential type.
5. Save the credential.

We need to create below credetials for automation jobs.
##### 1. OpenShift or Kubernetes API Bearer Token

Selecting this credential type allows you to create instance groups that point to a Kubernetes or OpenShift container.
Get more information how to create OpenShift API Bearer token type of credentials [here](https://docs.ansible.com/automation-controller/4.1.2/html/userguide/credentials.html#openshift-or-kubernetes-api-bearer-token)

This will be used to get access to OpenShift cluster from automation jobs using service account.

##### 2. Juniper Apstra Credentials

We need to create credentials type for Apstra.

1. Navigate to Creadentials Types.
2. Create Credential Types.
3. Name Credential Type as Juniper Apstra.
4. Put below in Input configuration.
```yaml
fields:
  - id: api_url
    type: string
    label: API URL
    help_text: The URL used to access the Apstra API
  - id: verify_certificates
    type: boolean
    label: Verify Certificates
    default: true
    help_text: Whether to verify SSL certificates
  - id: username
    type: string
    label: Username
    help_text: The username for authentication
  - id: password
    type: string
    label: Password
    secret: true
    help_text: The password for authentication
required:
  - api_url
  - username
  - password
```
5. Add below in Injector configuration.
```yaml
env:
  APSTRA_API_URL: '{{ api_url }}'
  APSTRA_PASSWORD: '{{ password }}'
  APSTRA_USERNAME: '{{ username }}'
  APSTRA_VERIFY_CERTIFICATES: '{{ verify_certificates }}'
file: {}
extra_vars: {}
```
6. Save the credentials type.

Next step is to create credential of type Juniper Apstra following the steps mentioned in  [Creating Credentials](#1-creating-credentials)

#### 5. Setting up inventories.
In this case, inventory should have jobs running on controlplane nodes in instance group. We can select controlplane nodes in Demo Inventory.

#### 6. Creating a Project from a Public Repository
A project is a logical collection of playbooks, inventories, and configurations.

1. Navigate to **Projects** in the Automation Controller.
2. Click **Add** to create a new project.
3. Configure the following:
   - **Name**: Enter a project name.
   - **Organization**: Select an organization.
   - **Source Control Type**: Choose **Git**.
   - **Source Control URL**: Enter the URL of the public repository.
   - **Credentials**: (Optional) Select credentials if the repository requires authentication.
4. Save the project and allow the sync process to complete.

#### 7. Creating Templates
Templates define jobs and workflows for automation execution.

1. Navigate to **Templates** in the Automation Controller.
2. Click **Add** and choose **Job Template**.
3. Provide the following information:
   - **Name**: A descriptive name for the job template.
   - **Inventory**: Select the inventory to run the job against.
   - **Project**: Select the previously created project.
   - **Playbook**: Choose a playbook from the selected project.
   - **Credentials**: Assign the required credentials.
4. Save the job template.

We need to templates for each type of action. Please refer the images for creating these templates.
1. [Create Security Zone](./tests/images/create-security-zone.png)
2. [Delete Security Zone](./tests/images/delete-security-zone.png)
3. [Create Virtual Network](./tests/images/create-virtual-network.png)
4. [Delete Virtual Network](./tests/images/delete-virtual-network.png)
6. [Create Connectivity Template](./tests/images/create-connectivity-template.png)
7. [Delete Connectivity Template](./tests/images/delete-connectivity-template.png)
8. [Init-done](./tests/images/init-done.png)

### Configuring Automation Decision 

#### 1. Creating Decision Environment
Automation Decisions help define and execute rule-based workflows.This is similar to creating execution environment mentioned in [Creating Execution Environments](#1-creating-execution-environments)

Please refer [guide](https://github.com/Juniper/k8s.eda/blob/main/README.md#building-and-publishing-a-decision-environment-image) to create container image and deploy decision environment. Once container image is create follow the steps below to create decision environment.

1. Navigate to **Automation Decisions**.
2. Click **Add Decision Environment** to set up the environment:
   - Configure inputs, such as decision tables, and link them to automation templates.
   - Specify the rule sets and rulebooks to be activated.
3. Deploy the decision environment.

This is sample decision environment creation [image](./tests/images/de-example.png).

For detailed guidance, refer to the [Using Automation Decisions Documentation](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/using_automation_decisions/index).

#### 2. Creating a Project

This step is similar to [Creating a Project from a Public Repository](#6-creating-a-project-from-a-public-repository)

#### 3. Creating Credentials

Below are the types of credentials that we create in Automation Decesions.

1. Red Hat Ansible Automation Platform

We need to get access to Ansible Execution to run jobs in Execution environment.

1. Navigate to Users, select the user and go to tokens.
2. Create token and save the token.
3. Navigate to Automation Decisions.
4. Go to Infrastructure and click on Credentials.
5. Create credentials type  Red Hat Ansible Automation Platform.
6. Paste the token and Red Hat Ansible Automation Platform URL.

Example credential can be reffered [here](./tests/images/tower-token.png).

#### 4. Creating Rulebook Activations
Rulebook activations are used to trigger specific rule-based workflows.

1. Navigate to **Rulebook Activations**.
2. Click **Add** to create a new activation.
3. Fill in the following details:
   - **Name**: Enter a name for the activation.
   - **Rulebook**: Choose the rulebook to activate.
   - **Inventory**: Select the inventory to use.
   - **Execution Environment**: Select the execution environment.
   - **Variables**: Provide any required input variables.
  We need to provide blueprint_name as variable for Apstra Blueprint name as shown in image [here](./tests/images/rulebook-activation.png)
4. Save and activate the rulebook.

Example of Rulebook Activation can be reffered [here](./tests/images/rulebook-activation.png)

## Configuring SRIOV nodes

### 1. Applying SriovNetworkNodePolicy
You specify the SR-IOV network device configuration for a node by creating an SR-IOV network node policy. The API object for the policy is part of the sriovnetwork.openshift.io API group.

Find example files [here](./tests/examples/sriovnetworknodepolicies/)

Please refer explanation of each field [here](https://docs.openshift.com/container-platform/4.11/networking/hardware_networks/configuring-sriov-device.html)

---

## Mappings of OpenShift Objects with Apstra Objects

This section highlight what you can expect while creating various OpenShift Objects.

| OpenShift Object | Apstra Object | Description |
|---|---|---|
| Project | Routing Zones(VRF) | Creating/Deleting Project will create Routing Zones(VRF) in Apstra. |
| SriovNetwork | Virtual Networks(VNET) | Creating/Deleting SriovNetwork will create Virtual Networks(VNET) in Apstra. |
| Pod | Connectivity Template | Creation of VNET creates connectivity template automatically in Apstra, Pod will be mapped to respective node and port in connectivity templates dynamically. | 


---

## Verification and Testing
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
---

## Troubleshooting
1. If blueprint is locked during the run.
- Ansible play fails if blueprint gets lock and shows below error 
```bash
fatal: [localhost]: FAILED! => {"changed": false, "msg": "Failed to lock blueprint 4b954fc4-91ba-478e-9f25-3e78168f83ca within 60 seconds"}
```
Solution: 
1. Unlock the blueprint from Apstra UI.
2. Restart rule book activation, which will trigger init-done playbooks to sync with OpenShift resources.


## Additional Resources
- [Red Hat Ansible Automation Platform Documentation](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/)
- [OpenShift Documentation](https://docs.openshift.com/)

---

## License
This project is licensed under the MIT License. See `LICENSE` for more details.

---

## Contact
For questions or issues, please reach out to [Pratik Dave] at [pratikd@juniper.net].

