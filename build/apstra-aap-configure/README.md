Ansible Role: apstra-aap-configure
=========

This role helps to configure Ansible Automation Controller(Ansible Tower) and Ansible Decisions(Event Drive Ansible) for Apstra EDA.

Requirements
------------

This role requires Ansible 2.15 or higher.

Role Variables
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

**Note**
Store all the senstive information like password, in Ansible vault and keep enctypted values in vars/main.yml


Files
------------
 openshift-ca.crt and openshift-sa.crt are empty files [here](../apstra-aap-configure/files), Please fill the content in those files as per the [document](https://developers.redhat.com/articles/2023/06/26/how-deploy-apps-k8s-cluster-automation-controller#install_and_configure_ansible_automation_platform)


| Name                           | Required to Change | Comments                                                                                                     |
|--------------------------------|--------------------|--------------------------------------------------------------------------------------------------------------|
| cred_injector_config.json      | No                 | This file requires to create Apstra credential types in Ansible automation platform.                         |
| cred_input_config.json         | No                 | This file requires to create Apstra credential types in Ansible automation platform.                         |
| openshift-ca.crt               | yes                | Certificate Authority data for OpenShift Cluster.                                                            |
| openshift-sa.crt               | yes                | API authentication bearer token of Service Account of OpenShift                                              |

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
