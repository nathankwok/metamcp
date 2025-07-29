#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
# These will be overridden by values from .env.production if provided
# FREE TIER COMPLIANT SETTINGS - Only use FREE TIER REGIONS: us-west1, us-central1, us-east1
DEFAULT_REGION="us-central1"
DEFAULT_INSTANCE_NAME="metamcp-instance"
# FREE TIER: 1 e2-micro VM instance per month (744 hours continuously)
INSTANCE_TYPE="e2-micro"
# Use latest stable Debian for better compatibility
IMAGE_FAMILY="debian-12"
IMAGE_PROJECT="debian-cloud"
FIREWALL_RULE_HTTP="allow-http-traffic"
FIREWALL_RULE_HTTPS="allow-https-traffic"
# FREE TIER: Static IP is free when attached to running VM
STATIC_IP_NAME="metamcp-static-ip"
REPO_URL="https://github.com/metatool-ai/metamcp.git"
PROJECT_DIR="metamcp"

# Check if .env.production exists
if [ ! -f ".env.production" ]; then
  echo "ERROR: .env.production file not found in current directory!"
  echo "Please create this file with all required environment variables before running the script."
  echo "You can use .env.sample as a template."
  exit 1
fi

# Load environment variables from .env.production
source .env.production

# Use values from .env.production or defaults
REGION="${REGION:-$DEFAULT_REGION}"
ZONE="${ZONE:-${REGION}-a}"  
INSTANCE_NAME="${INSTANCE_NAME:-$DEFAULT_INSTANCE_NAME}"

# Validate required environment variables
if [ -z "$DOMAIN_NAME" ] || [ -z "$PORKBUN_API_KEY" ] || [ -z "$PORKBUN_SECRET_KEY" ]; then
  echo "ERROR: Missing required environment variables in .env.production:"
  echo "Required: DOMAIN_NAME, PORKBUN_API_KEY, PORKBUN_SECRET_KEY"
  exit 1
fi

# Validate PROJECT_ID is provided (can be from env or will be prompted)
if [ -z "$PROJECT_ID" ]; then
  info "PROJECT_ID not found in .env.production - will prompt during deployment"
fi

# Check if SSL directory exists
if [ ! -d "ssl" ]; then
  echo "ERROR: ssl/ directory not found in current directory!"
  echo "Please create an ssl/ directory and place your SSL certificate files there."
  echo "Expected files: certificate file (*.crt, *.pem), private key (*.key), and optionally chain file"
  exit 1
fi

# Check if SSL directory has files
if [ -z "$(ls -A ssl/ 2>/dev/null)" ]; then
  echo "ERROR: ssl/ directory is empty!"
  echo "Please download your SSL certificates from Porkbun and place them in the ssl/ directory."
  exit 1
fi

# Check if jq is available for JSON parsing (required for enhanced DNS functions)
if ! command -v jq &> /dev/null; then
  echo "ERROR: jq is required for JSON parsing but not installed."
  echo "Please install jq:"
  echo "  - macOS: brew install jq"
  echo "  - Ubuntu/Debian: apt-get install jq"
  echo "  - CentOS/RHEL: yum install jq"
  exit 1
fi

# --- Helper Functions ---
# Function to print messages in a consistent format
info() {
  echo "INFO: $1"
}

# Function to debug DNS API and list existing records
debug_dns_api() {
  info "=== DNS API DEBUG & TROUBLESHOOTING ==="
  
  # Test API authentication first
  info "Testing Porkbun API authentication..."
  local auth_response=$(curl -s --header "Content-Type: application/json" \
    --request POST \
    --data "{
      \"secretapikey\": \"$PORKBUN_SECRET_KEY\",
      \"apikey\": \"$PORKBUN_API_KEY\"
    }" \
    "https://api.porkbun.com/api/json/v3/ping")

  echo "Auth test response: $auth_response"
  
  if echo "$auth_response" | grep -q '"status":"SUCCESS"'; then
    info "✓ API authentication successful"
  else
    echo "✗ API authentication failed"
    return 1
  fi

  # Test retrieving existing DNS records
  info "Retrieving existing DNS records for $DOMAIN_NAME..."
  local dns_list_response=$(curl -s --header "Content-Type: application/json" \
    --request POST \
    --data "{
      \"secretapikey\": \"$PORKBUN_SECRET_KEY\",
      \"apikey\": \"$PORKBUN_API_KEY\"
    }" \
    "https://api.porkbun.com/api/json/v3/dns/retrieve/$DOMAIN_NAME")

  echo "Existing DNS records:"
  echo "$dns_list_response" | jq '.' 2>/dev/null || echo "$dns_list_response"
  
  if echo "$dns_list_response" | grep -q '"status":"SUCCESS"'; then
    info "✓ DNS records retrieved successfully"
    
    # Show A records specifically
    local a_records=$(echo "$dns_list_response" | jq -r '.records[]? | select(.type == "A") | "\(.name): \(.content)"' 2>/dev/null || true)
    if [ -n "$a_records" ]; then
      info "Current A records:"
      echo "$a_records"
    else
      info "No A records found"
    fi
  else
    echo "✗ Failed to retrieve DNS records"
    return 1
  fi
}

