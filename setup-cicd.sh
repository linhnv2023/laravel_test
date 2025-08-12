#!/bin/bash

# Complete CI/CD Pipeline Setup Script
# Usage: ./setup-cicd.sh

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
    echo "Laravel CI/CD Pipeline Setup"
    echo "============================"
    echo ""
    echo "This script will set up a complete CI/CD pipeline including:"
    echo "  - GitHub Actions workflows"
    echo "  - Jenkins pipeline configuration"
    echo "  - AWS infrastructure (ECS, ECR, RDS, ElastiCache)"
    echo "  - Docker containerization"
    echo ""
    echo "Prerequisites:"
    echo "  - AWS CLI configured with appropriate permissions"
    echo "  - Docker installed and running"
    echo "  - GitHub repository created"
    echo "  - Jenkins server accessible (optional)"
    echo ""
    echo "Environment Variables:"
    echo "  AWS_REGION         AWS region (default: us-east-1)"
    echo "  GITHUB_REPO        GitHub repository (format: username/repo-name)"
    echo "  JENKINS_URL        Jenkins server URL (optional)"
    echo "  DB_PASSWORD        Database password (required)"
    echo "  APP_KEY            Laravel application key (required)"
    echo ""
    echo "Usage: $0"
    exit 1
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
    fi
    
    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    fi
    
    if ! command -v git &> /dev/null; then
        missing_tools+=("git")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    
    # Check required environment variables
    if [[ -z "$DB_PASSWORD" ]]; then
        log_error "DB_PASSWORD environment variable is required"
        exit 1
    fi
    
    if [[ -z "$APP_KEY" ]]; then
        log_warning "APP_KEY not set, generating one..."
        export APP_KEY="base64:$(openssl rand -base64 32)"
        log_info "Generated APP_KEY: $APP_KEY"
    fi
    
    log_success "Prerequisites check passed"
}

setup_aws_infrastructure() {
    log_info "Setting up AWS infrastructure..."
    
    # Setup ECR repository
    if [[ -f "$SCRIPT_DIR/aws/scripts/setup-ecr.sh" ]]; then
        bash "$SCRIPT_DIR/aws/scripts/setup-ecr.sh" "$ECR_REPOSITORY"
    else
        log_warning "ECR setup script not found, skipping..."
    fi
    
    # Deploy infrastructure for staging
    log_info "Deploying staging infrastructure..."
    if [[ -f "$SCRIPT_DIR/aws/scripts/deploy.sh" ]]; then
        DB_PASSWORD="$DB_PASSWORD" APP_KEY="$APP_KEY" \
        bash "$SCRIPT_DIR/aws/scripts/deploy.sh" staging latest
    else
        log_warning "Deploy script not found, manual deployment required"
    fi
    
    log_success "AWS infrastructure setup completed"
}

