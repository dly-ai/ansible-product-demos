#!/bin/bash
# Test script for triggering Catalyst EDA webhook events

# Configuration
EDA_HOST="${EDA_HOST:-localhost}"
EDA_PORT="${EDA_PORT:-5000}"
WEBHOOK_URL="http://${EDA_HOST}:${EDA_PORT}/endpoint"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Catalyst EDA Webhook Test Script ===${NC}\n"

# Test 1: Interface Down with Approval
echo -e "${GREEN}Test 1: Interface Down Alert (Approved)${NC}"
curl -X POST "${WEBHOOK_URL}" \
  -H "Content-Type: application/json" \
  -d '{
    "alert_type": "interface_down",
    "interface_name": "GigabitEthernet1/0/1",
    "title": "Interface Down Alert - Catalyst 9000",
    "description": "Interface GigabitEthernet1/0/1 detected as down. Remediation required.",
    "approval_granted": true,
    "severity": "high",
    "source": "test_script",
    "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
  }' \
  -w "\nHTTP Status: %{http_code}\n" \
  -s -o /dev/null

echo -e "\nWaiting 5 seconds...\n"
sleep 5

# Test 2: Interface Down without Approval
echo -e "${RED}Test 2: Interface Down Alert (Denied)${NC}"
curl -X POST "${WEBHOOK_URL}" \
  -H "Content-Type: application/json" \
  -d '{
    "alert_type": "interface_down",
    "interface_name": "GigabitEthernet1/0/2",
    "title": "Interface Down Alert - Catalyst 9000",
    "description": "Interface GigabitEthernet1/0/2 detected as down. Remediation blocked.",
    "approval_granted": false,
    "severity": "high",
    "source": "test_script",
    "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"
  }' \
  -w "\nHTTP Status: %{http_code}\n" \
  -s -o /dev/null

echo -e "\n${BLUE}=== Tests Complete ===${NC}"
echo -e "Check your EDA rulebook activation logs and ServiceNow incidents."