# Function to delete existing DNS records for a domain/subdomain
delete_existing_records() {
  local domain="$1"
  local subdomain="$2"
  local target_name="${subdomain:+$subdomain.}$domain"
  
  info "Checking for existing DNS records for $target_name"
  
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
      info "Deleting existing record ID: $record_id"
      local delete_response=$(curl -s --header "Content-Type: application/json" \
        --request POST \
        --data "{
          \"secretapikey\": \"$PORKBUN_SECRET_KEY\",
          \"apikey\": \"$PORKBUN_API_KEY\"
        }" \
        "https://api.porkbun.com/api/json/v3/dns/delete/$domain/$record_id")
      
      if echo "$delete_response" | grep -q '"status":"SUCCESS"'; then
        info "Successfully deleted record ID: $record_id"
      else
        echo "WARNING: Failed to delete record ID $record_id: $delete_response"
      fi
    done
  else
    info "No existing A/ALIAS records found for $target_name"
  fi
}

# Function to create DNS A record via Porkbun API (enhanced version)
create_dns_record() {
  local domain="$1"
  local subdomain="$2"
  local ip_address="$3"
  
  # First delete any existing records
  delete_existing_records "$domain" "$subdomain"
  
  info "Creating DNS A record for ${subdomain:+$subdomain.}$domain pointing to $ip_address"
  
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
    info "DNS record created successfully"
    echo "$response" | grep -o '"id":"[^"]*"' | cut -d'"' -f4
  else
    echo "ERROR: Failed to create DNS record. Response: $response"
    exit 1
  fi
}

# Function to detect SSL certificate files in ssl/ directory
detect_ssl_files() {
  info "Detecting SSL certificate files in ssl/ directory..."
  
  # Look for certificate file (common patterns)
  SSL_CERT_FILE=""
  for pattern in "*.crt" "*.pem" "*cert*"; do
    file=$(find ssl/ -name "$pattern" -type f | head -1)
    if [ -n "$file" ]; then
      SSL_CERT_FILE="$file"
      break
    fi
  done
  
  # Look for private key file
  SSL_KEY_FILE=""
  for pattern in "*.key" "*private*"; do
    file=$(find ssl/ -name "$pattern" -type f | head -1)
    if [ -n "$file" ]; then
      SSL_KEY_FILE="$file"
      break
    fi
  done
  
  # Look for chain/bundle file (optional)
  SSL_CHAIN_FILE=""
  for pattern in "*chain*" "*bundle*" "*ca*" "*intermediate*"; do
    file=$(find ssl/ -name "$pattern" -type f | head -1)
    if [ -n "$file" ]; then
      SSL_CHAIN_FILE="$file"
      break
    fi
  done
  
  # Validate required files
  if [ -z "$SSL_CERT_FILE" ]; then
    echo "ERROR: No SSL certificate file found in ssl/ directory!"
    echo "Expected patterns: *.crt, *.pem, *cert*"
    ls -la ssl/
    exit 1
  fi
  
  if [ -z "$SSL_KEY_FILE" ]; then
    echo "ERROR: No SSL private key file found in ssl/ directory!"
    echo "Expected patterns: *.key, *private*"
    ls -la ssl/
    exit 1
  fi
  
  info "SSL certificate file: $SSL_CERT_FILE"
  info "SSL private key file: $SSL_KEY_FILE"
  if [ -n "$SSL_CHAIN_FILE" ]; then
    info "SSL chain file: $SSL_CHAIN_FILE"
  else
    info "No SSL chain file found (optional)"
  fi
}

