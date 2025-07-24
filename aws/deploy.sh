#!/bin/bash
set -e

# MetaMCP AWS App Runner Deployment Script
# This script deploys both frontend and backend services to AWS App Runner

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
AWS_REGION=${AWS_REGION:-"us-east-1"}
ENVIRONMENT=${ENVIRONMENT:-"production"}
FRONTEND_SERVICE=${FRONTEND_SERVICE:-"metamcp-frontend"}
BACKEND_SERVICE=${BACKEND_SERVICE:-"metamcp-backend"}
ECR_REPOSITORY_PREFIX=${ECR_REPOSITORY_PREFIX:-"metamcp"}

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
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "No active AWS authentication found. Please run 'aws configure' or set up credentials"
        exit 1
    fi
    
    # Get AWS Account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        print_error "Could not determine AWS Account ID"
        exit 1
    fi
    
    # Check if Docker is installed and running
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install it first."
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    print_success "Prerequisites check passed"
    print_status "Using AWS Region: $AWS_REGION"
    print_status "Using AWS Account ID: $AWS_ACCOUNT_ID"
}

# Function to create ECR repositories
create_ecr_repositories() {
    print_status "Creating ECR repositories if they don't exist..."
    
    # Create backend repository
    aws ecr describe-repositories --repository-names "${ECR_REPOSITORY_PREFIX}/backend" --region $AWS_REGION &> /dev/null || {
        print_status "Creating ECR repository for backend..."
        aws ecr create-repository \
            --repository-name "${ECR_REPOSITORY_PREFIX}/backend" \
            --region $AWS_REGION
    }
    
    # Create frontend repository
    aws ecr describe-repositories --repository-names "${ECR_REPOSITORY_PREFIX}/frontend" --region $AWS_REGION &> /dev/null || {
        print_status "Creating ECR repository for frontend..."
        aws ecr create-repository \
            --repository-name "${ECR_REPOSITORY_PREFIX}/frontend" \
            --region $AWS_REGION
    }
    
    print_success "ECR repositories ready"
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
        sed -i "s|\${AWS_REGION:-[^}]*}|$AWS_REGION|g" "$output_file"
        sed -i "s|\${AWS_ACCOUNT_ID:-[^}]*}|$AWS_ACCOUNT_ID|g" "$output_file"
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
        
        # Process AWS-specific variables
        if [[ -n "$S3_BUCKET" ]]; then
            sed -i "s|\${S3_BUCKET:-[^}]*}|$S3_BUCKET|g" "$output_file"
        fi
        if [[ -n "$CLOUDFRONT_DISTRIBUTION_ID" ]]; then
            sed -i "s|\${CLOUDFRONT_DISTRIBUTION_ID:-[^}]*}|$CLOUDFRONT_DISTRIBUTION_ID|g" "$output_file"
        fi
    fi
    
    print_success "Environment variables processed"
}

# Function to build and push Docker images
build_and_push_images() {
    print_status "Building and pushing Docker images..."
    
    # Login to ECR
    aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
    
    # Build and push backend image
    print_status "Building backend image..."
    docker build -f aws/Dockerfile.backend -t "${ECR_REPOSITORY_PREFIX}/backend:latest" .
    docker tag "${ECR_REPOSITORY_PREFIX}/backend:latest" "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/${ECR_REPOSITORY_PREFIX}/backend:latest"
    docker push "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/${ECR_REPOSITORY_PREFIX}/backend:latest"
    
    # Build and push frontend image
    print_status "Building frontend image..."
    docker build -f aws/Dockerfile.frontend -t "${ECR_REPOSITORY_PREFIX}/frontend:latest" .
    docker tag "${ECR_REPOSITORY_PREFIX}/frontend:latest" "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/${ECR_REPOSITORY_PREFIX}/frontend:latest"
    docker push "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/${ECR_REPOSITORY_PREFIX}/frontend:latest"
    
    print_success "Images built and pushed successfully"
}

