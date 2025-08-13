#!/bin/bash

# Laravel Production Deployment Script
# Sử dụng script này để deploy lần đầu lên production

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="us-east-1"
ECR_REPOSITORY="laravel-app"
ENVIRONMENT="production"
ECS_CLUSTER="production-laravel-cluster"
ECS_SERVICE="production-laravel-service"

echo -e "${BLUE}🚀 Starting Laravel Production Deployment${NC}"
echo "=================================================="

# Step 1: Get AWS Account ID
echo -e "${YELLOW}📋 Getting AWS Account ID...${NC}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
echo "AWS Account ID: $AWS_ACCOUNT_ID"

# Step 2: Login to ECR
echo -e "${YELLOW}🔐 Logging into ECR...${NC}"
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# Step 3: Build Docker image
echo -e "${YELLOW}🏗️ Building Docker image...${NC}"
IMAGE_TAG="$(git rev-parse --short HEAD)-$(date +%s)"
FULL_IMAGE_NAME="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

docker build \
    --target production \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    -t $FULL_IMAGE_NAME \
    -t ${ECR_REGISTRY}/${ECR_REPOSITORY}:latest \
    -t ${ECR_REGISTRY}/${ECR_REPOSITORY}:production \
    .

# Step 4: Push image to ECR
echo -e "${YELLOW}📤 Pushing image to ECR...${NC}"
docker push $FULL_IMAGE_NAME
docker push ${ECR_REGISTRY}/${ECR_REPOSITORY}:latest
docker push ${ECR_REGISTRY}/${ECR_REPOSITORY}:production

# Step 5: Update ECS Task Definition
echo -e "${YELLOW}🔄 Updating ECS Task Definition...${NC}"

# Get current task definition
aws ecs describe-task-definition \
    --task-definition ${ENVIRONMENT}-laravel-task \
    --region $AWS_REGION \
    --query taskDefinition > task-definition.json

# Update image in task definition
jq --arg IMAGE "$FULL_IMAGE_NAME" \
   '.containerDefinitions[0].image = $IMAGE' \
   task-definition.json > updated-task-definition.json

# Remove unnecessary fields
jq 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)' \
   updated-task-definition.json > final-task-definition.json

# Register new task definition
NEW_TASK_DEF=$(aws ecs register-task-definition \
    --cli-input-json file://final-task-definition.json \
    --region $AWS_REGION \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

echo "New task definition: $NEW_TASK_DEF"

# Step 6: Update ECS Service
echo -e "${YELLOW}🚀 Updating ECS Service...${NC}"
aws ecs update-service \
    --cluster $ECS_CLUSTER \
    --service $ECS_SERVICE \
    --task-definition $NEW_TASK_DEF \
    --region $AWS_REGION

# Step 7: Wait for deployment
echo -e "${YELLOW}⏳ Waiting for deployment to complete...${NC}"
aws ecs wait services-stable \
    --cluster $ECS_CLUSTER \
    --services $ECS_SERVICE \
    --region $AWS_REGION

# Step 8: Run database migrations
echo -e "${YELLOW}🗄️ Running database migrations...${NC}"

# Get subnet and security group info
PRIVATE_SUBNETS=$(aws cloudformation describe-stacks \
    --stack-name ${ENVIRONMENT}-laravel-infrastructure \
    --query 'Stacks[0].Outputs[?OutputKey==`PrivateSubnets`].OutputValue' \
    --output text \
    --region $AWS_REGION)

ECS_SECURITY_GROUP=$(aws cloudformation describe-stacks \
    --stack-name ${ENVIRONMENT}-laravel-infrastructure \
    --query 'Stacks[0].Outputs[?OutputKey==`ECSSecurityGroup`].OutputValue' \
    --output text \
    --region $AWS_REGION)

SUBNET_ID=$(echo "$PRIVATE_SUBNETS" | cut -d',' -f1)

# Run migration task
TASK_ARN=$(aws ecs run-task \
    --cluster $ECS_CLUSTER \
    --task-definition ${ENVIRONMENT}-laravel-task \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],securityGroups=[$ECS_SECURITY_GROUP],assignPublicIp=DISABLED}" \
    --overrides '{
        "containerOverrides": [
            {
                "name": "laravel-app",
                "command": ["php", "artisan", "migrate", "--force"]
            }
        ]
    }' \
    --region $AWS_REGION \
    --query 'tasks[0].taskArn' \
    --output text)

echo "Migration task: $TASK_ARN"

# Wait for migration to complete
aws ecs wait tasks-stopped \
    --cluster $ECS_CLUSTER \
    --tasks $TASK_ARN \
    --region $AWS_REGION

# Check migration exit code
EXIT_CODE=$(aws ecs describe-tasks \
    --cluster $ECS_CLUSTER \
    --tasks $TASK_ARN \
    --region $AWS_REGION \
    --query 'tasks[0].containers[0].exitCode' \
    --output text)

if [ "$EXIT_CODE" != "0" ]; then
    echo -e "${RED}❌ Migration failed with exit code: $EXIT_CODE${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Migration completed successfully${NC}"

# Step 9: Health check
echo -e "${YELLOW}🏥 Performing health check...${NC}"

# Get ALB endpoint
ALB_ENDPOINT=$(aws elbv2 describe-load-balancers \
    --names ${ENVIRONMENT}-laravel-alb \
    --query 'LoadBalancers[0].DNSName' \
    --output text \
    --region $AWS_REGION)

echo "Application URL: http://$ALB_ENDPOINT"

# Health check with retry
for i in {1..10}; do
    echo "Health check attempt $i/10..."
    if curl -f -s "http://$ALB_ENDPOINT/health" > /dev/null; then
        echo -e "${GREEN}✅ Health check passed!${NC}"
        break
    else
        if [ $i -eq 10 ]; then
            echo -e "${RED}❌ Health check failed after 10 attempts${NC}"
            exit 1
        fi
        sleep 30
    fi
done

# Step 10: Cleanup
echo -e "${YELLOW}🧹 Cleaning up...${NC}"
rm -f task-definition.json updated-task-definition.json final-task-definition.json

# Clean up local images
docker rmi $FULL_IMAGE_NAME || true
docker rmi ${ECR_REGISTRY}/${ECR_REPOSITORY}:latest || true
docker rmi ${ECR_REGISTRY}/${ECR_REPOSITORY}:production || true

echo ""
echo "=================================================="
echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
echo -e "${GREEN}🌐 Application URL: http://$ALB_ENDPOINT${NC}"
echo -e "${GREEN}📊 Image deployed: $IMAGE_TAG${NC}"
echo "=================================================="
