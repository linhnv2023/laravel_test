#!/bin/bash

# Jenkins Configuration Checker
# Kiểm tra các cấu hình cần thiết cho Jenkins pipeline

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
JENKINS_URL="http://localhost:8080"  # Thay đổi URL Jenkins của bạn
JENKINS_JOB="laravel-production-deploy"

echo -e "${BLUE}🔍 Jenkins Configuration Checker${NC}"
echo "=================================================="

# Function to check command exists
check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✅ $1 is installed${NC}"
        return 0
    else
        echo -e "${RED}❌ $1 is not installed${NC}"
        return 1
    fi
}

# Function to check service status
check_service() {
    if systemctl is-active --quiet $1; then
        echo -e "${GREEN}✅ $1 service is running${NC}"
        return 0
    else
        echo -e "${RED}❌ $1 service is not running${NC}"
        return 1
    fi
}

echo -e "${YELLOW}1. Checking system requirements...${NC}"

# Check Docker
if check_command docker; then
    DOCKER_VERSION=$(docker --version)
    echo "   Version: $DOCKER_VERSION"
    
    # Check Docker daemon
    if docker ps &> /dev/null; then
        echo -e "${GREEN}   ✅ Docker daemon is running${NC}"
    else
        echo -e "${RED}   ❌ Docker daemon is not accessible${NC}"
        echo "   Fix: sudo systemctl start docker"
    fi
else
    echo "   Fix: Install Docker first"
fi

# Check AWS CLI
if check_command aws; then
    AWS_VERSION=$(aws --version)
    echo "   Version: $AWS_VERSION"
    
    # Check AWS credentials
    if aws sts get-caller-identity &> /dev/null; then
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        echo -e "${GREEN}   ✅ AWS credentials configured${NC}"
        echo "   Account ID: $AWS_ACCOUNT_ID"
    else
        echo -e "${RED}   ❌ AWS credentials not configured${NC}"
        echo "   Fix: aws configure"
    fi
else
    echo "   Fix: Install AWS CLI first"
fi

# Check Git
if check_command git; then
    GIT_VERSION=$(git --version)
    echo "   Version: $GIT_VERSION"
else
    echo "   Fix: Install Git first"
fi

# Check curl
check_command curl

echo ""
echo -e "${YELLOW}2. Checking Jenkins accessibility...${NC}"

# Check Jenkins URL
if curl -s -o /dev/null -w "%{http_code}" "$JENKINS_URL" | grep -q "200\|403"; then
    echo -e "${GREEN}✅ Jenkins is accessible at $JENKINS_URL${NC}"
    
    # Try to get Jenkins version
    JENKINS_VERSION=$(curl -s "$JENKINS_URL/api/json" | grep -o '"version":"[^"]*' | cut -d'"' -f4 2>/dev/null || echo "Unknown")
    echo "   Version: $JENKINS_VERSION"
else
    echo -e "${RED}❌ Jenkins is not accessible at $JENKINS_URL${NC}"
    echo "   Fix: Check Jenkins URL and ensure Jenkins is running"
fi

echo ""
echo -e "${YELLOW}3. Checking Docker permissions...${NC}"

# Check if current user can run Docker
if docker ps &> /dev/null; then
    echo -e "${GREEN}✅ Current user can run Docker commands${NC}"
else
    echo -e "${RED}❌ Current user cannot run Docker commands${NC}"
    echo "   Fix: sudo usermod -aG docker \$USER && newgrp docker"
fi

# Check if jenkins user exists and can run Docker
if id jenkins &> /dev/null; then
    echo -e "${GREEN}✅ Jenkins user exists${NC}"
    
    # Check if jenkins user is in docker group
    if groups jenkins | grep -q docker; then
        echo -e "${GREEN}✅ Jenkins user is in docker group${NC}"
    else
        echo -e "${RED}❌ Jenkins user is not in docker group${NC}"
        echo "   Fix: sudo usermod -aG docker jenkins && sudo systemctl restart jenkins"
    fi
else
    echo -e "${YELLOW}⚠️ Jenkins user not found (might be running in container)${NC}"
fi

echo ""
echo -e "${YELLOW}4. Checking AWS resources...${NC}"

