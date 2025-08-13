#!/bin/bash

# Test Generic Webhook Trigger Script
# Sử dụng để test webhook trigger từ command line

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration - Cập nhật các giá trị này
JENKINS_URL="http://your-jenkins-server:8080"
WEBHOOK_TOKEN="laravel-deploy-secret-token-2024"
REPOSITORY_NAME="laravel-app"
BRANCH_NAME="main"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --jenkins-url)
            JENKINS_URL="$2"
            shift 2
            ;;
        --token)
            WEBHOOK_TOKEN="$2"
            shift 2
            ;;
        --repo)
            REPOSITORY_NAME="$2"
            shift 2
            ;;
        --branch)
            BRANCH_NAME="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --jenkins-url URL    Jenkins server URL (default: http://your-jenkins-server:8080)"
            echo "  --token TOKEN        Webhook token"
            echo "  --repo REPO          Repository name (default: laravel-app)"
            echo "  --branch BRANCH      Branch name (default: main)"
            echo "  --help               Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}🔗 Testing Generic Webhook Trigger${NC}"
echo "=================================================="
echo "Jenkins URL: $JENKINS_URL"
echo "Repository: $REPOSITORY_NAME"
echo "Branch: $BRANCH_NAME"
echo "Token: ${WEBHOOK_TOKEN:0:10}..."
echo "=================================================="

# Get current git information if in a git repository
if git rev-parse --git-dir > /dev/null 2>&1; then
    CURRENT_COMMIT=$(git rev-parse HEAD)
    CURRENT_BRANCH=$(git branch --show-current)
    COMMIT_MESSAGE=$(git log -1 --pretty=%B)
    AUTHOR_NAME=$(git log -1 --pretty=%an)
    
    echo -e "${YELLOW}📋 Git Information:${NC}"
    echo "Current Branch: $CURRENT_BRANCH"
    echo "Current Commit: ${CURRENT_COMMIT:0:8}"
    echo "Author: $AUTHOR_NAME"
    echo "Message: $COMMIT_MESSAGE"
    echo ""
else
    # Default values if not in git repository
    CURRENT_COMMIT="abc123def456789"
    COMMIT_MESSAGE="Manual webhook test"
    AUTHOR_NAME="test-user"
fi

# Construct webhook URL
WEBHOOK_URL="${JENKINS_URL}/generic-webhook-trigger/invoke?token=${WEBHOOK_TOKEN}"

# Create webhook payload (GitHub format)
WEBHOOK_PAYLOAD=$(cat <<EOF
{
    "ref": "refs/heads/${BRANCH_NAME}",
    "before": "0000000000000000000000000000000000000000",
    "after": "${CURRENT_COMMIT}",
    "repository": {
        "id": 123456789,
        "name": "${REPOSITORY_NAME}",
        "full_name": "your-org/${REPOSITORY_NAME}",
        "private": false,
        "html_url": "https://github.com/your-org/${REPOSITORY_NAME}",
        "clone_url": "https://github.com/your-org/${REPOSITORY_NAME}.git",
        "default_branch": "main"
    },
    "pusher": {
        "name": "${AUTHOR_NAME}",
        "email": "${AUTHOR_NAME}@example.com"
    },
    "head_commit": {
        "id": "${CURRENT_COMMIT}",
        "message": "${COMMIT_MESSAGE}",
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "author": {
            "name": "${AUTHOR_NAME}",
            "email": "${AUTHOR_NAME}@example.com"
        },
        "committer": {
            "name": "${AUTHOR_NAME}",
            "email": "${AUTHOR_NAME}@example.com"
        }
    },
    "commits": [
        {
            "id": "${CURRENT_COMMIT}",
            "message": "${COMMIT_MESSAGE}",
            "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
            "author": {
                "name": "${AUTHOR_NAME}",
                "email": "${AUTHOR_NAME}@example.com"
            },
            "committer": {
                "name": "${AUTHOR_NAME}",
                "email": "${AUTHOR_NAME}@example.com"
            }
        }
    ]
}
EOF
)

