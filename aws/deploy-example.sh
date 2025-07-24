#!/bin/bash

# MetaMCP AWS Deployment Example Script
# This script shows how to configure environment variables and deploy MetaMCP to AWS

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo "🚀 MetaMCP AWS Deployment Example"
echo "================================="
echo ""

# ======================
# AWS Configuration
# ======================
print_status "Setting up AWS configuration..."

export AWS_REGION="us-east-1"                              # AWS region for deployment
export ENVIRONMENT="production"                            # Environment: development, staging, production
export FRONTEND_SERVICE="metamcp-frontend"                 # App Runner service name for frontend
export BACKEND_SERVICE="metamcp-backend"                   # App Runner service name for backend
export ECR_REPOSITORY_PREFIX="metamcp"                     # ECR repository prefix

print_success "AWS configuration set"

# ======================
# Database Configuration
# ======================
print_status "Setting up database configuration..."

# Replace these with your actual RDS instance details
export DB_HOST="your-rds-instance.${AWS_REGION}.rds.amazonaws.com"
export DB_PORT="5432"
export DB_NAME="metamcp_prod"
export DB_USER="metamcp_user"
# DB_PASSWORD should be stored in AWS Secrets Manager

print_success "Database configuration set"

# ======================
# Redis Configuration
# ======================
print_status "Setting up Redis configuration..."

# Replace with your actual ElastiCache cluster endpoint
export REDIS_URL="redis://your-elasticache-cluster.cache.amazonaws.com:6379"
# REDIS_PASSWORD should be stored in AWS Secrets Manager if auth is enabled

print_success "Redis configuration set"

# ======================
# Application Configuration
# ======================
print_status "Setting up application configuration..."

# Authentication configuration
export BETTER_AUTH_URL="https://api.yourdomain.com"        # Will be updated with actual App Runner URL

# Frontend configuration
export NEXT_PUBLIC_APP_NAME="MetaMCP"
export NEXT_PUBLIC_APP_VERSION="1.0.0"
export NEXT_PUBLIC_AWS_REGION="$AWS_REGION"

# CORS configuration for production
export CORS_ORIGINS="https://yourdomain.com,https://www.yourdomain.com"

# S3 configuration for file storage
export S3_BUCKET="metamcp-storage-prod"
export S3_REGION="$AWS_REGION"

print_success "Application configuration set"

# ======================
# AWS Services Configuration
# ======================
print_status "Setting up AWS services configuration..."

# CloudWatch configuration
export AWS_LOG_GROUP="/aws/apprunner/metamcp-backend-prod"
export AWS_LOG_STREAM="metamcp-backend-prod"

# Secrets Manager configuration
export SECRETS_MANAGER_REGION="$AWS_REGION"
export DB_SECRET_NAME="metamcp/prod/database/credentials"
export AUTH_SECRET_NAME="metamcp/prod/auth/secret"
export REDIS_SECRET_NAME="metamcp/prod/redis/auth"

# CloudWatch Metrics configuration
export ENABLE_CLOUDWATCH_METRICS="true"
export CLOUDWATCH_NAMESPACE="MetaMCP/Production"

# X-Ray Tracing configuration
export ENABLE_XRAY_TRACING="true"
export XRAY_TRACING_NAME="MetaMCP-Backend-Prod"

print_success "AWS services configuration set"

# ======================
# Frontend-specific Configuration
# ======================
print_status "Setting up frontend-specific configuration..."

# CDN and static assets
export NEXT_PUBLIC_CDN_URL="https://your-cloudfront-distribution.cloudfront.net"
export NEXT_PUBLIC_ASSETS_URL="https://your-s3-bucket.s3.amazonaws.com"

# AWS Cognito (if using for authentication)
export NEXT_PUBLIC_COGNITO_USER_POOL_ID="us-east-1_XXXXXXXXX"
export NEXT_PUBLIC_COGNITO_CLIENT_ID="your-cognito-client-id"
export NEXT_PUBLIC_COGNITO_REGION="$AWS_REGION"

