# Google Cloud Compute Engine Deployment Guide

This guide explains how to deploy the MetaMCP application to Google Cloud Compute Engine with automatic Supabase database integration and enhanced Porkbun DNS management. The deployment script provides step-by-step deployment with built-in DNS troubleshooting and automated DNS record cleanup.

## Prerequisites

1. **Google Cloud SDK** installed and authenticated
2. **Porkbun Domain** with API access enabled
3. **Supabase Project** set up with PostgreSQL database
4. **SSL Certificates** downloaded from Porkbun (see SSL Setup below)
5. **Docker Hub Access** (for pulling the application image)
6. **jq** installed for JSON parsing (see installation instructions below)

## Setup Instructions

### 1. Install jq (JSON Parser)

The deployment script requires `jq` for parsing JSON responses from the Porkbun API:

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# CentOS/RHEL/Fedora  
sudo yum install jq
# or on newer versions:
sudo dnf install jq

# Windows (with Chocolatey)
choco install jq
```

### 2. Download SSL Certificates

Download your SSL certificate bundle from Porkbun:

1. Log into your Porkbun account
2. Go to your domain management page  
3. Find the SSL certificate section
4. Download the certificate files (typically includes `.crt`, `.key`, and optionally chain/bundle files)
5. Create an `ssl/` directory in your project root
6. Place all certificate files in the `ssl/` directory

Expected file structure:
```
project-root/
├── ssl/
│   ├── domain.crt (or certificate.pem)
│   ├── domain.key (or private.key)  
│   └── bundle.crt (optional chain file)
└── ...
```

### 3. Configure Environment Variables

Create a `.env.production` file in the project root directory using `.env.sample` as a template:

```bash
cp .env.sample .env.production
```

Edit `.env.production` with your actual values. The file now includes all required variables:

- **Google Cloud Configuration**: Project ID, region, zone, and instance settings
- **Domain Configuration**: Your Porkbun domain name  
- **Porkbun API**: Your API key and secret key from Porkbun dashboard
- **Supabase Database**: Connection details from your Supabase project settings
- **Authentication**: Generate a secure secret key (minimum 32 characters)
- **Docker Configuration**: Set to `true` for production deployment

**Important**: All variables in `.env.production` are now used by the deployment script. You can customize deployment settings like region, instance name, and other parameters directly in the environment file.

### 4. Run Deployment Script

Execute the deployment script:

```bash
chmod +x compute_engine_deploy.sh
./compute_engine_deploy.sh
```

The script provides a step-by-step deployment process with these options:

- **Step 0**: Run all steps (full deployment)
- **Step 1**: Initial setup and validation
- **Step 2**: Project and API setup
- **Step 3**: Networking setup (static IP, firewall rules)
- **Step 4**: VM instance creation
- **Step 5**: DNS configuration (enhanced with automatic cleanup)
- **Step 6**: VM configuration and SSL setup
- **Step 7**: Node.js and Gemini CLI installation
- **Step 8**: Application startup (Docker Compose)
- **Step 9**: Health checks and validation
- **Step 10**: Final information display
- **Step 11**: DNS debug and troubleshooting

The script will automatically:

1. Detect and validate your SSL certificate files in the `ssl/` directory
2. Set up Google Cloud infrastructure (VM, static IP, firewall rules)
3. Clean up existing DNS records and create new A records for your domain and www subdomain
4. Upload SSL certificates to the VM and configure Nginx with HTTPS
5. Install Node.js (LTS) and @google/gemini-cli on the VM
6. Deploy and start the application with production configuration
7. Perform comprehensive health checks including SSL verification

## What Gets Deployed

### Infrastructure
- **Compute Engine VM**: e2-micro instance with Debian 11
- **Static IP Address**: Assigned to your domain
- **Firewall Rules**: HTTP (80) and HTTPS (443) traffic allowed
- **DNS Records**: Root domain and www subdomain pointing to static IP

### Application Stack
- **Frontend**: Next.js application on port 12008
- **Backend**: Node.js API on port 12009  
- **Database**: Supabase PostgreSQL (external)
- **Reverse Proxy**: Nginx with SSL termination
- **SSL Certificates**: Your Porkbun SSL certificates (pre-downloaded)
- **Node.js Runtime**: Latest LTS version with npm package manager
- **Gemini CLI**: @google/gemini-cli for AI assistance and development tools

## Post-Deployment

### Accessing Your Application
- **Primary URL**: `https://your-domain.com`
- **Alternative URL**: `https://www.your-domain.com`

