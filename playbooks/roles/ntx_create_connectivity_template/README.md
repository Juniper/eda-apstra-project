# ntx_create_connectivity_template

This Ansible role creates Apstra connectivity templates when Nutanix VM connectivity changes. It's designed to be triggered by Event-Driven Ansible (EDA) when monitoring Nutanix VM lifecycle events (creation, modification with network changes).

## Requirements

- Juniper Apstra collection (`juniper.apstra`)
- Kubernetes collection (`kubernetes.core`)
- Access to Apstra management server
- Valid Apstra credentials
- Kubernetes access for ConfigMap operations

## Role Variables

### Required Variables

The role expects structured data from Nutanix EDA events:

- `nutanix_event`: Event metadata with entity_type, event_type, timestamp
- `entity`: VM entity with name, uuid, state
- `vm`: Detailed VM information including network_interfaces with physical_connectivity

### Optional Variables

- `blueprint_label_value`: Target Apstra blueprint label (default: "apstra-datacenter")
- `require_powered_on_vm`: Only process VMs that are powered on (default: true)
- `require_physical_connectivity`: Only process VMs with physical connectivity data (default: true)
- `auto_commit_changes`: Whether to auto-commit blueprint changes (default: true)
- `create_connectivity_configmap`: Whether to create ConfigMap entries (default: true)

## Expected Input Event

This role expects to process Nutanix VM events with comprehensive connectivity information:

```json
{
  "nutanix_event": {
    "entity_type": "VM",
    "event_type": "MODIFIED",
    "timestamp": "2025-09-18T05:05:09.435239",
    "detection_time": "2025-09-18 05:05:09",
    "api_version": "v3"
  },
  "entity": {
    "name": "subvm",
    "uuid": "9dca77a3-4028-4198-a392-404f6f0dce66",
    "cluster_uuid": null,
    "state": "COMPLETE"
  },
  "vm": {
    "power_state": "ON",
    "host_info": {
      "host_name": "host-001",
      "host_uuid": "d7c8e1fe-fe19-479e-ab70-698089298ba2"
    },
    "network_interfaces": [
      {
        "nic_index": 1,
        "ip_address": "192.168.26.81",
        "mac_address": "50:6b:8d:bc:ce:a7",
        "physical_connectivity": {
          "vswitch_name": "vs2",
          "host_port": "eth1",
          "physical_switch": "switch-001",
          "switch_port": "xe-0/0/32"
        }
      }
    ]
  }
}
```

## Functionality

1. **Pre-Flight Checks**: Validates VM is powered on and has connectivity data
2. **Blueprint Access**: Retrieves target blueprint from ConfigMap configuration
3. **Application Points**: Converts VM network interfaces to Apstra application points
4. **Endpoint Policy**: Updates virtual network endpoint policies with connectivity
5. **Tagging**: Applies comprehensive tags for VM traceability
6. **ConfigMap Updates**: Stores VM connectivity information in Kubernetes ConfigMaps
7. **Blueprint Commit**: Commits changes to activate configuration

## Application Points Mapping

VM network interfaces are mapped to Apstra application points:

- `remote_host`: Physical switch name from `physical_connectivity.physical_switch`
- `if_name`: Switch port from `physical_connectivity.switch_port`
- `used`: Set to `true` for active VM connections

## Virtual Network Mapping

- Virtual network name derived from `vswitch_name` (e.g., "vs2")
- VLAN information extracted from subnet associations
- ConfigMap created per virtual network for connectivity tracking

## Tags Applied

- `vm_name={vm_name}`
- `vm_uuid={vm_uuid}`
- `host_name={host_name}`
- `source=nutanix_eda`
- `entity_type=vm`
- `event_type=connectivity`
- `vswitch={vswitch_name}`

## ConfigMap Management

Creates ConfigMaps in `juniper-apstra-eda` namespace:

- **Name**: `{vswitch_name}-connectivity`
- **Data**: VM connectivity information keyed by `{vm_name}-{host_name}`
- **Labels**: `managed-by=nutanix-eda`, `vswitch={vswitch_name}`

## Example Playbook

```yaml
- hosts: localhost
  vars:
    # Variables populated by Nutanix EDA service
    nutanix_event: "{{ nutanix_event }}"
    entity: "{{ entity }}"
    vm: "{{ vm }}"
    # Blueprint configuration
    blueprint_label_value: "datacenter-fabric"
  roles:
    - ntx_create_connectivity_template
```

## Error Handling

- Validates required variables are present
- Checks VM power state and connectivity requirements
- Implements retry logic for API operations
- Graceful handling of missing physical connectivity data
- Blueprint unlock on failures

## Integration with K8s Role

This role complements the `k8s_create_connectivity_template` role:

- **K8s Role**: Discovers connectivity from live cluster state
- **Nutanix Role**: Uses pre-processed connectivity from EDA events
- **Both**: Update Apstra endpoint policies and maintain ConfigMaps

## Dependencies

None

## License

Apache-2.0

## Author Information

Created for Nutanix-Apstra integration via Event-Driven Ansible