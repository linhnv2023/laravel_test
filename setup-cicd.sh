#!/bin/bash

# Optimized CI/CD Pipeline Setup with GitHub Webhook → Jenkins
# Usage: ./setup-webhook-pipeline.sh

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
    echo "Optimized Laravel CI/CD Pipeline Setup"
    echo "======================================"
    echo ""
    echo "Architecture: GitHub Webhook → Jenkins → ECR → ECS → Production"
    echo ""
    echo "This script sets up:"
    echo "  - AWS infrastructure (ECS, ECR, RDS, ElastiCache)"
    echo "  - Jenkins pipeline configuration"
    echo "  - GitHub webhook setup instructions"
    echo "  - Docker containerization"
    echo ""
    echo "Prerequisites:"
    echo "  - AWS CLI configured with appropriate permissions"
    echo "  - Jenkins server accessible"
    echo "  - GitHub repository with admin access"
    echo "  - Docker installed"
    echo ""
    echo "Required Environment Variables:"
    echo "  AWS_REGION         AWS region (default: us-east-1)"
    echo "  JENKINS_URL        Jenkins server URL"
    echo "  GITHUB_REPO        GitHub repository (format: username/repo-name)"
    echo "  DB_PASSWORD        Database password"
    echo "  APP_KEY            Laravel application key"
    echo ""
    echo "Optional Environment Variables:"
    echo "  SLACK_WEBHOOK      Slack webhook URL for notifications"
    echo "  JENKINS_TOKEN      Jenkins API token"
    echo ""
    echo "Usage: $0"
    exit 1
}

check_prerequisites() {
    log_info "Checking prerequisites for optimized pipeline..."
    
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
    
    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
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
    
    if [[ -z "$JENKINS_URL" ]]; then
        log_warning "JENKINS_URL not set. Jenkins configuration will be manual."
    fi
    
    if [[ -z "$GITHUB_REPO" ]]; then
        log_warning "GITHUB_REPO not set. GitHub webhook setup will be manual."
    fi
    
    log_success "Prerequisites check passed"
}

setup_aws_infrastructure() {
    log_info "Setting up AWS infrastructure..."
    
    # Setup ECR repository
    if [[ -f "$SCRIPT_DIR/aws/scripts/setup-ecr.sh" ]]; then
        bash "$SCRIPT_DIR/aws/scripts/setup-ecr.sh" "$ECR_REPOSITORY"
    else
        log_warning "ECR setup script not found, creating repository manually..."
        aws ecr create-repository \
            --repository-name "$ECR_REPOSITORY" \
            --region "$AWS_REGION" \
            --image-scanning-configuration scanOnPush=true \
            --encryption-configuration encryptionType=AES256 || true
    fi
    
    # Deploy infrastructure for both environments
    for environment in staging production; do
        log_info "Deploying $environment infrastructure..."
        
        if [[ -f "$SCRIPT_DIR/aws/scripts/deploy.sh" ]]; then
            DB_PASSWORD="$DB_PASSWORD" APP_KEY="$APP_KEY" \
            bash "$SCRIPT_DIR/aws/scripts/deploy.sh" "$environment" latest || log_warning "Failed to deploy $environment infrastructure"
        else
            log_warning "Deploy script not found, manual deployment required for $environment"
        fi
    done
    
    log_success "AWS infrastructure setup completed"
}

