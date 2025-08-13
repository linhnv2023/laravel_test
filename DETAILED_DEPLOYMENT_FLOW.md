# 🚀 Chi tiết quy trình Jenkins → ECR → ECS → Production

## 📋 Tổng quan quy trình

```
GitHub Push → Jenkins Webhook → Build Docker → Push ECR → Update ECS → Production Live
```

## 🔧 Bước 1: Jenkins Pipeline Execution

### 1.1 Webhook Trigger
```bash
# GitHub gửi webhook payload:
{
  "ref": "refs/heads/main",
  "after": "abc123def456",
  "repository": {"name": "laravel-app"},
  "pusher": {"name": "developer"},
  "head_commit": {"message": "Deploy to production"}
}
```

### 1.2 Jenkins nhận và parse webhook
```groovy
// Jenkins tự động tạo environment variables:
BRANCH_NAME = "refs/heads/main"
COMMIT_SHA = "abc123def456"
REPOSITORY_NAME = "laravel-app"
PUSHER_NAME = "developer"
COMMIT_MESSAGE = "Deploy to production"
```

### 1.3 Pipeline bắt đầu chạy
```bash
# Stage: Webhook Info & Setup
=== Webhook Information ===
Branch: refs/heads/main
Commit: abc123def456
Repository: laravel-app
Pusher: developer
==========================

# Lấy AWS Account ID
AWS_ACCOUNT_ID = "123456789012"

# Tạo image tag
IMAGE_TAG = "abc123de-1234"  # commit(8 chars) + build_number

# Tạo full image name
FULL_IMAGE_NAME = "123456789012.dkr.ecr.us-east-1.amazonaws.com/laravel-app:abc123de-1234"
```

## 🧪 Bước 2: Run Tests (Parallel)

### 2.1 PHP Tests
```bash
# Build test image
docker build -t laravel-test:1234 --target development .

# Run PHPUnit tests
docker run --rm \
    -v /workspace:/var/www/html \
    laravel-test:1234 \
    bash -c "
        cp .env.example .env
        php artisan key:generate
        composer install --no-dev --optimize-autoloader
        php artisan test --junit=test-results.xml
    "

# Results: ✅ Tests passed
```

### 2.2 Security Scan
```bash
# Composer security audit
docker run --rm -v /workspace:/app composer:latest \
    composer audit --format=json > composer-audit.json

# NPM security audit  
docker run --rm -v /workspace:/app node:20-alpine \
    npm audit --json > npm-audit.json

# Results: ✅ No vulnerabilities found
```

### 2.3 Code Quality Check
```bash
# Laravel Pint (PHP CS Fixer)
docker run --rm -v /workspace:/app php:8.3-cli \
    vendor/bin/pint --test

# Results: ✅ Code style passed
```

## 🏗️ Bước 3: Build & Push Docker Image

### 3.1 Login to ECR
```bash
# Get ECR login token
aws ecr get-login-password --region us-east-1 | \
docker login --username AWS --password-stdin \
123456789012.dkr.ecr.us-east-1.amazonaws.com

# Output: Login Succeeded
```

### 3.2 Create ECR Repository (if not exists)
```bash
# Check if repository exists
aws ecr describe-repositories --repository-names laravel-app --region us-east-1

# If not exists, create it
aws ecr create-repository \
    --repository-name laravel-app \
    --region us-east-1 \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256

# Output: Repository created successfully
```

### 3.3 Build Production Docker Image
```bash
# Build with cache optimization
docker build \
    --target production \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    --cache-from 123456789012.dkr.ecr.us-east-1.amazonaws.com/laravel-app:latest \
    -t 123456789012.dkr.ecr.us-east-1.amazonaws.com/laravel-app:abc123de-1234 \
    -t 123456789012.dkr.ecr.us-east-1.amazonaws.com/laravel-app:latest \
    -t 123456789012.dkr.ecr.us-east-1.amazonaws.com/laravel-app:production \
    .

# Build process:
# Step 1/15 : FROM webdevops/php-nginx:8.3-alpine as base
# Step 2/15 : WORKDIR /app
# Step 3/15 : COPY composer.json composer.lock ./
# ...
# Step 15/15 : CMD ["supervisord", "-c", "/opt/docker/etc/supervisor.conf"]
# Successfully built abc123def456
```

### 3.4 Push Images to ECR
```bash
# Push specific version
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/laravel-app:abc123de-1234

# Push latest tag
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/laravel-app:latest

# Push environment tag
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/laravel-app:production

# Output:
# abc123de-1234: Pushed
# latest: Pushed  
# production: Pushed
```

### 3.5 Start Image Security Scan
```bash
# Trigger ECR vulnerability scan
aws ecr start-image-scan \
    --repository-name laravel-app \
    --image-id imageTag=abc123de-1234 \
    --region us-east-1

# Output: Scan started successfully
```

