![Juniper Networks](https://juniper-prod.scene7.com/is/image/junipernetworks/juniper_black-rgb-header?wid=320&dpr=off)

# Juniper Apstra Event Drive Automation

## Overview
This project leverages **OpenShift 4.7** and **Red Hat Ansible Automation Platform 2.5** to automate workflows, streamline decision-making, and activate rulebooks. This document explains installation and use of Ansible Automation Platform with  Automation Decisions, Automation Execution Below is a step-by-step guide to setting up the environment and utilizing the platform's features effectively.

## Prerequisites
1. **OpenShift 4.7** environment set up and configured.
2. **Ansible Automation Platform 2.5** operator installed and configured.
3. **Kubernetes NMState** operator installed.
4. **OpenShift SR-IOV Network** operator installed.
5. Access to Juniper public Git repository containing the automation project files.

Useful documentation:
- [Automation Decisions](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/using_automation_decisions/index)
- [Automation Execution Configuration](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/configuring_automation_execution/index)

---

## Steps to Configure and Use Ansible Automation Platform

### 1. Creating Credentials
Credentials are essential for accessing external systems and running automation jobs. Follow these steps:

1. Navigate to **Automation Controller**.
2. Go to **Credentials** under the Resources section.
3. Click **Add** to create a new credential.
4. Fill in the following fields:
   - **Name**: A descriptive name for the credential.
   - **Type**: Select the appropriate credential type (e.g., Machine, GitHub Personal Access Token).
   - **Inputs**: Provide the required inputs based on the credential type.
5. Save the credential.

### 2. Creating a Project from a Public Repository
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

### 3. Creating Templates
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

### 4. Using Automation Decisions
Automation Decisions help define and execute rule-based workflows.

1. Navigate to **Automation Decisions**.
2. Click **Add Decision Environment** to set up the environment:
   - Configure inputs, such as decision tables, and link them to automation templates.
   - Specify the rule sets and rulebooks to be activated.
3. Deploy the decision environment.

For detailed guidance, refer to the [Using Automation Decisions Documentation](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/using_automation_decisions/index).

### 5. Creating Rulebook Activations
Rulebook activations are used to trigger specific rule-based workflows.

1. Navigate to **Rulebook Activations**.
2. Click **Add** to create a new activation.
3. Fill in the following details:
   - **Name**: Enter a name for the activation.
   - **Rulebook**: Choose the rulebook to activate.
   - **Inventory**: Select the inventory to use.
   - **Execution Environment**: Select the execution environment.
   - **Variables**: Provide any required input variables.
4. Save and activate the rulebook.

---

## Verification and Testing
1. Run automation jobs using the configured templates to ensure proper execution.
2. Validate the decision workflows and rulebook activations through logs and dashboards in the Automation Controller.
3. Troubleshoot any issues using the detailed execution logs available under each resource.

---

## Additional Resources
- [Red Hat Ansible Automation Platform Documentation](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/)
- [OpenShift Documentation](https://docs.openshift.com/)

---

## License
This project is licensed under the MIT License. See `LICENSE` for more details.

---

## Contact
For questions or issues, please reach out to [Your Name] at [pratikd@juniper.net].