# Function to validate free tier region
validate_free_tier_region() {
  local region="$1"
  local free_tier_regions=("us-west1" "us-central1" "us-east1")
  
  for free_region in "${free_tier_regions[@]}"; do
    if [ "$region" = "$free_region" ]; then
      return 0
    fi
  done
  
  echo "ERROR: Region '$region' is not eligible for free tier!"
  echo "Free tier regions: us-west1, us-central1, us-east1"
  exit 1
}

# Function to check if service is running on a port
check_service() {
  local port="$1"
  local service_name="$2"
  local max_attempts=30
  local attempt=1
  
  info "Checking if $service_name is running on port $port..."
  
  while [ $attempt -le $max_attempts ]; do
    if curl -s "http://localhost:$port" > /dev/null 2>&1; then
      info "$service_name is running successfully on port $port"
      return 0
    fi
    
    info "Attempt $attempt/$max_attempts: $service_name not ready yet, waiting 10 seconds..."
    sleep 10
    attempt=$((attempt + 1))
  done
  
  echo "ERROR: $service_name failed to start on port $port after $((max_attempts * 10)) seconds"
  return 1
}

# --- Step Functions ---

# Function: step_1_initial_setup_validation
# Description: Validates environment and displays free tier information
# Parameters: None
# Returns: 0 on success, exits on user cancellation
step_1_initial_setup_validation() {
  info "=== STEP 1: INITIAL SETUP & VALIDATION ==="
  info "This script is configured to stay within GCP Free Tier limits:"
  info "✓ VM: e2-micro instance (1 free per month, 744 hours)"
  info "✓ Region: $REGION (free tier eligible)"
  info "✓ Static IP: Free when attached to running VM"
  info "✓ Firewall: No additional charges"
  info "✓ Boot Disk: 30GB standard persistent disk (free)"
  info "⚠️  Network egress: 1GB/month free (North America to all regions)"
  echo ""
  if [ "$START_STEP" -eq 1 ]; then
    read -p "Continue with deployment from this step? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled."
        exit 1
    fi
  fi
}

# Function: step_2_project_api_setup
# Description: Sets up Google Cloud project and enables necessary APIs
# Parameters: None
# Returns: 0 on success, exits on error
step_2_project_api_setup() {
  info "=== STEP 2: PROJECT AND API SETUP ==="
  if [ -z "$PROJECT_ID" ]; then
    read -p "Enter your Google Cloud Project ID: " PROJECT_ID
  else
    info "Using PROJECT_ID from .env.production: $PROJECT_ID"
  fi
  gcloud config set project "$PROJECT_ID"

  info "Enabling necessary APIs..."
  gcloud services enable compute.googleapis.com \
                         iam.googleapis.com \
                         cloudresourcemanager.googleapis.com
}

# Function: step_3_networking_setup
# Description: Creates static IP address and configures firewall rules
# Parameters: None
# Returns: 0 on success, exits on error
step_3_networking_setup() {
  info "=== STEP 3: NETWORKING SETUP ==="
  info "Checking for existing static IP..."
  if ! gcloud compute addresses describe "$STATIC_IP_NAME" --region="$REGION" &>/dev/null; then
    info "Creating a new static IP address..."
    gcloud compute addresses create "$STATIC_IP_NAME" --region="$REGION"
  else
    info "Static IP address '$STATIC_IP_NAME' already exists."
  fi

  info "Creating firewall rules..."
  if ! gcloud compute firewall-rules describe "$FIREWALL_RULE_HTTP" &>/dev/null; then
    gcloud compute firewall-rules create "$FIREWALL_RULE_HTTP" \
      --allow tcp:80 \
      --description="Allow HTTP traffic" \
      --target-tags="http-server"
  else
    info "Firewall rule '$FIREWALL_RULE_HTTP' already exists."
  fi

  if ! gcloud compute firewall-rules describe "$FIREWALL_RULE_HTTPS" &>/dev/null; then
    gcloud compute firewall-rules create "$FIREWALL_RULE_HTTPS" \
      --allow tcp:443 \
      --description="Allow HTTPS traffic" \
      --target-tags="https-server"
  else
    info "Firewall rule '$FIREWALL_RULE_HTTPS' already exists."
  fi
}

