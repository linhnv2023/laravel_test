pipeline {
    agent any
    
    environment {
        AWS_DEFAULT_REGION = 'us-east-1'
        ECR_REPOSITORY = 'laravel-app'
        IMAGE_TAG = "${BUILD_NUMBER}"
    }
    
    stages {
        stage('Setup') {
            steps {
                withCredentials([aws(credentialsId: 'aws-ecr-credentials')]) {
                    script {
                        echo "Starting deployment..."
                        env.AWS_ACCOUNT_ID = sh(script: 'aws sts get-caller-identity --query Account --output text', returnStdout: true).trim()
                        env.FULL_IMAGE_NAME = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_DEFAULT_REGION}.amazonaws.com/${env.ECR_REPOSITORY}:${env.IMAGE_TAG}"
                        echo "Image: ${env.FULL_IMAGE_NAME}"
                    }
                }
            }
        }
        
        stage('Pre-Build Check') {
            steps {
                withCredentials([aws(credentialsId: 'aws-ecr-credentials')]) {
                    sh '''
                        echo "Checking prerequisites..."

                        # Check Docker
                        docker --version
                        docker ps

                        # Check AWS CLI
                        aws --version
                        aws sts get-caller-identity

                        # Check workspace files
                        echo "Workspace contents:"
                        ls -la

                        # Check Dockerfile exists
                        if [ -f "Dockerfile" ]; then
                            echo "✅ Dockerfile found"
                        else
                            echo "❌ Dockerfile not found"
                            exit 1
                        fi

                        # Check source code
                        ls -la composer.json || echo "No composer.json found"
                        ls -la package.json || echo "No package.json found"

                        echo "✅ Pre-build checks completed"
                    '''
                }
            }
        }

        stage('Build & Push to ECR') {
            steps {
                withCredentials([aws(credentialsId: 'aws-ecr-credentials')]) {
                    sh '''
                        echo "Starting build and push to ECR..."

                        # Login to ECR
                        echo "Logging into ECR..."
                        aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com

                        # Create ECR repository if not exists
                        echo "Checking ECR repository..."
                        aws ecr describe-repositories --repository-names ${ECR_REPOSITORY} --region ${AWS_DEFAULT_REGION} || aws ecr create-repository --repository-name ${ECR_REPOSITORY} --region ${AWS_DEFAULT_REGION}

                        # Build Docker image
                        echo "Building Docker image..."
                        docker build -t ${FULL_IMAGE_NAME} .

                        # Push to ECR
                        echo "Pushing image to ECR..."
                        docker push ${FULL_IMAGE_NAME}

                        echo "✅ Build and push completed successfully"
                    '''
                }
            }
        }
        

    }
    
    post {
        always {
            sh 'docker system prune -f || true'
            sh 'rm -f *.json || true'
        }
        success {
            echo "✅ Build and push to ECR successful!"
        }
        failure {
            echo "❌ Build and push to ECR failed!"
        }
    }
}
