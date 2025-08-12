pipeline {
    agent any
    
    parameters {
        string(name: 'IMAGE_TAG', defaultValue: 'latest', description: 'Docker image tag to deploy')
        string(name: 'ECR_REGISTRY', defaultValue: '', description: 'ECR registry URL')
        choice(name: 'ENVIRONMENT', choices: ['staging', 'production'], description: 'Deployment environment')
        booleanParam(name: 'RUN_MIGRATIONS', defaultValue: true, description: 'Run database migrations')
        booleanParam(name: 'SKIP_TESTS', defaultValue: false, description: 'Skip running tests')
    }
    
    environment {
        AWS_DEFAULT_REGION = 'us-east-1'
        ECR_REPOSITORY = 'laravel-app'
        ECS_CLUSTER = 'laravel-cluster'
        ECS_SERVICE_STAGING = 'laravel-service-staging'
        ECS_SERVICE_PRODUCTION = 'laravel-service-production'
        DOCKER_BUILDKIT = '1'
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()
                    env.BUILD_TIMESTAMP = sh(
                        script: 'date +%Y%m%d-%H%M%S',
                        returnStdout: true
                    ).trim()
                }
            }
        }
        
        stage('Environment Setup') {
            steps {
                script {
                    // Set environment-specific variables
                    if (params.ENVIRONMENT == 'production') {
                        env.ECS_SERVICE = env.ECS_SERVICE_PRODUCTION
                        env.DB_NAME = 'laravel_production'
                    } else {
                        env.ECS_SERVICE = env.ECS_SERVICE_STAGING
                        env.DB_NAME = 'laravel_staging'
                    }
                    
                    // Use provided ECR registry or default
                    if (params.ECR_REGISTRY) {
                        env.ECR_REGISTRY = params.ECR_REGISTRY
                    } else {
                        env.ECR_REGISTRY = sh(
                            script: 'aws sts get-caller-identity --query Account --output text',
                            returnStdout: true
                        ).trim() + '.dkr.ecr.' + env.AWS_DEFAULT_REGION + '.amazonaws.com'
                    }
                }
            }
        }
        
        stage('Build and Test') {
            when {
                not { params.SKIP_TESTS }
            }
            parallel {
                stage('PHP Tests') {
                    steps {
                        script {
                            docker.build("laravel-test:${env.BUILD_NUMBER}", "--target development .")
                            
                            docker.image("laravel-test:${env.BUILD_NUMBER}").inside(
                                "--network host -v ${WORKSPACE}:/var/www/html"
                            ) {
                                sh '''
                                    cp .env.example .env
                                    php artisan key:generate
                                    php artisan config:clear
                                    php artisan cache:clear
                                    composer install --no-dev --optimize-autoloader
                                    php artisan test --coverage --junit=test-results.xml
                                '''
                            }
                        }
                    }
                    post {
                        always {
                            publishTestResults testResultsPattern: 'test-results.xml'
                            publishHTML([
                                allowMissing: false,
                                alwaysLinkToLastBuild: true,
                                keepAll: true,
                                reportDir: 'coverage',
                                reportFiles: 'index.html',
                                reportName: 'Coverage Report'
                            ])
                        }
                    }
                }
                
                stage('Security Scan') {
                    steps {
                        script {
                            // Composer security audit
                            sh 'composer audit --format=json > composer-audit.json || true'
                            
                            // NPM security audit
                            sh 'npm audit --json > npm-audit.json || true'
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
                            sh 'vendor/bin/pint --test || true'
                            
                            // PHPStan
                            sh 'vendor/bin/phpstan analyse --error-format=junit > phpstan-report.xml || true'
                        }
                    }
                    post {
                        always {
                            publishTestResults testResultsPattern: 'phpstan-report.xml'
                        }
                    }
                }
            }
        }
        
        stage('Build Production Image') {
            steps {
                script {
                    // Login to ECR
                    sh 'aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY'
                    
                    // Build production image
                    def image = docker.build(
                        "${env.ECR_REGISTRY}/${env.ECR_REPOSITORY}:${params.IMAGE_TAG}",
                        "--target production --build-arg BUILDKIT_INLINE_CACHE=1 ."
                    )
                    
                    // Push to ECR
                    image.push()
                    image.push("${env.BUILD_NUMBER}")
                    
                    // Tag as latest if deploying to production
                    if (params.ENVIRONMENT == 'production') {
                        image.push('latest')
                    }
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
                            --task-definition laravel-task-${ENVIRONMENT} \
                            --query taskDefinition > task-definition.json
                        
                        # Update image in task definition
                        jq --arg IMAGE "${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}" \
                           '.containerDefinitions[0].image = $IMAGE' \
                           task-definition.json > updated-task-definition.json
                        
                        # Remove unnecessary fields
                        jq 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)' \
                           updated-task-definition.json > final-task-definition.json
                        
                        # Register new task definition
                        aws ecs register-task-definition \
                            --cli-input-json file://final-task-definition.json \
                            --query 'taskDefinition.taskDefinitionArn' \
                            --output text > task-definition-arn.txt
                        
                        # Update ECS service
                        aws ecs update-service \
                            --cluster $ECS_CLUSTER \
                            --service $ECS_SERVICE \
                            --task-definition $(cat task-definition-arn.txt)
                    '''
                }
            }
        }
        
        stage('Wait for Deployment') {
            steps {
                script {
                    timeout(time: 10, unit: 'MINUTES') {
                        sh '''
                            echo "Waiting for ECS service to stabilize..."
                            aws ecs wait services-stable \
                                --cluster $ECS_CLUSTER \
                                --services $ECS_SERVICE
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
                        # Run migration task
                        aws ecs run-task \
                            --cluster $ECS_CLUSTER \
                            --task-definition laravel-migration-task-${ENVIRONMENT} \
                            --network-configuration "awsvpcConfiguration={subnets=[${ECS_SUBNET_ID}],securityGroups=[${ECS_SECURITY_GROUP_ID}],assignPublicIp=ENABLED}" \
                            --overrides '{
                                "containerOverrides": [
                                    {
                                        "name": "laravel-app",
                                        "command": ["php", "artisan", "migrate", "--force"]
                                    }
                                ]
                            }' \
                            --query 'tasks[0].taskArn' \
                            --output text > migration-task-arn.txt
                        
                        # Wait for migration to complete
                        aws ecs wait tasks-stopped \
                            --cluster $ECS_CLUSTER \
                            --tasks $(cat migration-task-arn.txt)
                        
                        # Check migration task exit code
                        EXIT_CODE=$(aws ecs describe-tasks \
                            --cluster $ECS_CLUSTER \
                            --tasks $(cat migration-task-arn.txt) \
                            --query 'tasks[0].containers[0].exitCode' \
                            --output text)
                        
                        if [ "$EXIT_CODE" != "0" ]; then
                            echo "Migration failed with exit code: $EXIT_CODE"
                            exit 1
                        fi
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
                                --names laravel-alb-${ENVIRONMENT} \
                                --query 'LoadBalancers[0].DNSName' \
                                --output text
                        ''',
                        returnStdout: true
                    ).trim()
                    
                    // Health check with retry
                    retry(5) {
                        sleep(30)
                        sh "curl -f http://${albEndpoint}/health"
                    }
                }
            }
        }
    }
    
    post {
        always {
            // Clean up Docker images
            sh 'docker system prune -f'
            
            // Archive artifacts
            archiveArtifacts artifacts: '*.json,*.xml', allowEmptyArchive: true
        }
        
        success {
            // Notify success
            slackSend(
                channel: '#deployments',
                color: 'good',
                message: "✅ Deployment successful: ${env.JOB_NAME} #${env.BUILD_NUMBER} to ${params.ENVIRONMENT}\nImage: ${params.IMAGE_TAG}\nCommit: ${env.GIT_COMMIT_SHORT}"
            )
        }
        
        failure {
            // Notify failure
            slackSend(
                channel: '#deployments',
                color: 'danger',
                message: "❌ Deployment failed: ${env.JOB_NAME} #${env.BUILD_NUMBER} to ${params.ENVIRONMENT}\nImage: ${params.IMAGE_TAG}\nCommit: ${env.GIT_COMMIT_SHORT}"
            )
        }
        
        unstable {
            // Notify unstable build
            slackSend(
                channel: '#deployments',
                color: 'warning',
                message: "⚠️ Deployment unstable: ${env.JOB_NAME} #${env.BUILD_NUMBER} to ${params.ENVIRONMENT}\nImage: ${params.IMAGE_TAG}\nCommit: ${env.GIT_COMMIT_SHORT}"
            )
        }
    }
}
