#!/bin/bash

# CI/CD Pipeline Testing Script
# Usage: ./test-pipeline.sh [component]

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWS_REGION="${AWS_REGION:-us-east-1}"

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
    echo "CI/CD Pipeline Testing Script"
    echo "============================="
    echo ""
    echo "Usage: $0 [component]"
    echo ""
    echo "Components:"
    echo "  all          Test all components (default)"
    echo "  docker       Test Docker configuration"
    echo "  laravel      Test Laravel application"
    echo "  aws          Test AWS configuration"
    echo "  github       Test GitHub Actions workflows"
    echo "  jenkins      Test Jenkins configuration"
    echo ""
    echo "Examples:"
    echo "  $0           # Test all components"
    echo "  $0 docker    # Test only Docker"
    echo "  $0 laravel   # Test only Laravel"
    exit 1
}

test_docker() {
    log_info "Testing Docker configuration..."
    
    local errors=0
    
    # Check if Docker is running
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        ((errors++))
    else
        log_success "Docker daemon is running"
    fi
    
    # Check Dockerfile
    if [[ ! -f "$SCRIPT_DIR/Dockerfile" ]]; then
        log_error "Dockerfile not found"
        ((errors++))
    else
        log_success "Dockerfile found"
        
        # Validate Dockerfile syntax
        if docker build -t test-build --target development "$SCRIPT_DIR" &> /dev/null; then
            log_success "Dockerfile builds successfully"
            docker rmi test-build &> /dev/null || true
        else
            log_error "Dockerfile build failed"
            ((errors++))
        fi
    fi
    
    # Check docker-compose files
    local compose_files=("docker-compose.yml" "docker-compose.prod.yml")
    for file in "${compose_files[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$file" ]]; then
            log_error "$file not found"
            ((errors++))
        else
            log_success "$file found"
            
            # Validate docker-compose syntax
            if docker-compose -f "$SCRIPT_DIR/$file" config &> /dev/null; then
                log_success "$file syntax is valid"
            else
                log_error "$file syntax is invalid"
                ((errors++))
            fi
        fi
    done
    
    # Check Docker configuration files
    local docker_configs=(
        "docker/nginx/nginx.conf"
        "docker/nginx/default.conf"
        "docker/php/php.ini"
        "docker/php/php-fpm.conf"
        "docker/mysql/my.cnf"
        "docker/redis/redis.conf"
        "docker/supervisor/supervisord.conf"
    )
    
    for config in "${docker_configs[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$config" ]]; then
            log_error "$config not found"
            ((errors++))
        else
            log_success "$config found"
        fi
    done
    
    # Check .dockerignore
    if [[ ! -f "$SCRIPT_DIR/.dockerignore" ]]; then
        log_warning ".dockerignore not found (recommended)"
    else
        log_success ".dockerignore found"
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "Docker configuration test passed"
        return 0
    else
        log_error "Docker configuration test failed with $errors errors"
        return 1
    fi
}

test_laravel() {
    log_info "Testing Laravel application..."
    
    local errors=0
    
    # Check Laravel files
    local laravel_files=(
        "artisan"
        "composer.json"
        "composer.lock"
        "package.json"
        "app/Http/Kernel.php"
        "config/app.php"
        "routes/web.php"
        "database/migrations"
        "tests"
    )
    
    for file in "${laravel_files[@]}"; do
        if [[ ! -e "$SCRIPT_DIR/$file" ]]; then
            log_error "Laravel file/directory not found: $file"
            ((errors++))
        else
            log_success "Laravel file/directory found: $file"
        fi
    done
    
    # Check environment files
    if [[ ! -f "$SCRIPT_DIR/.env.example" ]]; then
        log_error ".env.example not found"
        ((errors++))
    else
        log_success ".env.example found"
    fi
    
    if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
        log_warning ".env not found (copy from .env.example)"
    else
        log_success ".env found"
        
        # Check required environment variables
        local required_vars=("APP_KEY" "DB_CONNECTION" "DB_HOST" "DB_DATABASE")
        for var in "${required_vars[@]}"; do
            if grep -q "^${var}=" "$SCRIPT_DIR/.env"; then
                log_success "Environment variable $var is set"
            else
                log_error "Environment variable $var is not set"
                ((errors++))
            fi
        done
    fi
    
    # Check if composer dependencies are installed
    if [[ ! -d "$SCRIPT_DIR/vendor" ]]; then
        log_warning "Composer dependencies not installed (run: composer install)"
    else
        log_success "Composer dependencies installed"
    fi
    
    # Check if npm dependencies are installed
    if [[ ! -d "$SCRIPT_DIR/node_modules" ]]; then
        log_warning "NPM dependencies not installed (run: npm install)"
    else
        log_success "NPM dependencies installed"
    fi
    
    # Test Laravel commands (if dependencies are installed)
    if [[ -d "$SCRIPT_DIR/vendor" ]]; then
        if php "$SCRIPT_DIR/artisan" --version &> /dev/null; then
            log_success "Laravel artisan command works"
        else
            log_error "Laravel artisan command failed"
            ((errors++))
        fi
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "Laravel application test passed"
        return 0
    else
        log_error "Laravel application test failed with $errors errors"
        return 1
    fi
}