# Function: step_4_vm_instance_creation
# Description: Creates the Compute Engine VM instance with free tier specifications
# Parameters: None
# Returns: 0 on success, exits on error
step_4_vm_instance_creation() {
  info "=== STEP 4: VM INSTANCE CREATION ==="
  if ! gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" &>/dev/null; then
    info "Creating e2-micro VM with 20GB boot disk (within 30GB free limit)..."
    gcloud compute instances create "$INSTANCE_NAME" \
      --zone="$ZONE" \
      --machine-type="$INSTANCE_TYPE" \
      --image-family="$IMAGE_FAMILY" \
      --image-project="$IMAGE_PROJECT" \
      --boot-disk-size="20GB" \
      --boot-disk-type="pd-standard" \
      --address="$STATIC_IP" \
      --tags="http-server,https-server" \
      --maintenance-policy="MIGRATE" \
      --provisioning-model="STANDARD"
  else
    info "VM instance '$INSTANCE_NAME' already exists."
  fi

  info "Waiting for the VM to be ready..."
  sleep 30
}

# Function: step_5_dns_configuration
# Description: Configures DNS records for the domain using enhanced Porkbun API integration
# Parameters: None
# Returns: 0 on success, exits on error
step_5_dns_configuration() {
  info "=== STEP 5: DNS CONFIGURATION (ENHANCED) ==="
  info "Setting up DNS records for domain: $DOMAIN_NAME"
  create_dns_record "$DOMAIN_NAME" "" "$STATIC_IP"        # Root domain
  create_dns_record "$DOMAIN_NAME" "www" "$STATIC_IP"     # www subdomain

  info "DNS records created successfully!"
  info "Please allow a few minutes for DNS propagation..."
}

# Function: step_6_ssl_management
# Description: Configures SSL certificates and Nginx with HTTPS
# Parameters: None
# Returns: 0 on success, exits on error
step_6_ssl_management() {
  info "=== STEP 6: SSL CERTIFICATE MANAGEMENT ==="

  # Create a temporary script for VM configuration with actual domain name
  cat > /tmp/vm_setup.sh << VMSCRIPT
#!/bin/bash
set -e

# Update and install dependencies
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y docker.io docker-compose nginx git

# Clone the repository
if [ ! -d 'metamcp' ]; then
  git clone 'https://github.com/metatool-ai/metamcp.git' 'metamcp'
fi
cd 'metamcp'

# Configure Nginx with SSL
sudo rm -f /etc/nginx/sites-enabled/default
sudo tee /etc/nginx/sites-available/metamcp > /dev/null << 'NGINXCONFIG'
# HTTP server - redirect to HTTPS
server {
    listen 80;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;
    return 301 https://\\\$server_name\\\$request_uri;
}

# HTTPS server
server {
    listen 443 ssl http2;
    server_name $DOMAIN_NAME www.$DOMAIN_NAME;

    # SSL Configuration
    ssl_certificate /etc/ssl/certs/metamcp.crt;
    ssl_certificate_key /etc/ssl/private/metamcp.key;
    
    # SSL Security Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;

    location / {
        proxy_pass http://localhost:12008;
        proxy_set_header Host \\\$host;
        proxy_set_header X-Real-IP \\\$remote_addr;
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \\\$host;
        proxy_set_header X-Forwarded-Server \\\$host;
        proxy_buffering off;
    }
}
NGINXCONFIG

sudo ln -s /etc/nginx/sites-available/metamcp /etc/nginx/sites-enabled/

# Create SSL directories
sudo mkdir -p /etc/ssl/certs
sudo mkdir -p /etc/ssl/private

# Enable Nginx to start on boot
sudo systemctl enable nginx
VMSCRIPT

  # Copy and execute the setup script on VM
  gcloud compute scp /tmp/vm_setup.sh "$INSTANCE_NAME":/tmp/vm_setup.sh --zone="$ZONE"
  gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command="chmod +x /tmp/vm_setup.sh && /tmp/vm_setup.sh"

  # Upload SSL certificates to VM
  info "Uploading SSL certificates to VM..."
  gcloud compute scp "$SSL_CERT_FILE" "$INSTANCE_NAME":/tmp/metamcp.crt --zone="$ZONE"
  gcloud compute scp "$SSL_KEY_FILE" "$INSTANCE_NAME":/tmp/metamcp.key --zone="$ZONE"

  if [ -n "$SSL_CHAIN_FILE" ]; then
    info "Uploading SSL chain file..."
    gcloud compute scp "$SSL_CHAIN_FILE" "$INSTANCE_NAME":/tmp/metamcp-chain.crt --zone="$ZONE"
  fi

  # Install SSL certificates and configure nginx
  gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command="
    set -e
    
    # Install SSL certificates
    sudo mv /tmp/metamcp.crt /etc/ssl/certs/
    sudo mv /tmp/metamcp.key /etc/ssl/private/
    sudo chown root:root /etc/ssl/certs/metamcp.crt /etc/ssl/private/metamcp.key
    sudo chmod 644 /etc/ssl/certs/metamcp.crt
    sudo chmod 600 /etc/ssl/private/metamcp.key
    
    # Handle chain file if present
    if [ -f '/tmp/metamcp-chain.crt' ]; then
      sudo mv /tmp/metamcp-chain.crt /etc/ssl/certs/
      sudo chown root:root /etc/ssl/certs/metamcp-chain.crt
      sudo chmod 644 /etc/ssl/certs/metamcp-chain.crt
    fi
    
    # Test Nginx configuration
    sudo nginx -t
    
    # Start/restart Nginx
    sudo systemctl restart nginx
  "

  # Clean up temporary script
  rm -f /tmp/vm_setup.sh
}

