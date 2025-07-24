# MetaMCP Cloud Run Deployment

This directory contains all the necessary files to deploy MetaMCP to Google Cloud Run as separate frontend and backend services with Cloud SQL for PostgreSQL.

## 🏗️ Architecture Overview

The Cloud Run deployment separates the original monolithic Docker Compose setup into:

- **Frontend Service**: Next.js application serving the web interface
- **Backend Service**: Node.js API server managing MCP servers and business logic
- **Cloud SQL**: Managed PostgreSQL database
- **Redis (Optional)**: Managed Redis instance for caching
- **Secret Manager**: Secure storage for sensitive configuration

## 📁 Directory Structure

```
cloud-run/
├── Dockerfile.frontend          # Frontend service Docker image
├── Dockerfile.backend           # Backend service Docker image
├── frontend-entrypoint.sh       # Frontend startup script
├── backend-entrypoint.sh        # Backend startup script
├── cloudbuild.yaml             # Build both services
├── cloudbuild-frontend.yaml    # Build frontend only
├── cloudbuild-backend.yaml     # Build backend only
├── .gcloudignore               # Files to ignore during build
├── deploy.sh                   # Main deployment script
├── deploy-frontend.sh          # Frontend deployment script
├── deploy-backend.sh           # Backend deployment script
├── env/                        # Environment configurations
│   ├── frontend.env.yaml       # Frontend dev environment
│   ├── frontend.prod.env.yaml  # Frontend production environment
│   ├── backend.env.yaml        # Backend dev environment
│   └── backend.prod.env.yaml   # Backend production environment
├── terraform/                  # Infrastructure as Code
│   ├── main.tf                 # Main Terraform configuration
│   ├── variables.tf            # Variable definitions
│   ├── outputs.tf              # Output definitions
│   ├── cloud-sql.tf            # Database configuration
│   ├── cloud-run.tf            # Cloud Run services
│   ├── iam.tf                  # IAM roles and permissions
│   └── networking.tf           # VPC, subnets, and networking
├── secrets/                    # Secret Manager documentation
│   └── README.md               # Secret setup instructions
├── monitoring/                 # Monitoring configuration
│   ├── alerts.yaml             # Cloud Monitoring alerts
│   ├── dashboards.json         # Custom dashboards
│   └── slo.yaml                # Service Level Objectives
├── terraform.tfvars.example    # Example Terraform variables
└── README.md                   # This file
```

## 🚀 Quick Start

### Prerequisites

1. **Google Cloud SDK** installed and authenticated
2. **Terraform** (>= 1.0) installed
3. **Docker** for local building (optional)
4. Required Google Cloud APIs enabled

### 1. Enable Required APIs

```bash
gcloud services enable \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com \
  redis.googleapis.com \
  compute.googleapis.com
```

### 2. Set Up Configuration

```bash
# Copy and customize Terraform variables
cp cloud-run/terraform.tfvars.example cloud-run/terraform/terraform.tfvars

# Edit the file with your project details
nano cloud-run/terraform/terraform.tfvars
```

### 3. Deploy Infrastructure (Option A: Terraform)

```bash
cd cloud-run/terraform

# Initialize Terraform
terraform init

# Plan the deployment
terraform plan

# Deploy infrastructure
terraform apply
```

### 4. Deploy Services (Option B: Script)

```bash
# Set environment variables
export PROJECT_ID="your-project-id"
export REGION="us-central1"

# Deploy both services
./cloud-run/deploy.sh
```

## 🔧 Configuration

### Environment Variables

Environment variables are managed through YAML files in the `env/` directory:

- **Development**: `frontend.env.yaml`, `backend.env.yaml`
- **Production**: `frontend.prod.env.yaml`, `backend.prod.env.yaml`

### Secrets

Sensitive configuration is stored in Google Cloud Secret Manager. See [`secrets/README.md`](secrets/README.md) for setup instructions.

Required secrets:
- Database password
- Better Auth secret key
- API keys for external services (optional)

### Infrastructure

Infrastructure is defined using Terraform in the `terraform/` directory. Key components:

- **Cloud Run Services**: Frontend and backend with auto-scaling
- **Cloud SQL**: PostgreSQL with automated backups
- **VPC**: Private networking for secure communication
- **IAM**: Service accounts with minimal required permissions
- **Redis**: Optional caching layer

## 📊 Monitoring and Observability

### Built-in Monitoring

- **Cloud Run Metrics**: Request count, latency, error rate
- **Cloud SQL Metrics**: Database performance and connections
- **Application Logs**: Structured logging to Cloud Logging
- **Distributed Tracing**: Cloud Trace integration