### Monitoring and Logs
SSH into the VM to monitor the application:

```bash
# SSH into the VM (adjust zone if different)
gcloud compute ssh metamcp-instance --zone=us-central1-a

# Navigate to project directory and check logs
cd metamcp
docker-compose -f docker-compose.prod.yml logs -f
```

### Using Gemini CLI
The Gemini CLI is installed globally with proper PATH configuration:

```bash
# SSH into the VM
gcloud compute ssh metamcp-instance --zone=us-central1-a

# If gemini command is not found, source the profile
source ~/.profile

# Check Gemini CLI version
gemini --version

# Configure with your API key (first time setup)
gemini config set api-key YOUR_GEMINI_API_KEY

# Use Gemini CLI for development assistance
gemini ask "How to optimize Node.js performance?"
```

**Notes**: 
- Node.js and Gemini CLI are automatically added to your PATH in `~/.profile` and `~/.bashrc`
- If the `gemini` command is not immediately available, run `source ~/.profile` or start a new shell session
- You'll need to configure the Gemini CLI with your Google AI API key for full functionality

### Health Checks
The script automatically verifies:
- Container status
- Application responsiveness on port 12008
- Database migration completion
- SSL certificate installation

## Troubleshooting

### DNS Issues and Debugging

The deployment script includes built-in DNS debugging capabilities. Run step 11 to troubleshoot DNS issues:

```bash
./compute_engine_deploy.sh
# Select option 11 for "DNS Debug & Troubleshooting"
```

This will:
- Test Porkbun API authentication
- List all existing DNS records for your domain  
- Show current A records and their values
- Provide guidance on DNS propagation

#### Manual DNS Troubleshooting

Check DNS propagation status:
```bash
# Local DNS lookup
dig your-domain.com
dig www.your-domain.com

# Check specific nameservers
dig @8.8.8.8 your-domain.com
dig @1.1.1.1 your-domain.com
```

Online DNS propagation checkers:
- [whatsmydns.net](https://www.whatsmydns.net/)
- [dnschecker.org](https://dnschecker.org/)

#### Common DNS Issues

1. **Conflicting Records**: The script automatically deletes conflicting A/ALIAS records before creating new ones
2. **Propagation Delay**: DNS changes may take up to 24 hours to propagate globally
3. **API Authentication**: Verify your Porkbun API credentials in `.env.production`

### SSL Certificate Issues
If SSL certificates fail to install, ensure:
- DNS records are properly set and propagated
- Domain ownership is verified
- No firewall blocking Let's Encrypt verification

### Application Startup Issues
Check container logs for any configuration or database connection issues:

```bash
docker-compose -f docker-compose.prod.yml logs app
```

### Database Connection
Verify Supabase connection details in your `.env.production` file match your Supabase project settings.

## Security Notes

- The deployment uses production-grade security with SSL/HTTPS
- Database credentials are securely managed via environment variables
- Firewall rules restrict access to necessary ports only
- Regular security updates should be applied to the VM

## Cost Considerations

- **VM Instance**: e2-micro eligible for Google Cloud Free Tier
- **Static IP**: May incur small charges if VM is stopped
- **Bandwidth**: Free tier includes generous bandwidth allowances
- **SSL Certificates**: Free via Let's Encrypt

## Maintenance

### Updating the Application
To update the application image:

```bash
gcloud compute ssh metamcp-instance --zone=us-central1-a
cd metamcp
docker-compose -f docker-compose.prod.yml pull
docker-compose -f docker-compose.prod.yml up -d
```

### Certificate Renewal
SSL certificates automatically renew via Certbot cron job. Manual renewal if needed:

```bash
sudo certbot renew
sudo systemctl reload nginx
```