if aws sts get-caller-identity &> /dev/null; then
    # Check ECR repository
    if aws ecr describe-repositories --repository-names laravel-app --region us-east-1 &> /dev/null; then
        echo -e "${GREEN}✅ ECR repository 'laravel-app' exists${NC}"
        ECR_URI=$(aws ecr describe-repositories --repository-names laravel-app --region us-east-1 --query 'repositories[0].repositoryUri' --output text)
        echo "   URI: $ECR_URI"
    else
        echo -e "${RED}❌ ECR repository 'laravel-app' not found${NC}"
        echo "   Fix: aws ecr create-repository --repository-name laravel-app --region us-east-1"
    fi
    
    # Check ECS cluster
    if aws ecs describe-clusters --clusters production-laravel-cluster --region us-east-1 &> /dev/null; then
        CLUSTER_STATUS=$(aws ecs describe-clusters --clusters production-laravel-cluster --region us-east-1 --query 'clusters[0].status' --output text)
        if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
            echo -e "${GREEN}✅ ECS cluster 'production-laravel-cluster' is active${NC}"
        else
            echo -e "${YELLOW}⚠️ ECS cluster status: $CLUSTER_STATUS${NC}"
        fi
    else
        echo -e "${RED}❌ ECS cluster 'production-laravel-cluster' not found${NC}"
        echo "   Fix: Deploy CloudFormation infrastructure stack first"
    fi
    
    # Check ECS service
    if aws ecs describe-services --cluster production-laravel-cluster --services production-laravel-service --region us-east-1 &> /dev/null; then
        SERVICE_STATUS=$(aws ecs describe-services --cluster production-laravel-cluster --services production-laravel-service --region us-east-1 --query 'services[0].status' --output text)
        if [ "$SERVICE_STATUS" = "ACTIVE" ]; then
            echo -e "${GREEN}✅ ECS service 'production-laravel-service' is active${NC}"
        else
            echo -e "${YELLOW}⚠️ ECS service status: $SERVICE_STATUS${NC}"
        fi
    else
        echo -e "${RED}❌ ECS service 'production-laravel-service' not found${NC}"
        echo "   Fix: Deploy CloudFormation services stack first"
    fi
else
    echo -e "${YELLOW}⚠️ Skipping AWS resources check (no AWS credentials)${NC}"
fi

echo ""
echo -e "${YELLOW}5. Checking project files...${NC}"

# Check Jenkinsfile
if [ -f "Jenkinsfile" ]; then
    echo -e "${GREEN}✅ Jenkinsfile exists${NC}"
    
    # Check if Jenkinsfile has webhook variables
    if grep -q "WEBHOOK_BRANCH" Jenkinsfile; then
        echo -e "${GREEN}   ✅ Webhook variables configured${NC}"
    else
        echo -e "${YELLOW}   ⚠️ Webhook variables not found${NC}"
    fi
else
    echo -e "${RED}❌ Jenkinsfile not found${NC}"
    echo "   Fix: Ensure Jenkinsfile exists in repository root"
fi

# Check Dockerfile
if [ -f "Dockerfile" ]; then
    echo -e "${GREEN}✅ Dockerfile exists${NC}"
else
    echo -e "${RED}❌ Dockerfile not found${NC}"
    echo "   Fix: Ensure Dockerfile exists in repository root"
fi

# Check CloudFormation templates
if [ -f "aws/cloudformation/ecs-infrastructure.yml" ]; then
    echo -e "${GREEN}✅ Infrastructure CloudFormation template exists${NC}"
else
    echo -e "${RED}❌ Infrastructure CloudFormation template not found${NC}"
fi

if [ -f "aws/cloudformation/ecs-services.yml" ]; then
    echo -e "${GREEN}✅ Services CloudFormation template exists${NC}"
else
    echo -e "${RED}❌ Services CloudFormation template not found${NC}"
fi

echo ""
echo -e "${YELLOW}6. Generating configuration commands...${NC}"

echo ""
echo -e "${BLUE}📋 Commands to fix common issues:${NC}"
echo ""

echo -e "${YELLOW}Fix Docker permissions:${NC}"
echo "sudo usermod -aG docker jenkins"
echo "sudo systemctl restart jenkins"
echo ""

echo -e "${YELLOW}Create ECR repository:${NC}"
echo "aws ecr create-repository --repository-name laravel-app --region us-east-1"
echo ""

echo -e "${YELLOW}Deploy infrastructure:${NC}"
echo "aws cloudformation deploy \\"
echo "    --template-file aws/cloudformation/ecs-infrastructure.yml \\"
echo "    --stack-name production-laravel-infrastructure \\"
echo "    --parameter-overrides Environment=production DBPassword=YourSecurePassword123! \\"
echo "    --capabilities CAPABILITY_IAM \\"
echo "    --region us-east-1"
echo ""

echo -e "${YELLOW}Test webhook:${NC}"
echo "chmod +x test-webhook.sh"
echo "./test-webhook.sh --jenkins-url $JENKINS_URL --token laravel-deploy-secret-token-2024"
echo ""

echo "=================================================="
echo -e "${BLUE}🎯 Configuration check completed!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Fix any ❌ issues shown above"
echo "2. Configure Jenkins job with Generic Webhook Trigger"
echo "3. Add AWS credentials to Jenkins"
echo "4. Test the pipeline with a manual build"
echo "5. Push code to trigger webhook"
