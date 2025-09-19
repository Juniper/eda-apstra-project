# ntx_delete_connectivity_template

This Ansible role removes Apstra connectivity templates when Nutanix VM connectivity is deleted. It's designed to be triggered by Event-Driven Ansible (EDA) when monitoring Nutanix VM lifecycle events (deletion, power off with network disconnection).

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
- `require_powered_on_vm`: Only process VMs that are powered on (default: false for delete operations)
- `require_physical_connectivity`: Only process VMs with physical connectivity data (default: true)
- `auto_commit_changes`: Whether to auto-commit blueprint changes (default: true)
- `create_connectivity_configmap`: Whether to update ConfigMap entries (default: true)

## Expected Input Event

This role expects to process Nutanix VM events with comprehensive connectivity information for deletion/disconnection scenarios:

```json
{
  "nutanix_event": {
    "entity_type": "VM",
    "event_type": "DELETED",
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
    "power_state": "OFF",
    "host_info": {
      "host_name": "nutanix-host-1",
      "host_uuid": "12345678-1234-1234-1234-123456789abc"
    },
    "network_interfaces": [
      {
        "nic_index": 0,
        "ip_address": "10.0.1.100",
        "mac_address": "50:6b:8d:12:34:56",
        "subnet_name": "production-network",
        "subnet_uuid": "subnet-uuid-123",
        "physical_connectivity": {
          "vswitch_name": "vs0",
          "vswitch_uuid": "vswitch-uuid-123",
          "host_port": "vmnic0",
          "physical_switch": "leaf01.datacenter.local",
          "switch_port": "et-0/0/48"
        }
      }
    ],
    "primary_connectivity": {
      "vswitch_uuid": "vswitch-uuid-123",
      "physical_switch": "leaf01.datacenter.local",
      "host_name": "nutanix-host-1"
    }
  }
}
```

## Features

- **Deletion Safety**: Processes VM deletion and power-off events
- **Application Point Removal**: Sets endpoint policy application points state to "absent"
- **ConfigMap Cleanup**: Removes VM connectivity entries from Kubernetes ConfigMaps
- **Blueprint Management**: Handles Apstra blueprint locking/unlocking and committing
- **Error Handling**: Graceful handling of missing resources and API errors
- **Tag Management**: Manages connectivity tags for proper resource tracking

## Behavior

1. **Event Filtering**: 
   - Processes DELETED events and powered-off VMs
   - Ignores CREATE events and powered-on VMs
   - Validates VM has required connectivity information

2. **Connectivity Removal**:
   - Removes application points from endpoint policies (state: absent)
   - Cleans up VM entries from connectivity ConfigMaps
   - Maintains virtual network and other shared resources

3. **Blueprint Operations**:
   - Locks blueprint during operations
   - Commits changes upon completion
   - Unlocks blueprint in error scenarios

## Usage

This role is typically called from EDA rulebooks for VM deletion events:

```yaml
---
- name: VM Deletion Connectivity Cleanup
  hosts: localhost
  roles:
    - role: ntx_delete_connectivity_template
      vars:
        nutanix_event: "{{ event_data.nutanix_event }}"
        entity: "{{ event_data.entity }}"
        vm: "{{ event_data.vm }}"
```

## Dependencies

- `juniper.apstra` collection for Apstra API operations
- `kubernetes.core` collection for ConfigMap management
- Proper authentication and network access to both Apstra and Kubernetes

## Notes

- This role is the counterpart to `ntx_create_connectivity_template`
- It focuses on cleanup and removal rather than creation
- ConfigMap entries are removed to maintain consistency
- Virtual networks and shared resources are preserved for other VMs

## License

Apache-2.0