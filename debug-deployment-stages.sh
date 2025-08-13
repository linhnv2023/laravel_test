#!/bin/bash

# Debug Deployment Stages
# Kiểm tra chi tiết từng stage của deployment process

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
AWS_REGION="us-east-1"
ECR_REPOSITORY="laravel-app"
ECS_CLUSTER="production-laravel-cluster"
ECS_SERVICE="production-laravel-service"

echo -e "${BLUE}🔍 Deployment Stages Debugger${NC}"
echo "=================================================="

# Function to check stage
check_stage() {
    local stage_name="$1"
    local stage_desc="$2"
    
    echo ""
    echo -e "${YELLOW}🔧 Stage: $stage_name${NC}"
    echo "Description: $stage_desc"
    echo "----------------------------------------"
}

# Function to run command with status
run_check() {
    local desc="$1"
    local cmd="$2"
    
    echo -n "Checking $desc... "
    
    if eval "$cmd" > /tmp/debug_output 2>&1; then
        echo -e "${GREEN}✅ OK${NC}"
        if [ -s /tmp/debug_output ]; then
            echo "  $(head -1 /tmp/debug_output)"
        fi
        return 0
    else
        echo -e "${RED}❌ FAILED${NC}"
        if [ -s /tmp/debug_output ]; then
            echo "  Error: $(cat /tmp/debug_output)"
        fi
        return 1
    fi
}

# Stage 1: Jenkins & Webhook
check_stage "1. Jenkins & Webhook" "Kiểm tra Jenkins pipeline và webhook configuration"

run_check "Jenkins accessibility" "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080 | grep -q '200\|403'"
run_check "AWS CLI configuration" "aws sts get-caller-identity"
run_check "Docker daemon" "docker ps"

# Get AWS Account ID for later use
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
echo "AWS Account ID: $AWS_ACCOUNT_ID"

# Stage 2: Source Code & Tests
check_stage "2. Source Code & Tests" "Kiểm tra source code và test environment"

run_check "Jenkinsfile exists" "test -f Jenkinsfile"
run_check "Dockerfile exists" "test -f Dockerfile"
run_check "Composer.json exists" "test -f composer.json"
run_check "Package.json exists" "test -f package.json"

if [ -f "Jenkinsfile" ]; then
    echo "Jenkinsfile stages:"
    grep -n "stage(" Jenkinsfile | head -5 | sed 's/^/  /'
fi

# Stage 3: ECR Repository
check_stage "3. ECR Repository" "Kiểm tra ECR repository và permissions"

run_check "ECR repository exists" "aws ecr describe-repositories --repository-names $ECR_REPOSITORY --region $AWS_REGION"

if aws ecr describe-repositories --repository-names $ECR_REPOSITORY --region $AWS_REGION > /dev/null 2>&1; then
    echo "ECR Repository details:"
    aws ecr describe-repositories --repository-names $ECR_REPOSITORY --region $AWS_REGION \
        --query 'repositories[0].{URI:repositoryUri,Created:createdAt}' --output table
    
    # Check recent images
    echo "Recent images:"
    aws ecr describe-images --repository-name $ECR_REPOSITORY --region $AWS_REGION \
        --query 'sort_by(imageDetails,&imagePushedAt)[-3:].{Tag:imageTags[0],Pushed:imagePushedAt,Size:imageSizeInBytes}' \
        --output table 2>/dev/null || echo "  No images found"
fi

run_check "ECR login test" "aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

# Stage 4: Docker Build
check_stage "4. Docker Build" "Kiểm tra Docker build process"

run_check "Docker build context" "test -f Dockerfile && echo 'Dockerfile found'"

if [ -f "Dockerfile" ]; then
    echo "Dockerfile stages:"
    grep -n "^FROM\|^RUN\|^COPY" Dockerfile | head -5 | sed 's/^/  /'
    
    echo "Testing Docker build (dry run):"
    if docker build --dry-run . > /tmp/docker_build 2>&1; then
        echo -e "  ${GREEN}✅ Docker build syntax OK${NC}"
    else
        echo -e "  ${RED}❌ Docker build syntax error${NC}"
        tail -3 /tmp/docker_build | sed 's/^/  /'
    fi
fi

# Stage 5: ECS Infrastructure
check_stage "5. ECS Infrastructure" "Kiểm tra ECS cluster và services"

run_check "ECS cluster exists" "aws ecs describe-clusters --clusters $ECS_CLUSTER --region $AWS_REGION"

if aws ecs describe-clusters --clusters $ECS_CLUSTER --region $AWS_REGION > /dev/null 2>&1; then
    echo "ECS Cluster details:"
    aws ecs describe-clusters --clusters $ECS_CLUSTER --region $AWS_REGION \
        --query 'clusters[0].{Status:status,Running:runningTasksCount,Active:activeServicesCount}' --output table
fi

run_check "ECS service exists" "aws ecs describe-services --cluster $ECS_CLUSTER --services $ECS_SERVICE --region $AWS_REGION"