## 🚀 Bước 4: Deploy to ECS

### 4.1 Get Current Task Definition
```bash
# Download current task definition
aws ecs describe-task-definition \
    --task-definition production-laravel-task \
    --region us-east-1 \
    --query taskDefinition > task-definition.json

# Current task definition structure:
{
  "family": "production-laravel-task",
  "revision": 5,
  "containerDefinitions": [
    {
      "name": "laravel-app",
      "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/laravel-app:old-version",
      "memory": 512,
      "cpu": 256,
      ...
    }
  ]
}
```

### 4.2 Update Task Definition with New Image
```bash
# Update image URL in task definition
jq --arg IMAGE "123456789012.dkr.ecr.us-east-1.amazonaws.com/laravel-app:abc123de-1234" \
   '.containerDefinitions[0].image = $IMAGE' \
   task-definition.json > updated-task-definition.json

# Remove unnecessary fields for registration
jq 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)' \
   updated-task-definition.json > final-task-definition.json
```

### 4.3 Register New Task Definition
```bash
# Register new task definition revision
NEW_TASK_DEF=$(aws ecs register-task-definition \
    --cli-input-json file://final-task-definition.json \
    --region us-east-1 \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

# Output: 
# arn:aws:ecs:us-east-1:123456789012:task-definition/production-laravel-task:6
echo "New task definition: $NEW_TASK_DEF"
```

### 4.4 Update ECS Service
```bash
# Update service to use new task definition
aws ecs update-service \
    --cluster production-laravel-cluster \
    --service production-laravel-service \
    --task-definition $NEW_TASK_DEF \
    --region us-east-1

# Output:
{
  "service": {
    "serviceName": "production-laravel-service",
    "clusterArn": "arn:aws:ecs:us-east-1:123456789012:cluster/production-laravel-cluster",
    "taskDefinition": "arn:aws:ecs:us-east-1:123456789012:task-definition/production-laravel-task:6",
    "desiredCount": 2,
    "runningCount": 2,
    "deploymentStatus": "PRIMARY"
  }
}
```

## ⏳ Bước 5: Wait for Deployment

### 5.1 Monitor Deployment Progress
```bash
# Wait for service to stabilize (max 15 minutes)
echo "Waiting for ECS service to stabilize..."
aws ecs wait services-stable \
    --cluster production-laravel-cluster \
    --services production-laravel-service \
    --region us-east-1

# ECS deployment process:
# 1. Stop old tasks gradually
# 2. Start new tasks with new image
# 3. Health check new tasks
# 4. Route traffic to new tasks
# 5. Terminate old tasks
```

### 5.2 Deployment Events
```bash
# Monitor deployment events
aws ecs describe-services \
    --cluster production-laravel-cluster \
    --services production-laravel-service \
    --region us-east-1 \
    --query 'services[0].events[0:5]'

# Sample events:
[
  {
    "message": "(service production-laravel-service) has reached a steady state.",
    "createdAt": "2024-01-15T10:30:00Z"
  },
  {
    "message": "(service production-laravel-service) registered 2 targets in target-group",
    "createdAt": "2024-01-15T10:29:45Z"
  }
]
```

## 🗄️ Bước 6: Run Database Migrations

### 6.1 Get Network Configuration
```bash
# Get private subnets from CloudFormation
PRIVATE_SUBNETS=$(aws cloudformation describe-stacks \
    --stack-name production-laravel-infrastructure \
    --query 'Stacks[0].Outputs[?OutputKey==`PrivateSubnets`].OutputValue' \
    --output text \
    --region us-east-1)

# Get ECS security group
ECS_SECURITY_GROUP=$(aws cloudformation describe-stacks \
    --stack-name production-laravel-infrastructure \
    --query 'Stacks[0].Outputs[?OutputKey==`ECSSecurityGroup`].OutputValue' \
    --output text \
    --region us-east-1)

# Select first subnet
SUBNET_ID=$(echo "$PRIVATE_SUBNETS" | cut -d',' -f1)

echo "Using subnet: $SUBNET_ID"
echo "Using security group: $ECS_SECURITY_GROUP"
```

### 6.2 Run Migration Task
```bash
# Run one-time migration task
TASK_ARN=$(aws ecs run-task \
    --cluster production-laravel-cluster \
    --task-definition production-laravel-task \
    --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],securityGroups=[$ECS_SECURITY_GROUP],assignPublicIp=DISABLED}" \
    --overrides '{
        "containerOverrides": [
            {
                "name": "laravel-app",
                "command": ["php", "artisan", "migrate", "--force"]
            }
        ]
    }' \
    --region us-east-1 \
    --query 'tasks[0].taskArn' \
    --output text)

echo "Migration task: $TASK_ARN"
```

