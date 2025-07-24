#!/bin/bash
set -e

# MetaMCP Frontend Service Deployment Script
# This script deploys only the frontend service to Cloud Run

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
PROJECT_ID=${PROJECT_ID:-""}
REGION=${REGION:-"us-central1"}
ENVIRONMENT=${ENVIRONMENT:-"production"}
FRONTEND_SERVICE=${FRONTEND_SERVICE:-"metamcp-frontend"}
BACKEND_SERVICE=${BACKEND_SERVICE:-"metamcp-backend"}
BUILD_ONLY=${BUILD_ONLY:-"false"}

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project ID is set
    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [ -z "$PROJECT_ID" ]; then
            print_error "PROJECT_ID is not set. Please set it as environment variable or run 'gcloud config set project YOUR_PROJECT_ID'"
            exit 1
        fi
    fi
    
    print_success "Prerequisites check passed"
    print_status "Using project: $PROJECT_ID"
    print_status "Using region: $REGION"
}

# Function to build frontend image
build_frontend_image() {
    print_status "Building frontend Docker image using Cloud Build..."
    
    # Submit build to Cloud Build for frontend only
    gcloud builds submit \
        --config=cloud-run/cloudbuild-frontend.yaml \
        --project=$PROJECT_ID \
        --substitutions=_ENVIRONMENT=$ENVIRONMENT \
        .
    
    print_success "Frontend image built successfully"
}

# Function to get backend URL
get_backend_url() {
    print_status "Getting backend service URL..."
    
    # Try to get backend service URL
    BACKEND_URL=$(gcloud run services describe $BACKEND_SERVICE \
        --region=$REGION \
        --project=$PROJECT_ID \
        --format='value(status.url)' 2>/dev/null || echo "")
    
    if [ -z "$BACKEND_URL" ]; then
        print_warning "Backend service not found or not deployed yet."
        print_warning "Frontend will be deployed without backend URL."
        print_warning "You may need to update the frontend service later."
        BACKEND_URL=""
    else
        print_success "Backend URL found: $BACKEND_URL"
    fi
}

# Function to deploy frontend service
deploy_frontend() {
    print_status "Deploying frontend service..."
    
    # Get the latest image
    FRONTEND_IMAGE="gcr.io/$PROJECT_ID/metamcp-frontend:latest"
    
    # Build the deployment command
    DEPLOY_CMD="gcloud run deploy $FRONTEND_SERVICE \
        --image=$FRONTEND_IMAGE \
        --platform=managed \
        --region=$REGION \
        --project=$PROJECT_ID \
        --allow-unauthenticated \
        --memory=1Gi \
        --cpu=1 \
        --concurrency=100 \
        --max-instances=50 \
        --min-instances=0 \
        --timeout=300 \
        --port=8080"
    
    # Add environment variables file if it exists
    if [ -f "cloud-run/env/frontend.$ENVIRONMENT.env.yaml" ]; then
        DEPLOY_CMD="$DEPLOY_CMD --env-vars-file=cloud-run/env/frontend.$ENVIRONMENT.env.yaml"
    fi
    
    # Add backend URL if available
    if [ -n "$BACKEND_URL" ]; then
        DEPLOY_CMD="$DEPLOY_CMD --set-env-vars=NEXT_PUBLIC_BACKEND_URL=$BACKEND_URL"
    fi
    
    # Execute deployment
    eval $DEPLOY_CMD
    
    print_success "Frontend service deployed successfully"
}

# Function to display deployment information
show_deployment_info() {
    print_success "Frontend deployment completed successfully!"
    echo ""
    
    FRONTEND_URL=$(gcloud run services describe $FRONTEND_SERVICE \
        --region=$REGION \
        --project=$PROJECT_ID \
        --format='value(status.url)')
    
    print_status "Frontend Service URL: $FRONTEND_URL"
    echo ""
    print_status "You can monitor your service at:"
    echo "  https://console.cloud.google.com/run/detail/$REGION/$FRONTEND_SERVICE?project=$PROJECT_ID"
}

# Function to update existing service
update_frontend() {
    print_status "Updating existing frontend service..."
    
    # Check if service exists
    if ! gcloud run services describe $FRONTEND_SERVICE \
        --region=$REGION \
        --project=$PROJECT_ID \
        --format='value(metadata.name)' &>/dev/null; then
        print_error "Frontend service '$FRONTEND_SERVICE' does not exist. Use deploy command instead."
        exit 1
    fi
    
    get_backend_url
    deploy_frontend
}

# Main deployment flow
main() {
    echo "🎨 MetaMCP Frontend Deployment"
    echo "==============================="
    
    check_prerequisites
    
    if [ "$BUILD_ONLY" = "true" ]; then
        build_frontend_image
        print_success "🎉 Frontend image built successfully!"
    else
        build_frontend_image
        get_backend_url
        deploy_frontend
        show_deployment_info
        print_success "🎉 Frontend deployment completed successfully!"
    fi
}

# Handle script arguments
case "${1:-}" in
    "build")
        print_status "Building frontend image only..."
        BUILD_ONLY="true"
        main
        ;;
    "update")
        print_status "Updating existing frontend service..."
        check_prerequisites
        get_backend_url
        deploy_frontend
        show_deployment_info
        ;;
    "help" | "-h" | "--help")
        echo "Usage: $0 [build|update|help]"
        echo ""
        echo "Commands:"
        echo "  build    Build frontend image only"
        echo "  update   Update existing frontend service"
        echo "  help     Show this help message"
        echo ""
        echo "Environment Variables:"
        echo "  PROJECT_ID        Google Cloud Project ID"
        echo "  REGION           Cloud Run region (default: us-central1)"
        echo "  ENVIRONMENT      Environment (default: production)"
        echo "  FRONTEND_SERVICE Frontend service name (default: metamcp-frontend)"
        echo "  BACKEND_SERVICE  Backend service name (default: metamcp-backend)"
        ;;
    *)
        main
        ;;
esac