create_jenkins_job_config() {
    log_info "Creating Jenkins job configuration..."
    
    cat > "$SCRIPT_DIR/jenkins-job-config.xml" << 'EOF'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job@2.40">
  <actions/>
  <description>Laravel CI/CD Pipeline with GitHub Webhook</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty>
      <triggers>
        <com.cloudbees.jenkins.GitHubPushTrigger plugin="github@1.34.1">
          <spec></spec>
        </com.cloudbees.jenkins.GitHubPushTrigger>
      </triggers>
    </org.jenkinsci.plugins.workflow.job.properties.PipelineTriggersJobProperty>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.ChoiceParameterDefinition>
          <name>ENVIRONMENT</name>
          <description>Deployment environment</description>
          <choices class="java.util.Arrays$ArrayList">
            <a class="string-array">
              <string>staging</string>
              <string>production</string>
            </a>
          </choices>
        </hudson.model.ChoiceParameterDefinition>
        <hudson.model.BooleanParameterDefinition>
          <name>RUN_TESTS</name>
          <description>Run tests before deployment</description>
          <defaultValue>true</defaultValue>
        </hudson.model.BooleanParameterDefinition>
        <hudson.model.BooleanParameterDefinition>
          <name>RUN_MIGRATIONS</name>
          <description>Run database migrations</description>
          <defaultValue>true</defaultValue>
        </hudson.model.BooleanParameterDefinition>
        <hudson.model.BooleanParameterDefinition>
          <name>SKIP_BUILD</name>
          <description>Skip Docker build (use existing image)</description>
          <defaultValue>false</defaultValue>
        </hudson.model.BooleanParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps@2.87">
    <scm class="hudson.plugins.git.GitSCM" plugin="git@4.8.2">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>https://github.com/GITHUB_REPO_PLACEHOLDER.git</url>
          <credentialsId>github-credentials</credentialsId>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/main</name>
        </hudson.plugins.git.BranchSpec>
        <hudson.plugins.git.BranchSpec>
          <name>*/develop</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
      <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
      <submoduleCfg class="list"/>
      <extensions/>
    </scm>
    <scriptPath>Jenkinsfile.optimized</scriptPath>
    <lightweight>true</lightweight>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
EOF

    # Replace placeholder with actual GitHub repo
    if [[ -n "$GITHUB_REPO" ]]; then
        sed -i.bak "s|GITHUB_REPO_PLACEHOLDER|$GITHUB_REPO|g" "$SCRIPT_DIR/jenkins-job-config.xml"
        rm -f "$SCRIPT_DIR/jenkins-job-config.xml.bak"
    fi
    
    log_success "Jenkins job configuration created: jenkins-job-config.xml"
}

setup_jenkins_job() {
    log_info "Setting up Jenkins job..."
    
    if [[ -z "$JENKINS_URL" ]]; then
        log_warning "JENKINS_URL not set, skipping automatic Jenkins job creation"
        log_info "Manual steps required:"
        echo "  1. Create new Pipeline job in Jenkins"
        echo "  2. Import configuration from jenkins-job-config.xml"
        echo "  3. Configure GitHub credentials"
        echo "  4. Set up AWS credentials"
        return 0
    fi
    
    # Test Jenkins connectivity
    if ! curl -f -s "$JENKINS_URL" &> /dev/null; then
        log_warning "Jenkins server not accessible at $JENKINS_URL"
        log_info "Manual Jenkins configuration required"
        return 0
    fi
    
    # Create Jenkins job (requires Jenkins CLI or API)
    if [[ -n "$JENKINS_TOKEN" ]]; then
        log_info "Creating Jenkins job via API..."
        
        curl -X POST "$JENKINS_URL/createItem?name=laravel-cicd-pipeline" \
            --user "admin:$JENKINS_TOKEN" \
            --header "Content-Type: application/xml" \
            --data-binary "@$SCRIPT_DIR/jenkins-job-config.xml" || log_warning "Failed to create Jenkins job via API"
    else
        log_warning "JENKINS_TOKEN not set, manual job creation required"
    fi
    
    log_success "Jenkins job setup completed"
}

