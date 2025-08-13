#!/bin/bash

# Script để kiểm tra Jenkins job configuration

echo "🔍 Checking Jenkins Job Configuration"
echo "======================================"

# 1. Kiểm tra files trong repository
echo "1. Files in current repository:"
ls -la

echo ""
echo "2. Dockerfile content preview:"
if [ -f "Dockerfile" ]; then
    head -10 Dockerfile
else
    echo "❌ Dockerfile not found in repository"
fi

echo ""
echo "3. Git information:"
git remote -v
git branch
git log --oneline -5

echo ""
echo "4. Jenkins workspace simulation:"
echo "If Jenkins can't find Dockerfile, check:"
echo "- Repository URL in Jenkins job"
echo "- Branch name (main vs master)"
echo "- Git credentials if private repo"
echo "- Clean workspace option"

echo ""
echo "5. Quick fixes to try:"
echo "a) In Jenkins job -> Configure -> Source Code Management:"
echo "   - Repository URL: $(git remote get-url origin)"
echo "   - Branch: */$(git branch --show-current)"
echo ""
echo "b) Add 'Clean before checkout' in Additional Behaviours"
echo ""
echo "c) Or manually trigger checkout in Jenkinsfile"
