#!/bin/bash
set -e

# MetaMCP Backend Service Deployment Script
# This script deploys only the backend service to Cloud Run

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
BACKEND_SERVICE=${BACKEND_SERVICE:-"metamcp-backend"}
BUILD_ONLY=${BUILD_ONLY:-"false"}
CLOUD_SQL_INSTANCE=${CLOUD_SQL_INSTANCE:-""}

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

# Function to build backend image
build_backend_image() {
    print_status "Building backend Docker image using Cloud Build..."
    
    # Submit build to Cloud Build for backend only
    gcloud builds submit \
        --config=cloud-run/cloudbuild-backend.yaml \
        --project=$PROJECT_ID \
        --substitutions=_ENVIRONMENT=$ENVIRONMENT \
        .
    
    print_success "Backend image built successfully"
}

# Function to check Cloud SQL instance
check_cloud_sql() {
    if [ -n "$CLOUD_SQL_INSTANCE" ]; then
        print_status "Checking Cloud SQL instance: $CLOUD_SQL_INSTANCE"
        
        # Check if instance exists
        if gcloud sql instances describe $CLOUD_SQL_INSTANCE --project=$PROJECT_ID &>/dev/null; then
            print_success "Cloud SQL instance found"
        else
            print_warning "Cloud SQL instance '$CLOUD_SQL_INSTANCE' not found."
            print_warning "Please create the instance first or update the CLOUD_SQL_INSTANCE variable."
        fi
    else
        print_warning "CLOUD_SQL_INSTANCE not set. Backend will deploy without Cloud SQL connection."
    fi
}

# Function to deploy backend service
deploy_backend() {
    print_status "Deploying backend service..."
    
    # Get the latest image
    BACKEND_IMAGE="gcr.io/$PROJECT_ID/metamcp-backend:latest"
    
    # Build the deployment command
    DEPLOY_CMD="gcloud run deploy $BACKEND_SERVICE \
        --image=$BACKEND_IMAGE \
        --platform=managed \
        --region=$REGION \
        --project=$PROJECT_ID \
        --allow-unauthenticated \
        --memory=2Gi \
        --cpu=2 \
        --concurrency=80 \
        --max-instances=100 \
        --min-instances=0 \
        --timeout=3600 \
        --port=8080"
    
    # Add environment variables file if it exists
    if [ -f "cloud-run/env/backend.$ENVIRONMENT.env.yaml" ]; then
        DEPLOY_CMD="$DEPLOY_CMD --env-vars-file=cloud-run/env/backend.$ENVIRONMENT.env.yaml"
    fi
    
    # Add Cloud SQL connection if instance is specified
    if [ -n "$CLOUD_SQL_INSTANCE" ]; then
        DEPLOY_CMD="$DEPLOY_CMD --add-cloudsql-instances=$PROJECT_ID:$REGION:$CLOUD_SQL_INSTANCE"
        print_status "Adding Cloud SQL connection: $PROJECT_ID:$REGION:$CLOUD_SQL_INSTANCE"
    fi
    
    # Add VPC connector if specified
    if [ -n "$VPC_CONNECTOR" ]; then
        DEPLOY_CMD="$DEPLOY_CMD --vpc-connector=$VPC_CONNECTOR"
        print_status "Adding VPC connector: $VPC_CONNECTOR"
    fi
    
    # Execute deployment
    eval $DEPLOY_CMD
    
    print_success "Backend service deployed successfully"
}

# Function to run database migrations
run_migrations() {
    if [ "$SKIP_MIGRATIONS" = "true" ]; then
        print_warning "Skipping database migrations (SKIP_MIGRATIONS=true)"
        return
    fi
    
    print_status "Running database migrations..."
    
    # Get the backend service URL
    BACKEND_URL=$(gcloud run services describe $BACKEND_SERVICE \
        --region=$REGION \
        --project=$PROJECT_ID \
        --format='value(status.url)')
    
    if [ -z "$BACKEND_URL" ]; then
        print_error "Could not get backend service URL for migrations"
        return
    fi
    
    print_status "Backend service is available at: $BACKEND_URL"
    print_status "Database migrations will run automatically on container startup"
}

