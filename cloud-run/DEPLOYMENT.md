# MetaMCP Cloud Run Deployment Guide

This guide provides step-by-step instructions for deploying MetaMCP to Google Cloud Run.

## 📋 Prerequisites

Before you begin, ensure you have:

- [x] Google Cloud Project with billing enabled
- [x] Google Cloud SDK (`gcloud`) installed and authenticated
- [x] Terraform (>= 1.0) installed
- [x] Sufficient IAM permissions (Project Editor or specific roles)
- [x] Domain name (optional, for custom domains)

## 🎯 Deployment Options

Choose your deployment approach:

1. **[Quick Deploy](#quick-deploy)** - Automated script deployment (Recommended for getting started)
2. **[Terraform Deploy](#terraform-deploy)** - Infrastructure as Code (Recommended for production)
3. **[Manual Deploy](#manual-deploy)** - Step-by-step manual deployment

---

## 🚀 Quick Deploy

### Step 1: Prepare Your Environment

```bash
# Set your project ID
export PROJECT_ID="your-project-id"
export REGION="us-central1"
export ENVIRONMENT="production"

# Authenticate with Google Cloud
gcloud auth login
gcloud config set project $PROJECT_ID
```

### Step 2: Enable Required APIs

```bash
gcloud services enable \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com \
  redis.googleapis.com \
  compute.googleapis.com \
  monitoring.googleapis.com \
  logging.googleapis.com
```

### Step 3: Set Up Secrets

```bash
# Generate and store database password
openssl rand -base64 32 | gcloud secrets create metamcp-db-password-production --data-file=-

# Generate and store Better Auth secret
openssl rand -hex 32 | gcloud secrets create metamcp-better-auth-secret-production --data-file=-
```

### Step 4: Deploy

```bash
# Make deployment script executable
chmod +x cloud-run/deploy.sh

# Run the deployment
./cloud-run/deploy.sh
```

### Step 5: Verify Deployment

The script will output the service URLs. Test your deployment:

```bash
# Test frontend
curl -I https://your-frontend-url

# Test backend health
curl https://your-backend-url/api/health
```

---

## 🏗️ Terraform Deploy

### Step 1: Prepare Terraform Configuration

```bash
# Navigate to terraform directory
cd cloud-run/terraform

# Copy and customize variables
cp ../terraform.tfvars.example terraform.tfvars
```

### Step 2: Edit Configuration

Edit `terraform.tfvars` with your settings:

```hcl
# Required settings
project_id = "your-project-id"
region     = "us-central1"
environment = "production"

# Customize as needed
database_tier = "db-f1-micro"
enable_redis = true
create_vpc = true
```

### Step 3: Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply the configuration
terraform apply
```

### Step 4: Update Images (if needed)

If you need to update the service images:

```bash
# Update variables.tf or terraform.tfvars with new image tags
frontend_image = "gcr.io/your-project-id/metamcp-frontend:v1.1.0"
backend_image = "gcr.io/your-project-id/metamcp-backend:v1.1.0"

# Apply changes
terraform apply
```

---

## ⚙️ Manual Deploy

### Step 1: Build Images

```bash
# Build and push backend image
gcloud builds submit \
  --config=cloud-run/cloudbuild-backend.yaml \
  --substitutions=_ENVIRONMENT=production

# Build and push frontend image
gcloud builds submit \
  --config=cloud-run/cloudbuild-frontend.yaml \
  --substitutions=_ENVIRONMENT=production
```

### Step 2: Create Database

```bash
# Create Cloud SQL instance
gcloud sql instances create metamcp-db-production \
  --database-version=POSTGRES_16 \
  --tier=db-f1-micro \
  --region=us-central1 \
  --storage-size=20GB \
  --storage-type=SSD

# Create database
gcloud sql databases create metamcp_prod \
  --instance=metamcp-db-production

# Create user with generated password
DB_PASSWORD=$(openssl rand -base64 32)
gcloud sql users create metamcp_user \
  --instance=metamcp-db-production \
  --password=$DB_PASSWORD

# Store password in Secret Manager
echo $DB_PASSWORD | gcloud secrets create metamcp-db-password-production --data-file=-
```

### Step 3: Deploy Backend Service

```bash
gcloud run deploy metamcp-backend \
  --image=gcr.io/$PROJECT_ID/metamcp-backend:latest \
  --region=us-central1 \
  --add-cloudsql-instances=$PROJECT_ID:us-central1:metamcp-db-production \
  --set-env-vars=NODE_ENV=production \
  --set-env-vars=DB_HOST=/cloudsql/$PROJECT_ID:us-central1:metamcp-db-production \
  --set-env-vars=DB_NAME=metamcp_prod \
  --set-env-vars=DB_USER=metamcp_user \
  --memory=2Gi \
  --cpu=2 \
  --min-instances=0 \
  --max-instances=100 \
  --allow-unauthenticated
```

### Step 4: Deploy Frontend Service

```bash
# Get backend URL
BACKEND_URL=$(gcloud run services describe metamcp-backend \
  --region=us-central1 \
  --format='value(status.url)')

# Deploy frontend
gcloud run deploy metamcp-frontend \
  --image=gcr.io/$PROJECT_ID/metamcp-frontend:latest \
  --region=us-central1 \
  --set-env-vars=NODE_ENV=production \
  --set-env-vars=NEXT_PUBLIC_BACKEND_URL=$BACKEND_URL \
  --memory=1Gi \
  --cpu=1 \
  --min-instances=0 \
  --max-instances=50 \
  --allow-unauthenticated
```

---

## 🔧 Environment-Specific Deployments

### Development Environment

```bash
export ENVIRONMENT="development"

# Use smaller resources for development
gcloud run deploy metamcp-backend-dev \
  --image=gcr.io/$PROJECT_ID/metamcp-backend:latest \
  --region=us-central1 \
  --memory=1Gi \
  --cpu=1 \
  --min-instances=0 \
  --max-instances=10
```

### Staging Environment

```bash
export ENVIRONMENT="staging"

# Deploy with staging configuration
./cloud-run/deploy.sh
```

---

## 🎛️ Configuration Management

### Environment Variables

Update environment variables without redeployment:

```bash
# Update backend environment variables
gcloud run services update metamcp-backend \
  --region=us-central1 \
  --set-env-vars=LOG_LEVEL=debug

# Update frontend environment variables
gcloud run services update metamcp-frontend \
  --region=us-central1 \
  --set-env-vars=NEXT_PUBLIC_DEBUG_MODE=true
```

### Secrets Management

Rotate secrets safely:

```bash
# Generate new secret
NEW_SECRET=$(openssl rand -hex 32)

# Add new version
echo $NEW_SECRET | gcloud secrets versions add metamcp-better-auth-secret-production --data-file=-

# Services will automatically use the new version on next deployment
```

---

## 🔄 Updates and Rollbacks

### Updating Services

```bash
# Update specific service
./cloud-run/deploy-backend.sh update

# Update with new image
gcloud run services update metamcp-backend \
  --image=gcr.io/$PROJECT_ID/metamcp-backend:v1.2.0 \
  --region=us-central1
```

### Rolling Back

```bash
# List revisions
gcloud run revisions list --service=metamcp-backend --region=us-central1

# Rollback to previous revision
gcloud run services update-traffic metamcp-backend \
  --to-revisions=metamcp-backend-00002=100 \
  --region=us-central1
```

---

## 📊 Monitoring Setup

### Enable Monitoring

```bash
# Create log-based metrics
gcloud logging metrics create metamcp_errors \
  --description="MetaMCP error count" \
  --log-filter='resource.type="cloud_run_revision" AND severity>=ERROR'

# Create alerting policy
gcloud alpha monitoring policies create \
  --policy-from-file=cloud-run/monitoring/alerts.yaml
```

### Custom Dashboards

```bash
# Import custom dashboard
gcloud monitoring dashboards create \
  --config-from-file=cloud-run/monitoring/dashboards.json
```

---

## 🌐 Custom Domain Setup

### SSL Certificate

```bash
# Create managed SSL certificate
gcloud compute ssl-certificates create metamcp-ssl-cert \
  --domains=metamcp.yourdomain.com \
  --global
```

### Load Balancer

```bash
# Create global IP
gcloud compute addresses create metamcp-ip --global

# Set up load balancer (use Terraform for complex setup)
# See terraform/networking.tf for complete configuration
```

---

## 🧪 Testing Deployment

### Health Checks

```bash
# Test backend health
curl https://your-backend-url/api/health

# Test frontend
curl -I https://your-frontend-url

# Test database connectivity (from backend service)
gcloud run services logs read metamcp-backend --region=us-central1
```

### Load Testing

```bash
# Install artillery for load testing
npm install -g artillery

# Create test configuration
cat > load-test.yml << EOF
config:
  target: 'https://your-frontend-url'
  phases:
    - duration: 60
      arrivalRate: 10
scenarios:
  - name: "Homepage"
    requests:
      - get:
          url: "/"
EOF

# Run load test
artillery run load-test.yml
```

---

## 🚨 Troubleshooting Deployment

### Common Issues

1. **Build Failures**
   ```bash
   # Check build logs
   gcloud builds log --region=us-central1
   ```

2. **Service Won't Start**
   ```bash
   # Check service logs
   gcloud run services logs read metamcp-backend --region=us-central1
   ```

3. **Database Connection Issues**
   ```bash
   # Test Cloud SQL connection
   gcloud sql connect metamcp-db-production --user=metamcp_user
   ```

4. **Permission Errors**
   ```bash
   # Check IAM permissions
   gcloud projects get-iam-policy $PROJECT_ID
   ```

### Debug Commands

```bash
# Service status
gcloud run services list

# Service details
gcloud run services describe metamcp-backend --region=us-central1

# Recent logs
gcloud logging read 'resource.type="cloud_run_revision"' --limit=50

# Service metrics
gcloud monitoring metrics list --filter="resource.type:cloud_run_revision"
```

---

## 🔒 Security Checklist

After deployment, verify:

- [ ] Services use service accounts with minimal permissions
- [ ] Database uses private IP and requires SSL
- [ ] Secrets are stored in Secret Manager
- [ ] VPC firewall rules are properly configured
- [ ] Cloud Armor is enabled (if configured)
- [ ] Audit logging is enabled
- [ ] Regular backups are configured

---

## 📞 Support

If you encounter issues:

1. Check the [Troubleshooting Guide](TROUBLESHOOTING.md)
2. Review [Google Cloud Run Documentation](https://cloud.google.com/run/docs)
3. Check [Cloud SQL Documentation](https://cloud.google.com/sql/docs)
4. Create an issue in the project repository

---

## 🎉 Post-Deployment

After successful deployment:

1. **Set up monitoring alerts** for error rates and performance
2. **Configure backup schedules** for your database
3. **Set up CI/CD pipelines** for automated deployments
4. **Document your configuration** for your team
5. **Plan for scaling** based on usage patterns

Your MetaMCP instance is now running on Google Cloud Run! 🚀