# ⚡ Quick Generic Webhook Trigger Setup

## 🚀 5-Minute Setup Guide

### 1. Cài đặt Plugin (2 phút)
```
Manage Jenkins → Manage Plugins → Available → "Generic Webhook Trigger" → Install
```

### 2. Cấu hình Jenkins Job (2 phút)

#### Build Triggers Section:
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

### 3. GitHub Webhook (1 phút)

**URL:**
```
http://your-jenkins-server:8080/generic-webhook-trigger/invoke?token=laravel-deploy-secret-token-2024
```

**Settings:**
- Content type: `application/json`
- Events: `Pushes`
- Active: ✅

## 🧪 Test Webhook

### Quick Test:
```bash
chmod +x test-webhook.sh
./test-webhook.sh --jenkins-url http://your-jenkins:8080 --token laravel-deploy-secret-token-2024
```

### Manual Test:
```bash
curl -X POST \
  'http://your-jenkins:8080/generic-webhook-trigger/invoke?token=laravel-deploy-secret-token-2024' \
  -H 'Content-Type: application/json' \
  -H 'X-GitHub-Event: push' \
  -d '{
    "ref": "refs/heads/main",
    "after": "abc123",
    "repository": {"name": "laravel-app"},
    "pusher": {"name": "developer"},
    "head_commit": {"message": "Test deployment"}
  }'
```

## 🔍 Verify Setup

### ✅ Checklist:
- [ ] Generic Webhook Trigger plugin installed
- [ ] Jenkins job configured with webhook trigger
- [ ] Token matches between Jenkins and GitHub
- [ ] GitHub webhook shows green checkmark
- [ ] Test webhook returns HTTP 200

### 🐛 Common Issues:

**404 Error:**
- Check job name and URL
- Verify plugin is installed

**403 Error:**
- Check token spelling
- Verify Jenkins security settings

**No trigger:**
- Check branch filter (refs/heads/main)
- Verify webhook payload format

## 🎯 Expected Flow

1. **Push to GitHub** → Webhook sent
2. **Jenkins receives** → Variables parsed
3. **Pipeline starts** → Webhook info displayed
4. **Build & Deploy** → Success notification

## 📊 Webhook Variables in Pipeline

Your Jenkinsfile now has access to:
- `${env.BRANCH_NAME}` - refs/heads/main
- `${env.COMMIT_SHA}` - Full commit hash
- `${env.REPOSITORY_NAME}` - Repository name
- `${env.PUSHER_NAME}` - Who pushed
- `${env.COMMIT_MESSAGE}` - Commit message

## 🔐 Security Notes

- Use strong, unique tokens
- Consider IP whitelisting
- Use HTTPS for production
- Rotate tokens periodically

## 📞 Support

If webhook doesn't work:
1. Check Jenkins System Log
2. Check GitHub webhook delivery logs
3. Test with curl command above
4. Verify all configurations match this guide