test_aws() {
    log_info "Testing AWS configuration..."
    
    local errors=0
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI not installed"
        ((errors++))
    else
        log_success "AWS CLI installed"
        
        # Check AWS credentials
        if aws sts get-caller-identity &> /dev/null; then
            log_success "AWS credentials configured"
        else
            log_error "AWS credentials not configured"
            ((errors++))
        fi
    fi
    
    # Check CloudFormation templates
    local cf_templates=(
        "aws/cloudformation/ecs-infrastructure.yml"
        "aws/cloudformation/ecs-services.yml"
    )
    
    for template in "${cf_templates[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$template" ]]; then
            log_error "CloudFormation template not found: $template"
            ((errors++))
        else
            log_success "CloudFormation template found: $template"
            
            # Validate CloudFormation template
            if aws cloudformation validate-template --template-body "file://$SCRIPT_DIR/$template" &> /dev/null; then
                log_success "CloudFormation template is valid: $template"
            else
                log_error "CloudFormation template is invalid: $template"
                ((errors++))
            fi
        fi
    done
    
    # Check AWS scripts
    local aws_scripts=(
        "aws/scripts/deploy.sh"
        "aws/scripts/setup-ecr.sh"
        "aws/scripts/cleanup.sh"
    )
    
    for script in "${aws_scripts[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
            log_error "AWS script not found: $script"
            ((errors++))
        elif [[ ! -x "$SCRIPT_DIR/$script" ]]; then
            log_error "AWS script not executable: $script"
            ((errors++))
        else
            log_success "AWS script found and executable: $script"
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        log_success "AWS configuration test passed"
        return 0
    else
        log_error "AWS configuration test failed with $errors errors"
        return 1
    fi
}

test_github() {
    log_info "Testing GitHub Actions configuration..."
    
    local errors=0
    
    # Check GitHub workflows directory
    if [[ ! -d "$SCRIPT_DIR/.github/workflows" ]]; then
        log_error ".github/workflows directory not found"
        ((errors++))
    else
        log_success ".github/workflows directory found"
        
        # Check workflow files
        local workflows=(
            ".github/workflows/ci.yml"
            ".github/workflows/cd.yml"
            ".github/workflows/docker.yml"
        )
        
        for workflow in "${workflows[@]}"; do
            if [[ ! -f "$SCRIPT_DIR/$workflow" ]]; then
                log_error "GitHub workflow not found: $workflow"
                ((errors++))
            else
                log_success "GitHub workflow found: $workflow"
                
                # Basic YAML syntax check
                if command -v yq &> /dev/null; then
                    if yq eval . "$SCRIPT_DIR/$workflow" &> /dev/null; then
                        log_success "GitHub workflow YAML is valid: $workflow"
                    else
                        log_error "GitHub workflow YAML is invalid: $workflow"
                        ((errors++))
                    fi
                elif python3 -c "import yaml" &> /dev/null; then
                    if python3 -c "import yaml; yaml.safe_load(open('$SCRIPT_DIR/$workflow'))" &> /dev/null; then
                        log_success "GitHub workflow YAML is valid: $workflow"
                    else
                        log_error "GitHub workflow YAML is invalid: $workflow"
                        ((errors++))
                    fi
                else
                    log_warning "Cannot validate YAML syntax (install yq or python3-yaml)"
                fi
            fi
        done
    fi
    
    # Check if we're in a git repository
    if [[ ! -d "$SCRIPT_DIR/.git" ]]; then
        log_warning "Not in a git repository"
    else
        log_success "Git repository detected"
        
        # Check for GitHub remote
        if git remote get-url origin &> /dev/null; then
            local remote_url=$(git remote get-url origin)
            if [[ "$remote_url" == *"github.com"* ]]; then
                log_success "GitHub remote configured"
            else
                log_warning "Remote is not GitHub: $remote_url"
            fi
        else
            log_warning "No git remote configured"
        fi
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "GitHub Actions configuration test passed"
        return 0
    else
        log_error "GitHub Actions configuration test failed with $errors errors"
        return 1
    fi
}

