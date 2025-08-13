# Jenkins Setup Guide

## Required Environment Variables

Trong Jenkins, cần thiết lập các environment variables sau:

### Global Environment Variables
Vào **Manage Jenkins** → **Configure System** → **Global properties** → **Environment variables**:

```
AWS_ACCOUNT_ID=123456789012  # Thay bằng AWS Account ID thực tế
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...  # Nếu sử dụng Slack
```

### Jenkins Credentials
Vào **Manage Jenkins** → **Manage Credentials** → **Global** → **Add Credentials**:

1. **AWS Credentials**:
   - Kind: AWS Credentials
   - ID: `aws-credentials`
   - Access Key ID: Your AWS Access Key
   - Secret Access Key: Your AWS Secret Key
   - Description: `AWS credentials for ECR and ECS`

2. **GitHub Credentials** (nếu repo private):
   - Kind: Username with password
   - ID: `github-credentials`
   - Username: Your GitHub username
   - Password: Your GitHub Personal Access Token

3. **Slack Token** (tùy chọn):
   - Kind: Secret text
   - ID: `slack-token`
   - Secret: Your Slack Bot Token

## Pipeline Configuration

### Build Parameters
Khi tạo Jenkins job, thêm các parameters:

1. **Choice Parameter**:
   - Name: `ENVIRONMENT`
   - Choices: 
     ```
     staging
     production
     ```
   - Default Value: `production`

2. **Boolean Parameter**:
   - Name: `RUN_TESTS`
   - Default Value: `true`
   - Description: `Run tests before deployment`

3. **Boolean Parameter**:
   - Name: `RUN_MIGRATIONS`
   - Default Value: `true`
   - Description: `Run database migrations`

4. **Boolean Parameter**:
   - Name: `SKIP_BUILD`
   - Default Value: `false`
   - Description: `Skip Docker build (use existing image)`

## Required Jenkins Plugins

Cài đặt các plugins sau:

1. **Pipeline Plugin**
2. **Docker Pipeline Plugin**
3. **AWS Pipeline Plugin**
4. **GitHub Plugin**
5. **Generic Webhook Trigger Plugin** ⭐ (Quan trọng)
6. **Slack Notification Plugin**
7. **JUnit Plugin**
8. **HTML Publisher Plugin**
9. **Timestamper Plugin**
10. **Build Timeout Plugin**
11. **Workspace Cleanup Plugin**

## Docker Configuration

Đảm bảo Jenkins có thể chạy Docker:

```bash
# Thêm jenkins user vào docker group
sudo usermod -aG docker jenkins

# Restart Jenkins service
sudo systemctl restart jenkins

# Hoặc nếu chạy Jenkins trong Docker:
docker exec -u root jenkins usermod -aG docker jenkins
docker restart jenkins
```

## AWS IAM Permissions

Jenkins cần các permissions sau:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:DescribeRepositories",
                "ecr:CreateRepository",
                "ecr:PutImage",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
                "ecr:StartImageScan"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ecs:DescribeTaskDefinition",
                "ecs:RegisterTaskDefinition",
                "ecs:UpdateService",
                "ecs:DescribeServices",
                "ecs:RunTask",
                "ecs:DescribeTasks",
                "ecs:ListTasks"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "elbv2:DescribeLoadBalancers",
                "cloudformation:DescribeStacks",
                "sts:GetCallerIdentity"
            ],
            "Resource": "*"
        }
    ]
}
```

## Testing the Pipeline

1. Commit và push code lên GitHub
2. Webhook sẽ trigger Jenkins build tự động
3. Hoặc trigger manual từ Jenkins UI
4. Theo dõi build logs để debug nếu có lỗi

## Troubleshooting

### Common Issues:

1. **Docker permission denied**:
   ```bash
   sudo usermod -aG docker jenkins
   sudo systemctl restart jenkins
   ```

2. **AWS credentials not found**:
   - Kiểm tra AWS credentials trong Jenkins
   - Đảm bảo IAM user có đủ permissions

3. **ECR login failed**:
   ```bash
   aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
   ```

4. **ECS deployment timeout**:
   - Kiểm tra ECS service health
   - Xem ECS task logs
   - Kiểm tra security groups và networking
