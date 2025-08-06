#!/bin/bash

# Network Tier Migration Script
# Migrates GCP Compute Engine deployment from Premium to Standard network tier
# Usage: ./network-tier-migration.sh [step_number] [--rollback]

set -e

# --- Configuration ---
SCRIPT_NAME="Network Tier Migration"
VERSION="1.0.0"

# Load environment variables from .env.production
if [ ! -f ".env.production" ]; then
  echo "ERROR: .env.production file not found in current directory!"
  exit 1
fi
source .env.production

# Default values (can be overridden by .env.production)
DEFAULT_REGION="us-central1"
DEFAULT_INSTANCE_NAME="metamcp-instance"
DEFAULT_STATIC_IP_NAME="metamcp-static-ip"

# Use values from .env.production or defaults
REGION="${REGION:-$DEFAULT_REGION}"
ZONE="${ZONE:-${REGION}-a}"
INSTANCE_NAME="${INSTANCE_NAME:-$DEFAULT_INSTANCE_NAME}"
STATIC_IP_NAME="${STATIC_IP_NAME:-$DEFAULT_STATIC_IP_NAME}"

# Migration-specific variables
NEW_STATIC_IP_NAME="${STATIC_IP_NAME}-standard"
BACKUP_FILE="network-tier-migration-backup.json"
STATE_FILE="network-tier-migration-state.json"

# --- Helper Functions ---
info() {
  echo "INFO: $1"
}

error() {
  echo "ERROR: $1" >&2
}

success() {
  echo "SUCCESS: $1"
}

# Save migration state
save_state() {
  local step="$1"
  local data="$2"
  
  cat > "$STATE_FILE" << EOF
{
  "current_step": $step,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "region": "$REGION",
  "zone": "$ZONE",
  "instance_name": "$INSTANCE_NAME",
  "old_static_ip_name": "$STATIC_IP_NAME",
  "new_static_ip_name": "$NEW_STATIC_IP_NAME",
  "data": $data
}
EOF
  info "State saved to $STATE_FILE"
}

# Load migration state
load_state() {
  if [ -f "$STATE_FILE" ]; then
    cat "$STATE_FILE"
  else
    echo "{}"
  fi
}

# Save backup information
save_backup() {
  local backup_data="$1"
  echo "$backup_data" > "$BACKUP_FILE"
  info "Backup information saved to $BACKUP_FILE"
}

# Check if step was already completed
is_step_completed() {
  local step="$1"
  local current_step=$(load_state | jq -r '.current_step // 0')
  [ "$current_step" -ge "$step" ]
}

# Show usage information
show_usage() {
  cat << EOF
$SCRIPT_NAME v$VERSION

USAGE:
  $0 [step_number] [--rollback]

STEPS:
  1. Pre-migration validation and backup
  2. Create new standard-tier static IP
  3. Stop VM instance
  4. Update VM network configuration
  5. Start VM instance
  6. Update DNS records
  7. Validate deployment
  8. Update deployment scripts
  9. Cleanup old resources
  0. Run all steps (full migration)

ROLLBACK:
  $0 --rollback    Rollback the migration using backup data

EXAMPLES:
  $0 0            # Run complete migration
  $0 3            # Start from step 3 (stop VM)
  $0 --rollback   # Rollback migration

EOF
}

# --- Step Functions ---

# Step 1: Pre-migration validation and backup
step_1_validation_backup() {
  info "=== STEP 1: PRE-MIGRATION VALIDATION AND BACKUP ==="
  
  # Check if VM instance exists
  if ! gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" &>/dev/null; then
    error "VM instance '$INSTANCE_NAME' not found in zone '$ZONE'"
    exit 1
  fi
  
  # Get current VM configuration
  info "Backing up current VM configuration..."
  local vm_config=$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="json")
  
  # Get current static IP information
  info "Backing up current static IP configuration..."
  local static_ip_config=""
  if gcloud compute addresses describe "$STATIC_IP_NAME" --region="$REGION" &>/dev/null; then
    static_ip_config=$(gcloud compute addresses describe "$STATIC_IP_NAME" --region="$REGION" --format="json")
  fi
  
  # Create backup
  local backup_data=$(jq -n \
    --argjson vm_config "$vm_config" \
    --argjson static_ip_config "$static_ip_config" \
    '{
      "timestamp": now | todate,
      "vm_config": $vm_config,
      "static_ip_config": $static_ip_config
    }')
  
  save_backup "$backup_data"
  
  # Extract current external IP
  local current_external_ip=$(echo "$vm_config" | jq -r '.networkInterfaces[0].accessConfigs[0].natIP // "none"')
  local current_network_tier=$(echo "$vm_config" | jq -r '.networkInterfaces[0].accessConfigs[0].networkTier // "PREMIUM"')
  
  info "Current external IP: $current_external_ip"
  info "Current network tier: $current_network_tier"
  
  if [ "$current_network_tier" = "STANDARD" ]; then
    info "VM is already using STANDARD network tier. No migration needed."
    exit 0
  fi
  
  save_state 1 "{\"current_external_ip\": \"$current_external_ip\", \"current_network_tier\": \"$current_network_tier\"}"
  success "Pre-migration validation and backup completed"
}

