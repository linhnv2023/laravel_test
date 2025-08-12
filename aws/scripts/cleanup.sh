#!/bin/bash

# AWS Resources Cleanup Script
# Usage: ./cleanup.sh [environment]

set -e

# Configuration
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
    echo "Usage: $0 [environment]"
    echo ""
    echo "Arguments:"
    echo "  environment    Target environment to cleanup (staging|production|all)"
    echo ""
    echo "Environment Variables:"
    echo "  AWS_REGION     AWS region (default: us-east-1)"
    echo ""
    echo "Examples:"
    echo "  $0 staging     # Cleanup staging environment"
    echo "  $0 production  # Cleanup production environment"
    echo "  $0 all         # Cleanup all environments"
    exit 1
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

confirm_cleanup() {
    local environment=$1
    
    echo ""
    log_warning "⚠️  DANGER: This will delete AWS resources for environment: $environment"
    echo ""
    echo "This action will:"
    echo "  - Delete ECS services and tasks"
    echo "  - Delete Application Load Balancer"
    echo "  - Delete RDS database (if not protected)"
    echo "  - Delete ElastiCache cluster"
    echo "  - Delete CloudFormation stacks"
    echo "  - Delete VPC and networking resources"
    echo ""
    log_error "THIS ACTION CANNOT BE UNDONE!"
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
}

cleanup_ecs_services() {
    local environment=$1
    
    log_info "Cleaning up ECS services for environment: $environment"
    
    local stack_name="$environment-laravel-services"
    
    if aws cloudformation describe-stacks --stack-name "$stack_name" --region "$AWS_REGION" &> /dev/null; then
        # Scale down ECS service to 0 first
        local cluster_name=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --query 'Stacks[0].Outputs[?OutputKey==`ECSCluster`].OutputValue' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "")
        
        local service_name=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --query 'Stacks[0].Outputs[?OutputKey==`ECSService`].OutputValue' \
            --output text \
            --region "$AWS_REGION" 2>/dev/null || echo "")
        
        if [[ -n "$cluster_name" && -n "$service_name" ]]; then
            log_info "Scaling down ECS service to 0 tasks..."
            aws ecs update-service \
                --cluster "$cluster_name" \
                --service "$service_name" \
                --desired-count 0 \
                --region "$AWS_REGION" &> /dev/null || true
            
            # Wait for tasks to stop
            log_info "Waiting for tasks to stop..."
            aws ecs wait services-stable \
                --cluster "$cluster_name" \
                --services "$service_name" \
                --region "$AWS_REGION" || true
        fi
        
        # Delete CloudFormation stack
        log_info "Deleting services CloudFormation stack..."
        aws cloudformation delete-stack \
            --stack-name "$stack_name" \
            --region "$AWS_REGION"
        
        # Wait for stack deletion
        log_info "Waiting for services stack deletion to complete..."
        aws cloudformation wait stack-delete-complete \
            --stack-name "$stack_name" \
            --region "$AWS_REGION" || true
        
        log_success "ECS services cleanup completed"
    else
        log_warning "Services stack $stack_name not found"
    fi
}

cleanup_infrastructure() {
    local environment=$1
    
    log_info "Cleaning up infrastructure for environment: $environment"
    
    local stack_name="$environment-laravel-infrastructure"
    
    if aws cloudformation describe-stacks --stack-name "$stack_name" --region "$AWS_REGION" &> /dev/null; then
        # Delete CloudFormation stack
        log_info "Deleting infrastructure CloudFormation stack..."
        aws cloudformation delete-stack \
            --stack-name "$stack_name" \
            --region "$AWS_REGION"
        
        # Wait for stack deletion
        log_info "Waiting for infrastructure stack deletion to complete..."
        aws cloudformation wait stack-delete-complete \
            --stack-name "$stack_name" \
            --region "$AWS_REGION" || true
        
        log_success "Infrastructure cleanup completed"
    else
        log_warning "Infrastructure stack $stack_name not found"
    fi
}