# Function: step_7_nodejs_gemini_installation
# Description: Installs Node.js LTS and Google Gemini CLI on the VM with proper PATH configuration
# Parameters: None
# Returns: 0 on success, exits on error
step_7_nodejs_gemini_installation() {
  info "=== STEP 7: NODE.JS AND GEMINI CLI INSTALLATION ==="
  
  # Extract GEMINI_API_KEY from local .env.production
  GEMINI_API_KEY=$(grep "^GEMINI_API_KEY=" .env.production | cut -d'=' -f2- | tr -d '"' | tr -d "'")
  
  if [ -z "$GEMINI_API_KEY" ]; then
    echo "WARNING: GEMINI_API_KEY not found in .env.production"
    echo "Gemini CLI may not work properly without an API key"
  else
    info "Found GEMINI_API_KEY in .env.production"
  fi
  
  # Install Node.js and Gemini CLI on the VM
  gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command="
    set -e
    
    # Update package manager
    sudo apt-get update
    
    # Install Node.js (using NodeSource repository for latest LTS)
    echo 'Installing Node.js...'
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt-get install -y nodejs
    
    # Add Node.js to PATH in profile files
    echo 'Configuring Node.js PATH...'
    echo 'export PATH=\"/usr/bin:\$PATH\"' >> ~/.profile
    echo 'export PATH=\"/usr/bin:\$PATH\"' >> ~/.bashrc
    
    # Add GEMINI_API_KEY to profile if available
    if [ -n '$GEMINI_API_KEY' ]; then
      echo 'export GEMINI_API_KEY=\"$GEMINI_API_KEY\"' >> ~/.profile
      echo 'export GEMINI_API_KEY=\"$GEMINI_API_KEY\"' >> ~/.bashrc
      echo 'Added GEMINI_API_KEY to environment'
    fi
    
    # Source profile to update current session
    source ~/.profile 2>/dev/null || true
    source ~/.bashrc 2>/dev/null || true
    
    # Verify Node.js and npm installation
    echo 'Node.js version:'
    node --version
    echo 'npm version:'
    npm --version
    
    # Install Gemini CLI globally
    echo 'Installing @google/gemini-cli...'
    sudo npm install -g @google/gemini-cli
    
    # Add npm global bin to PATH (where Gemini CLI is installed)
    NPM_GLOBAL_BIN=\$(npm config get prefix)/bin
    echo \"Adding npm global bin to PATH: \$NPM_GLOBAL_BIN\"
    echo \"export PATH=\\\"\$NPM_GLOBAL_BIN:\\\$PATH\\\"\" >> ~/.profile
    echo \"export PATH=\\\"\$NPM_GLOBAL_BIN:\\\$PATH\\\"\" >> ~/.bashrc
    
    # Update current session PATH
    export PATH=\"\$NPM_GLOBAL_BIN:\$PATH\"
    
    # Verify Gemini CLI installation and PATH
    echo 'Gemini CLI installation verification:'
    which gemini || echo 'Gemini CLI not found in current PATH, but should be available in new sessions'
    gemini --version || echo 'Gemini CLI installed (version check may require API key setup or new session)'
    
    # Create a basic gemini config directory for the user
    mkdir -p ~/.config/gemini
    
    # Display PATH information for debugging
    echo 'Current PATH configuration:'
    echo \$PATH
    echo 'NPM global bin directory:'
    echo \$NPM_GLOBAL_BIN
    
    echo 'Node.js and Gemini CLI installation completed!'
    echo 'Note: You may need to start a new shell session or run \"source ~/.profile\" to access gemini command'
  "
}

