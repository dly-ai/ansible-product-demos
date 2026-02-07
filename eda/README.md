# Catalyst 9000 Event-Driven Automation Demo with ServiceNow Integration

This demo showcases Ansible Event-Driven Automation (EDA) for automated network interface remediation on Cisco Catalyst 9000 devices, integrated with ServiceNow for incident management.

## Overview

The demo automatically:
1. **Listens** for interface down events (via syslog or webhook)
2. **Creates** a ServiceNow incident
3. **Checks** approval status (configurable boolean)
4. **Remediates** the interface if approved (shut/no shut)
5. **Gathers** CLI output from the device
6. **Attaches** CLI output to the ServiceNow incident
7. **Resolves** the incident automatically

If approval is denied, it sends notifications instead of remediating.

## Architecture

```
Event Source (Syslog/Webhook)
    ↓
EDA Rulebook (catalyst_interface_rulebook.yml)
    ↓
    ├─→ Approval Granted? YES → Remediation Playbook
    │                              ├─→ Create ServiceNow Incident
    │                              ├─→ Remediate Interface
    │                              ├─→ Gather CLI Output
    │                              ├─→ Attach to Incident
    │                              └─→ Resolve Incident
    │
    └─→ Approval Granted? NO → Notification Playbook
                                     ├─→ Create ServiceNow Incident
                                     └─→ Send Notifications
```

## Directory Structure

```
eda/
├── rulebooks/
│   └── catalyst_interface_rulebook.yml    # EDA rulebook with event sources
├── playbooks/
│   ├── remediate_and_close.yml            # Main remediation workflow
│   └── notify_no_approval.yml             # Notification workflow
├── roles/
│   ├── catalyst_remediation/
│   │   └── tasks/
│   │       └── main.yml                   # Network interface remediation
│   └── service_now_integration/
│       ├── defaults/
│       │   └── main.yml                   # ServiceNow defaults
│       └── tasks/
│           └── main.yml                    # ServiceNow REST API operations
├── vars.yml                                # Configuration variables
├── inventory.yml                           # Catalyst 9000 inventory
└── README.md                               # This file
```

## Prerequisites

### 1. Ansible Automation Platform 2.x
- Ansible Automation Platform Controller (AAP) 2.5+
- Event-Driven Ansible (EDA) controller configured
- Execution environment with required collections

### 2. Required Ansible Collections
```yaml
collections:
  - name: cisco.ios
    version: ">=7.0.0"
  - name: ansible.eda
    version: ">=2.1.0"
  - name: ansible.netcommon
    version: ">=6.0.0"
  - name: ansible.builtin
```

### 3. Python Dependencies
- `requests` (for ServiceNow REST API - included in ansible.builtin.uri)

### 4. ServiceNow Personal Developer Instance (PDI)
- Access to a ServiceNow PDI instance
- Technical user with REST API permissions
- User credentials (username/password)

### 5. Catalyst 9000 Always-On Sandbox
- Access to Cisco DevNet Catalyst 9000 sandbox
- SSH credentials configured

## Setup Instructions

### Step 1: Configure Variables

Edit `vars.yml` with your ServiceNow PDI credentials:

```yaml
sn_instance: "https://dev12345.service-now.com"  # Your PDI URL
sn_user: "admin"                                  # Your ServiceNow user
sn_pass: "your_password_here"                     # Your ServiceNow password
approval_granted: true                            # Set to false to test denial
```

### Step 2: Verify Inventory

Verify `inventory.yml` has correct Catalyst 9000 credentials:

```yaml
sandbox-iosxe-latest-1.cisco.com:
  ansible_host: devnetsandboxiosxec9k.cisco.com
  ansible_user: dly
  ansible_password: 9Cnz-V5_bq2U
```

### Step 3: Upload to Ansible Automation Platform

1. **Create a Project** in AAP Controller:
   - Name: `Catalyst EDA Demo`
   - SCM Type: Git (or Manual)
   - Source: This repository or upload files manually

2. **Create an Inventory**:
   - Name: `Catalyst EDA Inventory`
   - Source: Upload `inventory.yml` or create manually

3. **Create a Rulebook Activation**:
   - Name: `Catalyst Interface Remediation`
   - Rulebook: `rulebooks/catalyst_interface_rulebook.yml`
   - Inventory: `Catalyst EDA Inventory`
   - Extra Variables: Load from `vars.yml` or enter manually
   - Execution Environment: One with `cisco.ios` and `ansible.eda` collections

### Step 4: Activate the Rulebook

1. Navigate to **Event-Driven Ansible** → **Rulebook Activations**
2. Click **Create Rulebook Activation**
3. Configure:
   - **Name**: `Catalyst Interface Remediation`
   - **Rulebook**: Select `catalyst_interface_rulebook.yml`
   - **Inventory**: Select `Catalyst EDA Inventory`
   - **Extra Variables**: 
     ```yaml
     sn_instance: "https://dev12345.service-now.com"
     sn_user: "admin"
     sn_pass: "your_password"
     approval_granted: true
     ```
   - **Execution Environment**: Select one with required collections
4. Click **Save** and **Start** the activation

## Usage

### Method 1: Trigger via Syslog

The rulebook listens on port 514 for syslog messages. Send a test syslog message:

```bash
# From a Linux machine with netcat
echo "<134>Interface GigabitEthernet1/0/1, changed state to down" | nc -u <EDA_HOST> 514
```

Or use a syslog generator:
```bash
logger -n <EDA_HOST> -P 514 "Interface GigabitEthernet1/0/1, changed state to down"
```

### Method 2: Trigger via Webhook

The rulebook listens on port 5000 for webhook payloads. Send a test webhook:

