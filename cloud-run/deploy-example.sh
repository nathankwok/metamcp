#!/bin/bash
# Example deployment script with environment variables
# This script shows how to set environment variables for MetaMCP Cloud Run deployment

set -e

# Example: Set your specific environment variables here
export PROJECT_ID="my-gcp-project"
export REGION="us-central1"
export ENVIRONMENT="production"

# Database Configuration
export DB_HOST="/cloudsql/my-gcp-project:us-central1:metamcp-db"
export DB_PORT="5432"
export DB_NAME="metamcp_prod"
export DB_USER="metamcp_user"
# Note: DB_PASSWORD should be set via Secret Manager, not as environment variable

# Backend Service Configuration
export BETTER_AUTH_URL="https://metamcp-backend-xyz-uc.a.run.app"

# Redis Configuration (if using Memorystore)
export REDIS_URL="redis://10.123.45.67:6379"

# CORS Configuration
export CORS_ORIGINS="https://metamcp-frontend-xyz-uc.a.run.app,https://app.mydomain.com"

# Frontend Configuration
export NEXT_PUBLIC_APP_NAME="MetaMCP Production"
export NEXT_PUBLIC_APP_VERSION="1.0.0"

# Optional: Authentication Configuration
# export NEXT_PUBLIC_AUTH_DOMAIN="mydomain.auth0.com"
# export NEXT_PUBLIC_AUTH_CLIENT_ID="my-auth0-client-id"

# Optional: Error Tracking and Analytics (Production only)
# export NEXT_PUBLIC_SENTRY_DSN="https://my-sentry-dsn@sentry.io/project-id"
# export NEXT_PUBLIC_SENTRY_ENVIRONMENT="production"
# export NEXT_PUBLIC_GA_TRACKING_ID="UA-123456789-1"
# export NEXT_PUBLIC_GTM_ID="GTM-ABCDEFG"

# Validate required environment variables
if [[ -z "$PROJECT_ID" ]]; then
    echo "Error: PROJECT_ID environment variable is required"
    exit 1
fi

if [[ -z "$DB_HOST" ]]; then
    echo "Error: DB_HOST environment variable is required"
    exit 1
fi

if [[ -z "$BETTER_AUTH_URL" ]]; then
    echo "Warning: BETTER_AUTH_URL not set, using default from environment file"
fi

# Display configuration
echo "=== Deployment Configuration ==="
echo "Project ID: $PROJECT_ID"
echo "Region: $REGION"
echo "Environment: $ENVIRONMENT"
echo "Database Host: $DB_HOST"
echo "Database Name: $DB_NAME"
echo "Backend Auth URL: $BETTER_AUTH_URL"
echo "CORS Origins: $CORS_ORIGINS"
echo "================================="

# Confirm deployment
read -p "Deploy with these settings? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled"
    exit 0
fi

# Run the deployment
./cloud-run/deploy.sh "$ENVIRONMENT"