# Function to display deployment information
show_deployment_info() {
    print_success "Backend deployment completed successfully!"
    echo ""
    
    BACKEND_URL=$(gcloud run services describe $BACKEND_SERVICE \
        --region=$REGION \
        --project=$PROJECT_ID \
        --format='value(status.url)')
    
    print_status "Backend Service URL: $BACKEND_URL"
    
    # Display service configuration
    print_status "Service Configuration:"
    gcloud run services describe $BACKEND_SERVICE \
        --region=$REGION \
        --project=$PROJECT_ID \
        --format='table(
            spec.template.spec.containers[0].resources.limits.memory:label="Memory",
            spec.template.spec.containers[0].resources.limits.cpu:label="CPU",
            spec.template.spec.containerConcurrency:label="Concurrency",
            spec.template.metadata.annotations."autoscaling.knative.dev/maxScale":label="Max Instances"
        )'
    
    echo ""
    print_status "You can monitor your service at:"
    echo "  https://console.cloud.google.com/run/detail/$REGION/$BACKEND_SERVICE?project=$PROJECT_ID"
    
    # Health check
    print_status "Performing health check..."
    sleep 5
    if curl -s "$BACKEND_URL/api/health" &>/dev/null; then
        print_success "✅ Backend service is healthy"
    else
        print_warning "⚠️ Health check failed - service may still be starting up"
    fi
}

# Function to update existing service
update_backend() {
    print_status "Updating existing backend service..."
    
    # Check if service exists
    if ! gcloud run services describe $BACKEND_SERVICE \
        --region=$REGION \
        --project=$PROJECT_ID \
        --format='value(metadata.name)' &>/dev/null; then
        print_error "Backend service '$BACKEND_SERVICE' does not exist. Use deploy command instead."
        exit 1
    fi
    
    check_cloud_sql
    deploy_backend
    run_migrations
}

# Main deployment flow
main() {
    echo "⚙️ MetaMCP Backend Deployment"
    echo "=============================="
    
    check_prerequisites
    
    if [ "$BUILD_ONLY" = "true" ]; then
        build_backend_image
        print_success "🎉 Backend image built successfully!"
    else
        build_backend_image
        check_cloud_sql
        deploy_backend
        run_migrations
        show_deployment_info
        print_success "🎉 Backend deployment completed successfully!"
    fi
}

# Handle script arguments
case "${1:-}" in
    "build")
        print_status "Building backend image only..."
        BUILD_ONLY="true"
        main
        ;;
    "update")
        print_status "Updating existing backend service..."
        check_prerequisites
        update_backend
        show_deployment_info
        ;;
    "migrate")
        print_status "Running database migrations only..."
        check_prerequisites
        run_migrations
        ;;
    "help" | "-h" | "--help")
        echo "Usage: $0 [build|update|migrate|help]"
        echo ""
        echo "Commands:"
        echo "  build    Build backend image only"
        echo "  update   Update existing backend service"
        echo "  migrate  Run database migrations only"
        echo "  help     Show this help message"
        echo ""
        echo "Environment Variables:"
        echo "  PROJECT_ID           Google Cloud Project ID"
        echo "  REGION              Cloud Run region (default: us-central1)"
        echo "  ENVIRONMENT         Environment (default: production)"
        echo "  BACKEND_SERVICE     Backend service name (default: metamcp-backend)"
        echo "  CLOUD_SQL_INSTANCE  Cloud SQL instance name"
        echo "  VPC_CONNECTOR       VPC connector name"
        echo "  SKIP_MIGRATIONS     Skip database migrations (default: false)"
        ;;
    *)
        main
        ;;
esac