```bash
curl -X POST http://<EDA_HOST>:5000/endpoint \
  -H "Content-Type: application/json" \
  -d '{
    "alert_type": "interface_down",
    "interface_name": "GigabitEthernet1/0/1",
    "title": "Interface Down Alert",
    "description": "Interface GigabitEthernet1/0/1 is down",
    "approval_granted": true
  }'
```

### Method 3: Simulate Dynatrace Alert

```bash
curl -X POST http://<EDA_HOST>:5000/endpoint \
  -H "Content-Type: application/json" \
  -d '{
    "alert_type": "interface_down",
    "interface_name": "GigabitEthernet1/0/1",
    "title": "Dynatrace Alert: Interface Down",
    "description": "Dynatrace detected interface down condition",
    "approval_granted": true
  }'
```

## Testing Approval Denial

To test the notification flow when approval is denied:

1. Update `vars.yml`:
   ```yaml
   approval_granted: false
   ```

2. Or send webhook with denial:
   ```bash
   curl -X POST http://<EDA_HOST>:5000/endpoint \
     -H "Content-Type: application/json" \
     -d '{
       "alert_type": "interface_down",
       "interface_name": "GigabitEthernet1/0/1",
       "approval_granted": false
     }'
   ```

## Observing the Workflow

### 1. Check EDA Rulebook Activation Logs
- Navigate to **Event-Driven Ansible** → **Rulebook Activations**
- Click on your activation
- View **Activity Stream** for event processing

### 2. Check ServiceNow Incident
- Log into your ServiceNow PDI
- Navigate to **Incidents** → **All**
- Look for incidents with:
  - Short Description: "Interface Down Alert: GigabitEthernet1/0/1"
  - Category: "Network"
  - State: "Resolved" (after remediation)

### 3. Check Attached Files
- Open the ServiceNow incident
- Navigate to **Attachments** tab
- Download `catalyst_cli_output_*.txt` file
- Review CLI output (show interface, show vlan, etc.)

### 4. Check Catalyst Device
- SSH to the Catalyst 9000 device
- Verify interface status:
  ```bash
  show interface GigabitEthernet1/0/1
  ```

## Configuration Options

### Variables in `vars.yml`

| Variable | Description | Default |
|----------|-------------|---------|
| `sn_instance` | ServiceNow PDI URL | `https://dev12345.service-now.com` |
| `sn_user` | ServiceNow username | `admin` |
| `sn_pass` | ServiceNow password | (required) |
| `approval_granted` | Enable/disable remediation | `true` |
| `default_interface` | Default interface for remediation | `GigabitEthernet1/0/1` |
| `slack_webhook_url` | Slack webhook (optional) | (empty) |
| `notification_email` | Email for notifications | `admin@example.com` |

### Interface Remediation

The remediation playbook performs:
1. **Gather Facts**: Collects interface status and device information
2. **Gather CLI Output**: Runs multiple show commands
3. **Interface Bounce**: Shuts and re-enables the interface
4. **Verification**: Confirms interface is back up

### ServiceNow Integration

The ServiceNow role performs:
1. **Create Incident**: Creates new incident with event details
2. **Attach Files**: Attaches CLI output as text file
3. **Update Incident**: Sets state to "Resolved" with close notes

## Troubleshooting

### Issue: Rulebook not receiving events

**Solution:**
- Verify firewall allows ports 514 (syslog) and 5000 (webhook)
- Check EDA controller logs for errors
- Verify rulebook activation is running

### Issue: ServiceNow API errors

**Solution:**
- Verify ServiceNow credentials in `vars.yml`
- Check ServiceNow user has REST API permissions
- Verify PDI instance URL is correct
- Check ServiceNow API logs

### Issue: Catalyst connection fails

**Solution:**
- Verify inventory credentials in `inventory.yml`
- Test SSH connection manually
- Check network connectivity to Catalyst device
- Verify `ansible_network_os` is set correctly

### Issue: Interface remediation fails

**Solution:**
- Verify interface name exists on device
- Check user has enable privileges
- Review Catalyst device logs
- Verify `cisco.ios` collection is installed

## Advanced Configuration

### Custom CLI Commands

Edit `roles/catalyst_remediation/tasks/main.yml` to add custom commands:

```yaml
- name: Gather Custom CLI Output
  cisco.ios.ios_command:
    commands:
      - "show running-config interface {{ affected_interface }}"
  register: cli_custom
```

### Custom ServiceNow Fields

Edit `roles/service_now_integration/tasks/main.yml` to add custom fields:

```yaml
body:
  short_description: "{{ incident_short_description }}"
  custom_field: "{{ custom_value }}"
```

### Multiple Interfaces

Modify the rulebook to handle multiple interfaces:

```yaml
affected_interface: "{{ event.payload.interfaces | default(['GigabitEthernet1/0/1']) }}"
```

## Security Considerations

1. **Credentials**: Store ServiceNow and device credentials in AAP Credentials, not in files
2. **Network**: Use VPN or secure network for EDA controller
3. **TLS**: Configure HTTPS for ServiceNow API (update URL to use HTTPS)
4. **Firewall**: Restrict syslog/webhook ports to trusted sources
5. **Logging**: Set `no_log: true` in production for sensitive tasks

## Support and Resources

- [Ansible Event-Driven Automation Documentation](https://docs.ansible.com/automation-controller/latest/html/userguide/eda.html)
- [Cisco IOS Collection Documentation](https://docs.ansible.com/ansible/latest/collections/cisco/ios/)
- [ServiceNow REST API Documentation](https://developer.servicenow.com/dev.do#!/reference/api/rome/rest/c_TableAPI)
- [Catalyst 9000 DevNet Sandbox](https://developer.cisco.com/docs/sandbox/)

## License

This demo is provided as-is for educational and demonstration purposes.