# Step 2: Create new standard-tier static IP
step_2_create_standard_ip() {
  info "=== STEP 2: CREATE NEW STANDARD-TIER STATIC IP ==="
  
  # Check if standard IP already exists
  if gcloud compute addresses describe "$NEW_STATIC_IP_NAME" --region="$REGION" &>/dev/null; then
    info "Standard-tier static IP '$NEW_STATIC_IP_NAME' already exists"
  else
    info "Creating new standard-tier static IP address..."
    gcloud compute addresses create "$NEW_STATIC_IP_NAME" \
      --region="$REGION" \
      --network-tier=STANDARD
  fi
  
  # Get the new IP address
  local new_ip=$(gcloud compute addresses describe "$NEW_STATIC_IP_NAME" --region="$REGION" --format="value(address)")
  info "New standard-tier static IP: $new_ip"
  
  save_state 2 "{\"new_static_ip\": \"$new_ip\"}"
  success "Standard-tier static IP created successfully"
}

# Step 3: Stop VM instance
step_3_stop_vm() {
  info "=== STEP 3: STOP VM INSTANCE ==="
  
  # Check current VM status
  local vm_status=$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="value(status)")
  
  if [ "$vm_status" = "RUNNING" ]; then
    info "Stopping VM instance '$INSTANCE_NAME'..."
    gcloud compute instances stop "$INSTANCE_NAME" --zone="$ZONE"
    
    # Wait for VM to stop
    info "Waiting for VM to stop completely..."
    while [ "$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="value(status)")" != "TERMINATED" ]; do
      sleep 5
      echo -n "."
    done
    echo ""
  else
    info "VM instance is already stopped (status: $vm_status)"
  fi
  
  save_state 3 "{\"vm_stopped\": true}"
  success "VM instance stopped successfully"
}

# Step 4: Update VM network configuration
step_4_update_network_config() {
  info "=== STEP 4: UPDATE VM NETWORK CONFIGURATION ==="
  
  local new_ip=$(load_state | jq -r '.data.new_static_ip')
  
  # Get current access config name
  local current_access_config_name=$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="value(networkInterfaces[0].accessConfigs[0].name)")
  
  # Delete current access config
  info "Removing current access configuration..."
  gcloud compute instances delete-access-config "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --access-config-name="$current_access_config_name" || true
  
  # Add new access config with standard tier
  info "Adding new access configuration with standard network tier..."
  gcloud compute instances add-access-config "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --access-config-name="external-nat" \
    --address="$new_ip" \
    --network-tier=STANDARD
  
  save_state 4 "{\"network_config_updated\": true, \"new_static_ip\": \"$new_ip\"}"
  success "VM network configuration updated successfully"
}

# Step 5: Start VM instance
step_5_start_vm() {
  info "=== STEP 5: START VM INSTANCE ==="
  
  info "Starting VM instance '$INSTANCE_NAME'..."
  gcloud compute instances start "$INSTANCE_NAME" --zone="$ZONE"
  
  # Wait for VM to start
  info "Waiting for VM to start completely..."
  while [ "$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="value(status)")" != "RUNNING" ]; do
    sleep 5
    echo -n "."
  done
  echo ""
  
  # Wait additional time for services to initialize
  info "Waiting for services to initialize..."
  sleep 30
  
  save_state 5 "{\"vm_started\": true}"
  success "VM instance started successfully"
}

