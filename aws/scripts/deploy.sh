#!/bin/bash

# Laravel AWS ECS Deployment Script
# Usage: ./deploy.sh [environment] [image_tag]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AWS_REGION="${AWS_REGION:-us-east-1}"
ECR_REPOSITORY="laravel-app"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    echo "Usage: $0 [environment] [image_tag]"
    echo ""
    echo "Arguments:"
    echo "  environment    Target environment (staging|production)"
    echo "  image_tag      Docker image tag to deploy (default: latest)"
    echo ""
    echo "Environment Variables:"
    echo "  AWS_REGION     AWS region (default: us-east-1)"
    echo "  DB_PASSWORD    Database password (required)"
    echo "  APP_KEY        Laravel application key (required)"
    echo ""
    echo "Examples:"
    echo "  $0 staging latest"
    echo "  $0 production v1.2.3"
    exit 1
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        exit 1
    fi
    
    # Check required environment variables
    if [[ -z "$DB_PASSWORD" ]]; then
        log_error "DB_PASSWORD environment variable is required"
        exit 1
    fi
    
    if [[ -z "$APP_KEY" ]]; then
        log_error "APP_KEY environment variable is required"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

get_account_id() {
    aws sts get-caller-identity --query Account --output text
}

get_ecr_registry() {
    echo "$(get_account_id).dkr.ecr.${AWS_REGION}.amazonaws.com"
}

create_ecr_repository() {
    local repository_name=$1
    
    log_info "Creating ECR repository: $repository_name"
    
    if aws ecr describe-repositories --repository-names "$repository_name" --region "$AWS_REGION" &> /dev/null; then
        log_info "ECR repository $repository_name already exists"
    else
        aws ecr create-repository \
            --repository-name "$repository_name" \
            --region "$AWS_REGION" \
            --image-scanning-configuration scanOnPush=true \
            --encryption-configuration encryptionType=AES256
        
        log_success "ECR repository $repository_name created"
    fi
}

deploy_infrastructure() {
    local environment=$1
    
    log_info "Deploying infrastructure for environment: $environment"
    
    # Deploy VPC and networking
    aws cloudformation deploy \
        --template-file "$PROJECT_ROOT/aws/cloudformation/ecs-infrastructure.yml" \
        --stack-name "$environment-laravel-infrastructure" \
        --parameter-overrides \
            Environment="$environment" \
            DBUsername="laravel" \
            DBPassword="$DB_PASSWORD" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$AWS_REGION" \
        --tags \
            Environment="$environment" \
            Project="laravel" \
            ManagedBy="CloudFormation"
    
    log_success "Infrastructure deployment completed"
}

deploy_services() {
    local environment=$1
    local image_tag=$2
    local ecr_registry=$(get_ecr_registry)
    local image_uri="$ecr_registry/$ECR_REPOSITORY:$image_tag"
    
    log_info "Deploying services for environment: $environment"
    log_info "Using image: $image_uri"
    
    # Deploy ECS services
    aws cloudformation deploy \
        --template-file "$PROJECT_ROOT/aws/cloudformation/ecs-services.yml" \
        --stack-name "$environment-laravel-services" \
        --parameter-overrides \
            Environment="$environment" \
            ImageURI="$image_uri" \
            DBPassword="$DB_PASSWORD" \
            AppKey="$APP_KEY" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$AWS_REGION" \
        --tags \
            Environment="$environment" \
            Project="laravel" \
            ManagedBy="CloudFormation"
    
    log_success "Services deployment completed"
}