# Function to create App Runner service configuration
create_apprunner_config() {
    local service_name=$1
    local image_uri=$2
    local env_file=$3
    local port=$4
    local memory=${5:-"2048"}
    local cpu=${6:-"1024"}
    
    # Convert env file to App Runner format
    local env_vars=""
    while IFS=': ' read -r key value; do
        # Skip comments and empty lines
        [[ $key =~ ^#.*$ ]] || [[ -z $key ]] && continue
        
        # Remove leading/trailing whitespace and quotes
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs | sed 's/^"//;s/"$//')
        
        if [[ -n "$env_vars" ]]; then
            env_vars="$env_vars,"
        fi
        env_vars="$env_vars{\"Name\":\"$key\",\"Value\":\"$value\"}"
    done < "$env_file"
    
    # Create App Runner service configuration
    cat > "/tmp/${service_name}-config.json" << EOF
{
    "ServiceName": "$service_name",
    "SourceConfiguration": {
        "ImageRepository": {
            "ImageIdentifier": "$image_uri",
            "ImageConfiguration": {
                "Port": "$port",
                "RuntimeEnvironmentVariables": {
                    $(echo "$env_vars" | sed 's/},{/,/g' | sed 's/^{//;s/}$//')
                }
            },
            "ImageRepositoryType": "ECR"
        },
        "AutoDeploymentsEnabled": false
    },
    "InstanceConfiguration": {
        "Cpu": "$cpu",
        "Memory": "$memory"
    },
    "HealthCheckConfiguration": {
        "Protocol": "HTTP",
        "Path": "/health",
        "Interval": 20,
        "Timeout": 10,
        "HealthyThreshold": 2,
        "UnhealthyThreshold": 5
    }
}
EOF
}

# Function to deploy backend service
deploy_backend() {
    print_status "Deploying backend service to App Runner..."
    
    # Process environment variables for backend
    local env_file="aws/env/backend.env.yaml"
    if [[ "$ENVIRONMENT" != "development" ]]; then
        env_file="aws/env/backend.$ENVIRONMENT.env.yaml"
    fi
    
    local processed_env_file="/tmp/backend.env.yaml"
    process_env_vars "$env_file" "$processed_env_file"
    
    # Backend image URI
    local backend_image="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/${ECR_REPOSITORY_PREFIX}/backend:latest"
    
    # Create App Runner service configuration
    create_apprunner_config "$BACKEND_SERVICE" "$backend_image" "$processed_env_file" "8080" "2048" "1024"
    
    # Check if App Runner service exists
    if aws apprunner describe-service --service-arn "arn:aws:apprunner:$AWS_REGION:$AWS_ACCOUNT_ID:service/$BACKEND_SERVICE" --region $AWS_REGION &> /dev/null; then
        print_status "Updating existing App Runner service..."
        aws apprunner update-service \
            --service-arn "arn:aws:apprunner:$AWS_REGION:$AWS_ACCOUNT_ID:service/$BACKEND_SERVICE" \
            --source-configuration file:///tmp/${BACKEND_SERVICE}-config.json \
            --region $AWS_REGION
    else
        print_status "Creating new App Runner service..."
        aws apprunner create-service \
            --cli-input-json file:///tmp/${BACKEND_SERVICE}-config.json \
            --region $AWS_REGION
    fi
    
    # Wait for service to be running
    print_status "Waiting for backend service to be running..."
    aws apprunner wait service-running \
        --service-arn "arn:aws:apprunner:$AWS_REGION:$AWS_ACCOUNT_ID:service/$BACKEND_SERVICE" \
        --region $AWS_REGION
    
    # Clean up temporary files
    rm -f "$processed_env_file" "/tmp/${BACKEND_SERVICE}-config.json"
    
    print_success "Backend service deployed successfully"
}

# Function to deploy frontend service
deploy_frontend() {
    print_status "Getting backend service URL..."
    
    # Get backend service URL
    local backend_url=$(aws apprunner describe-service \
        --service-arn "arn:aws:apprunner:$AWS_REGION:$AWS_ACCOUNT_ID:service/$BACKEND_SERVICE" \
        --region $AWS_REGION \
        --query 'Service.ServiceUrl' \
        --output text)
    
    if [ -z "$backend_url" ]; then
        print_error "Could not get backend service URL. Make sure backend is deployed first."
        exit 1
    fi
    
    # Ensure URL has https:// prefix
    if [[ "$backend_url" != https://* ]]; then
        backend_url="https://$backend_url"
    fi
    
    print_status "Backend URL: $backend_url"
    print_status "Deploying frontend service to App Runner..."
    
    # Set backend URL for environment variable processing
    export NEXT_PUBLIC_BACKEND_URL="$backend_url"
    
    # Process environment variables for frontend
    local env_file="aws/env/frontend.env.yaml"
    if [[ "$ENVIRONMENT" != "development" ]]; then
        env_file="aws/env/frontend.$ENVIRONMENT.env.yaml"
    fi
    
    local processed_env_file="/tmp/frontend.env.yaml"
    process_env_vars "$env_file" "$processed_env_file"
    
    # Frontend image URI
    local frontend_image="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/${ECR_REPOSITORY_PREFIX}/frontend:latest"
    
    # Create App Runner service configuration
    create_apprunner_config "$FRONTEND_SERVICE" "$frontend_image" "$processed_env_file" "8080" "1024" "512"
    
    # Check if App Runner service exists
    if aws apprunner describe-service --service-arn "arn:aws:apprunner:$AWS_REGION:$AWS_ACCOUNT_ID:service/$FRONTEND_SERVICE" --region $AWS_REGION &> /dev/null; then
        print_status "Updating existing App Runner service..."
        aws apprunner update-service \
            --service-arn "arn:aws:apprunner:$AWS_REGION:$AWS_ACCOUNT_ID:service/$FRONTEND_SERVICE" \
            --source-configuration file:///tmp/${FRONTEND_SERVICE}-config.json \
            --region $AWS_REGION
    else
        print_status "Creating new App Runner service..."
        aws apprunner create-service \
            --cli-input-json file:///tmp/${FRONTEND_SERVICE}-config.json \
            --region $AWS_REGION
    fi
    
    # Wait for service to be running
    print_status "Waiting for frontend service to be running..."
    aws apprunner wait service-running \
        --service-arn "arn:aws:apprunner:$AWS_REGION:$AWS_ACCOUNT_ID:service/$FRONTEND_SERVICE" \
        --region $AWS_REGION
    
    # Clean up temporary files
    rm -f "$processed_env_file" "/tmp/${FRONTEND_SERVICE}-config.json"
    
    print_success "Frontend service deployed successfully"
}

# Function to display deployment information
show_deployment_info() {
    print_success "Deployment completed successfully!"
    echo ""
    print_status "Service URLs:"
    
    local frontend_url=$(aws apprunner describe-service \
        --service-arn "arn:aws:apprunner:$AWS_REGION:$AWS_ACCOUNT_ID:service/$FRONTEND_SERVICE" \
        --region $AWS_REGION \
        --query 'Service.ServiceUrl' \
        --output text)
    
    local backend_url=$(aws apprunner describe-service \
        --service-arn "arn:aws:apprunner:$AWS_REGION:$AWS_ACCOUNT_ID:service/$BACKEND_SERVICE" \
        --region $AWS_REGION \
        --query 'Service.ServiceUrl' \
        --output text)
    
    echo "  Frontend: https://$frontend_url"
    echo "  Backend:  https://$backend_url"
    echo ""
    print_status "You can monitor your services at:"
    echo "  https://$AWS_REGION.console.aws.amazon.com/apprunner/home?region=$AWS_REGION#/services"
}

# Main deployment flow
main() {
    echo "🚀 MetaMCP AWS App Runner Deployment"
    echo "======================================"
    
    check_prerequisites
    create_ecr_repositories
    build_and_push_images
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
        create_ecr_repositories
        build_and_push_images
        deploy_backend
        ;;
    "frontend")
        print_status "Deploying frontend service only..."
        check_prerequisites
        create_ecr_repositories
        build_and_push_images
        deploy_frontend
        ;;
    "build")
        print_status "Building and pushing images only..."
        check_prerequisites
        create_ecr_repositories
        build_and_push_images
        ;;
    "help" | "-h" | "--help")
        echo "Usage: $0 [backend|frontend|build|help]"
        echo ""
        echo "Commands:"
        echo "  backend   Deploy backend service only"
        echo "  frontend  Deploy frontend service only"
        echo "  build     Build and push images only"
        echo "  help      Show this help message"
        echo ""
        echo "Environment Variables:"
        echo "  AWS_REGION              AWS region (default: us-east-1)"
        echo "  ENVIRONMENT            Environment (default: production)"
        echo "  FRONTEND_SERVICE       Frontend service name (default: metamcp-frontend)"
        echo "  BACKEND_SERVICE        Backend service name (default: metamcp-backend)"
        echo "  ECR_REPOSITORY_PREFIX  ECR repository prefix (default: metamcp)"
        ;;
    *)
        main
        ;;
esac