# 🔗 Jenkins Generic Webhook Trigger Setup

## Cài đặt Plugin

1. Vào **Manage Jenkins** → **Manage Plugins**
2. Tab **Available**, tìm kiếm "Generic Webhook Trigger"
3. Cài đặt plugin và restart Jenkins

## Cấu hình Jenkins Job với Generic Webhook Trigger

### 1. Tạo Pipeline Job

1. **New Item** → **Pipeline** → Name: `laravel-production-deploy`

### 2. Cấu hình Build Triggers

Trong phần **Build Triggers**, chọn **Generic Webhook Trigger** và cấu hình:

#### Post content parameters:
```
Variable: BRANCH_NAME
Expression: $.ref
JSONPath: $.ref

Variable: COMMIT_SHA
Expression: $.after
JSONPath: $.after

Variable: REPOSITORY_NAME
Expression: $.repository.name
JSONPath: $.repository.name

Variable: PUSHER_NAME
Expression: $.pusher.name
JSONPath: $.pusher.name

Variable: COMMIT_MESSAGE
Expression: $.head_commit.message
JSONPath: $.head_commit.message
```

#### Header parameters (Optional):
```
Variable: GITHUB_EVENT
Header name: X-GitHub-Event
```

#### Request parameters:
```
Variable: WEBHOOK_TOKEN
Parameter name: token
```

#### Token:
```
Token: laravel-deploy-secret-token-2024
```

#### Optional filter:
```
Expression: $ref
Text: refs/heads/main
```
*Chỉ trigger khi push vào main branch*

#### Cause:
```
Triggered by GitHub webhook for $repository.name
```

### 3. Webhook URL

Sau khi cấu hình, webhook URL sẽ là:
```
http://your-jenkins-server:8080/generic-webhook-trigger/invoke?token=laravel-deploy-secret-token-2024
```

## Cấu hình GitHub Webhook

### 1. Trong GitHub Repository

1. Vào **Settings** → **Webhooks** → **Add webhook**

### 2. Webhook Configuration

```
Payload URL: http://your-jenkins-server:8080/generic-webhook-trigger/invoke?token=laravel-deploy-secret-token-2024
Content type: application/json
Secret: (để trống hoặc thêm secret key)
SSL verification: Enable SSL verification (nếu Jenkins có HTTPS)
```

### 3. Events

Chọn **Let me select individual events**:
- ✅ Pushes
- ✅ Pull requests (nếu muốn test PR)

### 4. Active
- ✅ Active

## Cập nhật Jenkinsfile để sử dụng Webhook Variables

<function_calls>
<invoke name="str-replace-editor">
<parameter name="command">str_replace
