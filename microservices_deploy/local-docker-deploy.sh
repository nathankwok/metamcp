#!/bin/bash
# MetaMCP Local Docker Build + Cloud Run Deployment Script
# Builds Docker images locally and pushes to GCR, then deploys to Cloud Run with Supabase PostgreSQL
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Print functions
print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "${PURPLE}[DEPLOY]${NC} $1"; }

# Default configuration
PROJECT_ID=${PROJECT_ID:-""}
REGION=${REGION:-"us-central1"}
ENVIRONMENT=${ENVIRONMENT:-"production"}
BACKEND_URL=${BACKEND_URL:-"https://metamcp-backend-555166161772.us-central1.run.app"}
FRONTEND_URL=${FRONTEND_URL:-"https://metamcp-frontend-555166161772.us-central1.run.app"}


# Service names
FRONTEND_SERVICE="metamcp-frontend"
BACKEND_SERVICE="metamcp-backend"

# Get git commit SHA
GIT_SHORT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

print_header "🚀 MetaMCP Local Docker + Cloud Run Deployment"
print_header "=============================================="
echo ""

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if docker is installed
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install it first."
        print_error "Visit: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed. Please install it first."
        print_error "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_error "No active gcloud authentication found."
        print_error "Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if Docker is configured for GCR
    print_status "Configuring Docker for Google Container Registry..."
    if ! gcloud auth configure-docker --quiet; then
        print_error "Failed to configure Docker for GCR"
        exit 1
    fi
    
    # Check if git is available and we're in a git repository
    if ! command -v git &> /dev/null; then
        print_error "git is not installed. Please install it first."
        exit 1
    fi
    
    if ! git rev-parse --git-dir &> /dev/null; then
        print_error "Not in a git repository. Please run this script from the project root."
        exit 1
    fi
    
    # Check required commands
    local required_commands=("openssl" "curl")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            print_error "$cmd is not installed. Please install it first."
            exit 1
        fi
    done
    
    print_success "Prerequisites check passed ✅"
}