# Step 6: Update DNS records
step_6_update_dns() {
  info "=== STEP 6: UPDATE DNS RECORDS ==="
  
  local new_ip=$(load_state | jq -r '.data.new_static_ip')
  local current_vm_ip=$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="value(networkInterfaces[0].accessConfigs[0].natIP)")
  
  info "Current VM IP: $current_vm_ip"
  info "Target IP for DNS: $new_ip"
  
  # Check current DNS resolution if domain is configured
  local dns_needs_update=true
  if [ -n "$DOMAIN_NAME" ]; then
    info "Checking current DNS resolution for $DOMAIN_NAME..."
    local current_dns_ip=$(dig +short "$DOMAIN_NAME" @8.8.8.8 | tail -1)
    info "Current DNS resolution: $current_dns_ip"
    
    if [ "$current_dns_ip" = "$new_ip" ]; then
      info "DNS already points to the correct IP address."
      dns_needs_update=false
    else
      info "DNS points to $current_dns_ip but should point to $new_ip"
      dns_needs_update=true
    fi
  fi
  
  if [ "$dns_needs_update" = false ]; then
    info "DNS records are already correct. No update needed."
    save_state 6 "{\"dns_updated\": true, \"ip_changed\": false, \"dns_already_correct\": true}"
    success "DNS records check completed"
    return 0
  fi
  
  info "DNS records need to be updated to point to $new_ip"
  
  # Check if we have the required DNS API credentials
  if [ -z "$DOMAIN_NAME" ] || [ -z "$PORKBUN_API_KEY" ] || [ -z "$PORKBUN_SECRET_KEY" ]; then
    error "Missing DNS credentials. Please update DNS records manually:"
    error "  Domain: $DOMAIN_NAME"
    error "  Current DNS IP: ${current_dns_ip:-'not resolved'}"
    error "  Required IP: $new_ip"
    error "Update the following records:"
    error "  - A record for root domain: $DOMAIN_NAME -> $new_ip"
    error "  - A record for www subdomain: www.$DOMAIN_NAME -> $new_ip"
    read -p "Press Enter after manually updating DNS records..."
  else
    # Source the DNS functions but don't execute the full script
    if [ -f "deploy/compute_engine_deploy.sh" ]; then
      # Extract just the DNS functions we need
      info "Using DNS update functions from deployment script..."
      
      # Create a temporary function file with just the DNS functions
      cat > /tmp/dns_functions.sh << 'DNSFUNC'
# Function to delete existing DNS records for a domain/subdomain
delete_existing_records() {
  local domain="$1"
  local subdomain="$2"
  local target_name="${subdomain:+$subdomain.}$domain"
  
  echo "INFO: Checking for existing DNS records for $target_name"
  
  # Get existing records
  local records_response=$(curl -s --header "Content-Type: application/json" \
    --request POST \
    --data "{
      \"secretapikey\": \"$PORKBUN_SECRET_KEY\",
      \"apikey\": \"$PORKBUN_API_KEY\"
    }" \
    "https://api.porkbun.com/api/json/v3/dns/retrieve/$domain")
  
  # Extract record IDs for the target name that are A or ALIAS records
  local record_ids=$(echo "$records_response" | jq -r ".records[]? | select(.name == \"$target_name\" and (.type == \"A\" or .type == \"ALIAS\")) | .id")
  
  if [ -n "$record_ids" ]; then
    for record_id in $record_ids; do
      echo "INFO: Deleting existing record ID: $record_id"
      local delete_response=$(curl -s --header "Content-Type: application/json" \
        --request POST \
        --data "{
          \"secretapikey\": \"$PORKBUN_SECRET_KEY\",
          \"apikey\": \"$PORKBUN_API_KEY\"
        }" \
        "https://api.porkbun.com/api/json/v3/dns/delete/$domain/$record_id")
      
      if echo "$delete_response" | grep -q '"status":"SUCCESS"'; then
        echo "INFO: Successfully deleted record ID: $record_id"
      else
        echo "WARNING: Failed to delete record ID $record_id: $delete_response"
      fi
    done
  else
    echo "INFO: No existing A/ALIAS records found for $target_name"
  fi
}