echo -e "${YELLOW}🚀 Sending webhook request...${NC}"
echo "URL: $WEBHOOK_URL"
echo ""

# Send webhook request
HTTP_STATUS=$(curl -w "%{http_code}" -s -o /tmp/webhook_response.txt \
    -X POST \
    -H "Content-Type: application/json" \
    -H "X-GitHub-Event: push" \
    -H "X-GitHub-Delivery: $(uuidgen)" \
    -d "$WEBHOOK_PAYLOAD" \
    "$WEBHOOK_URL")

# Check response
if [ "$HTTP_STATUS" -eq 200 ]; then
    echo -e "${GREEN}✅ Webhook sent successfully!${NC}"
    echo "HTTP Status: $HTTP_STATUS"
    
    # Show response
    if [ -s /tmp/webhook_response.txt ]; then
        echo ""
        echo -e "${YELLOW}📄 Response:${NC}"
        cat /tmp/webhook_response.txt
        echo ""
    fi
    
    echo ""
    echo -e "${BLUE}🔍 Next Steps:${NC}"
    echo "1. Check Jenkins job: ${JENKINS_URL}/job/laravel-production-deploy/"
    echo "2. Monitor build progress in Jenkins console"
    echo "3. Check build logs for webhook variables"
    
elif [ "$HTTP_STATUS" -eq 404 ]; then
    echo -e "${RED}❌ Webhook failed - Job not found${NC}"
    echo "HTTP Status: $HTTP_STATUS"
    echo ""
    echo "Possible issues:"
    echo "- Jenkins job name incorrect"
    echo "- Generic Webhook Trigger not configured"
    echo "- Token mismatch"
    
elif [ "$HTTP_STATUS" -eq 403 ]; then
    echo -e "${RED}❌ Webhook failed - Forbidden${NC}"
    echo "HTTP Status: $HTTP_STATUS"
    echo ""
    echo "Possible issues:"
    echo "- Incorrect webhook token"
    echo "- Jenkins security settings"
    echo "- IP restrictions"
    
else
    echo -e "${RED}❌ Webhook failed${NC}"
    echo "HTTP Status: $HTTP_STATUS"
    
    if [ -s /tmp/webhook_response.txt ]; then
        echo ""
        echo -e "${YELLOW}📄 Error Response:${NC}"
        cat /tmp/webhook_response.txt
        echo ""
    fi
fi

# Cleanup
rm -f /tmp/webhook_response.txt

echo ""
echo -e "${BLUE}📊 Webhook Test Summary${NC}"
echo "=================================================="
echo "Status: $([ "$HTTP_STATUS" -eq 200 ] && echo -e "${GREEN}SUCCESS${NC}" || echo -e "${RED}FAILED${NC}")"
echo "Jenkins URL: $JENKINS_URL"
echo "Repository: $REPOSITORY_NAME"
echo "Branch: refs/heads/$BRANCH_NAME"
echo "Commit: ${CURRENT_COMMIT:0:8}"
echo "=================================================="

# Additional debugging information
echo ""
echo -e "${YELLOW}🔧 Debugging Information:${NC}"
echo "Full webhook URL: $WEBHOOK_URL"
echo "Payload size: $(echo "$WEBHOOK_PAYLOAD" | wc -c) bytes"
echo "Timestamp: $(date)"

if [ "$HTTP_STATUS" -ne 200 ]; then
    echo ""
    echo -e "${YELLOW}💡 Troubleshooting Tips:${NC}"
    echo "1. Verify Jenkins is accessible: curl -I $JENKINS_URL"
    echo "2. Check Jenkins job exists: ${JENKINS_URL}/job/laravel-production-deploy/"
    echo "3. Verify Generic Webhook Trigger plugin is installed"
    echo "4. Check Jenkins system logs for errors"
    echo "5. Test with simple curl command:"
    echo "   curl -X POST '$WEBHOOK_URL' -H 'Content-Type: application/json' -d '{}'"
fi
