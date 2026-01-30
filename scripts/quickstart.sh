#!/usr/bin/env bash
set -euo pipefail

# OrbitPay POV Provisioner
# - Interactive wizard to spin up a POV environment
# - Handles Workspace creation per customer
# - Auto-detects configuration or prompts user

echo "========================================"
echo "   OrbitPay POV Provisioner (Sandbox)"
echo "========================================"

# 1. Credentials
if [[ -z "${PAGERDUTY_TOKEN:-}" ]]; then
  read -rsp "Enter PagerDuty API User Token: " token
  echo
  if [[ -z "$token" ]]; then
    echo "Error: Token required." >&2
    exit 1
  fi
  export PAGERDUTY_TOKEN="$token"
fi
export TF_VAR_pagerduty_token="$PAGERDUTY_TOKEN"

# 2. User Email (for Schedules)
if [[ -z "${POV_USER_EMAIL:-}" ]]; then
  echo "Who should be on-call? (Enter email address)"
  read -r user_email
  if [[ -z "$user_email" ]]; then
    echo "Error: Email required to assign schedules." >&2
    exit 1
  fi
  export POV_USER_EMAIL="$user_email"
fi
export TF_VAR_pov_user_email="$POV_USER_EMAIL"

# 3. Customer / Workspace Name
echo
echo "Enter Customer Name for this POV (e.g. 'Acme Corp'):"
read -r customer_name
# Sanitize: lowercase, replace spaces with dashes, remove special chars
safe_name=$(echo "$customer_name" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-' | sed 's/[^a-z0-9-]//g')

if [[ -z "$safe_name" ]]; then
  echo "Error: Invalid customer name." >&2
  exit 1
fi

WORKSPACE="pov-$safe_name"
echo "-> Target Workspace: $WORKSPACE"

# 4. Terraform Init & Workspace
echo "-> Initializing Terraform..."
terraform init -upgrade -input=false >/dev/null

echo "-> Selecting Workspace..."
terraform workspace new "$WORKSPACE" >/dev/null 2>&1 || true
terraform workspace select "$WORKSPACE"

# 5. Plan & Apply
echo
echo "Ready to provision OrbitPay POV for '$customer_name'."
echo "This will create:"
echo "  - 4 Teams (PP, WL, CX, CI)"
echo "  - Services & Dependencies"
echo "  - On-call schedules for $POV_USER_EMAIL"
echo
read -p "Press Enter to continue or Ctrl+C to cancel..."

terraform apply -auto-approve

echo
echo "========================================"
echo "   POV Provisioned Successfully!"
echo "   Workspace: $WORKSPACE"
echo "========================================"