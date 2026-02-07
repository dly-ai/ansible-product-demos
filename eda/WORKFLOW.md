# Catalyst EDA Workflow Documentation

## Complete Workflow Overview

This document describes the end-to-end workflow of the Catalyst 9000 Event-Driven Automation demo.

## High-Level Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    EVENT SOURCES                                │
│  ┌──────────────┐              ┌──────────────┐                │
│  │   Syslog     │              │   Webhook    │                │
│  │  (Port 514)  │              │ (Port 5000)  │                │
│  └──────┬───────┘              └──────┬───────┘                │
│         │                              │                         │
│         └──────────┬───────────────────┘                         │
│                   │                                             │
│                   ▼                                             │
│         ┌─────────────────────┐                                 │
│         │  EDA RULEBOOK       │                                 │
│         │  (Event Processing) │                                 │
│         └──────────┬──────────┘                                 │
│                   │                                             │
│         ┌─────────┴─────────┐                                  │
│         │                    │                                  │
│         ▼                    ▼                                  │
│  ┌──────────────┐    ┌──────────────┐                           │
│  │   APPROVAL   │    │   APPROVAL   │                           │
│  │   GRANTED    │    │   DENIED     │                           │
│  │   (true)     │    │   (false)    │                           │
│  └──────┬───────┘    └──────┬───────┘                           │
│         │                   │                                   │
│         ▼                   ▼                                   │
│  ┌─────────────────┐  ┌─────────────────┐                      │
│  │   REMEDIATION   │  │   NOTIFICATION  │                      │
│  │   PLAYBOOK      │  │   PLAYBOOK      │                      │
│  └─────────────────┘  └─────────────────┘                      │
└─────────────────────────────────────────────────────────────────┘
```

## Detailed Workflow Steps

### Phase 1: Event Detection

**Step 1.1: Event Sources Listen**
- **Syslog Listener** (Port 514): Listens for UDP syslog messages
- **Webhook Listener** (Port 5000): Listens for HTTP POST requests with JSON payloads

**Step 1.2: Event Received**
- Syslog: Receives message like `"Interface GigabitEthernet1/0/1, changed state to down"`
- Webhook: Receives JSON payload with `alert_type: "interface_down"`

### Phase 2: Rulebook Processing

**Step 2.1: Rule Matching**

The rulebook evaluates events against three rules:

#### Rule 1: Syslog Interface Down
```yaml
Condition:
  - event.syslog_message is defined
  - Contains "interface" (case-insensitive)
  - Contains "down" (case-insensitive)

Action:
  - Run: remediate_and_close.yml
  - Extract interface name from syslog message
  - Set approval_granted from vars (default: true)
```

#### Rule 2: Webhook Interface Alert
```yaml
Condition:
  - event.payload.alert_type == "interface_down"

Action:
  - Run: remediate_and_close.yml
  - Get interface name from payload
  - Get approval_granted from payload (or default: true)
```

#### Rule 3: Approval Denied Check
```yaml
Condition:
  - event.approval_granted == false

Action:
  - Run: notify_no_approval.yml
```

**Step 2.2: Approval Check**
- Checks `approval_granted` variable:
  - **Source 1**: From rulebook activation Extra Variables
  - **Source 2**: From webhook payload (`event.payload.approval_granted`)
  - **Default**: `true` (if not specified)

### Phase 3A: Remediation Workflow (approval_granted = true)

**Step 3A.1: Check Approval Status**
- Playbook: `remediate_and_close.yml`
- Task: Display approval status
- Task: Fail if approval not granted (safety check)

**Step 3A.2: Create ServiceNow Incident**
- **Role**: `service_now_integration`
- **Action**: POST to ServiceNow API
- **Creates**: New incident with:
  - Short Description: "Interface Down Alert: [interface]"
  - Description: Event details
  - Category: Network
  - State: In Progress
- **Stores**: Incident number and sys_id for later use

**Step 3A.3: Remediate Catalyst Interface**
- **Host**: Catalyst 9000 device
- **Role**: `catalyst_remediation`
- **Actions**:
  1. Gather network facts (interface status, device info)
  2. Gather CLI output:
     - `show interface [interface]`
     - `show vlan brief`
     - `show ip interface brief`
     - `show version`
  3. **Remediate**: Shut interface, wait 2 seconds, bring back up
  4. **Verify**: Check interface status after remediation
  5. **Compile**: Combine all CLI output with timestamps

**Step 3A.4: Attach CLI Output to ServiceNow**
- **Role**: `service_now_integration`
- **Action**: POST file attachment to ServiceNow
- **File**: `catalyst_cli_output_[interface]_[timestamp].txt`
- **Content**: All gathered CLI commands with timestamps

**Step 3A.5: Resolve ServiceNow Incident**
- **Role**: `service_now_integration`
- **Action**: PUT to update incident
- **Updates**:
  - State: Resolved (6)
  - Close Notes: "Issue automatically remediated by Ansible"
  - Work Notes: Remediation details

**Step 3A.6: Display Summary**
- Shows completion status
- Displays ServiceNow incident number
- Confirms remediation success

### Phase 3B: Notification Workflow (approval_granted = false)

**Step 3B.1: Create ServiceNow Incident**
- **Role**: `service_now_integration`
- **Action**: POST to ServiceNow API
- **Creates**: New incident with:
  - Short Description: "Interface Down - Remediation Blocked"
  - Description: "Remediation blocked due to lack of approval"
  - State: In Progress (requires manual intervention)

**Step 3B.2: Send Debug Notification**
- Displays notification message in AAP logs
- Shows interface, event source, and incident number

**Step 3B.3: Send Email Notification**
- **Module**: `community.general.mail`
- **Recipient**: Configured email address
- **Subject**: "Catalyst Interface Remediation Blocked - Interface [name]"
- **Body**: Includes:
  - Interface name
  - Event source
  - ServiceNow incident number
  - Direct link to ServiceNow incident
  - Instructions for manual intervention
- **Fallback**: If SMTP not configured, shows email content in debug output

**Step 3B.4: Display Summary**
- Shows notification completion
- Displays email status
- Confirms ServiceNow incident created

## Workflow Decision Points

### Decision Point 1: Event Type
```
Event Received
    │
    ├─→ Syslog Message?
    │   └─→ Rule 1: Extract interface, set vars
    │
    └─→ Webhook Payload?
        └─→ Rule 2: Get interface from payload