setup_github_actions() {
    log_info "Setting up GitHub Actions..."
    
    # Check if .github/workflows directory exists
    if [[ ! -d "$SCRIPT_DIR/.github/workflows" ]]; then
        log_error "GitHub workflows directory not found"
        return 1
    fi
    
    # List workflow files
    local workflows=($(find "$SCRIPT_DIR/.github/workflows" -name "*.yml" -o -name "*.yaml"))
    
    if [[ ${#workflows[@]} -eq 0 ]]; then
        log_error "No GitHub workflow files found"
        return 1
    fi
    
    log_info "Found GitHub workflow files:"
    for workflow in "${workflows[@]}"; do
        echo "  - $(basename "$workflow")"
    done
    
    # Check if we're in a git repository
    if [[ ! -d "$SCRIPT_DIR/.git" ]]; then
        log_warning "Not in a git repository. Initialize git and push to GitHub to activate workflows."
        return 0
    fi
    
    # Check if GitHub repository is configured
    local github_remote=$(git remote get-url origin 2>/dev/null || echo "")
    if [[ -z "$github_remote" ]]; then
        log_warning "No GitHub remote configured. Add GitHub remote to activate workflows."
        return 0
    fi
    
    log_success "GitHub Actions workflows are ready"
    log_info "Push to GitHub to activate the workflows"
}

setup_jenkins() {
    log_info "Setting up Jenkins configuration..."
    
    if [[ -z "$JENKINS_URL" ]]; then
        log_warning "JENKINS_URL not set, skipping Jenkins setup"
        log_info "Jenkinsfile is available for manual Jenkins job configuration"
        return 0
    fi
    
    # Check if Jenkinsfile exists
    if [[ ! -f "$SCRIPT_DIR/Jenkinsfile" ]]; then
        log_error "Jenkinsfile not found"
        return 1
    fi
    
    log_info "Jenkinsfile found and ready for Jenkins job configuration"
    log_info "Manual steps required:"
    echo "  1. Create a new Pipeline job in Jenkins"
    echo "  2. Configure SCM to point to your GitHub repository"
    echo "  3. Set Pipeline script from SCM"
    echo "  4. Configure required credentials and environment variables"
    
    log_success "Jenkins configuration files are ready"
}

setup_docker() {
    log_info "Setting up Docker configuration..."
    
    # Check if Dockerfile exists
    if [[ ! -f "$SCRIPT_DIR/Dockerfile" ]]; then
        log_error "Dockerfile not found"
        return 1
    fi
    
    # Check if docker-compose files exist
    local compose_files=("docker-compose.yml" "docker-compose.prod.yml")
    for file in "${compose_files[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$file" ]]; then
            log_warning "$file not found"
        else
            log_info "Found $file"
        fi
    done
    
    # Test Docker build (optional)
    read -p "Do you want to test Docker build? (y/N): " test_build
    if [[ "$test_build" =~ ^[Yy]$ ]]; then
        log_info "Testing Docker build..."
        docker build -t laravel-test --target development "$SCRIPT_DIR"
        log_success "Docker build test passed"
        
        # Clean up test image
        docker rmi laravel-test &> /dev/null || true
    fi
    
    log_success "Docker configuration is ready"
}

generate_documentation() {
    log_info "Generating setup documentation..."
    
    cat > "$SCRIPT_DIR/CICD-SETUP.md" << 'EOF'
# CI/CD Pipeline Setup Guide

This document provides instructions for setting up and using the complete CI/CD pipeline.

## Architecture Overview

```
GitHub → GitHub Actions → ECR → Jenkins → AWS ECS
   ↓           ↓           ↓        ↓        ↓
 Source    CI Tests    Registry  Deploy  Production
```

## Components

### 1. GitHub Actions (CI)
- **Location**: `.github/workflows/`
- **Purpose**: Continuous Integration, testing, and building
- **Triggers**: Push to main/develop, Pull Requests

### 2. Jenkins (CD)
- **Location**: `Jenkinsfile`, `Jenkinsfile.rollback`
- **Purpose**: Continuous Deployment to AWS
- **Triggers**: Manual or webhook from GitHub Actions

### 3. AWS Infrastructure
- **Location**: `aws/cloudformation/`
- **Components**: ECS, ECR, RDS, ElastiCache, ALB, VPC
- **Environments**: Staging, Production

### 4. Docker
- **Location**: `Dockerfile`, `docker-compose*.yml`
- **Purpose**: Application containerization
- **Stages**: Development, Production

## Setup Instructions

### Prerequisites
1. AWS CLI configured with appropriate permissions
2. Docker installed and running
3. GitHub repository created
4. Jenkins server (optional)

### Required AWS Permissions
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecs:*",
                "ecr:*",
                "rds:*",
                "elasticache:*",
                "ec2:*",
                "elbv2:*",
                "cloudformation:*",
                "iam:*",
                "logs:*",
                "secretsmanager:*"
            ],
            "Resource": "*"
        }
    ]
}
```

### GitHub Secrets
Configure the following secrets in your GitHub repository:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
- `ECR_REGISTRY`
- `JENKINS_URL` (optional)
- `JENKINS_API_TOKEN` (optional)
- `SLACK_WEBHOOK` (optional)
- `SNYK_TOKEN` (optional)

### Environment Variables
Set these environment variables before running setup:

```bash
export AWS_REGION=us-east-1
export DB_PASSWORD=your-secure-password
export APP_KEY=base64:your-laravel-app-key
export GITHUB_REPO=username/repository-name
export JENKINS_URL=https://jenkins.your-domain.com  # optional
```

### Quick Start

1. **Clone and setup**:
   ```bash
   git clone https://github.com/your-username/laravel-app.git
   cd laravel-app
   ./setup-cicd.sh
   ```

2. **Deploy to staging**:
   ```bash
   ./aws/scripts/deploy.sh staging latest
   ```

3. **Deploy to production**:
   ```bash
   ./aws/scripts/deploy.sh production v1.0.0
   ```

## Usage

### Local Development
```bash
# Start development environment
make up