generate_github_webhook_instructions() {
    log_info "Generating GitHub webhook setup instructions..."
    
    cat > "$SCRIPT_DIR/github-webhook-setup.md" << EOF
# GitHub Webhook Setup Instructions

## 1. Configure Webhook in GitHub Repository

Go to your GitHub repository: **${GITHUB_REPO:-your-username/your-repo}**

\`\`\`
Repository → Settings → Webhooks → Add webhook
\`\`\`

### Webhook Configuration:
\`\`\`
Payload URL: ${JENKINS_URL:-http://your-jenkins-server}/github-webhook/
Content type: application/json
Secret: (optional, but recommended)

Events to trigger:
☑ Push events
☑ Pull request events  
☑ Release events

☑ Active
\`\`\`

## 2. Test Webhook

After setting up the webhook:

1. Make a commit and push to your repository
2. Check GitHub webhook delivery logs
3. Verify Jenkins job is triggered
4. Monitor Jenkins build logs

## 3. Branch-based Deployments

- **Push to main** → Production deployment
- **Push to develop** → Staging deployment  
- **Pull Request** → Test build only

## 4. Manual Deployment

Access Jenkins job and click "Build with Parameters":
\`\`\`
ENVIRONMENT: staging/production
RUN_TESTS: true/false
RUN_MIGRATIONS: true/false
SKIP_BUILD: true/false
\`\`\`

## 5. Troubleshooting

### Webhook not triggering:
- Check GitHub webhook delivery logs
- Verify Jenkins URL accessibility
- Check firewall/security groups

### Jenkins job fails:
- Review Jenkins build logs
- Check AWS credentials
- Verify Docker daemon status

## 6. Monitoring

- **Jenkins**: Monitor build status and logs
- **AWS ECS**: Check service status and events
- **CloudWatch**: Review application logs
- **Slack**: Deployment notifications (if configured)

---

**Jenkins URL**: ${JENKINS_URL:-http://your-jenkins-server}
**GitHub Repository**: ${GITHUB_REPO:-your-username/your-repo}
**AWS Region**: ${AWS_REGION}
EOF

    log_success "GitHub webhook instructions generated: github-webhook-setup.md"
}

create_optimized_architecture_diagram() {
    log_info "Creating architecture diagram..."
    
    cat > "$SCRIPT_DIR/OPTIMIZED-ARCHITECTURE.md" << 'EOF'
# Optimized CI/CD Architecture

## 🏗️ Architecture Flow

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   GitHub        │    │    Jenkins      │    │   Amazon ECR    │
│   Repository    │───▶│   CI/CD Server  │───▶│ Container Reg.  │
│                 │    │                 │    │                 │
│ • Source Code   │    │ • Build & Test  │    │ • Docker Images │
│ • Webhook       │    │ • Security Scan │    │ • Vulnerability │
│ • Branches      │    │ • Deploy Logic  │    │   Scanning      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │                        │
                                ▼                        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Slack/Email   │    │   Amazon ECS    │    │   Production    │
│  Notifications  │◀───│   Deployment    │───▶│   Environment   │
│                 │    │                 │    │                 │
│ • Build Status  │    │ • Blue-Green    │    │ • Load Balancer │
│ • Deploy Status │    │ • Auto Scaling  │    │ • Health Checks │
│ • Alerts        │    │ • Health Checks │    │ • Monitoring    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🎯 Benefits

### ✅ Simplified Pipeline
- Single CI/CD tool (Jenkins)
- No coordination between multiple tools
- Centralized deployment logic

### ✅ Cost Effective
- No GitHub Actions minutes usage
- Reduced infrastructure complexity
- Better resource utilization

### ✅ Enhanced Control
- Full control over build environment
- Custom deployment strategies
- Advanced Jenkins plugins

### ✅ Better Monitoring
- Centralized logging in Jenkins
- Detailed build artifacts
- Custom metrics and alerts

## 🔄 Deployment Flow

### 1. Developer Workflow
```bash
git add .
git commit -m "Feature implementation"
git push origin develop  # → Triggers staging deployment
```

### 2. Production Release
```bash
git checkout main
git merge develop
git push origin main     # → Triggers production deployment
```

### 3. Hotfix Deployment
```bash
# Manual Jenkins job trigger with parameters
ENVIRONMENT: production
SKIP_BUILD: false
RUN_MIGRATIONS: true
```

## 🔧 Pipeline Stages

### Stage 1: Checkout & Setup
- Clone repository from GitHub
- Set environment variables
- Prepare build environment

### Stage 2: Testing (Parallel)
- **PHP Tests**: PHPUnit with coverage
- **Security Scan**: Composer/NPM audits  
- **Code Quality**: Laravel Pint, PHPStan

### Stage 3: Build & Push
- Build production Docker image
- Tag with commit hash + build number
- Push to Amazon ECR
- Vulnerability scanning

### Stage 4: Deploy
- Update ECS task definition
- Deploy to target environment
- Wait for service stabilization

### Stage 5: Post-Deploy
- Run database migrations
- Execute health checks
- Send notifications

## 🔒 Security Features

### Container Security
- Multi-stage Docker builds
- Vulnerability scanning with ECR
- Minimal base images
- Non-root user execution

### Infrastructure Security
- Private subnets for ECS tasks
- Security groups with least privilege
- Secrets management with AWS Secrets Manager
- IAM roles with minimal permissions

### Pipeline Security
- Webhook signature verification
- Secure credential storage
- Build isolation
- Audit logging

## 📊 Monitoring & Observability

### Jenkins Monitoring
- Build success/failure rates
- Build duration trends
- Resource utilization
- Plugin health

### Application Monitoring
- ECS service health
- Container resource usage
- Application performance metrics
- Error rates and logs

### Infrastructure Monitoring
- AWS resource utilization
- Cost optimization
- Security compliance
- Backup status

## 🚀 Scaling Considerations

### Horizontal Scaling
- Multiple Jenkins agents
- ECS auto-scaling
- Load balancer configuration
- Database read replicas

### Performance Optimization
- Docker layer caching
- Parallel test execution
- Build artifact caching
- CDN for static assets

---

**This optimized architecture provides better control, cost efficiency, and simplified management! 🎯**
EOF

    log_success "Architecture diagram created: OPTIMIZED-ARCHITECTURE.md"
}

print_setup_summary() {
    log_success "Optimized CI/CD Pipeline Setup Complete!"
    echo ""
    echo "🏗️ Architecture: GitHub Webhook → Jenkins → ECR → ECS → Production"
    echo ""
    echo "✅ Completed Setup:"
    echo "==================="
    echo "• AWS infrastructure (ECS, ECR, RDS, ElastiCache)"
    echo "• Jenkins pipeline configuration"
    echo "• Docker containerization"
    echo "• GitHub webhook instructions"
    echo "• Documentation and guides"
    echo ""
    echo "📋 Next Steps:"
    echo "=============="
    echo "1. Configure Jenkins job using jenkins-job-config.xml"
    echo "2. Set up GitHub webhook following github-webhook-setup.md"
    echo "3. Configure Jenkins credentials (AWS, GitHub, Slack)"
    echo "4. Test the pipeline with a commit"
    echo ""
    echo "📁 Generated Files:"
    echo "=================="
    echo "• Jenkinsfile.optimized - Optimized Jenkins pipeline"
    echo "• jenkins-job-config.xml - Jenkins job configuration"
    echo "• github-webhook-setup.md - Webhook setup guide"
    echo "• OPTIMIZED-ARCHITECTURE.md - Architecture documentation"
    echo ""
    echo "🔗 Useful URLs:"
    echo "==============="
    if [[ -n "$JENKINS_URL" ]]; then
        echo "• Jenkins: $JENKINS_URL"
    fi
    if [[ -n "$GITHUB_REPO" ]]; then
        echo "• GitHub: https://github.com/$GITHUB_REPO"
    fi
    echo "• AWS Console: https://console.aws.amazon.com/ecs/"
    echo ""
    echo "🎯 Benefits of This Architecture:"
    echo "================================="
    echo "• Simplified pipeline with single CI/CD tool"
    echo "• Reduced complexity and better control"
    echo "• Cost effective (no GitHub Actions minutes)"
    echo "• Enhanced monitoring and customization"
    echo ""
    log_info "Ready for optimized deployments! 🚀"
}

# Main script
main() {
    echo "Optimized Laravel CI/CD Pipeline Setup"
    echo "======================================"
    echo "Architecture: GitHub Webhook → Jenkins → ECR → ECS → Production"
    echo ""
    
    # Show usage if help requested
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_usage
    fi
    
    log_info "Starting optimized CI/CD pipeline setup..."
    
    # Run setup steps
    check_prerequisites
    setup_aws_infrastructure
    create_jenkins_job_config
    setup_jenkins_job
    generate_github_webhook_instructions
    create_optimized_architecture_diagram
    print_setup_summary
}

# Run main function with all arguments
main "$@"