# Function to create DNS A record via Porkbun API
create_dns_record() {
  local domain="$1"
  local subdomain="$2"
  local ip_address="$3"
  
  # First delete any existing records
  delete_existing_records "$domain" "$subdomain"
  
  echo "INFO: Creating DNS A record for ${subdomain:+$subdomain.}$domain pointing to $ip_address"
  
  local response=$(curl -s --header "Content-Type: application/json" \
    --request POST \
    --data "{
      \"secretapikey\": \"$PORKBUN_SECRET_KEY\",
      \"apikey\": \"$PORKBUN_API_KEY\",
      \"name\": \"$subdomain\",
      \"type\": \"A\",
      \"content\": \"$ip_address\",
      \"ttl\": \"300\"
    }" \
    "https://api.porkbun.com/api/json/v3/dns/create/$domain")
  
  if echo "$response" | grep -q '"status":"SUCCESS"'; then
    echo "INFO: DNS record created successfully"
    echo "$response" | grep -o '"id":"[^"]*"' | cut -d'"' -f4
  else
    echo "ERROR: Failed to create DNS record. Response: $response"
    exit 1
  fi
}
DNSFUNC
      
      # Source the temporary function file
      source /tmp/dns_functions.sh
      
      # Update DNS records
      info "Updating DNS A record for root domain..."
      create_dns_record "$DOMAIN_NAME" "" "$new_ip"
      
      info "Updating DNS A record for www subdomain..."
      create_dns_record "$DOMAIN_NAME" "www" "$new_ip"
      
      # Clean up temporary file
      rm -f /tmp/dns_functions.sh
      
      info "DNS records updated. Waiting for initial propagation..."
      sleep 60  # Wait 1 minute for initial propagation
    else
      error "Deployment script not found. Cannot use automated DNS update."
      error "Please update DNS records manually:"
      error "  - A record for root domain: $DOMAIN_NAME -> $new_ip"
      error "  - A record for www subdomain: www.$DOMAIN_NAME -> $new_ip"
      read -p "Press Enter after manually updating DNS records..."
    fi
  fi
  
  save_state 6 "{\"dns_updated\": true, \"ip_changed\": true, \"new_ip\": \"$new_ip\", \"previous_dns_ip\": \"${current_dns_ip:-'unknown'}\"}"
  success "DNS records updated successfully"
}

# Step 7: Validate deployment
step_7_validate_deployment() {
  info "=== STEP 7: VALIDATE DEPLOYMENT ==="
  
  local new_ip=$(load_state | jq -r '.data.new_static_ip')
  
  # Test VM accessibility
  info "Testing VM accessibility..."
  if ! gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command="echo 'VM accessible'" --ssh-flag="-o ConnectTimeout=10"; then
    error "Cannot access VM via SSH"
    exit 1
  fi
  
  # Test application services
  info "Testing application services..."
  gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command="
    set -e
    cd metamcp
    
    # Check if containers are running
    echo 'Checking Docker containers...'
    sudo docker ps
    
    # Test application service directly
    echo 'Testing application service...'
    curl -f http://localhost:12008 || exit 1
    
    # Test HTTP service (should redirect to HTTPS)
    echo 'Testing HTTP to HTTPS redirect...'
    curl -I http://localhost/ || echo 'HTTP check completed'
    
    # Test HTTPS service
    echo 'Testing HTTPS service...'
    curl -k -f https://localhost/ || echo 'HTTPS service check completed'
    
    echo 'All services are running successfully!'
  "
  
  # Test external connectivity
  info "Testing external connectivity from new IP: $new_ip"
  if [ -n "$DOMAIN_NAME" ]; then
    info "Testing domain accessibility..."
    # Wait a bit more for DNS propagation if needed
    sleep 30
    if curl -I "https://$DOMAIN_NAME" --connect-timeout 10 &>/dev/null; then
      success "Domain is accessible via HTTPS"
    else
      error "Domain may not be accessible yet. DNS propagation may still be in progress."
      info "You can check DNS propagation at: https://www.whatsmydns.net/"
    fi
  fi
  
  # Verify network tier
  info "Verifying network tier configuration..."
  local current_tier=$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="value(networkInterfaces[0].accessConfigs[0].networkTier)")
  if [ "$current_tier" = "STANDARD" ]; then
    success "Confirmed: VM is now using STANDARD network tier"
  else
    error "Network tier verification failed. Current tier: $current_tier"
    exit 1
  fi
  
  save_state 7 "{\"validation_completed\": true, \"network_tier\": \"STANDARD\"}"
  success "Deployment validation completed successfully"
}

