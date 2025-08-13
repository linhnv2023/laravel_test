# 🔧 Jenkins Configuration Steps

## Bước 1: Cấu hình AWS Credentials

### 1.1 Thêm AWS Credentials
1. Vào **Manage Jenkins** → **Manage Credentials**
2. Click **Global** → **Add Credentials**
3. Chọn **Kind**: `AWS Credentials`
4. Điền thông tin:
   ```
   ID: aws-credentials
   Access Key ID: AKIA... (AWS Access Key của bạn)
   Secret Access Key: ... (AWS Secret Key của bạn)
   Description: AWS credentials for ECR and ECS
   ```
5. Click **OK**

### 1.2 Kiểm tra AWS CLI trong Jenkins
Vào job → **Build Now** → **Console Output** để xem có lỗi AWS không.

## Bước 2: Cấu hình Environment Variables

### 2.1 Global Environment Variables
1. Vào **Manage Jenkins** → **Configure System**
2. Tìm **Global properties** → **Environment variables**
3. Thêm các biến:
   ```
   AWS_ACCOUNT_ID=123456789012  (Thay bằng Account ID thực tế)
   AWS_DEFAULT_REGION=us-east-1
   ```

### 2.2 Lấy AWS Account ID
Nếu chưa biết AWS Account ID:
```bash
aws sts get-caller-identity --query Account --output text
```

## Bước 3: Cấu hình Docker trong Jenkins

### 3.1 Kiểm tra Docker
SSH vào Jenkins server và chạy:
```bash
# Kiểm tra Docker
docker --version
docker ps

# Thêm jenkins user vào docker group (nếu chưa)
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

### 3.2 Test Docker trong Jenkins
Tạo một test job với script:
```bash
docker --version
docker ps
whoami
groups
```

## Bước 4: Cấu hình Pipeline Job

### 4.1 Tạo Pipeline Job
1. **New Item** → **Pipeline**
2. Name: `laravel-production-deploy`
3. **OK**

### 4.2 General Configuration
- ✅ **Discard old builds**: Keep 10 builds
- ✅ **This project is parameterized**:
  
  **Choice Parameter 1:**
  ```
  Name: ENVIRONMENT
  Choices: 
  staging
  production
  Default Value: production
  Description: Deployment environment
  ```
  
  **Boolean Parameter 1:**
  ```
  Name: RUN_TESTS
  Default Value: ✅ Checked
  Description: Run tests before deployment
  ```
  
  **Boolean Parameter 2:**
  ```
  Name: RUN_MIGRATIONS
  Default Value: ✅ Checked
  Description: Run database migrations
  ```
  
  **Boolean Parameter 3:**
  ```
  Name: SKIP_BUILD
  Default Value: ❌ Unchecked
  Description: Skip Docker build (use existing image)
  ```

### 4.3 Build Triggers
✅ **Generic Webhook Trigger**

**Post content parameters:**
```
Variable: BRANCH_NAME     | Expression: $.ref
Variable: COMMIT_SHA      | Expression: $.after
Variable: REPOSITORY_NAME | Expression: $.repository.name
Variable: PUSHER_NAME     | Expression: $.pusher.name
Variable: COMMIT_MESSAGE  | Expression: $.head_commit.message
```

**Token:**
```
laravel-deploy-secret-token-2024
```

**Optional filter:**
```
Expression: $ref
Text: refs/heads/main
```

**Cause:**
```
Triggered by GitHub webhook for $repository.name
```

### 4.4 Pipeline Configuration
**Definition:** Pipeline script from SCM

**SCM:** Git
```
Repository URL: https://github.com/your-username/your-repo.git
Credentials: (Thêm GitHub credentials nếu repo private)
Branch Specifier: */main
Script Path: Jenkinsfile
```

**Additional Behaviours:**
- ✅ **Clean before checkout**
- ✅ **Clean after checkout**

## Bước 5: Test Pipeline

### 5.1 Manual Test
1. Vào job → **Build with Parameters**
2. Chọn:
   - ENVIRONMENT: `staging` (để test trước)
   - RUN_TESTS: ✅
   - RUN_MIGRATIONS: ❌ (skip migration lần đầu)
   - SKIP_BUILD: ❌
3. Click **Build**

### 5.2 Kiểm tra Console Output
Xem **Console Output** để debug:
- AWS credentials có hoạt động không
- Docker có chạy được không
- Git checkout có thành công không
- Webhook variables có được parse không

## Bước 6: Troubleshooting Common Issues

### 6.1 AWS Permission Denied
```bash
# Kiểm tra AWS credentials
aws sts get-caller-identity

# Nếu lỗi, thêm credentials:
aws configure
```

### 6.2 Docker Permission Denied
```bash
# Thêm jenkins vào docker group
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins

# Hoặc nếu Jenkins chạy trong Docker:
docker exec -u root jenkins-container usermod -aG docker jenkins
docker restart jenkins-container
```

### 6.3 Git Checkout Failed
- Kiểm tra repository URL
- Thêm GitHub credentials nếu repo private
- Kiểm tra branch name (main vs master)

### 6.4 ECR Repository Not Found
```bash
# Tạo ECR repository
aws ecr create-repository \
    --repository-name laravel-app \
    --region us-east-1
```

### 6.5 ECS Cluster Not Found
```bash
# Kiểm tra ECS cluster
aws ecs describe-clusters \
    --clusters production-laravel-cluster \
    --region us-east-1

# Nếu chưa có, deploy CloudFormation stack trước
```

## Bước 7: Monitor First Build

### 7.1 Các Stage cần chú ý:
1. **Webhook Info & Setup** - Kiểm tra webhook variables
2. **Run Tests** - Đảm bảo tests pass
3. **Build & Push Docker Image** - ECR login và push
4. **Deploy to ECS** - Update service
5. **Health Check** - Application accessible

### 7.2 Expected Output:
```
=== Webhook Information ===
Branch: refs/heads/main
Commit: abc123def
Repository: laravel-app
Pusher: your-username
==========================

Building image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/laravel-app:abc123de-123
Deploying to: production
```

## Bước 8: Fix Issues Step by Step

### Nếu Stage 1 (Setup) fails:
- Kiểm tra AWS credentials
- Kiểm tra AWS Account ID

### Nếu Stage 2 (Tests) fails:
- Kiểm tra Docker permissions
- Kiểm tra Dockerfile syntax

### Nếu Stage 3 (Build) fails:
- Kiểm tra ECR repository exists
- Kiểm tra ECR permissions

### Nếu Stage 4 (Deploy) fails:
- Kiểm tra ECS cluster exists
- Kiểm tra ECS service exists
- Kiểm tra task definition

## 🎯 Next Steps After Successful Build

1. **Check Application**: Visit ALB endpoint
2. **Monitor ECS**: Check tasks are running
3. **Test Webhook**: Push another commit
4. **Setup Notifications**: Configure Slack (optional)
5. **Production Deploy**: Change ENVIRONMENT to production