cleanup_ecr_images() {
    local environment=$1
    
    log_info "Cleaning up ECR images for environment: $environment"
    
    if aws ecr describe-repositories --repository-names "$ECR_REPOSITORY" --region "$AWS_REGION" &> /dev/null; then
        # List and delete images with environment tags
        local image_tags=""
        
        if [[ "$environment" == "all" ]]; then
            # Get all image tags
            image_tags=$(aws ecr list-images \
                --repository-name "$ECR_REPOSITORY" \
                --region "$AWS_REGION" \
                --query 'imageIds[?imageTag!=null].imageTag' \
                --output text 2>/dev/null || echo "")
        else
            # Get images for specific environment
            image_tags=$(aws ecr list-images \
                --repository-name "$ECR_REPOSITORY" \
                --region "$AWS_REGION" \
                --query "imageIds[?contains(imageTag, '$environment')].imageTag" \
                --output text 2>/dev/null || echo "")
        fi
        
        if [[ -n "$image_tags" ]]; then
            log_info "Deleting ECR images: $image_tags"
            
            for tag in $image_tags; do
                aws ecr batch-delete-image \
                    --repository-name "$ECR_REPOSITORY" \
                    --region "$AWS_REGION" \
                    --image-ids imageTag="$tag" &> /dev/null || true
            done
            
            log_success "ECR images cleanup completed"
        else
            log_info "No ECR images found for environment: $environment"
        fi
    else
        log_warning "ECR repository $ECR_REPOSITORY not found"
    fi
}

cleanup_secrets() {
    local environment=$1
    
    log_info "Cleaning up Secrets Manager secrets for environment: $environment"
    
    # List and delete secrets for the environment
    local secrets=$(aws secretsmanager list-secrets \
        --region "$AWS_REGION" \
        --query "SecretList[?contains(Name, '$environment/laravel')].Name" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$secrets" ]]; then
        for secret in $secrets; do
            log_info "Deleting secret: $secret"
            aws secretsmanager delete-secret \
                --secret-id "$secret" \
                --force-delete-without-recovery \
                --region "$AWS_REGION" &> /dev/null || true
        done
        
        log_success "Secrets cleanup completed"
    else
        log_info "No secrets found for environment: $environment"
    fi
}

cleanup_log_groups() {
    local environment=$1
    
    log_info "Cleaning up CloudWatch log groups for environment: $environment"
    
    # List and delete log groups for the environment
    local log_groups=$(aws logs describe-log-groups \
        --region "$AWS_REGION" \
        --log-group-name-prefix "/ecs/$environment-laravel" \
        --query 'logGroups[].logGroupName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$log_groups" ]]; then
        for log_group in $log_groups; do
            log_info "Deleting log group: $log_group"
            aws logs delete-log-group \
                --log-group-name "$log_group" \
                --region "$AWS_REGION" &> /dev/null || true
        done
        
        log_success "Log groups cleanup completed"
    else
        log_info "No log groups found for environment: $environment"
    fi
}

cleanup_environment() {
    local environment=$1
    
    log_info "Starting cleanup for environment: $environment"
    
    # Cleanup in order (services first, then infrastructure)
    cleanup_ecs_services "$environment"
    cleanup_infrastructure "$environment"
    cleanup_ecr_images "$environment"
    cleanup_secrets "$environment"
    cleanup_log_groups "$environment"
    
    log_success "Cleanup completed for environment: $environment"
}

# Main script
main() {
    local environment=${1:-}
    
    # Validate arguments
    if [[ -z "$environment" ]]; then
        log_error "Environment is required"
        show_usage
    fi
    
    if [[ "$environment" != "staging" && "$environment" != "production" && "$environment" != "all" ]]; then
        log_error "Environment must be 'staging', 'production', or 'all'"
        show_usage
    fi
    
    log_info "Starting AWS resources cleanup"
    log_info "Environment: $environment"
    log_info "Region: $AWS_REGION"
    
    # Run cleanup steps
    check_prerequisites
    confirm_cleanup "$environment"
    
    if [[ "$environment" == "all" ]]; then
        cleanup_environment "staging"
        cleanup_environment "production"
        
        # Also cleanup ECR repository if cleaning all
        if aws ecr describe-repositories --repository-names "$ECR_REPOSITORY" --region "$AWS_REGION" &> /dev/null; then
            log_info "Deleting ECR repository: $ECR_REPOSITORY"
            aws ecr delete-repository \
                --repository-name "$ECR_REPOSITORY" \
                --force \
                --region "$AWS_REGION" || true
        fi
    else
        cleanup_environment "$environment"
    fi
    
    log_success "All cleanup operations completed successfully!"
}

# Run main function with all arguments
main "$@"
