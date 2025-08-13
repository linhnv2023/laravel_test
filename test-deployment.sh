#!/bin/bash

# Test Production Deployment Script
# Kiểm tra tất cả components của production deployment

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
AWS_REGION="us-east-1"
ENVIRONMENT="production"
ECS_CLUSTER="production-laravel-cluster"
ECS_SERVICE="production-laravel-service"

echo -e "${BLUE}🧪 Testing Production Deployment${NC}"
echo "=================================================="

# Test 1: AWS Connectivity
echo -e "${YELLOW}1. Testing AWS connectivity...${NC}"
if aws sts get-caller-identity > /dev/null 2>&1; then
    echo -e "${GREEN}✅ AWS CLI configured correctly${NC}"
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo "   Account ID: $AWS_ACCOUNT_ID"
else
    echo -e "${RED}❌ AWS CLI not configured${NC}"
    exit 1
fi

# Test 2: ECR Repository
echo -e "${YELLOW}2. Testing ECR repository...${NC}"
if aws ecr describe-repositories --repository-names laravel-app --region $AWS_REGION > /dev/null 2>&1; then
    echo -e "${GREEN}✅ ECR repository exists${NC}"
    ECR_URI=$(aws ecr describe-repositories --repository-names laravel-app --region $AWS_REGION --query 'repositories[0].repositoryUri' --output text)
    echo "   Repository URI: $ECR_URI"
else
    echo -e "${RED}❌ ECR repository not found${NC}"
    echo "   Creating ECR repository..."
    aws ecr create-repository --repository-name laravel-app --region $AWS_REGION
    echo -e "${GREEN}✅ ECR repository created${NC}"
fi

# Test 3: CloudFormation Stacks
echo -e "${YELLOW}3. Testing CloudFormation stacks...${NC}"

# Infrastructure stack
if aws cloudformation describe-stacks --stack-name ${ENVIRONMENT}-laravel-infrastructure --region $AWS_REGION > /dev/null 2>&1; then
    STACK_STATUS=$(aws cloudformation describe-stacks --stack-name ${ENVIRONMENT}-laravel-infrastructure --region $AWS_REGION --query 'Stacks[0].StackStatus' --output text)
    if [ "$STACK_STATUS" = "CREATE_COMPLETE" ] || [ "$STACK_STATUS" = "UPDATE_COMPLETE" ]; then
        echo -e "${GREEN}✅ Infrastructure stack is ready${NC}"
    else
        echo -e "${YELLOW}⚠️ Infrastructure stack status: $STACK_STATUS${NC}"
    fi
else
    echo -e "${RED}❌ Infrastructure stack not found${NC}"
    echo "   Please deploy infrastructure first: aws cloudformation deploy --template-file aws/cloudformation/ecs-infrastructure.yml ..."
fi

# Services stack
if aws cloudformation describe-stacks --stack-name ${ENVIRONMENT}-laravel-services --region $AWS_REGION > /dev/null 2>&1; then
    STACK_STATUS=$(aws cloudformation describe-stacks --stack-name ${ENVIRONMENT}-laravel-services --region $AWS_REGION --query 'Stacks[0].StackStatus' --output text)
    if [ "$STACK_STATUS" = "CREATE_COMPLETE" ] || [ "$STACK_STATUS" = "UPDATE_COMPLETE" ]; then
        echo -e "${GREEN}✅ Services stack is ready${NC}"
    else
        echo -e "${YELLOW}⚠️ Services stack status: $STACK_STATUS${NC}"
    fi
else
    echo -e "${RED}❌ Services stack not found${NC}"
    echo "   Please deploy services first: aws cloudformation deploy --template-file aws/cloudformation/ecs-services.yml ..."
fi

# Test 4: ECS Cluster
echo -e "${YELLOW}4. Testing ECS cluster...${NC}"
if aws ecs describe-clusters --clusters $ECS_CLUSTER --region $AWS_REGION > /dev/null 2>&1; then
    CLUSTER_STATUS=$(aws ecs describe-clusters --clusters $ECS_CLUSTER --region $AWS_REGION --query 'clusters[0].status' --output text)
    if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
        echo -e "${GREEN}✅ ECS cluster is active${NC}"
        RUNNING_TASKS=$(aws ecs describe-clusters --clusters $ECS_CLUSTER --region $AWS_REGION --query 'clusters[0].runningTasksCount' --output text)
        echo "   Running tasks: $RUNNING_TASKS"
    else
        echo -e "${YELLOW}⚠️ ECS cluster status: $CLUSTER_STATUS${NC}"
    fi
else
    echo -e "${RED}❌ ECS cluster not found${NC}"
fi

# Test 5: ECS Service
echo -e "${YELLOW}5. Testing ECS service...${NC}"
if aws ecs describe-services --cluster $ECS_CLUSTER --services $ECS_SERVICE --region $AWS_REGION > /dev/null 2>&1; then
    SERVICE_STATUS=$(aws ecs describe-services --cluster $ECS_CLUSTER --services $ECS_SERVICE --region $AWS_REGION --query 'services[0].status' --output text)
    if [ "$SERVICE_STATUS" = "ACTIVE" ]; then
        echo -e "${GREEN}✅ ECS service is active${NC}"
        DESIRED_COUNT=$(aws ecs describe-services --cluster $ECS_CLUSTER --services $ECS_SERVICE --region $AWS_REGION --query 'services[0].desiredCount' --output text)
        RUNNING_COUNT=$(aws ecs describe-services --cluster $ECS_CLUSTER --services $ECS_SERVICE --region $AWS_REGION --query 'services[0].runningCount' --output text)
        echo "   Desired: $DESIRED_COUNT, Running: $RUNNING_COUNT"
    else
        echo -e "${YELLOW}⚠️ ECS service status: $SERVICE_STATUS${NC}"
    fi
