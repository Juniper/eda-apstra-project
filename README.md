![Juniper Networks](https://juniper-prod.scene7.com/is/image/junipernetworks/juniper_black-rgb-header?wid=320&dpr=off)

# Juniper Apstra Event Drive Automation

## Overview
This project leverages **OpenShift 4.17** and **Red Hat Ansible Automation Platform 2.5** to automate workflows, streamline decision-making, and activate rulebooks. This document explains installation and use of Ansible Automation Platform with  Automation Decisions, Automation Execution Below is a step-by-step guide to setting up the environment and utilizing the platform's features effectively.

## Notes: For running Apstra EDA for upstream kubernetes use [this](./tests/upstream/README.md) documentation.

## Prerequisites
1. **OpenShift 4.17** environment set up and configured.
2. **Ansible Automation Platform 2.5** operator installed and configured.
3. **Kubernetes NMState** operator installed and lldp configured on the nodes.
4. **OpenShift SR-IOV Network** operator installed.
5. Juniper Apstra 5.0,5.1 and 6.0
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

## Steps to configure lldp on nodes

There are two steps to enable lldp configuration on node using NMState.


1. Chnage the interfaces and apply below yaml for NodeNetworkConfigurationPolicy.

```yaml
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: lldp-node-policy 
spec:
  nodeSelector: 
    node-role.kubernetes.io/worker: ""   # Label the node role worker node if not already
  maxUnavailable: 3 
  desiredState:
    interfaces:
      - name: enp4s0f0
        type: ethernet
        lldp:
          enabled: true
      - name: enp4s0f1
        type: ethernet
        lldp:
          enabled: true
```

2. Check the NodeNetworkState and see lldp neighbours are visible using below command.

``` 
kubectl get NodeNetworkState <nodeName> -o yaml

```yaml
      lldp:
        enabled: true
        neighbors:
```

---

## Steps to Configure and Use Ansible Automation Platform

This project uses Automation Decisions and Automation Execusion for getting events and running ansible jobs respectively. This document describes how to configure both the tools for Juniper Apstra Event Driven Automation.

Please follow instructions from [here](./build/apstra-aap-configure/README.md) to configure Ansible Automation Platform.

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