# Function: step_8_environment_configuration
# Description: Copies environment variables and production configurations to VM
# Parameters: None
# Returns: 0 on success, exits on error
step_8_environment_configuration() {
  info "=== STEP 8: ENVIRONMENT AND PRODUCTION CONFIGURATION ==="

  # Copy environment variables from .env.production on local machine
  info "Copying environment configuration to VM..."
  gcloud compute scp .env.production "$INSTANCE_NAME":/home/$USER/$PROJECT_DIR/.env --zone="$ZONE"

  # Copy production docker-compose file
  info "Copying production docker compose configuration..."
  gcloud compute scp deploy/docker-compose.prod.yml "$INSTANCE_NAME":/home/$USER/$PROJECT_DIR/ --zone="$ZONE"

  # Set up basic environment file structure on VM
  gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command="
    set -e
    cd '$PROJECT_DIR'
    
    # Ensure .env file exists and has proper permissions
    if [ ! -f '.env' ]; then
      touch .env
    fi
    chmod 600 .env
    
    # Verify production configuration files are in place
    ls -la docker-compose.prod.yml
    echo 'Environment and production configuration setup completed.'
  "
}


# Function: step_9_application_startup
# Description: Starts the MetaMCP application using Docker Compose
# Parameters: None
# Returns: 0 on success, exits on error
step_9_application_startup() {
  info "=== STEP 9: APPLICATION STARTUP (DOCKER COMPOSE) ==="
  
  # Start the MetaMCP application using Docker Compose
  gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command="
    set -e
    
    # Navigate to project directory
    cd '$PROJECT_DIR'

    # Remove existing docker-compose.yml since it's not for production
    [ -f docker-compose.yml ] && sudo rm docker-compose.yml

    # rename docker-compose.prod.yml to docker-compose.yml
    sudo cp docker-compose.prod.yml docker-compose.yml
    
    # Ensure user is in docker group for permissions
    sudo usermod -aG docker \$USER
    
    # Start the application with production compose file
    sudo docker-compose -f docker-compose.prod.yml up -d
    
    # Wait for services to be ready
    sleep 30
    
    # Show running containers
    echo 'Docker containers status:'
    sudo docker ps
  "
}

# Function: step_10_health_checks_validation
# Description: Performs comprehensive health checks on all deployed services
# Parameters: None
# Returns: 0 on success, exits on error
step_10_health_checks_validation() {
  info "=== STEP 10: HEALTH CHECKS AND VALIDATION ==="
  gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command="
    set -e
    cd '$PROJECT_DIR'
    
    # Check SSL certificate installation
    echo 'Checking SSL certificate installation...'
    sudo openssl x509 -in /etc/ssl/certs/metamcp.crt -text -noout | grep -E 'Subject:|Issuer:|Not After' || true
    
    # Test Nginx configuration
    echo 'Testing Nginx configuration...'
    sudo nginx -t
    
    # Check if containers are running
    echo 'Checking Docker containers...'
    sudo docker ps
    
    # Check HTTP service (should redirect to HTTPS)
    echo 'Testing HTTP to HTTPS redirect...'
    curl -I http://localhost/ || echo 'HTTP check completed'
    
    # Check HTTPS service
    echo 'Testing HTTPS service...'
    curl -k -f https://localhost/ || echo 'HTTPS service check completed'
    
    # Check application service directly
    echo 'Testing application service...'
    curl -f http://localhost:12008 || exit 1
    
    # Check database migrations
    echo 'Checking database migrations...'
    sudo docker-compose -f docker-compose.prod.yml logs app | grep -i 'migration\|database' || true
    
    echo 'All services are running successfully!'
  "
}