### 6.3 Wait for Migration Completion
```bash
# Wait for migration task to complete
aws ecs wait tasks-stopped \
    --cluster production-laravel-cluster \
    --tasks $TASK_ARN \
    --region us-east-1

# Check migration exit code
EXIT_CODE=$(aws ecs describe-tasks \
    --cluster production-laravel-cluster \
    --tasks $TASK_ARN \
    --region us-east-1 \
    --query 'tasks[0].containers[0].exitCode' \
    --output text)

if [ "$EXIT_CODE" = "0" ]; then
    echo "✅ Migration completed successfully"
else
    echo "❌ Migration failed with exit code: $EXIT_CODE"
    exit 1
fi
```

## 🏥 Bước 7: Health Check

### 7.1 Get Application Load Balancer Endpoint
```bash
# Get ALB DNS name
ALB_ENDPOINT=$(aws elbv2 describe-load-balancers \
    --names production-laravel-alb \
    --query 'LoadBalancers[0].DNSName' \
    --output text \
    --region us-east-1)

echo "Application URL: http://$ALB_ENDPOINT"
```

### 7.2 Perform Health Checks
```bash
# Health check with retry (10 attempts, 30s interval)
for i in {1..10}; do
    echo "Health check attempt $i/10..."
    
    if curl -f -s "http://$ALB_ENDPOINT/health" > /dev/null; then
        echo "✅ Health check passed!"
        
        # Get health response
        HEALTH_RESPONSE=$(curl -s "http://$ALB_ENDPOINT/health")
        echo "Response: $HEALTH_RESPONSE"
        
        # Expected response:
        # {
        #   "status": "ok",
        #   "timestamp": "2024-01-15T10:30:00Z",
        #   "environment": "production",
        #   "version": "1.0.0"
        # }
        
        break
    else
        if [ $i -eq 10 ]; then
            echo "❌ Health check failed after 10 attempts"
            exit 1
        fi
        sleep 30
    fi
done
```

## 🎉 Bước 8: Deployment Success

### 8.1 Final Status
```bash
echo "=================================================="
echo "🎉 Deployment completed successfully!"
echo "🌐 Application URL: http://$ALB_ENDPOINT"
echo "📊 Image deployed: abc123de-1234"
echo "🕒 Deployment time: 8 minutes 32 seconds"
echo "=================================================="
```

### 8.2 Slack Notification
```bash
# Send success notification to Slack
curl -X POST -H 'Content-type: application/json' \
    --data '{
        "text": "✅ *Deployment Successful!*\n• *Environment*: production\n• *Repository*: laravel-app\n• *Branch*: main\n• *Pusher*: developer\n• *Image*: abc123de-1234\n• *URL*: http://production-alb-123456789.us-east-1.elb.amazonaws.com"
    }' \
    $SLACK_WEBHOOK_URL
```

## 🧹 Bước 9: Cleanup

### 9.1 Remove Local Images
```bash
# Clean up local Docker images to save space
docker rmi 123456789012.dkr.ecr.us-east-1.amazonaws.com/laravel-app:abc123de-1234 || true
docker rmi 123456789012.dkr.ecr.us-east-1.amazonaws.com/laravel-app:latest || true
docker rmi 123456789012.dkr.ecr.us-east-1.amazonaws.com/laravel-app:production || true

# Clean up temporary files
rm -f task-definition.json updated-task-definition.json final-task-definition.json

# Docker system cleanup
docker system prune -f
```

## 📊 Monitoring & Verification

### 9.1 ECS Service Status
```bash
# Check final service status
aws ecs describe-services \
    --cluster production-laravel-cluster \
    --services production-laravel-service \
    --region us-east-1 \
    --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,TaskDefinition:taskDefinition}'

# Output:
{
  "Status": "ACTIVE",
  "Running": 2,
  "Desired": 2,
  "TaskDefinition": "arn:aws:ecs:us-east-1:123456789012:task-definition/production-laravel-task:6"
}
```

### 9.2 Application Verification
```bash
# Test application endpoints
curl -s http://$ALB_ENDPOINT/health | jq .
curl -s http://$ALB_ENDPOINT/ | grep -o "<title>.*</title>"

# Check application logs
aws logs tail /ecs/production-laravel-task --follow --since 5m
```

---

## 🎯 Tổng kết quy trình

**Thời gian**: ~8-12 phút
**Stages**: 9 bước chính
**Zero-downtime**: ✅ Rolling deployment
**Rollback**: ✅ Có thể rollback về version trước
**Monitoring**: ✅ Health checks và logs
**Security**: ✅ Image scanning và vulnerability checks
