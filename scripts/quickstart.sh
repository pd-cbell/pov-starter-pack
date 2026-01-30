#!/usr/bin/env bash
set -euo pipefail

# OrbitPay POV Provisioner
# - Interactive wizard to spin up or tear down a POV environment
# - Handles Workspace creation per customer
# - Auto-detects configuration or prompts user

MODE="provision"
if [[ "${1:-}" == "--destroy" || "${1:-}" == "-d" || "${1:-}" == "destroy" ]]; then
  MODE="destroy"
fi

echo "========================================"
if [[ "$MODE" == "destroy" ]]; then
  echo "   OrbitPay POV CLEANUP (Destroy)"
else
  echo "   OrbitPay POV Provisioner (Sandbox)"
fi
echo "========================================"

# --- 1. Credentials ---
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

# --- 2. Region Selection ---
if [[ -z "${PD_REGION:-}" ]]; then
  echo
  echo "Select PagerDuty Region:"
  echo "  1) US (default)"
  echo "  2) EU"
  read -r -p "Enter 1 or 2: " region_choice
  case "$region_choice" in
    2|EU|eu)
      PD_REGION="EU"
      ;;
    *)
      PD_REGION="US"
      ;;
  esac
fi

if [[ "$PD_REGION" == "EU" ]]; then
  API_BASE_URL="https://api.eu.pagerduty.com"
else
  API_BASE_URL="https://api.pagerduty.com"
fi
export TF_VAR_pagerduty_api_url_override="$API_BASE_URL"

# --- 3. Domain Check ---
# (Verify connectivity - useful for both modes to ensure token is valid)
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

echo "-> Verifying connectivity to $PD_DOMAIN ($PD_REGION)..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Token token=$PAGERDUTY_TOKEN" -H "Accept: application/vnd.pagerduty+json;version=2" "$API_BASE_URL/priorities")

if [[ "$HTTP_STATUS" == "200" ]]; then
  echo "   [OK] Auth valid."
elif [[ "$HTTP_STATUS" == "401" || "$HTTP_STATUS" == "403" ]]; then
  echo "   [ERROR] Authentication failed (Status: $HTTP_STATUS). Check your Token."
  exit 1
else
  echo "   [WARN] API Check returned status $HTTP_STATUS. Proceeding..."
fi

# --- 4. Customer / Workspace Name ---
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

# --- 5. Terraform Init ---
echo "-> Initializing Terraform..."
terraform init -upgrade -input=false >/dev/null

# --- 6. Mode Execution ---

if [[ "$MODE" == "provision" ]]; then

  # User Email (Only needed for provisioning schedules)
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

  echo "-> Selecting/Creating Workspace..."
  terraform workspace new "$WORKSPACE" >/dev/null 2>&1 || true
  terraform workspace select "$WORKSPACE"

  echo
  echo "Ready to provision OrbitPay POV for '$customer_name'."
  echo "This will create teams, services, and schedules for $POV_USER_EMAIL."
  read -p "Press Enter to continue..."

  terraform apply -auto-approve
  
  echo
  echo "========================================"
  echo "   POV Provisioned Successfully!"
  echo "   Workspace: $WORKSPACE"
  echo "========================================"

else # MODE == destroy

  echo "-> Selecting Workspace..."
  if ! terraform workspace select "$WORKSPACE"; then
    echo "Error: Workspace '$WORKSPACE' does not exist. Nothing to destroy?"
    exit 1
  fi
  
  # We need to set dummy variables for destroy to work if validation requires them
  # (Though TF destroy usually needs valid inputs if providers use them)
  export TF_VAR_pov_user_email="dummy@example.com"

  echo
  echo "WARNING: You are about to DESTROY the OrbitPay POV for '$customer_name'."
  echo "Workspace: $WORKSPACE"
  echo "This action cannot be undone."
  read -p "Type 'yes' to confirm destruction: " confirm
  
  if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    exit 0
  fi

  terraform destroy -auto-approve

  echo "-> Removing Workspace..."
  terraform workspace select default
  terraform workspace delete "$WORKSPACE"

  echo
  echo "========================================"
  echo "   Cleanup Complete."
  echo "========================================"
fi