if aws ecs describe-services --cluster $ECS_CLUSTER --services $ECS_SERVICE --region $AWS_REGION > /dev/null 2>&1; then
    echo "ECS Service details:"
    aws ecs describe-services --cluster $ECS_CLUSTER --services $ECS_SERVICE --region $AWS_REGION \
        --query 'services[0].{Status:status,Desired:desiredCount,Running:runningCount,TaskDef:taskDefinition}' --output table
fi

# Stage 6: Task Definition
check_stage "6. Task Definition" "Kiểm tra ECS task definition"

run_check "Task definition exists" "aws ecs describe-task-definition --task-definition production-laravel-task --region $AWS_REGION"

if aws ecs describe-task-definition --task-definition production-laravel-task --region $AWS_REGION > /dev/null 2>&1; then
    echo "Task Definition details:"
    aws ecs describe-task-definition --task-definition production-laravel-task --region $AWS_REGION \
        --query 'taskDefinition.{Family:family,Revision:revision,CPU:cpu,Memory:memory}' --output table
    
    echo "Container definitions:"
    aws ecs describe-task-definition --task-definition production-laravel-task --region $AWS_REGION \
        --query 'taskDefinition.containerDefinitions[0].{Name:name,Image:image,Memory:memory,CPU:cpu}' --output table
fi

# Stage 7: Load Balancer
check_stage "7. Load Balancer" "Kiểm tra Application Load Balancer"

run_check "ALB exists" "aws elbv2 describe-load-balancers --names production-laravel-alb --region $AWS_REGION"

if aws elbv2 describe-load-balancers --names production-laravel-alb --region $AWS_REGION > /dev/null 2>&1; then
    ALB_DNS=$(aws elbv2 describe-load-balancers --names production-laravel-alb --region $AWS_REGION \
        --query 'LoadBalancers[0].DNSName' --output text)
    
    echo "ALB DNS: $ALB_DNS"
    
    run_check "ALB health check" "curl -f -s http://$ALB_DNS/health"
    
    if curl -f -s "http://$ALB_DNS/health" > /dev/null 2>&1; then
        echo "Health check response:"
        curl -s "http://$ALB_DNS/health" | jq . 2>/dev/null || curl -s "http://$ALB_DNS/health"
    fi
fi

# Stage 8: Database & Cache
check_stage "8. Database & Cache" "Kiểm tra RDS và ElastiCache"

run_check "RDS cluster exists" "aws rds describe-db-clusters --db-cluster-identifier production-laravel-rds --region $AWS_REGION"

if aws rds describe-db-clusters --db-cluster-identifier production-laravel-rds --region $AWS_REGION > /dev/null 2>&1; then
    echo "RDS Cluster details:"
    aws rds describe-db-clusters --db-cluster-identifier production-laravel-rds --region $AWS_REGION \
        --query 'DBClusters[0].{Status:Status,Engine:Engine,Endpoint:Endpoint}' --output table
fi

run_check "ElastiCache cluster exists" "aws elasticache describe-cache-clusters --cache-cluster-id production-laravel-redis --region $AWS_REGION"

# Stage 9: Networking
check_stage "9. Networking" "Kiểm tra VPC, subnets, security groups"

# Get VPC info from CloudFormation
if aws cloudformation describe-stacks --stack-name production-laravel-infrastructure --region $AWS_REGION > /dev/null 2>&1; then
    echo "CloudFormation Infrastructure Stack:"
    aws cloudformation describe-stacks --stack-name production-laravel-infrastructure --region $AWS_REGION \
        --query 'Stacks[0].{Status:StackStatus,Created:CreationTime}' --output table
    
    echo "Stack Outputs:"
    aws cloudformation describe-stacks --stack-name production-laravel-infrastructure --region $AWS_REGION \
        --query 'Stacks[0].Outputs[].{Key:OutputKey,Value:OutputValue}' --output table
fi

# Stage 10: Permissions
check_stage "10. Permissions" "Kiểm tra IAM permissions"

echo "Current AWS identity:"
aws sts get-caller-identity --output table

echo "Testing key AWS permissions:"
run_check "ECR permissions" "aws ecr describe-repositories --region $AWS_REGION"
run_check "ECS permissions" "aws ecs list-clusters --region $AWS_REGION"
run_check "CloudFormation permissions" "aws cloudformation list-stacks --region $AWS_REGION"

# Summary
echo ""
echo "=================================================="
echo -e "${BLUE}🎯 Debug Summary${NC}"
echo "=================================================="

echo -e "${YELLOW}✅ Ready for deployment if all checks passed${NC}"
echo -e "${YELLOW}❌ Fix any failed checks before deploying${NC}"
echo ""

echo "Next steps:"
echo "1. Fix any ❌ failed checks above"
echo "2. Run manual Jenkins build to test"
echo "3. Monitor deployment with: ./monitor-deployment.sh --build-number <number>"
echo "4. Check application health after deployment"

echo ""
echo "Useful commands:"
echo "• Jenkins logs: curl http://localhost:8080/job/laravel-production-deploy/<build>/consoleText"
echo "• ECS logs: aws logs tail /ecs/production-laravel-task --follow"
echo "• Application health: curl http://$ALB_DNS/health"

# Cleanup
rm -f /tmp/debug_output /tmp/docker_build
