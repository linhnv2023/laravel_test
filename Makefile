# Laravel Docker Makefile

# Variables
DOCKER_COMPOSE = docker-compose
DOCKER_COMPOSE_PROD = docker-compose -f docker-compose.prod.yml
DOCKER_EXEC = docker exec -it
APP_CONTAINER = laravel-app
MYSQL_CONTAINER = laravel-mysql

# Colors for output
GREEN = \033[0;32m
YELLOW = \033[1;33m
RED = \033[0;31m
NC = \033[0m # No Color

.PHONY: help build up down restart logs shell mysql artisan composer npm test clean

# Default target
help: ## Show this help message
	@echo "$(GREEN)Laravel Docker Commands$(NC)"
	@echo "======================="
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "$(YELLOW)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Development commands
build: ## Build Docker images
	@echo "$(GREEN)Building Docker images...$(NC)"
	$(DOCKER_COMPOSE) build --no-cache

up: ## Start development environment
	@echo "$(GREEN)Starting development environment...$(NC)"
	$(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)Application is running at http://localhost:8000$(NC)"

down: ## Stop development environment
	@echo "$(YELLOW)Stopping development environment...$(NC)"
	$(DOCKER_COMPOSE) down

restart: ## Restart development environment
	@echo "$(YELLOW)Restarting development environment...$(NC)"
	$(DOCKER_COMPOSE) restart

logs: ## Show logs
	$(DOCKER_COMPOSE) logs -f

logs-app: ## Show application logs
	$(DOCKER_COMPOSE) logs -f app

logs-nginx: ## Show nginx logs
	$(DOCKER_COMPOSE) logs -f nginx

logs-mysql: ## Show MySQL logs
	$(DOCKER_COMPOSE) logs -f mysql

# Production commands
build-prod: ## Build production images
	@echo "$(GREEN)Building production Docker images...$(NC)"
	$(DOCKER_COMPOSE_PROD) build --no-cache

up-prod: ## Start production environment
	@echo "$(GREEN)Starting production environment...$(NC)"
	$(DOCKER_COMPOSE_PROD) up -d
	@echo "$(GREEN)Production application is running at http://localhost$(NC)"

down-prod: ## Stop production environment
	@echo "$(YELLOW)Stopping production environment...$(NC)"
	$(DOCKER_COMPOSE_PROD) down

# Container access
shell: ## Access application container shell
	$(DOCKER_EXEC) $(APP_CONTAINER) /bin/sh

mysql: ## Access MySQL container
	$(DOCKER_EXEC) $(MYSQL_CONTAINER) mysql -u laravel -psecret laravel

# Laravel commands
artisan: ## Run artisan command (usage: make artisan cmd="migrate")
	$(DOCKER_EXEC) $(APP_CONTAINER) php artisan $(cmd)

migrate: ## Run database migrations
	$(DOCKER_EXEC) $(APP_CONTAINER) php artisan migrate

migrate-fresh: ## Fresh migration with seeding
	$(DOCKER_EXEC) $(APP_CONTAINER) php artisan migrate:fresh --seed

seed: ## Run database seeders
	$(DOCKER_EXEC) $(APP_CONTAINER) php artisan db:seed

tinker: ## Access Laravel Tinker
	$(DOCKER_EXEC) $(APP_CONTAINER) php artisan tinker

# Composer commands
composer: ## Run composer command (usage: make composer cmd="install")
	$(DOCKER_EXEC) $(APP_CONTAINER) composer $(cmd)

composer-install: ## Install composer dependencies
	$(DOCKER_EXEC) $(APP_CONTAINER) composer install

composer-update: ## Update composer dependencies
	$(DOCKER_EXEC) $(APP_CONTAINER) composer update

# NPM commands
npm: ## Run npm command (usage: make npm cmd="install")
	$(DOCKER_EXEC) $(APP_CONTAINER) npm $(cmd)

npm-install: ## Install npm dependencies
	$(DOCKER_EXEC) $(APP_CONTAINER) npm install

npm-dev: ## Run npm development build
	$(DOCKER_EXEC) $(APP_CONTAINER) npm run dev

npm-build: ## Run npm production build
	$(DOCKER_EXEC) $(APP_CONTAINER) npm run build

npm-watch: ## Run npm watch
	$(DOCKER_EXEC) $(APP_CONTAINER) npm run dev -- --watch

# Testing
test: ## Run PHPUnit tests
	$(DOCKER_EXEC) $(APP_CONTAINER) php artisan test

test-coverage: ## Run tests with coverage
	$(DOCKER_EXEC) $(APP_CONTAINER) php artisan test --coverage

# Maintenance
clear-cache: ## Clear all Laravel caches
	$(DOCKER_EXEC) $(APP_CONTAINER) php artisan cache:clear
	$(DOCKER_EXEC) $(APP_CONTAINER) php artisan config:clear
	$(DOCKER_EXEC) $(APP_CONTAINER) php artisan route:clear
	$(DOCKER_EXEC) $(APP_CONTAINER) php artisan view:clear

optimize: ## Optimize Laravel for production
	$(DOCKER_EXEC) $(APP_CONTAINER) php artisan config:cache
	$(DOCKER_EXEC) $(APP_CONTAINER) php artisan route:cache
	$(DOCKER_EXEC) $(APP_CONTAINER) php artisan view:cache

# Cleanup
clean: ## Clean up Docker resources
	@echo "$(YELLOW)Cleaning up Docker resources...$(NC)"
	docker system prune -f
	docker volume prune -f

clean-all: ## Clean up all Docker resources (including images)
	@echo "$(RED)Cleaning up all Docker resources...$(NC)"
	docker system prune -a -f
	docker volume prune -f

# Status
status: ## Show container status
	$(DOCKER_COMPOSE) ps

# Backup
backup-db: ## Backup MySQL database
	@echo "$(GREEN)Creating database backup...$(NC)"
	$(DOCKER_EXEC) $(MYSQL_CONTAINER) mysqldump -u laravel -psecret laravel > backup_$(shell date +%Y%m%d_%H%M%S).sql

# Health check
health: ## Check application health
	@echo "$(GREEN)Checking application health...$(NC)"
	curl -f http://localhost:8000/health || echo "$(RED)Health check failed$(NC)"
