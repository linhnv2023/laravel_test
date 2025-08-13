pipeline {
    agent any
    
    parameters {
        choice(name: 'ENVIRONMENT', choices: ['staging', 'production'], description: 'Deployment environment')
        booleanParam(name: 'RUN_TESTS', defaultValue: true, description: 'Run tests before deployment')
        booleanParam(name: 'RUN_MIGRATIONS', defaultValue: true, description: 'Run database migrations')
        booleanParam(name: 'SKIP_BUILD', defaultValue: false, description: 'Skip Docker build (use existing image)')
    }
    
    environment {
        AWS_DEFAULT_REGION = 'us-east-1'
        ECR_REPOSITORY = 'laravel-app'
        ECS_CLUSTER = 'production-laravel-cluster'
        DOCKER_BUILDKIT = '1'

        // Dynamic environment variables
        ECS_SERVICE = "${params.ENVIRONMENT}-laravel-service"
        IMAGE_TAG = "${env.GIT_COMMIT.take(8)}-${env.BUILD_NUMBER}"
        ECR_REGISTRY = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
    }
    
    stages {
        stage('Checkout & Setup') {
            steps {
                script {
                    // Get AWS Account ID
                    env.AWS_ACCOUNT_ID = sh(
                        script: 'aws sts get-caller-identity --query Account --output text',
                        returnStdout: true
                    ).trim()
                    
                    // Set full ECR registry URL
                    env.ECR_REGISTRY = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_DEFAULT_REGION}.amazonaws.com"
                    env.FULL_IMAGE_NAME = "${env.ECR_REGISTRY}/${env.ECR_REPOSITORY}:${env.IMAGE_TAG}"
                    
                    echo "Building image: ${env.FULL_IMAGE_NAME}"
                    echo "Deploying to: ${params.ENVIRONMENT}"
                }
            }
        }
        
        stage('Run Tests') {
            when {
                expression { params.RUN_TESTS }
            }
            parallel {
                stage('PHP Tests') {
                    steps {
                        script {
                            // Build test image
                            sh '''
                                docker build -t laravel-test:${BUILD_NUMBER} --target development .
                            '''
                            
                            // Run tests in container
                            sh '''
                                docker run --rm \
                                    -v ${WORKSPACE}:/var/www/html \
                                    -w /var/www/html \
                                    laravel-test:${BUILD_NUMBER} \
                                    bash -c "
                                        cp .env.example .env
                                        php artisan key:generate
                                        composer install --no-dev --optimize-autoloader
                                        php artisan test --junit=test-results.xml --coverage-clover=coverage.xml
                                    "
                            '''
                        }
                    }
                    post {
                        always {
                            // Publish test results
                            publishTestResults testResultsPattern: 'test-results.xml'
                            
                            // Publish coverage
                            publishHTML([
                                allowMissing: false,
                                alwaysLinkToLastBuild: true,
                                keepAll: true,
                                reportDir: 'coverage',
                                reportFiles: 'index.html',
                                reportName: 'Coverage Report'
                            ])
                            
                            // Clean up test image
                            sh 'docker rmi laravel-test:${BUILD_NUMBER} || true'
                        }
                    }
                }
                
                stage('Security Scan') {
                    steps {
                        script {
                            // Composer security audit
                            sh '''
                                docker run --rm -v ${WORKSPACE}:/app -w /app composer:latest \
                                    composer audit --format=json > composer-audit.json || true
                            '''
                            
                            // NPM security audit
                            sh '''
                                docker run --rm -v ${WORKSPACE}:/app -w /app node:20-alpine \
                                    npm audit --json > npm-audit.json || true
                            '''
                        }
                    }
                    post {
                        always {
                            archiveArtifacts artifacts: '*-audit.json', allowEmptyArchive: true
                        }
                    }
                }
                
                stage('Code Quality') {
                    steps {
                        script {
                            // Laravel Pint (PHP CS Fixer)
                            sh '''
                                docker run --rm -v ${WORKSPACE}:/app -w /app \
                                    php:8.3-cli bash -c "
                                        curl -sS https://getcomposer.org/installer | php
                                        php composer.phar install --no-dev
                                        vendor/bin/pint --test || true
                                    "
                            '''
                        }
                    }
                }
            }
        }
        
        stage('Build & Push Docker Image') {
            when {
                not { params.SKIP_BUILD }
            }
            steps {
                script {
                    // Login to ECR
                    sh '''
                        aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | \
                        docker login --username AWS --password-stdin ${ECR_REGISTRY}
                    '''
                    
                    // Create ECR repository if it doesn't exist
                    sh '''
                        aws ecr describe-repositories --repository-names ${ECR_REPOSITORY} --region ${AWS_DEFAULT_REGION} || \
                        aws ecr create-repository --repository-name ${ECR_REPOSITORY} --region ${AWS_DEFAULT_REGION} \
                            --image-scanning-configuration scanOnPush=true \
                            --encryption-configuration encryptionType=AES256
                    '''
                    
                    // Build production image
                    sh '''
                        docker build \
                            --target production \
                            --build-arg BUILDKIT_INLINE_CACHE=1 \
                            --cache-from ${ECR_REGISTRY}/${ECR_REPOSITORY}:latest \
                            -t ${FULL_IMAGE_NAME} \
                            -t ${ECR_REGISTRY}/${ECR_REPOSITORY}:latest \
                            -t ${ECR_REGISTRY}/${ECR_REPOSITORY}:${ENVIRONMENT} \
                            .
                    '''
                    
                    // Push images to ECR
                    sh '''
                        docker push ${FULL_IMAGE_NAME}
                        docker push ${ECR_REGISTRY}/${ECR_REPOSITORY}:latest
                        docker push ${ECR_REGISTRY}/${ECR_REPOSITORY}:${ENVIRONMENT}
                    '''
                    
                    // Scan image for vulnerabilities
                    sh '''
                        aws ecr start-image-scan \
                            --repository-name ${ECR_REPOSITORY} \
                            --image-id imageTag=${IMAGE_TAG} \
                            --region ${AWS_DEFAULT_REGION} || true
                    '''
                }
            }
            post {
                always {
                    // Clean up local images
                    sh '''
                        docker rmi ${FULL_IMAGE_NAME} || true
                        docker rmi ${ECR_REGISTRY}/${ECR_REPOSITORY}:latest || true
                        docker rmi ${ECR_REGISTRY}/${ECR_REPOSITORY}:${ENVIRONMENT} || true
                    '''
                }
            }
        }
        
        stage('Deploy to ECS') {
            steps {
                script {
                    // Update ECS task definition
                    sh '''
                        # Get current task definition
                        aws ecs describe-task-definition \
                            --task-definition ${ENVIRONMENT}-laravel-task \
                            --region ${AWS_DEFAULT_REGION} \
                            --query taskDefinition > task-definition.json
                        
                        # Update image in task definition
                        jq --arg IMAGE "${FULL_IMAGE_NAME}" \
                           '.containerDefinitions[0].image = $IMAGE' \
                           task-definition.json > updated-task-definition.json
                        
                        # Remove unnecessary fields
                        jq 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)' \
                           updated-task-definition.json > final-task-definition.json
                        
                        # Register new task definition
                        NEW_TASK_DEF=$(aws ecs register-task-definition \
                            --cli-input-json file://final-task-definition.json \
                            --region ${AWS_DEFAULT_REGION} \
                            --query 'taskDefinition.taskDefinitionArn' \
                            --output text)
                        
                        echo "New task definition: $NEW_TASK_DEF"
                        
                        # Update ECS service
                        aws ecs update-service \
                            --cluster ${ECS_CLUSTER} \
                            --service ${ECS_SERVICE} \
                            --task-definition $NEW_TASK_DEF \
                            --region ${AWS_DEFAULT_REGION}
                    '''
                }
            }
        }
        
        stage('Wait for Deployment') {
            steps {
                script {
                    timeout(time: 15, unit: 'MINUTES') {
                        sh '''
                            echo "Waiting for ECS service to stabilize..."
                            aws ecs wait services-stable \
                                --cluster ${ECS_CLUSTER} \
                                --services ${ECS_SERVICE} \
                                --region ${AWS_DEFAULT_REGION}
                        '''
                    }
                }
            }
        }
        
        stage('Run Migrations') {
            when {
                expression { params.RUN_MIGRATIONS }
            }
            steps {
                script {
                    sh '''
                        # Get subnet and security group info
                        PRIVATE_SUBNETS=$(aws cloudformation describe-stacks \
                            --stack-name ${ENVIRONMENT}-laravel-infrastructure \
                            --query 'Stacks[0].Outputs[?OutputKey==`PrivateSubnets`].OutputValue' \
                            --output text \
                            --region ${AWS_DEFAULT_REGION})
                        
                        ECS_SECURITY_GROUP=$(aws cloudformation describe-stacks \
                            --stack-name ${ENVIRONMENT}-laravel-infrastructure \
                            --query 'Stacks[0].Outputs[?OutputKey==`ECSSecurityGroup`].OutputValue' \
                            --output text \
                            --region ${AWS_DEFAULT_REGION})
                        
                        SUBNET_ID=$(echo "$PRIVATE_SUBNETS" | cut -d',' -f1)
                        
                        # Run migration task
                        TASK_ARN=$(aws ecs run-task \
                            --cluster ${ECS_CLUSTER} \
                            --task-definition ${ENVIRONMENT}-laravel-task \
                            --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID],securityGroups=[$ECS_SECURITY_GROUP],assignPublicIp=DISABLED}" \
                            --overrides '{
                                "containerOverrides": [
                                    {
                                        "name": "laravel-app",
                                        "command": ["php", "artisan", "migrate", "--force"]
                                    }
                                ]
                            }' \
                            --region ${AWS_DEFAULT_REGION} \
                            --query 'tasks[0].taskArn' \
                            --output text)
                        
                        echo "Migration task: $TASK_ARN"
                        
                        # Wait for migration to complete
                        aws ecs wait tasks-stopped \
                            --cluster ${ECS_CLUSTER} \
                            --tasks $TASK_ARN \
                            --region ${AWS_DEFAULT_REGION}
                        
                        # Check migration exit code
                        EXIT_CODE=$(aws ecs describe-tasks \
                            --cluster ${ECS_CLUSTER} \
                            --tasks $TASK_ARN \
                            --region ${AWS_DEFAULT_REGION} \
                            --query 'tasks[0].containers[0].exitCode' \
                            --output text)
                        
                        if [ "$EXIT_CODE" != "0" ]; then
                            echo "Migration failed with exit code: $EXIT_CODE"
                            exit 1
                        fi
                        
                        echo "Migration completed successfully"
                    '''
                }
            }
        }
        
        stage('Health Check') {
            steps {
                script {
                    // Get ALB endpoint
                    def albEndpoint = sh(
                        script: '''
                            aws elbv2 describe-load-balancers \
                                --names ${ENVIRONMENT}-laravel-alb \
                                --query 'LoadBalancers[0].DNSName' \
                                --output text \
                                --region ${AWS_DEFAULT_REGION}
                        ''',
                        returnStdout: true
                    ).trim()
                    
                    echo "Application URL: http://${albEndpoint}"
                    
                    // Health check with retry
                    retry(10) {
                        sleep(30)
                        sh "curl -f http://${albEndpoint}/health"
                    }
                    
                    echo "✅ Health check passed!"
                    echo "🚀 Application deployed successfully to ${params.ENVIRONMENT}"
                    echo "🌐 URL: http://${albEndpoint}"
                }
            }
        }
    }
    
    post {
        always {
            // Clean up workspace
            sh 'docker system prune -f || true'
            
            // Archive artifacts
            archiveArtifacts artifacts: '*.json,*.xml', allowEmptyArchive: true
        }
        
        success {
            script {
                def albEndpoint = sh(
                    script: '''
                        aws elbv2 describe-load-balancers \
                            --names ${ENVIRONMENT}-laravel-alb \
                            --query 'LoadBalancers[0].DNSName' \
                            --output text \
                            --region ${AWS_DEFAULT_REGION} 2>/dev/null || echo "N/A"
                    ''',
                    returnStdout: true
                ).trim()
                
                slackSend(
                    channel: '#deployments',
                    color: 'good',
                    message: """
✅ *Deployment Successful!*
• *Environment*: ${params.ENVIRONMENT}
• *Image*: ${env.IMAGE_TAG}
• *Commit*: ${env.GIT_COMMIT.take(8)}
• *Build*: #${env.BUILD_NUMBER}
• *URL*: http://${albEndpoint}
• *Duration*: ${currentBuild.durationString}
                    """.stripIndent()
                )
            }
        }
        
        failure {
            slackSend(
                channel: '#deployments',
                color: 'danger',
                message: """
❌ *Deployment Failed!*
• *Environment*: ${params.ENVIRONMENT}
• *Image*: ${env.IMAGE_TAG}
• *Commit*: ${env.GIT_COMMIT.take(8)}
• *Build*: #${env.BUILD_NUMBER}
• *Stage*: ${env.STAGE_NAME}
• *Duration*: ${currentBuild.durationString}
                """.stripIndent()
            )
        }
        
        unstable {
            slackSend(
                channel: '#deployments',
                color: 'warning',
                message: """
⚠️ *Deployment Unstable!*
• *Environment*: ${params.ENVIRONMENT}
• *Image*: ${env.IMAGE_TAG}
• *Commit*: ${env.GIT_COMMIT.take(8)}
• *Build*: #${env.BUILD_NUMBER}
• *Duration*: ${currentBuild.durationString}
                """.stripIndent()
            )
        }
    }
}
