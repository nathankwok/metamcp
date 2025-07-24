# MetaMCP AWS Deployment

This directory contains configuration files and deployment scripts for running MetaMCP on AWS using App Runner, RDS, ElastiCache, and other AWS services.

## Overview

The AWS deployment uses the following services:
- **AWS App Runner**: Container hosting for frontend and backend services
- **Amazon RDS**: PostgreSQL database
- **Amazon ElastiCache**: Redis cache
- **Amazon ECR**: Container registry
- **AWS Secrets Manager**: Secure storage for credentials
- **Amazon S3**: File storage
- **Amazon CloudWatch**: Logging and monitoring

## Prerequisites

1. **AWS CLI**: Install and configure the AWS CLI
   ```bash
   aws configure
   ```

2. **Docker**: Ensure Docker is installed and running

3. **Required AWS Permissions**: Your AWS user/role needs permissions for:
   - App Runner (create, update, delete services)
   - ECR (create repositories, push images)
   - RDS (if creating database)
   - ElastiCache (if creating Redis instance)
   - Secrets Manager (create and access secrets)
   - S3 (create buckets, manage objects)

## Quick Start

1. **Set environment variables**:
   ```bash
   export AWS_REGION="us-east-1"
   export ENVIRONMENT="production"
   export DB_HOST="your-rds-instance.region.rds.amazonaws.com"
   export DB_NAME="metamcp_prod"
   export DB_USER="metamcp_user"
   export REDIS_URL="redis://your-elasticache-cluster.cache.amazonaws.com:6379"
   ```

2. **Run the deployment**:
   ```bash
   ./aws/deploy.sh
   ```

## Environment Configuration

### Backend Environment Variables

The backend service requires the following key environment variables:

#### Database (RDS)
- `DB_HOST`: RDS instance endpoint
- `DB_PORT`: Database port (default: 5432)
- `DB_NAME`: Database name
- `DB_USER`: Database username
- `DB_PASSWORD`: Set via AWS Secrets Manager

#### Redis (ElastiCache)
- `REDIS_URL`: ElastiCache cluster endpoint
- `REDIS_PASSWORD`: Set via AWS Secrets Manager (if auth enabled)

#### Authentication
- `BETTER_AUTH_SECRET`: Set via AWS Secrets Manager
- `BETTER_AUTH_URL`: Your App Runner service URL

#### AWS Services
- `AWS_REGION`: AWS region
- `S3_BUCKET`: S3 bucket for file storage
- `AWS_LOG_GROUP`: CloudWatch log group

### Frontend Environment Variables

- `NEXT_PUBLIC_BACKEND_URL`: Backend service URL (auto-configured)
- `NEXT_PUBLIC_APP_NAME`: Application name
- `NEXT_PUBLIC_AWS_REGION`: AWS region for client-side AWS SDK

## Environment Files

- `env/backend.env.yaml`: Development backend configuration
- `env/backend.prod.env.yaml`: Production backend configuration
- `env/frontend.env.yaml`: Development frontend configuration
- `env/frontend.prod.env.yaml`: Production frontend configuration

All environment files support variable substitution using `${VAR_NAME:-default_value}` syntax.

## Deployment Commands

### Full Deployment
```bash
./aws/deploy.sh
```

### Deploy Individual Services
```bash
# Backend only
./aws/deploy.sh backend

# Frontend only
./aws/deploy.sh frontend

# Build images only
./aws/deploy.sh build
```

### Environment-Specific Deployments
```bash
# Development
ENVIRONMENT=development ./aws/deploy.sh

# Staging
ENVIRONMENT=staging ./aws/deploy.sh

# Production (default)
ENVIRONMENT=production ./aws/deploy.sh
```

## AWS Infrastructure Setup

### 1. RDS Database

Create a PostgreSQL database:

