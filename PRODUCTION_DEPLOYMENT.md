# 🚀 Production Deployment Guide

## Quy trình GitHub → Webhook → Jenkins → ECR → ECS → Production

### Tổng quan quy trình
```
Developer Push Code → GitHub → Webhook → Jenkins → Build & Test → ECR → ECS → Production
```

## 📋 Checklist trước khi deploy

### ✅ AWS Infrastructure
- [ ] VPC và subnets đã được tạo
- [ ] ECS Cluster đã được tạo
- [ ] ECR Repository đã được tạo
- [ ] RDS Database đã được tạo
- [ ] ElastiCache Redis đã được tạo
- [ ] Application Load Balancer đã được tạo
- [ ] Security Groups đã được cấu hình

### ✅ Jenkins Setup
- [ ] Jenkins server đã được cài đặt
- [ ] Các plugins cần thiết đã được cài đặt
- [ ] AWS credentials đã được cấu hình
- [ ] Docker đã được cấu hình
- [ ] Pipeline job đã được tạo

### ✅ GitHub Setup
- [ ] Repository đã có Jenkinsfile
- [ ] Webhook đã được cấu hình
- [ ] Credentials đã được thiết lập (nếu repo private)

## 🚀 Deployment Steps

### Bước 1: Chuẩn bị Infrastructure

```bash
# 1. Tạo ECR repository
aws ecr create-repository \
    --repository-name laravel-app \
    --region us-east-1 \
    --image-scanning-configuration scanOnPush=true

# 2. Deploy infrastructure
aws cloudformation deploy \
    --template-file aws/cloudformation/ecs-infrastructure.yml \
    --stack-name production-laravel-infrastructure \
    --parameter-overrides \
        Environment=production \
        DBPassword=YourSecurePassword123! \
    --capabilities CAPABILITY_IAM \
    --region us-east-1

# 3. Deploy ECS services
aws cloudformation deploy \
    --template-file aws/cloudformation/ecs-services.yml \
    --stack-name production-laravel-services \
    --parameter-overrides \
        Environment=production \
        ImageURI=123456789012.dkr.ecr.us-east-1.amazonaws.com/laravel-app:latest \
    --capabilities CAPABILITY_IAM \
    --region us-east-1
```

### Bước 2: Cấu hình Jenkins

1. **Tạo Jenkins Pipeline Job**:
   - Name: `laravel-production-deploy`
   - Type: Pipeline
   - Source: SCM (GitHub)
   - Script Path: `Jenkinsfile`

2. **Cấu hình Build Parameters**:
   - ENVIRONMENT: Choice (staging/production)
   - RUN_TESTS: Boolean (default: true)
   - RUN_MIGRATIONS: Boolean (default: true)
   - SKIP_BUILD: Boolean (default: false)

3. **Cấu hình Build Triggers**:
   - ✅ GitHub hook trigger for GITScm polling

### Bước 3: Deploy lần đầu

```bash
# Cấp quyền execute cho script
chmod +x deploy-production.sh

# Chạy deployment script
./deploy-production.sh
```

### Bước 4: Kiểm tra deployment

```bash
# Kiểm tra ECS service
aws ecs describe-services \
    --cluster production-laravel-cluster \
    --services production-laravel-service \
    --region us-east-1

# Kiểm tra tasks đang chạy
aws ecs list-tasks \
    --cluster production-laravel-cluster \
    --service-name production-laravel-service \
    --region us-east-1

# Lấy URL của Load Balancer
aws elbv2 describe-load-balancers \
    --names production-laravel-alb \
    --query 'LoadBalancers[0].DNSName' \
    --output text \
    --region us-east-1
```

## 🔄 Automatic Deployment Process

Sau khi setup xong, quy trình tự động sẽ hoạt động như sau:

1. **Developer push code** lên GitHub
2. **GitHub webhook** trigger Jenkins build
3. **Jenkins pipeline** thực hiện:
   - Checkout code
   - Run tests (PHP tests, security scan, code quality)
   - Build Docker image
   - Push image to ECR
   - Update ECS task definition
   - Deploy to ECS
   - Run database migrations
   - Perform health check
   - Send notification (Slack)

## 📊 Monitoring & Logging

### CloudWatch Logs
```bash
# Xem logs của ECS tasks
aws logs describe-log-groups --log-group-name-prefix "/ecs/production-laravel"

# Tail logs realtime
aws logs tail /ecs/production-laravel-task --follow
```

### Application Metrics
- ECS Service metrics trong CloudWatch
- ALB metrics (request count, latency, errors)
- RDS metrics (connections, CPU, memory)
- ElastiCache metrics

## 🛠️ Troubleshooting

### Common Issues

1. **ECS Task không start**:
   ```bash
   # Kiểm tra task definition
   aws ecs describe-task-definition --task-definition production-laravel-task
   
   # Kiểm tra task logs
   aws logs tail /ecs/production-laravel-task --follow
   ```

2. **Health check failed**:
   ```bash
   # Test health endpoint
   curl -v http://your-alb-endpoint/health
   
   # Kiểm tra security groups
   aws ec2 describe-security-groups --group-ids sg-xxxxxxxxx
   ```

3. **Database connection issues**:
   ```bash
   # Kiểm tra RDS status
   aws rds describe-db-clusters --db-cluster-identifier production-laravel-rds
   
   # Test connection từ ECS task
   aws ecs run-task --cluster production-laravel-cluster \
     --task-definition production-laravel-task \
     --overrides '{"containerOverrides":[{"name":"laravel-app","command":["php","artisan","tinker"]}]}'
   ```

## 🔐 Security Best Practices

1. **Environment Variables**: Sử dụng AWS Systems Manager Parameter Store hoặc Secrets Manager
2. **IAM Roles**: Sử dụng task roles thay vì hardcode credentials
3. **Network Security**: Cấu hình security groups chặt chẽ
4. **SSL/TLS**: Sử dụng HTTPS với ACM certificates
5. **Database**: Enable encryption at rest và in transit

## 📈 Scaling & Performance

### Auto Scaling
```bash
# Cấu hình ECS Service Auto Scaling
aws application-autoscaling register-scalable-target \
    --service-namespace ecs \
    --scalable-dimension ecs:service:DesiredCount \
    --resource-id service/production-laravel-cluster/production-laravel-service \
    --min-capacity 2 \
    --max-capacity 10
```

### Performance Optimization
- Enable Laravel caching (config, routes, views)
- Use Redis for sessions và cache
- Optimize database queries
- Use CDN for static assets
- Enable gzip compression

## 🎯 Next Steps

1. **Setup monitoring**: CloudWatch dashboards, alerts
2. **Implement logging**: Centralized logging với ELK stack
3. **Setup backup**: Automated RDS snapshots
4. **Implement blue-green deployment**: Zero-downtime deployments
5. **Setup staging environment**: Test changes trước khi production
