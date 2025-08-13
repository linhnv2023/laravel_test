#!/bin/bash

# Monitor Deployment Script
# Theo dõi realtime quá trình deployment từ Jenkins → ECR → ECS

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
AWS_REGION="us-east-1"
ECR_REPOSITORY="laravel-app"
ECS_CLUSTER="production-laravel-cluster"
ECS_SERVICE="production-laravel-service"
JENKINS_URL="http://localhost:8080"
JENKINS_JOB="laravel-production-deploy"

# Parse arguments
BUILD_NUMBER=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --build-number)
            BUILD_NUMBER="$2"
            shift 2
            ;;
        --jenkins-url)
            JENKINS_URL="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}📊 Deployment Monitor${NC}"
echo "=================================================="
echo "Jenkins: $JENKINS_URL"
echo "Build: #$BUILD_NUMBER"
echo "Cluster: $ECS_CLUSTER"
echo "Service: $ECS_SERVICE"
echo "=================================================="

# Function to get Jenkins build status
get_jenkins_status() {
    if [ -n "$BUILD_NUMBER" ]; then
        curl -s "$JENKINS_URL/job/$JENKINS_JOB/$BUILD_NUMBER/api/json" | \
        jq -r '.result // "BUILDING"' 2>/dev/null || echo "UNKNOWN"
    else
        echo "N/A"
    fi
}

# Function to get current stage from Jenkins
get_jenkins_stage() {
    if [ -n "$BUILD_NUMBER" ]; then
        curl -s "$JENKINS_URL/job/$JENKINS_JOB/$BUILD_NUMBER/wfapi/describe" | \
        jq -r '.stages[] | select(.status == "IN_PROGRESS") | .name' 2>/dev/null || echo "Unknown"
    else
        echo "N/A"
    fi
}

# Function to check ECR image
check_ecr_image() {
    local image_tag="$1"
    aws ecr describe-images \
        --repository-name $ECR_REPOSITORY \
        --image-ids imageTag=$image_tag \
        --region $AWS_REGION \
        --query 'imageDetails[0].imagePushedAt' \
        --output text 2>/dev/null || echo "None"
}

# Function to get ECS service status
get_ecs_status() {
    aws ecs describe-services \
        --cluster $ECS_CLUSTER \
        --services $ECS_SERVICE \
        --region $AWS_REGION \
        --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,Pending:pendingCount}' \
        --output json 2>/dev/null || echo '{"Status":"Unknown","Running":0,"Desired":0,"Pending":0}'
}

# Function to get latest ECS events
get_ecs_events() {
    aws ecs describe-services \
        --cluster $ECS_CLUSTER \
        --services $ECS_SERVICE \
        --region $AWS_REGION \
        --query 'services[0].events[0:3].[createdAt,message]' \
        --output text 2>/dev/null | head -3
}

# Function to get ALB health
check_alb_health() {
    local alb_dns=$(aws elbv2 describe-load-balancers \
        --names production-laravel-alb \
        --query 'LoadBalancers[0].DNSName' \
        --output text \
        --region $AWS_REGION 2>/dev/null)
    
    if [ "$alb_dns" != "None" ] && [ -n "$alb_dns" ]; then
        if curl -f -s "http://$alb_dns/health" > /dev/null 2>&1; then
            echo "✅ Healthy"
        else
            echo "❌ Unhealthy"
        fi
    else
        echo "⚠️ ALB not found"
    fi
}

