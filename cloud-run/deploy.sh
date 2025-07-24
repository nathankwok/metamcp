#!/bin/bash
set -e

# MetaMCP Cloud Run Deployment Script
# This script deploys both frontend and backend services to Cloud Run

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

# Function to enable required APIs
enable_apis() {
    print_status "Enabling required Google Cloud APIs..."
    
    gcloud services enable \
        cloudbuild.googleapis.com \
        run.googleapis.com \
        sqladmin.googleapis.com \
        secretmanager.googleapis.com \
        redis.googleapis.com \
        compute.googleapis.com \
        --project=$PROJECT_ID
    
    print_success "APIs enabled successfully"
}

# Function to process environment variables
process_env_vars() {
    local env_file=$1
    local output_file=$2
    
    print_status "Processing environment variables for $env_file..."
    
    # Create a temporary file for processed environment variables
    cp "$env_file" "$output_file"
    
    # Use envsubst to substitute environment variables
    if command -v envsubst &> /dev/null; then
        envsubst < "$env_file" > "$output_file"
    else
        # Fallback: manual substitution for common patterns
        sed -i "s|\${PROJECT_ID:-[^}]*}|$PROJECT_ID|g" "$output_file"
        sed -i "s|\${REGION:-[^}]*}|$REGION|g" "$output_file"
        sed -i "s|\${ENVIRONMENT:-[^}]*}|$ENVIRONMENT|g" "$output_file"
        
        # Process database environment variables
        if [[ -n "$DB_HOST" ]]; then
            sed -i "s|\${DB_HOST:-[^}]*}|$DB_HOST|g" "$output_file"
        fi
        if [[ -n "$DB_NAME" ]]; then
            sed -i "s|\${DB_NAME:-[^}]*}|$DB_NAME|g" "$output_file"
        fi
        if [[ -n "$DB_USER" ]]; then
            sed -i "s|\${DB_USER:-[^}]*}|$DB_USER|g" "$output_file"
        fi
        if [[ -n "$BETTER_AUTH_URL" ]]; then
            sed -i "s|\${BETTER_AUTH_URL:-[^}]*}|$BETTER_AUTH_URL|g" "$output_file"
        fi
        if [[ -n "$REDIS_URL" ]]; then
            sed -i "s|\${REDIS_URL:-[^}]*}|$REDIS_URL|g" "$output_file"
        fi
        if [[ -n "$CORS_ORIGINS" ]]; then
            sed -i "s|\${CORS_ORIGINS:-[^}]*}|$CORS_ORIGINS|g" "$output_file"
        fi
        
        # Process frontend environment variables
        if [[ -n "$NEXT_PUBLIC_BACKEND_URL" ]]; then
            sed -i "s|\${NEXT_PUBLIC_BACKEND_URL}|$NEXT_PUBLIC_BACKEND_URL|g" "$output_file"
        fi
        if [[ -n "$NEXT_PUBLIC_APP_NAME" ]]; then
            sed -i "s|\${NEXT_PUBLIC_APP_NAME:-[^}]*}|$NEXT_PUBLIC_APP_NAME|g" "$output_file"
        fi
        if [[ -n "$NEXT_PUBLIC_APP_VERSION" ]]; then
            sed -i "s|\${NEXT_PUBLIC_APP_VERSION:-[^}]*}|$NEXT_PUBLIC_APP_VERSION|g" "$output_file"
        fi
    fi
    
    print_success "Environment variables processed"
}

# Function to build images
build_images() {
    print_status "Building Docker images using Cloud Build..."
    
    # Submit build to Cloud Build
    gcloud builds submit \
        --config=cloud-run/cloudbuild.yaml \
        --project=$PROJECT_ID \
        --substitutions=_ENVIRONMENT=$ENVIRONMENT,_REGION=$REGION \
        .
    
    print_success "Images built successfully"
}

