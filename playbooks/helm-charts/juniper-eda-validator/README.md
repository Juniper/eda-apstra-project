# juniper-eda-validator
This chart deploys openshift specific objects that are required to validate the 
Juniper Apstra Event Drive Automation.


## Prerequisites

* Openshift 4.17+
* Ansible Automation Platform 2.5
* Juniper Apstra 5.0 or 5.1
* Helm v3.17+


## Installing the Chart

helm install juniper-eda-validator playbooks/helm-charts/juniper-eda-validator

## Installing the Chart

helm uninstall juniper-eda-validator

## Properties

| Key | Type | Description | Default |
|-----|------|-------------|---------|
| `project` | string | name of the project to be created in openshift cluster | `None` |
| `vrf` | string | name of the Routing Zone to be created in Apstra | `None` |
| `workloads.deployment.name` | string | name of the deployment to be created in openshift cluster | `None` |
| `workloads.deployment.image` | string | Container image for deployment  | `centos/tools` |
| `workloads.deployment.replicas` | int | No of pods in a deployment   | 1 |
| `workloads.deployment.sriovnet` | dict | Details of sriovnet to be attached to Deployment | `None` |
| `workloads.deployment.vnet` | dict | name of the vnet to be created in Apstra and attache to deployment pods| `None` |
| `workloads.deployment.resource` | string | Physical resource name created while creating sriovnet policy| `None` |
| `workloads.kubevirtvm.name` | string | Kuevirt VM name to be created in openshift cluster | `None` |
| `workloads.kubevirtvm.sriovnet` | dict | Details of sriovnet to be attached to KubevritVM | `None` |
| `workloads.kubevirtvm.vnet` | string | Name of the Vnet to be crated in Apstra and attached to Kubevirt VM | `None` |
| `workloads.kubevirtvm.resource` | string | Physical resource name created while creating sriovnet policy | `None` |