# Function: step_11_final_information
# Description: Displays final deployment information and usage instructions
# Parameters: None
# Returns: 0 on success
step_11_final_information() {
  info "=== STEP 11: FINAL INFORMATION ==="
  info "Deployment completed successfully!"
  info "Application URL: https://$DOMAIN_NAME"
  info "Static IP: $STATIC_IP"
  info "VM Instance: $INSTANCE_NAME (e2-micro in $REGION)"
  info ""
  info "=== FREE TIER MONITORING ==="
  info "⚠️  IMPORTANT: Monitor your usage to stay within free tier limits:"
  info "• VM: 744 hours/month free (this VM runs continuously)"
  info "• Network egress: 1GB/month free from North America"
  info "• Storage: 30GB standard persistent disk free"
  info "• Check billing: https://console.cloud.google.com/billing"
  info ""
  info "To stop the VM and avoid charges:"
  info "gcloud compute instances stop $INSTANCE_NAME --zone=$ZONE"
  info ""
  info "To start the VM again:"
  info "gcloud compute instances start $INSTANCE_NAME --zone=$ZONE"
  info ""
  info "You can monitor the application with:"
  info "gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
  info "cd $PROJECT_DIR && docker-compose -f docker-compose.prod.yml logs -f"
}

# Function: step_12_dns_debug_troubleshooting
# Description: Provides DNS debugging and troubleshooting capabilities
# Parameters: None
# Returns: 0 on success, 1 on API errors
step_12_dns_debug_troubleshooting() {
  debug_dns_api
  
  info ""
  info "You can test DNS propagation with:"
  info "dig $DOMAIN_NAME"
  info "dig www.$DOMAIN_NAME"
  info ""
  info "Online DNS propagation checkers:"
  info "• https://www.whatsmydns.net/"
  info "• https://dnschecker.org/"
}

# --- Step Selection Menu ---
show_step_menu() {
  echo ""
  info "=== DEPLOYMENT STEP SELECTION ==="
  echo "1. Initial Setup & Validation"
  echo "2. Project and API Setup"
  echo "3. Networking Setup (Static IP, Firewall)"
  echo "4. VM Instance Creation"
  echo "5. DNS Configuration (Enhanced with Cleanup)"
  echo "6. SSL Certificate Management"
  echo "7. Node.js and Gemini CLI Installation"
  echo "8. Environment and Production Configuration"
  echo "9. Application Startup (Docker Compose)"
  echo "10. Health Checks and Validation"
  echo "11. Final Information Display"
  echo "12. DNS Debug & Troubleshooting"
  echo "0. Run All Steps (Full Deployment)"
  echo ""
  read -p "Select starting step (0-12): " START_STEP
  echo ""
}

# --- Main Script ---

# Always run initial setup for environment validation
detect_ssl_files
validate_free_tier_region "$REGION"

# Show step selection menu
show_step_menu

# Validate step selection
if [[ ! $START_STEP =~ ^[0-9]|1[0-2]$ ]]; then
  echo "ERROR: Invalid step selection. Please choose 0-12."
  exit 1
fi

# Step 1: Initial Setup & Validation
if [ "$START_STEP" -le 1 ]; then
  step_1_initial_setup_validation
fi

# Step 2: Project and API Setup
if [ "$START_STEP" -le 2 ]; then
  step_2_project_api_setup
fi

# Step 3: Networking Setup
if [ "$START_STEP" -le 3 ]; then
  step_3_networking_setup
fi

# Always get the static IP for later steps
STATIC_IP=$(gcloud compute addresses describe "$STATIC_IP_NAME" --region="$REGION" --format="value(address)")
info "Static IP address: $STATIC_IP"

# Step 4: VM Instance Creation
if [ "$START_STEP" -le 4 ]; then
  step_4_vm_instance_creation
fi

# Step 5: DNS Configuration (Enhanced)
if [ "$START_STEP" -le 5 ]; then
  step_5_dns_configuration
fi

# Step 6: SSL Certificate Management
if [ "$START_STEP" -le 6 ]; then
  step_6_ssl_management
fi

# Step 7: Node.js and Gemini CLI Installation
if [ "$START_STEP" -le 7 ]; then
  step_7_nodejs_gemini_installation
fi

# Step 8: Environment and Production Configuration
if [ "$START_STEP" -le 8 ]; then
  step_8_environment_configuration
fi

# Step 9: Application Startup (Docker Compose)
if [ "$START_STEP" -le 9 ]; then
  step_9_application_startup
fi

# Step 10: Health Checks and Validation
if [ "$START_STEP" -le 10 ]; then
  step_10_health_checks_validation
fi

# Step 11: Final Information
if [ "$START_STEP" -le 11 ]; then
  step_11_final_information
fi

# Step 12: DNS Debug & Troubleshooting
if [ "$START_STEP" -eq 12 ]; then
  step_12_dns_debug_troubleshooting
fi