# Function to deploy backend service
deploy_backend() {
    print_status "Deploying backend service..."
    
    # Process environment variables for backend
    ENV_FILE="cloud-run/env/backend.$ENVIRONMENT.env.yaml"
    PROCESSED_ENV_FILE="/tmp/backend.env.yaml"
    process_env_vars "$ENV_FILE" "$PROCESSED_ENV_FILE"
    
    # Get the latest image
    BACKEND_IMAGE="gcr.io/$PROJECT_ID/metamcp-backend:latest"
    
    # Deploy backend service
    gcloud run deploy $BACKEND_SERVICE \
        --image=$BACKEND_IMAGE \
        --platform=managed \
        --region=$REGION \
        --project=$PROJECT_ID \
        --env-vars-file="$PROCESSED_ENV_FILE" \
        --allow-unauthenticated \
        --memory=2Gi \
        --cpu=2 \
        --concurrency=80 \
        --max-instances=100 \
        --min-instances=0 \
        --timeout=3600 \
        --port=8080
    
    # Clean up temporary file
    rm -f "$PROCESSED_ENV_FILE"
    
    print_success "Backend service deployed successfully"
}

# Function to deploy frontend service
deploy_frontend() {
    print_status "Getting backend service URL..."
    
    # Get backend service URL
    BACKEND_URL=$(gcloud run services describe $BACKEND_SERVICE \
        --region=$REGION \
        --project=$PROJECT_ID \
        --format='value(status.url)')
    
    if [ -z "$BACKEND_URL" ]; then
        print_error "Could not get backend service URL. Make sure backend is deployed first."
        exit 1
    fi
    
    print_status "Backend URL: $BACKEND_URL"
    print_status "Deploying frontend service..."
    
    # Set backend URL for environment variable processing
    export NEXT_PUBLIC_BACKEND_URL="$BACKEND_URL"
    
    # Process environment variables for frontend
    ENV_FILE="cloud-run/env/frontend.$ENVIRONMENT.env.yaml"
    PROCESSED_ENV_FILE="/tmp/frontend.env.yaml"
    process_env_vars "$ENV_FILE" "$PROCESSED_ENV_FILE"
    
    # Get the latest image
    FRONTEND_IMAGE="gcr.io/$PROJECT_ID/metamcp-frontend:latest"
    
    # Deploy frontend service with processed environment variables
    gcloud run deploy $FRONTEND_SERVICE \
        --image=$FRONTEND_IMAGE \
        --platform=managed \
        --region=$REGION \
        --project=$PROJECT_ID \
        --env-vars-file="$PROCESSED_ENV_FILE" \
        --allow-unauthenticated \
        --memory=1Gi \
        --cpu=1 \
        --concurrency=100 \
        --max-instances=50 \
        --min-instances=0 \
        --timeout=300 \
        --port=8080
    
    # Clean up temporary file
    rm -f "$PROCESSED_ENV_FILE"
    
    print_success "Frontend service deployed successfully"
}

# Function to display deployment information
show_deployment_info() {
    print_success "Deployment completed successfully!"
    echo ""
    print_status "Service URLs:"
    
    FRONTEND_URL=$(gcloud run services describe $FRONTEND_SERVICE \
        --region=$REGION \
        --project=$PROJECT_ID \
        --format='value(status.url)')
    
    BACKEND_URL=$(gcloud run services describe $BACKEND_SERVICE \
        --region=$REGION \
        --project=$PROJECT_ID \
        --format='value(status.url)')
    
    echo "  Frontend: $FRONTEND_URL"
    echo "  Backend:  $BACKEND_URL"
    echo ""
    print_status "You can monitor your services at:"
    echo "  https://console.cloud.google.com/run?project=$PROJECT_ID"
}

# Main deployment flow
main() {
    echo "🚀 MetaMCP Cloud Run Deployment"
    echo "================================="
    
    check_prerequisites
    enable_apis
    build_images
    deploy_backend
    deploy_frontend
    show_deployment_info
    
    print_success "🎉 Deployment completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    "backend")
        print_status "Deploying backend service only..."
        check_prerequisites
        build_images
        deploy_backend
        ;;
    "frontend")
        print_status "Deploying frontend service only..."
        check_prerequisites
        build_images
        deploy_frontend
        ;;
    "build")
        print_status "Building images only..."
        check_prerequisites
        build_images
        ;;
    "help" | "-h" | "--help")
        echo "Usage: $0 [backend|frontend|build|help]"
        echo ""
        echo "Commands:"
        echo "  backend   Deploy backend service only"
        echo "  frontend  Deploy frontend service only"
        echo "  build     Build images only"
        echo "  help      Show this help message"
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