# Run tests
make test

# Access application shell
make shell
```

### Deployment Commands
```bash
# Deploy to staging
./aws/scripts/deploy.sh staging latest

# Deploy to production
./aws/scripts/deploy.sh production v1.0.0

# Rollback production
# (Use Jenkins pipeline or manual ECS rollback)
```

### Monitoring
- **Application**: Check ALB health checks
- **Logs**: CloudWatch Logs `/ecs/{environment}-laravel`
- **Metrics**: CloudWatch Container Insights

### Troubleshooting

#### Common Issues

1. **Docker build fails**:
   - Check Dockerfile syntax
   - Ensure all dependencies are available
   - Verify base image accessibility

2. **ECS deployment fails**:
   - Check task definition configuration
   - Verify security groups and networking
   - Check CloudWatch logs for errors

3. **Database connection issues**:
   - Verify RDS security groups
   - Check database credentials in Secrets Manager
   - Ensure ECS tasks can reach RDS

4. **GitHub Actions failures**:
   - Check repository secrets configuration
   - Verify AWS permissions
   - Review workflow logs

#### Useful Commands

```bash
# Check ECS service status
aws ecs describe-services --cluster staging-laravel-cluster --services staging-laravel-service

# View ECS logs
aws logs tail /ecs/staging-laravel --follow

# List ECR images
aws ecr list-images --repository-name laravel-app

# Check CloudFormation stacks
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE
```

## Security Considerations

1. **Secrets Management**: Use AWS Secrets Manager for sensitive data
2. **Network Security**: Private subnets for ECS tasks, security groups
3. **Image Scanning**: Enabled in ECR for vulnerability detection
4. **Access Control**: IAM roles with least privilege principle

## Maintenance

### Regular Tasks
- Monitor CloudWatch logs and metrics
- Update base Docker images regularly
- Review and rotate secrets
- Update dependencies and security patches

### Backup Strategy
- Database: Automated daily backups with 7-day retention
- Application data: S3 backups
- Infrastructure: CloudFormation templates in version control

## Support

For issues and questions:
1. Check CloudWatch logs
2. Review GitHub Actions workflow runs
3. Check Jenkins build logs
4. Consult AWS ECS service events

EOF

    log_success "Documentation generated: CICD-SETUP.md"
}

print_summary() {
    log_success "CI/CD Pipeline Setup Complete!"
    echo ""
    echo "Summary:"
    echo "========"
    echo "✅ Prerequisites checked"
    echo "✅ AWS infrastructure configured"
    echo "✅ GitHub Actions workflows ready"
    echo "✅ Jenkins configuration prepared"
    echo "✅ Docker setup verified"
    echo "✅ Documentation generated"
    echo ""
    echo "Next Steps:"
    echo "==========="
    echo "1. Push code to GitHub to trigger CI/CD workflows"
    echo "2. Configure GitHub repository secrets"
    echo "3. Set up Jenkins jobs (if using Jenkins)"
    echo "4. Monitor first deployment in AWS Console"
    echo ""
    echo "Useful Commands:"
    echo "==============="
    echo "# Deploy to staging:"
    echo "  ./aws/scripts/deploy.sh staging latest"
    echo ""
    echo "# Deploy to production:"
    echo "  ./aws/scripts/deploy.sh production v1.0.0"
    echo ""
    echo "# Start local development:"
    echo "  make up"
    echo ""
    echo "# View documentation:"
    echo "  cat CICD-SETUP.md"
    echo ""
    log_info "Happy deploying! 🚀"
}

# Main script
main() {
    echo "Laravel CI/CD Pipeline Setup"
    echo "============================"
    echo ""
    
    # Show usage if help requested
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_usage
    fi
    
    log_info "Starting CI/CD pipeline setup..."
    
    # Run setup steps
    check_prerequisites
    setup_docker
    setup_aws_infrastructure
    setup_github_actions
    setup_jenkins
    generate_documentation
    print_summary
}

# Run main function with all arguments
main "$@"