```

### Decision Point 2: Approval Status
```
approval_granted Check
    │
    ├─→ true
    │   └─→ Run: remediate_and_close.yml
    │       ├─→ Create ServiceNow Incident
    │       ├─→ Remediate Interface
    │       ├─→ Attach CLI Output
    │       └─→ Resolve Incident
    │
    └─→ false
        └─→ Run: notify_no_approval.yml
            ├─→ Create ServiceNow Incident
            └─→ Send Email Notification
```

## Data Flow

### Variables Flow
```
Rulebook Activation Extra Variables
    │
    ├─→ approval_granted
    ├─→ sn_instance, sn_user, sn_pass
    └─→ notification_email
         │
         ▼
Rulebook (sets vars for playbook)
    │
    ├─→ affected_interface
    ├─→ event_source
    ├─→ event_message
    ├─→ approval_granted
    └─→ incident_short_description
         │
         ▼
Playbook (uses vars)
    │
    ├─→ Passes to roles
    └─→ Stores facts (sn_incident_sys_id, cli_output_combined)
```

### ServiceNow Integration Flow
```
1. Create Incident
   └─→ Returns: incident_number, incident_sys_id
        │
        ▼
2. Attach File (if remediation)
   └─→ Uses: incident_sys_id
        │
        ▼
3. Update Incident
   └─→ Uses: incident_sys_id
        └─→ Sets: state = Resolved
```

## Timing Sequence

### Remediation Workflow Timeline
```
0s    - Event received
1s    - Rulebook matches rule
2s    - Playbook starts
3s    - ServiceNow incident created
5s    - Catalyst connection established
8s    - CLI commands gathered
12s   - Interface remediation (shut/no shut)
15s   - Interface verification
18s   - CLI output attached to ServiceNow
20s   - ServiceNow incident resolved
22s   - Workflow complete
```

### Notification Workflow Timeline
```
0s    - Event received
1s    - Rulebook matches rule (approval denied)
2s    - Playbook starts
3s    - ServiceNow incident created
5s    - Email notification sent
7s    - Workflow complete
```

## Key Components

### 1. Event Sources
- **Syslog**: Real-time network device logs
- **Webhook**: External monitoring systems (Dynatrace, etc.)

### 2. Rulebook
- **Purpose**: Event filtering and routing
- **Location**: `eda/rulebooks/catalyst_interface_rulebook.yml`
- **Functions**:
  - Listen for events
  - Match conditions
  - Route to appropriate playbook

### 3. Remediation Playbook
- **Purpose**: Automated interface remediation
- **Location**: `eda/playbooks/remediate_and_close.yml`
- **Functions**:
  - Create ServiceNow incident
  - Remediate network interface
  - Attach evidence
  - Close incident

### 4. Notification Playbook
- **Purpose**: Alert when remediation blocked
- **Location**: `eda/playbooks/notify_no_approval.yml`
- **Functions**:
  - Create ServiceNow incident
  - Send email notification

### 5. Roles
- **catalyst_remediation**: Network device operations
- **service_now_integration**: ServiceNow API operations

## Error Handling

### If Approval Denied
- Playbook fails early (safety check)
- Notification playbook runs instead
- ServiceNow incident created for tracking
- Email sent to notify team

### If Catalyst Connection Fails
- Playbook fails at remediation step
- ServiceNow incident remains "In Progress"
- Error logged in AAP activity stream

### If ServiceNow API Fails
- Playbook continues (ignore_errors: true where appropriate)
- Error logged in AAP activity stream
- Debug output shows failure details

## Testing the Workflow

### Test Remediation (approval_granted = true)
```bash
curl -X POST http://<EDA_HOST>:5000/endpoint \
  -H "Content-Type: application/json" \
  -d '{
    "alert_type": "interface_down",
    "interface_name": "GigabitEthernet1/0/1",
    "approval_granted": true
  }'
```

### Test Notification (approval_granted = false)
```bash
curl -X POST http://<EDA_HOST>:5000/endpoint \
  -H "Content-Type: application/json" \
  -d '{
    "alert_type": "interface_down",
    "interface_name": "GigabitEthernet1/0/1",
    "approval_granted": false
  }'
```

## Summary

The workflow is **event-driven**, **conditional**, and **fully automated**:

1. **Event** triggers rulebook
2. **Rulebook** routes based on approval status
3. **Remediation** or **Notification** playbook executes
4. **ServiceNow** tracks all actions
5. **Email** notifies when blocked
6. **Complete** automation with full audit trail
