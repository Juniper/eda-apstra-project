# ntx_create_security_zone

This Ansible role creates an Apstra security zone when a Nutanix virtual switch is created. It's designed to be triggered by Event-Driven Ansible (EDA) when monitoring Nutanix infrastructure events.

## Requirements

- Juniper Apstra collection (`juniper.apstra`)
- Access to Apstra management server
- Valid Apstra credentials

## Role Variables

### Required Variables

- `vswitch_name`: Name of the virtual switch from Nutanix event
- `blueprint_label_value`: Target Apstra blueprint label
- `apstra_server`: Apstra server URL
- `apstra_username`: Apstra username  
- `apstra_password`: Apstra password

### Optional Variables

- `vswitch_uuid`: UUID of the virtual switch (for tagging)
- `create_routing_policy`: Whether to create routing policy (default: true)
- `auto_commit_changes`: Whether to auto-commit blueprint changes (default: true)

## Expected Input Event

This role expects to process Nutanix virtual switch creation events with the following structure:

```json
{
  "nutanix_event": {
    "entity_type": "VIRTUAL_SWITCH",
    "event_type": "CREATED", 
    "timestamp": "2025-09-06T13:30:20.189667",
    "detection_time": "2025-09-06 13:30:20",
    "api_version": "v3"
  },
  "entity": {
    "name": "vs-test",
    "uuid": "018e3997-47ee-4018-bdfb-93eca6838d68",
    "cluster_uuid": null,
    "state": "ACTIVE"
  }
}
```

## Example Playbook

```yaml
- hosts: localhost
  vars:
    vswitch_name: "{{ entity.name }}"
    vswitch_uuid: "{{ entity.uuid }}"
    blueprint_label_value: "datacenter-fabric"
    apstra_server: "https://apstra.example.com"
    apstra_username: "admin"
    apstra_password: "password"
  roles:
    - ntx_create_security_zone
```

## Functionality

1. **Authentication**: Authenticates with Apstra server
2. **Blueprint Selection**: Retrieves target blueprint by label
3. **Security Zone Creation**: Creates security zone with naming convention `ntx-{vswitch_name}`
4. **VRF Creation**: Creates associated VRF with naming convention `vrf-{vswitch_name}`
5. **Tagging**: Applies comprehensive tags for traceability
6. **Routing Policy**: Optionally creates basic routing policy
7. **Blueprint Commit**: Commits changes to activate configuration

## Naming Conventions

- Security Zone: `ntx-{vswitch_name}` (sanitized)
- VRF: `vrf-{vswitch_name}` (sanitized)
- Routing Policy: `rp-ntx-{vswitch_name}` (if created)

## Tags Applied

- `source=nutanix_eda`
- `vswitch_name={vswitch_name}`
- `vswitch_uuid={vswitch_uuid}`
- `entity_type=virtual_switch`
- `event_type=created`

## Error Handling

- Validates required variables are present
- Checks for existing security zones to avoid conflicts
- Implements retry logic for API operations
- Graceful handling of tag creation conflicts

## Dependencies

None

## License

MIT

## Author Information

Created for Nutanix-Apstra integration via Event-Driven Ansible
