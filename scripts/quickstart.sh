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
  echo "Please enter your PagerDuty API Token."
  echo "  (If using a User Token, you must be an Admin/Owner to provision resources)"
  echo "  (If using a Domain Token, ensure it has full access)"
  read -rsp "Token: " token
  echo
  if [[ -z "$token" ]]; then
    echo "Error: Token required." >&2
    exit 1
  fi
  export PAGERDUTY_TOKEN="$token"
fi
export TF_VAR_pagerduty_token="$PAGERDUTY_TOKEN"

# 2. Domain Check & Priorities Validation
echo
if [[ -z "${PD_DOMAIN:-}" ]]; then
  echo "Enter PagerDuty Domain Name (subdomain only):"
  echo "  Example: for 'https://acme-corp.pagerduty.com', enter 'acme-corp'"
  read -r domain
  if [[ -z "$domain" ]]; then
    echo "Error: Domain required." >&2
    exit 1
  fi
  export PD_DOMAIN="$domain"
fi

echo "-> Verifying connectivity to $PD_DOMAIN..."
# Check if Priorities are enabled (GET /priorities)
# We use this to test auth AND to warn the user if priorities are missing.
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Token token=$PAGERDUTY_TOKEN" -H "Accept: application/vnd.pagerduty+json;version=2" "https://api.pagerduty.com/priorities")

if [[ "$HTTP_STATUS" == "200" ]]; then
  echo "   [OK] Auth valid & Priorities enabled."
elif [[ "$HTTP_STATUS" == "401" || "$HTTP_STATUS" == "403" ]]; then
  echo "   [ERROR] Authentication failed (Status: $HTTP_STATUS). Check your Token."
  exit 1
else
  echo "   [WARN] Could not verify Priorities (Status: $HTTP_STATUS)."
  echo "          If this is a Free account, Event Orchestration rules involving P1-P5 might fail."
  echo "          Please enable 'Incident Priority' in Account Settings if available."
  read -p "   Press Enter to attempt provisioning anyway..."
fi

# 3. User Email (for Schedules)
if [[ -z "${POV_USER_EMAIL:-}" ]]; then
  echo
  echo "Who should be on-call for these teams?"
  echo "  Enter the email address of a valid user in this account."
  read -r user_email
  if [[ -z "$user_email" ]]; then
    echo "Error: Email required to assign schedules." >&2
    exit 1
  fi
  export POV_USER_EMAIL="$user_email"
fi
export TF_VAR_pov_user_email="$POV_USER_EMAIL"

# 4. Customer / Workspace Name
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

# 5. Terraform Init & Workspace
echo "-> Initializing Terraform..."
terraform init -upgrade -input=false >/dev/null

echo "-> Selecting Workspace..."
terraform workspace new "$WORKSPACE" >/dev/null 2>&1 || true
terraform workspace select "$WORKSPACE"

# 6. Plan & Apply
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