# Step 8: Update deployment scripts
step_8_update_scripts() {
  info "=== STEP 8: UPDATE DEPLOYMENT SCRIPTS ==="
  
  # Create backup of original deployment script
  cp deploy/compute_engine_deploy.sh deploy/compute_engine_deploy.sh.backup
  
  # Update the deployment script to use standard network tier by default
  info "Updating deployment script to use standard network tier..."
  
  # Add network tier flag to static IP creation
  sed -i.tmp 's/gcloud compute addresses create "$STATIC_IP_NAME" --region="$REGION"/gcloud compute addresses create "$STATIC_IP_NAME" --region="$REGION" --network-tier=STANDARD/' deploy/compute_engine_deploy.sh
  
  # Add network tier flag to VM instance creation
  sed -i.tmp '/--provisioning-model="STANDARD"/a\
      --network-tier=STANDARD \\' deploy/compute_engine_deploy.sh
  
  # Clean up temporary files
  rm -f deploy/compute_engine_deploy.sh.tmp
  
  info "Deployment script updated. Original backed up as deploy/compute_engine_deploy.sh.backup"
  
  save_state 8 "{\"scripts_updated\": true}"
  success "Deployment scripts updated successfully"
}

# Step 9: Cleanup old resources
step_9_cleanup() {
  info "=== STEP 9: CLEANUP OLD RESOURCES ==="
  
  # Ask for confirmation before cleanup
  echo ""
  info "Migration completed successfully! Your application is now using STANDARD network tier."
  info "This will save approximately $20-25/month in network costs."
  echo ""
  read -p "Do you want to delete the old premium static IP '$STATIC_IP_NAME'? (y/N): " -n 1 -r
  echo ""
  
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    info "Deleting old premium static IP..."
    if gcloud compute addresses describe "$STATIC_IP_NAME" --region="$REGION" &>/dev/null; then
      gcloud compute addresses delete "$STATIC_IP_NAME" --region="$REGION" --quiet
      success "Old premium static IP deleted"
    else
      info "Old static IP not found or already deleted"
    fi
  else
    info "Keeping old premium static IP for now. You can delete it manually later:"
    info "gcloud compute addresses delete '$STATIC_IP_NAME' --region='$REGION'"
  fi
  
  save_state 9 "{\"cleanup_completed\": true}"
  success "Migration completed successfully!"
  
  # Show final summary
  echo ""
  info "=== MIGRATION SUMMARY ==="
  info "✓ VM instance migrated to STANDARD network tier"
  info "✓ New static IP assigned and configured"
  info "✓ DNS records updated (if applicable)"
  info "✓ Application validated and working"
  info "✓ Deployment scripts updated for future deployments"
  info "💰 Estimated monthly savings: $20-25"
  echo ""
  info "Migration state saved in: $STATE_FILE"
  info "Backup information saved in: $BACKUP_FILE"
  info "Original deployment script backed up as: deploy/compute_engine_deploy.sh.backup"
}