test_jenkins() {
    log_info "Testing Jenkins configuration..."
    
    local errors=0
    
    # Check Jenkinsfile
    if [[ ! -f "$SCRIPT_DIR/Jenkinsfile" ]]; then
        log_error "Jenkinsfile not found"
        ((errors++))
    else
        log_success "Jenkinsfile found"
    fi
    
    # Check rollback Jenkinsfile
    if [[ ! -f "$SCRIPT_DIR/Jenkinsfile.rollback" ]]; then
        log_error "Jenkinsfile.rollback not found"
        ((errors++))
    else
        log_success "Jenkinsfile.rollback found"
    fi
    
    # Check Jenkins URL (if provided)
    if [[ -n "$JENKINS_URL" ]]; then
        log_info "Testing Jenkins connectivity..."
        if curl -f -s "$JENKINS_URL" &> /dev/null; then
            log_success "Jenkins server is accessible"
        else
            log_warning "Jenkins server is not accessible (check URL and network)"
        fi
    else
        log_info "JENKINS_URL not set, skipping connectivity test"
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "Jenkins configuration test passed"
        return 0
    else
        log_error "Jenkins configuration test failed with $errors errors"
        return 1
    fi
}

run_all_tests() {
    log_info "Running all CI/CD pipeline tests..."
    
    local total_errors=0
    
    # Run all tests
    test_docker || ((total_errors++))
    echo ""
    
    test_laravel || ((total_errors++))
    echo ""
    
    test_aws || ((total_errors++))
    echo ""
    
    test_github || ((total_errors++))
    echo ""
    
    test_jenkins || ((total_errors++))
    echo ""
    
    # Summary
    if [[ $total_errors -eq 0 ]]; then
        log_success "All CI/CD pipeline tests passed! ✅"
        echo ""
        echo "Your pipeline is ready for deployment!"
        echo "Next steps:"
        echo "1. Push code to GitHub to trigger CI/CD workflows"
        echo "2. Configure GitHub repository secrets"
        echo "3. Deploy to staging: ./aws/scripts/deploy.sh staging latest"
        return 0
    else
        log_error "CI/CD pipeline tests failed with $total_errors component(s) having errors ❌"
        echo ""
        echo "Please fix the errors above before proceeding with deployment."
        return 1
    fi
}

# Main script
main() {
    local component=${1:-all}
    
    # Show usage if help requested
    if [[ "$component" == "-h" || "$component" == "--help" ]]; then
        show_usage
    fi
    
    echo "CI/CD Pipeline Testing"
    echo "====================="
    echo ""
    
    case "$component" in
        "all")
            run_all_tests
            ;;
        "docker")
            test_docker
            ;;
        "laravel")
            test_laravel
            ;;
        "aws")
            test_aws
            ;;
        "github")
            test_github
            ;;
        "jenkins")
            test_jenkins
            ;;
        *)
            log_error "Unknown component: $component"
            show_usage
            ;;
    esac
}

# Run main function with all arguments
main "$@"