```bash
aws rds create-db-instance \
    --db-instance-identifier metamcp-db \
    --db-instance-class db.t3.micro \
    --engine postgres \
    --master-username metamcp_user \
    --master-user-password YOUR_PASSWORD \
    --allocated-storage 20 \
    --db-name metamcp_prod
```

### 2. ElastiCache Redis

Create a Redis cache cluster:

```bash
aws elasticache create-cache-cluster \
    --cache-cluster-id metamcp-redis \
    --cache-node-type cache.t3.micro \
    --engine redis \
    --num-cache-nodes 1
```

### 3. S3 Bucket

Create an S3 bucket for file storage:

```bash
aws s3 mb s3://metamcp-storage-prod
```

### 4. Secrets Manager

Store sensitive configuration in AWS Secrets Manager:

```bash
# Database credentials
aws secretsmanager create-secret \
    --name metamcp/prod/database/credentials \
    --description "MetaMCP Database Credentials" \
    --secret-string '{"username":"metamcp_user","password":"YOUR_DB_PASSWORD"}'

# Auth secret
aws secretsmanager create-secret \
    --name metamcp/prod/auth/secret \
    --description "MetaMCP Auth Secret" \
    --secret-string '{"secret":"YOUR_AUTH_SECRET"}'
```

## Monitoring and Logging

### CloudWatch Logs

Logs are automatically sent to CloudWatch:
- Backend: `/aws/apprunner/metamcp-backend`
- Frontend: `/aws/apprunner/metamcp-frontend`

### CloudWatch Metrics

App Runner provides built-in metrics:
- Request count
- Response time
- Error rate
- CPU and memory utilization

### Health Checks

Both services include health check endpoints:
- Backend: `https://your-backend-url/health`
- Frontend: `https://your-frontend-url/health`

## Security Considerations

1. **Secrets Management**: Store sensitive data in AWS Secrets Manager
2. **Network Security**: Configure VPC and security groups appropriately
3. **IAM Roles**: Use least-privilege IAM roles for App Runner services
4. **HTTPS**: App Runner provides automatic HTTPS termination
5. **CORS**: Configure CORS origins appropriately for production

## Cost Optimization

1. **App Runner**: Pay-per-use pricing with automatic scaling
2. **RDS**: Use appropriate instance sizes and storage types
3. **ElastiCache**: Consider reserved instances for production
4. **S3**: Use appropriate storage classes
5. **CloudWatch**: Set log retention periods

## Troubleshooting

### Common Issues

1. **Service fails to start**:
   - Check CloudWatch logs
   - Verify environment variables
   - Ensure database connectivity

2. **Image build failures**:
   - Check Docker daemon is running
   - Verify ECR permissions
   - Check image size limits

3. **Database connection issues**:
   - Verify RDS security groups
   - Check database credentials in Secrets Manager
   - Ensure database is publicly accessible (if needed)

### Debugging Commands

```bash
# Check App Runner service status
aws apprunner describe-service --service-arn "SERVICE_ARN"

# View CloudWatch logs
aws logs tail /aws/apprunner/metamcp-backend --follow

# Test database connectivity
aws rds describe-db-instances --db-instance-identifier metamcp-db
```

## Advanced Configuration

### Custom Domains

Configure custom domains for your App Runner services:

```bash
aws apprunner associate-custom-domain \
    --service-arn "SERVICE_ARN" \
    --domain-name "api.yourdomain.com"
```

### Auto Scaling

App Runner automatically scales based on traffic, but you can configure:
- Minimum instances: 0 (default)
- Maximum instances: 25 (default)
- Concurrency: 100 requests per instance (default)

### VPC Integration

For enhanced security, configure VPC connectivity:

```bash
aws apprunner create-vpc-connector \
    --vpc-connector-name metamcp-vpc-connector \
    --subnets subnet-12345 subnet-67890 \
    --security-groups sg-12345
```

## Support

For issues and questions:
1. Check CloudWatch logs
2. Review AWS App Runner documentation
3. Open an issue in the MetaMCP repository