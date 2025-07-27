#!/bin/bash

# Google Cloud Service Account Setup Script
# This script creates a service account with necessary permissions for:
# - Pushing Docker images to Artifact Registry
# - Running Cloud Build builds
# - Deploying revisions to Cloud Run
# - Creating secret versions in Secret Manager

set -e

# Configuration
PROJECT_ID=${PROJECT_ID:-$(gcloud config get-value project)}
SERVICE_ACCOUNT_NAME=${SERVICE_ACCOUNT_NAME:-"terragon-deploy"}
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
KEY_FILE="terragon-service-account-key.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Setting up Google Cloud Service Account for Terragon deployment...${NC}"

# Check if gcloud is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    echo -e "${RED}Error: You must be authenticated with gcloud. Run 'gcloud auth login' first.${NC}"
    exit 1
fi

# Check if project is set
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: No project set. Use 'gcloud config set project PROJECT_ID' or set PROJECT_ID environment variable.${NC}"
    exit 1
fi

echo -e "${YELLOW}Using project: ${PROJECT_ID}${NC}"

# Enable required APIs
echo -e "${GREEN}Enabling required Google Cloud APIs...${NC}"
gcloud services enable cloudbuild.googleapis.com \
    run.googleapis.com \
    artifactregistry.googleapis.com \
    secretmanager.googleapis.com \
    iam.googleapis.com \
    --project="${PROJECT_ID}"

# Create service account
echo -e "${GREEN}Creating service account: ${SERVICE_ACCOUNT_NAME}...${NC}"
if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    echo -e "${YELLOW}Service account already exists. Skipping creation.${NC}"
else
    gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
        --display-name="Terragon Deployment Service Account" \
        --description="Service account for automated deployments with Cloud Build, Cloud Run, Artifact Registry, and Secret Manager" \
        --project="${PROJECT_ID}"
fi

# Grant necessary roles
echo -e "${GREEN}Granting IAM roles to service account...${NC}"

# Cloud Build roles
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/cloudbuild.builds.builder"

# Cloud Run roles
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/run.admin"

# Artifact Registry roles
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/artifactregistry.writer"

# Secret Manager roles
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/secretmanager.secretVersionAdder"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/secretmanager.secretAccessor"

# IAM roles for service account management
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/iam.serviceAccountUser"

# Storage roles (needed for Cloud Build artifacts)
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/storage.admin"

# Compute Engine roles (needed for Cloud Run deployment)
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
    --role="roles/compute.viewer"

# Create and download service account key
echo -e "${GREEN}Creating service account key...${NC}"
gcloud iam service-accounts keys create "${KEY_FILE}" \
    --iam-account="${SERVICE_ACCOUNT_EMAIL}" \
    --project="${PROJECT_ID}"

echo -e "${GREEN}✅ Service account setup complete!${NC}"
echo ""
echo -e "${YELLOW}📋 Setup Summary:${NC}"
echo "  • Service Account: ${SERVICE_ACCOUNT_EMAIL}"
echo "  • Key File: ${KEY_FILE}"
echo ""
echo -e "${YELLOW}🔑 Authentication Instructions:${NC}"
echo "  1. Copy the key file to your compute instance:"
echo "     scp ${KEY_FILE} your-instance:/path/to/key.json"
echo ""
echo "  2. Set environment variable on your compute instance:"
echo "     export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json"
echo ""
echo "  3. Or use the install script with:"
echo "     export SERVICE_ACCOUNT_KEY_JSON='\$(cat ${KEY_FILE})'"
echo ""
echo -e "${RED}⚠️  Security Note:${NC}"
echo "  • Keep the key file secure and never commit it to version control"
echo "  • Consider using Workload Identity instead of key files for production"
echo "  • Rotate keys regularly for enhanced security"