### Custom Alerts

Configure alerts in `monitoring/alerts.yaml`:
- High error rates
- Database connection issues
- Memory/CPU usage thresholds
- Service availability

## 🔄 Deployment Options

### Full Deployment
```bash
./cloud-run/deploy.sh
```

### Service-Specific Deployment
```bash
# Backend only
./cloud-run/deploy-backend.sh

# Frontend only
./cloud-run/deploy-frontend.sh
```

### Build Only
```bash
# Build both images
./cloud-run/deploy.sh build

# Build specific service
./cloud-run/deploy-frontend.sh build
./cloud-run/deploy-backend.sh build
```

## 🛠️ Development Workflow

### Local Development
Continue using Docker Compose for local development:
```bash
docker-compose up -d
```

### Testing Cloud Run Locally
Use the Cloud Run emulator for testing:
```bash
# Build and test frontend locally
docker build -f cloud-run/Dockerfile.frontend -t metamcp-frontend .
docker run -p 8080:8080 metamcp-frontend

# Build and test backend locally
docker build -f cloud-run/Dockerfile.backend -t metamcp-backend .
docker run -p 8080:8080 metamcp-backend
```

### CI/CD Integration
Integrate with Cloud Build triggers:
```bash
# Set up automated builds on git push
gcloud builds triggers create github \
  --repo-name=your-repo \
  --repo-owner=your-username \
  --branch-pattern=main \
  --build-config=cloud-run/cloudbuild.yaml
```

## 💰 Cost Optimization

### Production Recommendations
- Use `db-f1-micro` for small workloads
- Set `min_instances = 0` for automatic scaling to zero
- Enable request-based scaling
- Use regional persistent disks

### Development Recommendations
- Use smaller instance types
- Disable Redis for development
- Use shorter backup retention periods
- Disable high availability features

## 🔒 Security

### Network Security
- Private VPC with VPC connector
- Cloud SQL with private IP
- No direct internet access to database

### Access Control
- Service accounts with minimal permissions
- IAM-based access control
- Secret Manager for sensitive data

### Compliance
- Encrypted data at rest and in transit
- Audit logging enabled
- Regular security updates via base image updates

## 📈 Scaling

### Automatic Scaling
Cloud Run automatically scales based on:
- Incoming request volume
- CPU and memory utilization
- Configured concurrency limits

### Manual Scaling Control
Adjust scaling parameters in:
- Terraform variables (`min_instances`, `max_instances`)
- Environment-specific configurations
- Cloud Console (temporary overrides)

## 🐛 Troubleshooting

### Common Issues

1. **Build Failures**
   ```bash
   # Check build logs
   gcloud builds log BUILD_ID
   ```

2. **Service Startup Issues**
   ```bash
   # Check service logs
   gcloud run services logs read SERVICE_NAME --region=REGION
   ```

3. **Database Connection Issues**
   ```bash
   # Test Cloud SQL connectivity
   gcloud sql connect INSTANCE_NAME --user=USERNAME
   ```

### Debug Commands
```bash
# View all Cloud Run services
gcloud run services list

# Describe specific service
gcloud run services describe SERVICE_NAME --region=REGION

# View recent logs
gcloud logging read 'resource.type="cloud_run_revision"' --limit=50
```

## 🔄 Migration from Docker Compose

The Cloud Run deployment maintains compatibility with the existing Docker Compose setup:

1. **Database**: Migrated from containerized PostgreSQL to Cloud SQL
2. **Networking**: Changed from Docker networks to VPC
3. **Secrets**: Moved from environment variables to Secret Manager
4. **Storage**: Persistent volumes replaced with Cloud Storage (if needed)

### Migration Steps

1. Export data from Docker Compose PostgreSQL
2. Deploy Cloud Run infrastructure
3. Import data to Cloud SQL
4. Update DNS/load balancer to point to Cloud Run
5. Monitor and validate

## 📚 Additional Resources

- [Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Cloud SQL Documentation](https://cloud.google.com/sql/docs)
- [Terraform Google Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [Secret Manager Documentation](https://cloud.google.com/secret-manager/docs)

## 🤝 Contributing

When adding new features:

1. Update both Docker Compose and Cloud Run configurations
2. Update environment variable templates
3. Add appropriate Terraform resources
4. Update documentation
5. Test in both local and Cloud Run environments

## 📄 License

This Cloud Run deployment configuration is part of the MetaMCP project and follows the same license terms.