run_migrations() {
    local environment=$1
    
    log_info "Running database migrations..."
    
    # Get cluster and task definition info
    local cluster_name=$(aws cloudformation describe-stacks \
        --stack-name "$environment-laravel-services" \
        --query 'Stacks[0].Outputs[?OutputKey==`ECSCluster`].OutputValue' \
        --output text \
        --region "$AWS_REGION")
    
    local task_definition=$(aws cloudformation describe-stacks \
        --stack-name "$environment-laravel-services" \
        --query 'Stacks[0].Outputs[?OutputKey==`TaskDefinition`].OutputValue' \
        --output text \
        --region "$AWS_REGION")
    
    # Get subnet and security group from infrastructure stack
    local private_subnets=$(aws cloudformation describe-stacks \
        --stack-name "$environment-laravel-infrastructure" \
        --query 'Stacks[0].Outputs[?OutputKey==`PrivateSubnets`].OutputValue' \
        --output text \
        --region "$AWS_REGION")
    
    local ecs_security_group=$(aws cloudformation describe-stacks \
        --stack-name "$environment-laravel-infrastructure" \
        --query 'Stacks[0].Outputs[?OutputKey==`ECSSecurityGroup`].OutputValue' \
        --output text \
        --region "$AWS_REGION")
    
    local subnet_id=$(echo "$private_subnets" | cut -d',' -f1)
    
    # Run migration task
    local task_arn=$(aws ecs run-task \
        --cluster "$cluster_name" \
        --task-definition "$task_definition" \
        --network-configuration "awsvpcConfiguration={subnets=[$subnet_id],securityGroups=[$ecs_security_group],assignPublicIp=DISABLED}" \
        --overrides '{
            "containerOverrides": [
                {
                    "name": "laravel-app",
                    "command": ["php", "artisan", "migrate", "--force"]
                }
            ]
        }' \
        --region "$AWS_REGION" \
        --query 'tasks[0].taskArn' \
        --output text)
    
    log_info "Migration task started: $task_arn"
    
    # Wait for task to complete
    aws ecs wait tasks-stopped \
        --cluster "$cluster_name" \
        --tasks "$task_arn" \
        --region "$AWS_REGION"
    
    # Check task exit code
    local exit_code=$(aws ecs describe-tasks \
        --cluster "$cluster_name" \
        --tasks "$task_arn" \
        --region "$AWS_REGION" \
        --query 'tasks[0].containers[0].exitCode' \
        --output text)
    
    if [[ "$exit_code" == "0" ]]; then
        log_success "Database migrations completed successfully"
    else
        log_error "Database migrations failed with exit code: $exit_code"
        exit 1
    fi
}

health_check() {
    local environment=$1
    
    log_info "Performing health check..."
    
    # Get ALB URL
    local alb_url=$(aws cloudformation describe-stacks \
        --stack-name "$environment-laravel-services" \
        --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerURL`].OutputValue' \
        --output text \
        --region "$AWS_REGION")
    
    log_info "Application URL: $alb_url"
    
    # Wait for ALB to be ready
    sleep 60
    
    # Health check with retry
    local max_attempts=10
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        log_info "Health check attempt $attempt/$max_attempts"
        
        if curl -f -s "$alb_url/health" > /dev/null; then
            log_success "Health check passed!"
            log_success "Application is available at: $alb_url"
            return 0
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            log_error "Health check failed after $max_attempts attempts"
            return 1
        fi
        
        log_warning "Health check failed, retrying in 30 seconds..."
        sleep 30
        ((attempt++))
    done
}

# Main script
main() {
    local environment=${1:-}
    local image_tag=${2:-latest}
    
    # Validate arguments
    if [[ -z "$environment" ]]; then
        log_error "Environment is required"
        show_usage
    fi
    
    if [[ "$environment" != "staging" && "$environment" != "production" ]]; then
        log_error "Environment must be 'staging' or 'production'"
        show_usage
    fi
    
    log_info "Starting deployment to $environment environment"
    log_info "Image tag: $image_tag"
    
    # Run deployment steps
    check_prerequisites
    create_ecr_repository "$ECR_REPOSITORY"
    deploy_infrastructure "$environment"
    deploy_services "$environment" "$image_tag"
    run_migrations "$environment"
    health_check "$environment"
    
    log_success "Deployment completed successfully!"
}

# Run main function with all arguments
main "$@"
