#!/bin/bash

# ECR Repository Setup Script
# Usage: ./setup-ecr.sh [repository_name]

set -e

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
REPOSITORY_NAME="${1:-laravel-app}"

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
    echo "Usage: $0 [repository_name]"
    echo ""
    echo "Arguments:"
    echo "  repository_name    ECR repository name (default: laravel-app)"
    echo ""
    echo "Environment Variables:"
    echo "  AWS_REGION         AWS region (default: us-east-1)"
    echo ""
    echo "Examples:"
    echo "  $0 laravel-app"
    echo "  AWS_REGION=eu-west-1 $0 my-laravel-app"
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

get_account_id() {
    aws sts get-caller-identity --query Account --output text
}

create_ecr_repository() {
    local repository_name=$1
    
    log_info "Creating ECR repository: $repository_name in region: $AWS_REGION"
    
    if aws ecr describe-repositories --repository-names "$repository_name" --region "$AWS_REGION" &> /dev/null; then
        log_warning "ECR repository $repository_name already exists"
        return 0
    fi
    
    # Create repository
    aws ecr create-repository \
        --repository-name "$repository_name" \
        --region "$AWS_REGION" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256 \
        --tags Key=Project,Value=Laravel Key=ManagedBy,Value=Script
    
    log_success "ECR repository $repository_name created successfully"
}

setup_lifecycle_policy() {
    local repository_name=$1
    
    log_info "Setting up lifecycle policy for repository: $repository_name"
    
    # Create lifecycle policy JSON
    cat > /tmp/lifecycle-policy.json << EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep last 10 production images",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["v", "prod"],
                "countType": "imageCountMoreThan",
                "countNumber": 10
            },
            "action": {
                "type": "expire"
            }
        },
        {
            "rulePriority": 2,
            "description": "Keep last 5 staging images",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["staging", "develop"],
                "countType": "imageCountMoreThan",
                "countNumber": 5
            },
            "action": {
                "type": "expire"
            }
        },
        {
            "rulePriority": 3,
            "description": "Keep last 3 latest images",
            "selection": {
                "tagStatus": "tagged",
                "tagPrefixList": ["latest"],
                "countType": "imageCountMoreThan",
                "countNumber": 3
            },
            "action": {
                "type": "expire"
            }
        },
        {
            "rulePriority": 4,
            "description": "Delete untagged images older than 1 day",
            "selection": {
                "tagStatus": "untagged",
                "countType": "sinceImagePushed",
                "countUnit": "days",
                "countNumber": 1
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
    
    # Apply lifecycle policy
    aws ecr put-lifecycle-policy \
        --repository-name "$repository_name" \
        --region "$AWS_REGION" \
        --lifecycle-policy-text file:///tmp/lifecycle-policy.json
    
    # Clean up
    rm -f /tmp/lifecycle-policy.json
    
    log_success "Lifecycle policy applied successfully"
}

setup_repository_policy() {
    local repository_name=$1
    local account_id=$(get_account_id)
    
    log_info "Setting up repository policy for: $repository_name"
    
    # Create repository policy JSON
    cat > /tmp/repository-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowPushPull",
            "Effect": "Allow",
            "Principal": {
                "AWS": [
                    "arn:aws:iam::${account_id}:root"
                ]
            },
            "Action": [
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:BatchCheckLayerAvailability",
                "ecr:PutImage",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload"
            ]
        }
    ]
}
EOF
    
    # Apply repository policy
    aws ecr set-repository-policy \
        --repository-name "$repository_name" \
        --region "$AWS_REGION" \
        --policy-text file:///tmp/repository-policy.json
    
    # Clean up
    rm -f /tmp/repository-policy.json
    
    log_success "Repository policy applied successfully"
}

get_login_command() {
    local repository_name=$1
    local account_id=$(get_account_id)
    local registry_url="${account_id}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    
    log_info "ECR repository setup completed!"
    echo ""
    echo "Repository Details:"
    echo "  Name: $repository_name"
    echo "  Region: $AWS_REGION"
    echo "  Registry URL: $registry_url"
    echo "  Repository URI: $registry_url/$repository_name"
    echo ""
    echo "To login to ECR, run:"
    echo "  aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $registry_url"
    echo ""
    echo "To build and push your image:"
    echo "  docker build -t $repository_name ."
    echo "  docker tag $repository_name:latest $registry_url/$repository_name:latest"
    echo "  docker push $registry_url/$repository_name:latest"
}

# Main script
main() {
    local repository_name=${1:-$REPOSITORY_NAME}
    
    if [[ -z "$repository_name" ]]; then
        log_error "Repository name is required"
        show_usage
    fi
    
    log_info "Setting up ECR repository: $repository_name"
    
    # Run setup steps
    check_prerequisites
    create_ecr_repository "$repository_name"
    setup_lifecycle_policy "$repository_name"
    setup_repository_policy "$repository_name"
    get_login_command "$repository_name"
    
    log_success "ECR setup completed successfully!"
}

# Run main function with all arguments
main "$@"