# Function to load and validate configuration
load_configuration() {
    print_status "Loading configuration..."
    
    # Check for environment file
    if [[ -f ".env.deployment" ]]; then
        print_status "Found .env.deployment file, loading configuration..."
        source .env.deployment
    fi
    
    # Validate PROJECT_ID
    if [[ -z "$PROJECT_ID" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [[ -z "$PROJECT_ID" ]]; then
            print_error "PROJECT_ID is not set."
            print_error ""
            print_error "Please set it by:"
            print_error "1. Creating .env.deployment file with PROJECT_ID=\"your-project-id\""
            print_error "2. Running: export PROJECT_ID=\"your-project-id\""
            print_error "3. Running: gcloud config set project your-project-id"
            exit 1
        fi
    fi
    
    # Validate SUPABASE_CONNECTION_STRING
    if [[ -z "$SUPABASE_CONNECTION_STRING" ]]; then
        print_error "SUPABASE_CONNECTION_STRING is not set."
        print_error ""
        print_error "To get your connection string:"
        print_error "1. Go to your Supabase project dashboard"
        print_error "2. Navigate to Settings → Database"
        print_error "3. Copy the 'Connection string' (should use port 6543)"
        print_error ""
        print_error "Then set it by:"
        print_error "1. Adding to .env.deployment file, or"
        print_error "2. Running: export SUPABASE_CONNECTION_STRING=\"postgresql://...\""
        exit 1
    fi
    
    # Validate connection string format
    if [[ ! "$SUPABASE_CONNECTION_STRING" =~ ^postgresql://.*\.supabase\.com:6543/ ]]; then
        print_warning "Connection string validation failed!"
        print_warning "Expected format: postgresql://postgres.[ref]:[password]@...pooler.supabase.com:6543/postgres"
        print_warning "Make sure you're using the pooler connection (port 6543) not direct (port 5432)"
        print_warning ""
        echo -n "Continue anyway? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_error "Deployment cancelled"
            exit 1
        fi
    fi
    
    print_success "Configuration validated ✅"
    print_status "Project ID: $PROJECT_ID"
    print_status "Region: $REGION"
    print_status "Environment: $ENVIRONMENT"
    print_status "Git SHA: $GIT_SHORT_SHA"
    echo ""
}

# Function to enable required APIs
enable_apis() {
    print_status "Enabling required Google Cloud APIs..."
    
    local apis=(
        "run.googleapis.com"
        "secretmanager.googleapis.com"
        "compute.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        print_status "Enabling $api..."
        gcloud services enable "$api" --project="$PROJECT_ID" --quiet
    done
    
    print_success "APIs enabled successfully ✅"
    echo ""
}

# Function to create secrets
create_secrets() {
    print_status "Creating Secret Manager secrets..."
    
    # Create or update database URL secret
    print_status "Creating/updating database connection secret..."
    if gcloud secrets describe metamcp-database-url-production --project="$PROJECT_ID" &>/dev/null; then
        print_status "Secret exists, adding new version..."
        echo "$SUPABASE_CONNECTION_STRING" | gcloud secrets versions add metamcp-database-url-production \
            --data-file=- --project="$PROJECT_ID"
    else
        print_status "Creating new secret..."
        echo "$SUPABASE_CONNECTION_STRING" | gcloud secrets create metamcp-database-url-production \
            --data-file=- --project="$PROJECT_ID"
    fi
    
    # Generate and store Better Auth secret
    print_status "Creating/updating Better Auth secret..."
    BETTER_AUTH_SECRET=$(openssl rand -hex 32)
    if gcloud secrets describe metamcp-better-auth-secret-production --project="$PROJECT_ID" &>/dev/null; then
        print_status "Secret exists, adding new version..."
        echo "$BETTER_AUTH_SECRET" | gcloud secrets versions add metamcp-better-auth-secret-production \
            --data-file=- --project="$PROJECT_ID"
    else
        print_status "Creating new secret..."
        echo "$BETTER_AUTH_SECRET" | gcloud secrets create metamcp-better-auth-secret-production \
            --data-file=- --project="$PROJECT_ID"
    fi
    
    print_success "Secrets created successfully ✅"
    echo ""
}

# Function to run database migrations
run_migrations() {
    print_status "Running database migrations..."

    # Check if we're in the project root and backend exists
    if [[ ! -d "apps/backend" ]]; then
        print_error "apps/backend directory not found. Make sure you're in the project root."
        exit 1
    fi

    # Check if drizzle directory exists with migration files
    if [[ ! -d "apps/backend/drizzle" ]]; then
        print_warning "No drizzle directory found in apps/backend. Skipping migrations."
        return 0
    fi

    # Check if there are any .sql files in drizzle directory
    if ! ls apps/backend/drizzle/*.sql >/dev/null 2>&1; then
        print_status "No migration files found in apps/backend/drizzle. Skipping migrations."
        return 0
    fi

    print_status "Found migration files, running migrations..."

    # Store current directory
    local original_dir=$(pwd)

    # Change to backend directory
    cd apps/backend

    # Set the database URL for migrations
    export DATABASE_URL="$SUPABASE_CONNECTION_STRING"

    # Run migrations using drizzle-kit
    print_status "Executing: pnpm exec drizzle-kit migrate"
    if pnpm exec drizzle-kit migrate; then
        print_success "Migrations completed successfully! ✅"
    else
        print_error "❌ Migration failed! Deployment will continue but database may be out of sync."
        print_error "You may need to run migrations manually:"
        print_error "cd apps/backend && DATABASE_URL=\"\$SUPABASE_CONNECTION_STRING\" pnpm exec drizzle-kit migrate"

        # Ask if user wants to continue
        echo -n "Continue with deployment anyway? (y/N): "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            print_error "Deployment cancelled due to migration failure"
            cd "$original_dir"
            exit 1
        fi
        print_warning "Continuing deployment despite migration failure..."
    fi

    # Return to original directory
    cd "$original_dir"

    echo ""
}

# Function to build backend Docker image locally
build_backend_image() {
    print_status "Building backend container image locally..."
    
    # Check if main Dockerfile exists
    if [[ ! -f "Dockerfile" ]]; then
        print_error "Dockerfile not found!"
        print_error "Make sure you're running this script from the project root directory."
        exit 1
    fi
    
    local backend_image="gcr.io/$PROJECT_ID/$BACKEND_SERVICE:$GIT_SHORT_SHA"
    local backend_latest="gcr.io/$PROJECT_ID/$BACKEND_SERVICE:latest"
    
    print_status "Building backend image: $backend_image"
    docker build \
        --file=microservices_deploy/Dockerfile.backend \
        --tag="$backend_latest" \
        --tag="$backend_image" \
        .
    
    print_status "Pushing backend image to Google Container Registry..."
    docker push "$backend_image"
    docker push "$backend_latest"
    
    print_success "Backend image built and pushed successfully ✅"
    print_status "Backend image: $backend_image"
    echo ""
}

# Function to build frontend Docker image locally
build_frontend_image() {
    print_status "Building frontend container image locally..."
    
    # Check if frontend Dockerfile exists
    if [[ ! -f "microservices_deploy/Dockerfile.frontend" ]]; then
        print_error "microservices_deploy/Dockerfile.frontend not found!"
        print_error "Make sure you're running this script from the project root directory."
        exit 1
    fi
    
    local frontend_image="gcr.io/$PROJECT_ID/$FRONTEND_SERVICE:$GIT_SHORT_SHA"
    local frontend_latest="gcr.io/$PROJECT_ID/$FRONTEND_SERVICE:latest"
    
    print_status "Building frontend image: $frontend_image"
    docker build \
        --file=microservices_deploy/Dockerfile.frontend \
        --tag="$frontend_image" \
        --tag="$frontend_latest" \
        .
    
    print_status "Pushing frontend image to Google Container Registry..."
    docker push "$frontend_image"
    docker push "$frontend_latest"
    
    print_success "Frontend image built and pushed successfully ✅"
    print_status "Frontend image: $frontend_image"
    echo ""
}

# Function to build both images
build_images() {
    print_status "Building all container images locally..."
    build_backend_image
    build_frontend_image
    print_success "All images built and pushed successfully ✅"
}

# Function to deploy backend service
deploy_backend() {
    print_status "Deploying backend service (optimized for free tier)..."
    
    local backend_image="gcr.io/$PROJECT_ID/$BACKEND_SERVICE:$GIT_SHORT_SHA"
    
#    # Get frontend URL first (needed for APP_URL environment variable)
#    local frontend_url=$(gcloud run services describe "$FRONTEND_SERVICE" \
#        --region="$REGION" \
#        --project="$PROJECT_ID" \
#        --format='value(status.url)' 2>/dev/null || echo "https://$FRONTEND_SERVICE-$PROJECT_ID.${REGION}.run.app")
    
    print_status "Deploying $BACKEND_SERVICE with image: $backend_image..."
#    print_status "Using frontend URL for APP_URL: $frontend_url"
    print_status "Using backend URL for APP_URL: $BACKEND_URL"
    gcloud run deploy "$BACKEND_SERVICE" \
        --image="$backend_image" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --platform=managed \
        --set-env-vars="NODE_ENV=production,APP_URL=$BACKEND_URL" \
        --set-secrets="DATABASE_URL=metamcp-database-url-production:latest,BETTER_AUTH_SECRET=metamcp-better-auth-secret-production:latest" \
        --memory=1Gi \
        --cpu=1000m \
        --min-instances=0 \
        --max-instances=1 \
        --concurrency=50 \
        --timeout=300 \
        --port=12009 \
        --allow-unauthenticated \
        --quiet
    
    # Get backend URL
    BACKEND_URL=$(gcloud run services describe "$BACKEND_SERVICE" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format='value(status.url)')
    
    if [[ -z "$BACKEND_URL" ]]; then
        print_error "Failed to get backend service URL"
        exit 1
    fi
    
    print_success "Backend deployed successfully ✅"
    print_status "Backend URL: $BACKEND_URL"
    echo ""
}

# Function to deploy frontend service
deploy_frontend() {
    print_status "Deploying frontend service (optimized for free tier)..."
    
    if [[ -z "$BACKEND_URL" ]]; then
        print_error "Backend URL not available. Backend deployment may have failed."
        exit 1
    fi
    
    local frontend_image="gcr.io/$PROJECT_ID/$FRONTEND_SERVICE:$GIT_SHORT_SHA"
    
    # Get frontend URL first (in case service already exists)
    FRONTEND_URL=$(gcloud run services describe "$FRONTEND_SERVICE" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format='value(status.url)' 2>/dev/null || echo "")
    
    # If no existing service, we'll get the URL after deployment
    if [[ -z "$FRONTEND_URL" ]]; then
        FRONTEND_URL="https://$FRONTEND_SERVICE-$PROJECT_ID.${REGION}.run.app"
    fi
    
    print_status "Deploying $FRONTEND_SERVICE with image: $frontend_image..."
    gcloud run deploy "$FRONTEND_SERVICE" \
        --image="$frontend_image" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --platform=managed \
        --set-env-vars="NODE_ENV=production,NEXT_PUBLIC_APP_URL=$FRONTEND_URL,NEXT_PUBLIC_API_URL=$BACKEND_URL" \
        --memory=512Mi \
        --cpu=1000m \
        --min-instances=0 \
        --max-instances=5 \
        --concurrency=100 \
        --timeout=300 \
        --port=12008 \
        --allow-unauthenticated \
        --quiet
    
    # Get the actual frontend URL after deployment
    FRONTEND_URL=$(gcloud run services describe "$FRONTEND_SERVICE" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format='value(status.url)')
    
    if [[ -z "$FRONTEND_URL" ]]; then
        print_error "Failed to get frontend service URL"
        exit 1
    fi
    
    print_success "Frontend deployed successfully ✅"
    print_status "Frontend URL: $FRONTEND_URL"
    echo ""
}

# Function to test deployment
test_deployment() {
    print_status "Testing deployment..."
    
    # Test backend health
    print_status "Testing backend health endpoint..."
    if curl -f -s "$BACKEND_URL/health" > /dev/null; then
        print_success "Backend health check passed ✅"
    else
        print_warning "Backend health check failed (this might be normal if health endpoint doesn't exist yet)"
    fi
    
    # Test frontend
    print_status "Testing frontend..."
    if curl -f -s -I "$FRONTEND_URL" > /dev/null; then
        print_success "Frontend accessibility check passed ✅"
    else
        print_warning "Frontend accessibility check failed"
    fi
    
    echo ""
}

# Function to show deployment summary
show_deployment_summary() {
    print_success "🎉 Deployment completed successfully!"
    echo ""
    print_header "📋 Deployment Summary"
    print_header "====================="
    echo ""
    echo "🌐 Service URLs:"
    echo "   Frontend: $FRONTEND_URL"
    echo "   Backend:  $BACKEND_URL"
    echo ""
    echo "🗄️  Database:"
    echo "   Provider: Supabase PostgreSQL"
    echo "   Connection: Pooled (port 6543)"
    echo ""
    echo "🔒 Security:"
    echo "   Secrets: Google Secret Manager"
    echo "   Auth: Better Auth"
    echo ""
    echo "⚡ Performance (Free Tier Optimized):"
    echo "   Frontend: 512Mi RAM, 1 vCPU, 0-5 instances"
    echo "   Backend:  1Gi RAM, 1 vCPU, 0-5 instances"
    echo ""
    echo "🐳 Build Method: Local Docker Build & Push"
    echo ""
    print_header "🚀 Next Steps"
    print_header "============="
    echo ""
    echo "1. 🧪 Test your deployment:"
    echo "   curl $BACKEND_URL/health"
    echo "   open $FRONTEND_URL"
    echo ""
    echo "2. 📈 Monitor your services:"
    echo "   - Cloud Run: https://console.cloud.google.com/run?project=$PROJECT_ID"
    echo "   - Supabase: https://supabase.com/dashboard"
    echo ""
    echo "3. 📝 Free Tier Limits to Monitor:"
    echo "   - Cloud Run: 2M requests/month, 360K GB-seconds/month"
    echo "   - Supabase: 500MB storage, 1 week pause after inactivity"
    echo ""
    print_success "Happy coding! 🚀"
}

# Function to handle cleanup on error
cleanup_on_error() {
    print_error "Deployment failed. Check the logs above for details."
    print_status "You can re-run this script after fixing any issues."
    exit 1
}

# Set error trap
trap cleanup_on_error ERR

# Main deployment flow
main() {
    check_prerequisites
    load_configuration
    enable_apis
    create_secrets
#    run_migrations
    build_backend_image
    build_frontend_image
    deploy_backend
    deploy_frontend
    test_deployment
    show_deployment_summary
}

# Handle script arguments
case "${1:-}" in
    "backend")
        print_status "Deploying backend service only..."
        check_prerequisites
        load_configuration
        enable_apis
        create_secrets
#        run_migrations
        build_backend_image
        deploy_backend
        print_success "Backend deployment completed!"
        ;;
    "frontend")
        print_status "Deploying frontend service only..."
        check_prerequisites
        load_configuration
        build_frontend_image
        deploy_frontend
        print_success "Frontend deployment completed!"
        ;;
    "build")
        print_status "Building images only..."
        check_prerequisites
        load_configuration
        build_backend_image
        build_frontend_image
        print_success "Build completed!"
        ;;
    "build-backend")
        print_status "Building backend image only..."
        check_prerequisites
        load_configuration
        build_backend_image
        print_success "Backend build completed!"
        ;;
    "build-frontend")
        print_status "Building frontend image only..."
        check_prerequisites
        load_configuration
        build_frontend_image
        print_success "Frontend build completed!"
        ;;
    "deploy-backend")
        print_status "Deploying backend service only..."
        check_prerequisites
        load_configuration
        deploy_backend
        print_success "Deploy backend completed!"
        ;;
    "deploy-frontend")
        print_status "Deploying frontend service only..."
        check_prerequisites
        load_configuration
        deploy_frontend
        print_success "Deploy frontend completed!"
        ;;
    "secrets")
        print_status "Creating secrets only..."
        check_prerequisites
        load_configuration
        enable_apis
        create_secrets
        print_success "Secrets created!"
        ;;
    "migrate")
        print_status "Running database migrations only..."
        check_prerequisites
        load_configuration
        run_migrations
        print_success "Migration completed!"
        ;;
    "test")
        print_status "Testing deployment..."
        load_configuration
        BACKEND_URL=$(gcloud run services describe "$BACKEND_SERVICE" --region="$REGION" --project="$PROJECT_ID" --format='value(status.url)')
        FRONTEND_URL=$(gcloud run services describe "$FRONTEND_SERVICE" --region="$REGION" --project="$PROJECT_ID" --format='value(status.url)')
        test_deployment
        ;;
    "help" | "-h" | "--help")
        echo "MetaMCP Local Docker + Cloud Run Deployment Script"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  (no args)       Full deployment (default)"  
        echo "  backend         Deploy backend service only"
        echo "  frontend        Deploy frontend service only"
        echo "  build           Build all container images locally"
        echo "  build-backend   Build backend container image only"
        echo "  build-frontend  Build frontend container image only"
        echo "  secrets         Create/update secrets only"
        echo "  migrate         Run database migrations only"
        echo "  test            Test existing deployment"
        echo "  help            Show this help message"
        echo ""
        echo "Required Environment Variables:"
        echo "  PROJECT_ID                  Google Cloud Project ID"
        echo "  SUPABASE_CONNECTION_STRING  PostgreSQL connection string from Supabase"
        echo ""
        echo "Optional Environment Variables:"
        echo "  REGION                      Cloud Run region (default: us-central1)"
        echo "  ENVIRONMENT                 Environment name (default: production)"
        echo ""
        echo "Configuration Methods:"
        echo "  1. Create .env.deployment file with variables"
        echo "  2. Export environment variables before running"
        echo "  3. Set gcloud project: gcloud config set project PROJECT_ID"
        echo ""
        echo "Example .env.deployment file:"
        echo "  PROJECT_ID=\"my-gcp-project\""
        echo "  SUPABASE_CONNECTION_STRING=\"postgresql://postgres.[ref]:[password]@...pooler.supabase.com:6543/postgres\""
        echo ""
        echo "Key Differences from Cloud Build version:"
        echo "  - Builds Docker images locally instead of using Cloud Build"
        echo "  - Pushes images directly to Google Container Registry"
        echo "  - Requires Docker to be installed and running locally"
        echo "  - Faster for small projects, no Cloud Build API required"
        echo ""
        ;;
    *)
        main
        ;;
esac