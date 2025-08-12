# Laravel CI/CD Project

A complete Laravel application with full CI/CD pipeline using GitHub Actions, Jenkins, AWS, and Docker.

## 🚀 Features

- **Modern Laravel 12** with PHP 8.3
- **Complete CI/CD Pipeline** with GitHub Actions and Jenkins
- **AWS Cloud Infrastructure** with ECS, RDS, ElastiCache, and ALB
- **Docker Containerization** with multi-stage builds
- **Automated Testing** with PHPUnit and security scanning
- **Infrastructure as Code** with CloudFormation
- **Production-Ready** with monitoring, logging, and rollback capabilities

## 🏗️ Architecture

```
┌─────────────┐    ┌──────────────┐    ┌─────────────┐    ┌──────────────┐
│   GitHub    │───▶│ GitHub       │───▶│   Amazon    │───▶│   Amazon     │
│ Repository  │    │ Actions (CI) │    │ ECR         │    │ ECS (Deploy) │
└─────────────┘    └──────────────┘    └─────────────┘    └──────────────┘
                           │                                       │
                           ▼                                       ▼
                   ┌──────────────┐                        ┌──────────────┐
                   │   Jenkins    │                        │   Production │
                   │ (CD Pipeline)│                        │ Environment  │
                   └──────────────┘                        └──────────────┘
```

## 📋 Prerequisites

- **Docker** and Docker Compose
- **AWS CLI** configured with appropriate permissions
- **PHP 8.3** and Composer (for local development)
- **Node.js 20** and npm (for frontend assets)
- **Git** for version control

## 🚀 Quick Start

### 1. Clone and Setup

```bash
git clone <your-repository-url>
cd laravel-cicd-project
```

### 2. Environment Configuration

```bash
# Copy environment file
cp .env.example .env

# Generate application key
php artisan key:generate

# Set required environment variables
export DB_PASSWORD=your-secure-password
export APP_KEY=base64:your-laravel-app-key
export AWS_REGION=us-east-1
```

### 3. Local Development with Docker

```bash
# Start development environment
make up

# Install dependencies
make composer-install
make npm-install

# Run migrations
make migrate

# Access application at http://localhost:8000
```

### 4. Deploy to AWS

```bash
# Setup complete CI/CD pipeline
./setup-cicd.sh

# Deploy to staging
./aws/scripts/deploy.sh staging latest

# Deploy to production
./aws/scripts/deploy.sh production v1.0.0
```

## 🛠️ Available Commands

### Docker Commands
```bash
make build          # Build Docker images
make up             # Start development environment
make down           # Stop development environment
make logs           # View logs
make shell          # Access container shell
```

### Laravel Commands
```bash
make artisan cmd="migrate"     # Run artisan commands
make composer cmd="install"   # Run composer commands
make test                     # Run PHPUnit tests
make migrate                  # Run database migrations
```

### AWS Commands
```bash
./aws/scripts/deploy.sh staging latest        # Deploy to staging
./aws/scripts/deploy.sh production v1.0.0     # Deploy to production
./aws/scripts/cleanup.sh staging              # Cleanup staging resources
```

## 📁 Project Structure

```
├── .github/workflows/          # GitHub Actions workflows
│   ├── ci.yml                 # Continuous Integration
│   ├── cd.yml                 # Continuous Deployment
│   └── docker.yml             # Docker build and push
├── aws/                       # AWS infrastructure
│   ├── cloudformation/        # CloudFormation templates
│   └── scripts/              # Deployment scripts
├── docker/                    # Docker configuration
│   ├── nginx/                # Nginx configuration
│   ├── php/                  # PHP configuration
│   └── mysql/                # MySQL configuration
├── app/                      # Laravel application
├── Dockerfile                # Multi-stage Docker build
├── docker-compose.yml        # Development environment
├── docker-compose.prod.yml   # Production environment
├── Jenkinsfile              # Jenkins pipeline
├── Makefile                 # Development commands
└── setup-cicd.sh           # Complete setup script
```

## 🔧 CI/CD Pipeline

### GitHub Actions (Continuous Integration)
- **Triggers**: Push to main/develop, Pull Requests
- **Jobs**: 
  - PHP tests with PHPUnit
  - Security scanning with Snyk
  - Code quality checks with Laravel Pint
  - Docker image building and vulnerability scanning

### Jenkins (Continuous Deployment)
- **Triggers**: Manual or webhook from GitHub Actions
- **Stages**:
  - Environment setup and validation
  - Production image building
  - ECS deployment with health checks
  - Database migrations
  - Rollback capabilities

### AWS Infrastructure
- **ECS Fargate**: Container orchestration
- **ECR**: Container registry
- **RDS MySQL**: Database with automated backups
- **ElastiCache Redis**: Caching and sessions
- **Application Load Balancer**: Traffic distribution
- **VPC**: Network isolation and security

## 🔒 Security Features

- **Container Scanning**: Trivy and Snyk vulnerability scanning
- **Secrets Management**: AWS Secrets Manager integration
- **Network Security**: Private subnets and security groups
- **Image Signing**: Docker content trust (optional)
- **Dependency Scanning**: Automated security audits

## 📊 Monitoring & Observability

- **Health Checks**: Application and infrastructure monitoring
- **CloudWatch Logs**: Centralized logging
- **Container Insights**: ECS metrics and monitoring
- **Slack Notifications**: Deployment status updates
- **Rollback Automation**: Automatic rollback on failure

## 🧪 Testing

### Local Testing
```bash
# Run all tests
make test

# Run specific test suite
make artisan cmd="test --testsuite=Feature"

# Run with coverage
make test-coverage
```

### CI/CD Testing
- **Unit Tests**: PHPUnit with code coverage
- **Integration Tests**: Database and API testing
- **Security Tests**: Vulnerability scanning
- **Performance Tests**: Load testing (optional)

## 🚀 Deployment Strategies

### Staging Deployment
- Automatic deployment on develop branch
- Single instance for cost optimization
- Full feature testing environment

### Production Deployment
- Manual approval required
- Blue-green deployment strategy
- Multiple instances with load balancing
- Automated rollback on health check failure

## 📚 Documentation

- **[CICD-SETUP.md](CICD-SETUP.md)**: Detailed setup instructions
- **[API Documentation](docs/api.md)**: API endpoints and usage
- **[Deployment Guide](docs/deployment.md)**: Step-by-step deployment
- **[Troubleshooting](docs/troubleshooting.md)**: Common issues and solutions

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

For support and questions:
- **Issues**: GitHub Issues
- **Documentation**: Check the docs/ directory
- **Monitoring**: CloudWatch dashboards
- **Logs**: ECS CloudWatch logs

## 🎯 Roadmap

- [ ] Kubernetes deployment option
- [ ] Multi-region deployment
- [ ] Advanced monitoring with Prometheus
- [ ] Automated performance testing
- [ ] Infrastructure cost optimization
- [ ] GitOps with ArgoCD

---

**Built with ❤️ using Laravel, Docker, AWS, and modern DevOps practices**