# Function to display status
display_status() {
    clear
    echo -e "${BLUE}📊 Real-time Deployment Monitor${NC}"
    echo "=================================================="
    echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # Jenkins Status
    echo -e "${YELLOW}🔧 Jenkins Pipeline${NC}"
    local jenkins_status=$(get_jenkins_status)
    local jenkins_stage=$(get_jenkins_stage)
    
    case $jenkins_status in
        "SUCCESS")
            echo -e "Status: ${GREEN}✅ SUCCESS${NC}"
            ;;
        "FAILURE")
            echo -e "Status: ${RED}❌ FAILED${NC}"
            ;;
        "BUILDING")
            echo -e "Status: ${CYAN}🔄 BUILDING${NC}"
            ;;
        *)
            echo -e "Status: ${YELLOW}⚠️ $jenkins_status${NC}"
            ;;
    esac
    
    echo "Current Stage: $jenkins_stage"
    echo "Build URL: $JENKINS_URL/job/$JENKINS_JOB/$BUILD_NUMBER/"
    echo ""
    
    # ECR Status
    echo -e "${YELLOW}📦 ECR Repository${NC}"
    local latest_images=$(aws ecr describe-images \
        --repository-name $ECR_REPOSITORY \
        --region $AWS_REGION \
        --query 'sort_by(imageDetails,&imagePushedAt)[-3:].{Tag:imageTags[0],Pushed:imagePushedAt,Size:imageSizeInBytes}' \
        --output table 2>/dev/null || echo "No images found")
    
    echo "$latest_images"
    echo ""
    
    # ECS Status
    echo -e "${YELLOW}🚀 ECS Service${NC}"
    local ecs_status=$(get_ecs_status)
    local status=$(echo "$ecs_status" | jq -r '.Status')
    local running=$(echo "$ecs_status" | jq -r '.Running')
    local desired=$(echo "$ecs_status" | jq -r '.Desired')
    local pending=$(echo "$ecs_status" | jq -r '.Pending')
    
    echo "Status: $status"
    echo "Tasks: $running/$desired running, $pending pending"
    
    # ECS Events
    echo ""
    echo -e "${CYAN}📋 Recent Events:${NC}"
    get_ecs_events | while read -r line; do
        if [ -n "$line" ]; then
            echo "  $line"
        fi
    done
    echo ""
    
    # Health Check
    echo -e "${YELLOW}🏥 Application Health${NC}"
    local health_status=$(check_alb_health)
    echo "Health Check: $health_status"
    
    # Get ALB URL
    local alb_dns=$(aws elbv2 describe-load-balancers \
        --names production-laravel-alb \
        --query 'LoadBalancers[0].DNSName' \
        --output text \
        --region $AWS_REGION 2>/dev/null)
    
    if [ "$alb_dns" != "None" ] && [ -n "$alb_dns" ]; then
        echo "URL: http://$alb_dns"
    fi
    
    echo ""
    echo "=================================================="
    echo "Press Ctrl+C to exit monitoring"
}

# Function to monitor deployment
monitor_deployment() {
    local max_iterations=120  # 10 minutes (5s intervals)
    local iteration=0
    
    while [ $iteration -lt $max_iterations ]; do
        display_status
        
        # Check if deployment is complete
        local jenkins_status=$(get_jenkins_status)
        if [ "$jenkins_status" = "SUCCESS" ]; then
            echo ""
            echo -e "${GREEN}🎉 Deployment completed successfully!${NC}"
            break
        elif [ "$jenkins_status" = "FAILURE" ]; then
            echo ""
            echo -e "${RED}❌ Deployment failed!${NC}"
            echo "Check Jenkins logs: $JENKINS_URL/job/$JENKINS_JOB/$BUILD_NUMBER/console"
            break
        fi
        
        sleep 5
        ((iteration++))
    done
    
    if [ $iteration -eq $max_iterations ]; then
        echo ""
        echo -e "${YELLOW}⏰ Monitoring timeout reached${NC}"
    fi
}

# Function to show deployment summary
show_summary() {
    echo ""
    echo -e "${BLUE}📊 Deployment Summary${NC}"
    echo "=================================================="
    
    # Final Jenkins status
    local jenkins_status=$(get_jenkins_status)
    echo "Jenkins Build: $jenkins_status"
    
    # Final ECS status
    local ecs_status=$(get_ecs_status)
    echo "ECS Service: $(echo "$ecs_status" | jq -r '.Status')"
    echo "Running Tasks: $(echo "$ecs_status" | jq -r '.Running')/$(echo "$ecs_status" | jq -r '.Desired')"
    
    # Application health
    local health_status=$(check_alb_health)
    echo "Health Check: $health_status"
    
    # Get application URL
    local alb_dns=$(aws elbv2 describe-load-balancers \
        --names production-laravel-alb \
        --query 'LoadBalancers[0].DNSName' \
        --output text \
        --region $AWS_REGION 2>/dev/null)
    
    if [ "$alb_dns" != "None" ] && [ -n "$alb_dns" ]; then
        echo "Application URL: http://$alb_dns"
    fi
    
    echo "=================================================="
}

# Trap Ctrl+C
trap 'echo -e "\n${YELLOW}Monitoring stopped by user${NC}"; show_summary; exit 0' INT

# Main execution
if [ -z "$BUILD_NUMBER" ]; then
    echo -e "${YELLOW}⚠️ No build number specified${NC}"
    echo "Usage: $0 --build-number <number> [--jenkins-url <url>]"
    echo ""
    echo "Getting latest build number..."
    
    # Try to get latest build number
    LATEST_BUILD=$(curl -s "$JENKINS_URL/job/$JENKINS_JOB/api/json" | jq -r '.lastBuild.number' 2>/dev/null)
    
    if [ "$LATEST_BUILD" != "null" ] && [ -n "$LATEST_BUILD" ]; then
        BUILD_NUMBER=$LATEST_BUILD
        echo "Using latest build: #$BUILD_NUMBER"
    else
        echo -e "${RED}❌ Could not get build number${NC}"
        exit 1
    fi
fi

# Start monitoring
echo -e "${CYAN}🔍 Starting deployment monitoring...${NC}"
echo "Monitoring build #$BUILD_NUMBER"
echo ""

monitor_deployment
show_summary
