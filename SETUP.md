# 🚀 Setup Guide

## Prerequisites

- Docker & Docker Compose
- AWS CLI configured
- Jenkins server accessible
- GitHub repository with admin access

## Quick Setup

### 1. Environment Variables
```bash
export DB_PASSWORD=your-secure-password
export APP_KEY=base64:your-laravel-app-key
export JENKINS_URL=http://your-jenkins-server
export GITHUB_REPO=username/repository-name
```

### 2. Run Setup
```bash
./setup-cicd.sh
```

### 3. Configure Jenkins
1. Import `jenkins-job-config.xml` in Jenkins
2. Set up credentials:
   - `aws-credentials` (AWS access)
   - `github-credentials` (GitHub access)
   - `slack-token` (optional)

### 4. Setup GitHub Webhook
```
Repository → Settings → Webhooks → Add webhook
Payload URL: http://your-jenkins-server/github-webhook/
Content type: application/json
Events: Push, Pull Request
```

### 5. Test
```bash
git commit -m "Test deployment"
git push origin main
```

## Local Development

```bash
make up              # Start environment
make composer-install && make npm-install
make migrate         # Run migrations
make test           # Run tests
```

Access: http://localhost:8000

## Deployment

- **Push to main** → Production deployment
- **Push to develop** → Staging deployment
- **Manual**: Jenkins job with parameters

## Troubleshooting

### Webhook not triggering
- Check GitHub webhook delivery logs
- Verify Jenkins URL accessibility
- Check firewall/security groups

### Build fails
- Review Jenkins build logs
- Check AWS credentials
- Verify Docker daemon status

### Deployment fails
- Check ECS service events
- Review CloudWatch logs
- Verify security groups

## Support

- Jenkins: Monitor build logs
- AWS: Check ECS service status
- Logs: CloudWatch `/ecs/{environment}-laravel`