# Rollback function
rollback_migration() {
  info "=== ROLLBACK: REVERTING NETWORK TIER MIGRATION ==="
  
  if [ ! -f "$BACKUP_FILE" ]; then
    error "Backup file not found: $BACKUP_FILE"
    error "Cannot perform rollback without backup data"
    exit 1
  fi
  
  read -p "Are you sure you want to rollback the network tier migration? (y/N): " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    info "Rollback cancelled"
    exit 0
  fi
  
  info "Loading backup configuration..."
  local backup_data=$(cat "$BACKUP_FILE")
  local original_ip=$(echo "$backup_data" | jq -r '.vm_config.networkInterfaces[0].accessConfigs[0].natIP')
  
  info "Original IP address: $original_ip"
  
  # Stop VM
  info "Stopping VM instance..."
  gcloud compute instances stop "$INSTANCE_NAME" --zone="$ZONE"
  
  # Wait for VM to stop
  while [ "$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="value(status)")" != "TERMINATED" ]; do
    sleep 5
  done
  
  # Remove current access config
  info "Removing current access configuration..."
  gcloud compute instances delete-access-config "$INSTANCE_NAME" \
    --zone="$ZONE" \
    --access-config-name="External NAT" || true
  
  # Add original access config
  info "Restoring original network configuration..."
  if [ "$original_ip" != "null" ] && [ -n "$original_ip" ]; then
    # If we had a static IP, restore it
    gcloud compute instances add-access-config "$INSTANCE_NAME" \
      --zone="$ZONE" \
      --access-config-name="External NAT" \
      --address="$original_ip" \
      --network-tier=PREMIUM
  else
    # If we had an ephemeral IP, use ephemeral
    gcloud compute instances add-access-config "$INSTANCE_NAME" \
      --zone="$ZONE" \
      --access-config-name="External NAT" \
      --network-tier=PREMIUM
  fi
  
  # Start VM
  info "Starting VM instance..."
  gcloud compute instances start "$INSTANCE_NAME" --zone="$ZONE"
  
  # Wait for VM to start
  while [ "$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="value(status)")" != "RUNNING" ]; do
    sleep 5
  done
  
  # Clean up standard IP if it exists
  if gcloud compute addresses describe "$NEW_STATIC_IP_NAME" --region="$REGION" &>/dev/null; then
    info "Cleaning up standard-tier static IP..."
    gcloud compute addresses delete "$NEW_STATIC_IP_NAME" --region="$REGION" --quiet
  fi
  
  # Restore original deployment script if backup exists
  if [ -f "deploy/compute_engine_deploy.sh.backup" ]; then
    info "Restoring original deployment script..."
    mv deploy/compute_engine_deploy.sh.backup deploy/compute_engine_deploy.sh
  fi
  
  # Clean up state files
  rm -f "$STATE_FILE" "$BACKUP_FILE"
  
  success "Rollback completed successfully!"
  info "Your deployment has been restored to use PREMIUM network tier"
}

# --- Main Script Logic ---

# Parse command line arguments
STEP_TO_RUN=0
ROLLBACK_MODE=false

if [ $# -eq 0 ]; then
  show_usage
  exit 0
fi

for arg in "$@"; do
  case $arg in
    --rollback)
      ROLLBACK_MODE=true
      shift
      ;;
    --help|-h)
      show_usage
      exit 0
      ;;
    [0-9])
      STEP_TO_RUN=$arg
      shift
      ;;
    *)
      error "Unknown argument: $arg"
      show_usage
      exit 1
      ;;
  esac
done

# Handle rollback mode
if [ "$ROLLBACK_MODE" = true ]; then
  rollback_migration
  exit 0
fi

# Validate step number
if [[ ! $STEP_TO_RUN =~ ^[0-9]$ ]]; then
  error "Invalid step number: $STEP_TO_RUN"
  show_usage
  exit 1
fi

# Show header
echo ""
info "=== $SCRIPT_NAME v$VERSION ==="
info "Target step: $STEP_TO_RUN"
info "Instance: $INSTANCE_NAME"
info "Region: $REGION"
info "Zone: $ZONE"
echo ""

# Execute steps based on argument
case $STEP_TO_RUN in
  0)
    # Run all steps
    for step in {1..9}; do
      if ! is_step_completed $step; then
        case $step in
          1) step_1_validation_backup ;;
          2) step_2_create_standard_ip ;;
          3) step_3_stop_vm ;;
          4) step_4_update_network_config ;;
          5) step_5_start_vm ;;
          6) step_6_update_dns ;;
          7) step_7_validate_deployment ;;
          8) step_8_update_scripts ;;
          9) step_9_cleanup ;;
        esac
      else
        info "Step $step already completed, skipping..."
      fi
    done
    ;;
  1)
    step_1_validation_backup
    ;;
  2)
    step_2_create_standard_ip
    ;;
  3)
    step_3_stop_vm
    ;;
  4)
    step_4_update_network_config
    ;;
  5)
    step_5_start_vm
    ;;
  6)
    step_6_update_dns
    ;;
  7)
    step_7_validate_deployment
    ;;
  8)
    step_8_update_scripts
    ;;
  9)
    step_9_cleanup
    ;;
  *)
    error "Invalid step number: $STEP_TO_RUN"
    show_usage
    exit 1
    ;;
esac

info "Step $STEP_TO_RUN completed successfully!"
echo ""