else
    echo -e "${RED}❌ ECS service not found${NC}"
fi

# Test 6: Load Balancer
echo -e "${YELLOW}6. Testing Application Load Balancer...${NC}"
if aws elbv2 describe-load-balancers --names ${ENVIRONMENT}-laravel-alb --region $AWS_REGION > /dev/null 2>&1; then
    ALB_STATE=$(aws elbv2 describe-load-balancers --names ${ENVIRONMENT}-laravel-alb --region $AWS_REGION --query 'LoadBalancers[0].State.Code' --output text)
    if [ "$ALB_STATE" = "active" ]; then
        echo -e "${GREEN}✅ Load balancer is active${NC}"
        ALB_DNS=$(aws elbv2 describe-load-balancers --names ${ENVIRONMENT}-laravel-alb --region $AWS_REGION --query 'LoadBalancers[0].DNSName' --output text)
        echo "   DNS Name: $ALB_DNS"
        
        # Test 7: Health Check
        echo -e "${YELLOW}7. Testing application health...${NC}"
        if curl -f -s "http://$ALB_DNS/health" > /dev/null; then
            echo -e "${GREEN}✅ Application health check passed${NC}"
            HEALTH_RESPONSE=$(curl -s "http://$ALB_DNS/health")
            echo "   Response: $HEALTH_RESPONSE"
        else
            echo -e "${RED}❌ Application health check failed${NC}"
            echo "   URL: http://$ALB_DNS/health"
        fi
    else
        echo -e "${YELLOW}⚠️ Load balancer state: $ALB_STATE${NC}"
    fi
else
    echo -e "${RED}❌ Load balancer not found${NC}"
fi

# Test 8: RDS Database
echo -e "${YELLOW}8. Testing RDS database...${NC}"
if aws rds describe-db-clusters --db-cluster-identifier ${ENVIRONMENT}-laravel-rds --region $AWS_REGION > /dev/null 2>&1; then
    DB_STATUS=$(aws rds describe-db-clusters --db-cluster-identifier ${ENVIRONMENT}-laravel-rds --region $AWS_REGION --query 'DBClusters[0].Status' --output text)
    if [ "$DB_STATUS" = "available" ]; then
        echo -e "${GREEN}✅ RDS database is available${NC}"
        DB_ENDPOINT=$(aws rds describe-db-clusters --db-cluster-identifier ${ENVIRONMENT}-laravel-rds --region $AWS_REGION --query 'DBClusters[0].Endpoint' --output text)
        echo "   Endpoint: $DB_ENDPOINT"
    else
        echo -e "${YELLOW}⚠️ RDS database status: $DB_STATUS${NC}"
    fi
else
    echo -e "${RED}❌ RDS database not found${NC}"
fi

# Test 9: ElastiCache Redis
echo -e "${YELLOW}9. Testing ElastiCache Redis...${NC}"
if aws elasticache describe-cache-clusters --cache-cluster-id ${ENVIRONMENT}-laravel-redis --region $AWS_REGION > /dev/null 2>&1; then
    REDIS_STATUS=$(aws elasticache describe-cache-clusters --cache-cluster-id ${ENVIRONMENT}-laravel-redis --region $AWS_REGION --query 'CacheClusters[0].CacheClusterStatus' --output text)
    if [ "$REDIS_STATUS" = "available" ]; then
        echo -e "${GREEN}✅ ElastiCache Redis is available${NC}"
        REDIS_ENDPOINT=$(aws elasticache describe-cache-clusters --cache-cluster-id ${ENVIRONMENT}-laravel-redis --region $AWS_REGION --query 'CacheClusters[0].RedisConfiguration.PrimaryEndpoint.Address' --output text 2>/dev/null || echo "N/A")
        echo "   Endpoint: $REDIS_ENDPOINT"
    else
        echo -e "${YELLOW}⚠️ ElastiCache Redis status: $REDIS_STATUS${NC}"
    fi
else
    echo -e "${RED}❌ ElastiCache Redis not found${NC}"
fi

# Test 10: Docker Image in ECR
echo -e "${YELLOW}10. Testing Docker images in ECR...${NC}"
IMAGES=$(aws ecr list-images --repository-name laravel-app --region $AWS_REGION --query 'imageIds[?imageTag!=`null`]' --output text 2>/dev/null || echo "")
if [ -n "$IMAGES" ]; then
    echo -e "${GREEN}✅ Docker images found in ECR${NC}"
    IMAGE_COUNT=$(aws ecr list-images --repository-name laravel-app --region $AWS_REGION --query 'length(imageIds)' --output text)
    echo "   Total images: $IMAGE_COUNT"
else
    echo -e "${YELLOW}⚠️ No Docker images found in ECR${NC}"
    echo "   Run deployment to build and push first image"
fi

echo ""
echo "=================================================="
echo -e "${BLUE}📊 Test Summary${NC}"
echo "=================================================="

# Summary
if [ -n "$ALB_DNS" ]; then
    echo -e "${GREEN}🌐 Application URL: http://$ALB_DNS${NC}"
    echo -e "${GREEN}🏥 Health Check: http://$ALB_DNS/health${NC}"
fi

echo ""
echo -e "${YELLOW}📋 Next Steps:${NC}"
echo "1. If any tests failed, fix the issues before deploying"
echo "2. Run './deploy-production.sh' to deploy your application"
echo "3. Setup Jenkins pipeline for automated deployments"
echo "4. Configure monitoring and alerting"
echo ""
echo -e "${GREEN}🎉 Production environment test completed!${NC}"