# Error tracking and analytics
export NEXT_PUBLIC_ENABLE_ERROR_TRACKING="true"
export NEXT_PUBLIC_ERROR_TRACKING_DSN="https://your-error-tracking-dsn"
export NEXT_PUBLIC_GA_TRACKING_ID="G-XXXXXXXXXX"
export NEXT_PUBLIC_CLOUDWATCH_RUM_ID="your-rum-id"

print_success "Frontend configuration set"

# ======================
# Validation
# ======================
print_status "Validating configuration..."

# Check required environment variables
required_vars=(
    "AWS_REGION"
    "DB_HOST"
    "DB_NAME"
    "DB_USER"
    "REDIS_URL"
    "S3_BUCKET"
)

missing_vars=()

for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
        missing_vars+=("$var")
    fi
done

if [[ ${#missing_vars[@]} -gt 0 ]]; then
    print_error "Missing required environment variables:"
    for var in "${missing_vars[@]}"; do
        echo "  - $var"
    done
    echo ""
    print_error "Please set the missing variables and try again."
    exit 1
fi

print_success "Configuration validation passed"

# ======================
# Pre-deployment Setup
# ======================
print_status "Setting up AWS infrastructure (if needed)..."

print_warning "Make sure you have created the following AWS resources:"
echo "  1. RDS PostgreSQL instance: $DB_HOST"
echo "  2. ElastiCache Redis cluster: ${REDIS_URL#redis://}"
echo "  3. S3 bucket: $S3_BUCKET"
echo "  4. Secrets in AWS Secrets Manager:"
echo "     - $DB_SECRET_NAME (database credentials)"
echo "     - $AUTH_SECRET_NAME (authentication secret)"
echo "     - $REDIS_SECRET_NAME (Redis password, if auth enabled)"
echo ""

# Check if user wants to continue
read -p "Have you set up the required AWS infrastructure? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Please set up the required infrastructure first, then run this script again."
    echo ""
    print_status "You can use the following commands to create the infrastructure:"
    echo ""
    echo "# Create RDS instance"
    echo "aws rds create-db-instance \\"
    echo "    --db-instance-identifier metamcp-db \\"
    echo "    --db-instance-class db.t3.micro \\"
    echo "    --engine postgres \\"
    echo "    --master-username $DB_USER \\"
    echo "    --master-user-password YOUR_PASSWORD \\"
    echo "    --allocated-storage 20 \\"
    echo "    --db-name $DB_NAME"
    echo ""
    echo "# Create ElastiCache cluster"
    echo "aws elasticache create-cache-cluster \\"
    echo "    --cache-cluster-id metamcp-redis \\"
    echo "    --cache-node-type cache.t3.micro \\"
    echo "    --engine redis \\"
    echo "    --num-cache-nodes 1"
    echo ""
    echo "# Create S3 bucket"
    echo "aws s3 mb s3://$S3_BUCKET"
    echo ""
    echo "# Store database credentials in Secrets Manager"
    echo "aws secretsmanager create-secret \\"
    echo "    --name $DB_SECRET_NAME \\"
    echo "    --description \"MetaMCP Database Credentials\" \\"
    echo "    --secret-string '{\"username\":\"$DB_USER\",\"password\":\"YOUR_DB_PASSWORD\"}'"
    echo ""
    exit 0
fi

# ======================
# Deployment
# ======================
print_status "Starting deployment..."
echo ""

# Change to the directory containing the deployment script
cd "$(dirname "$0")"

# Run the deployment script
./deploy.sh

print_success "🎉 Deployment completed!"
echo ""
print_status "Next steps:"
echo "1. Verify your services are running in the AWS App Runner console"
echo "2. Test your application endpoints"
echo "3. Set up monitoring and alerting"
echo "4. Configure custom domains (optional)"
echo ""
print_status "Monitor your services at:"
echo "https://$AWS_REGION.console.aws.amazon.com/apprunner/home?region=$AWS_REGION#/services"