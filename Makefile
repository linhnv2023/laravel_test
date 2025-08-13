# ==========================================
# Laravel Docker Makefile
# ==========================================
# Tập hợp các commands tiện ích để quản lý Laravel Docker environment
# Usage: make <command>
# Help: make help

# ==========================================
# VARIABLES - CẤU HÌNH CƠ BẢN
# ==========================================
DOCKER_COMPOSE = docker-compose          # Command docker-compose
DOCKER_EXEC = docker exec -it            # Command để exec vào container
APP_CONTAINER = laravel-app              # Tên container chứa Laravel app
MYSQL_CONTAINER = laravel-mysql          # Tên container chứa MySQL

# ==========================================
# COLORS - MÀU SẮC CHO OUTPUT
# ==========================================
GREEN = \033[0;32m                       # Màu xanh lá (success)
YELLOW = \033[1;33m                      # Màu vàng (warning/info)
RED = \033[0;31m                         # Màu đỏ (error)
NC = \033[0m                             # No Color (reset)

# ==========================================
# PHONY TARGETS - KHÔNG PHẢI FILE THẬT
# ==========================================
.PHONY: help build up down restart logs shell mysql artisan composer npm test clean

# ==========================================
# DEFAULT TARGET - HIỂN THỊ HELP
# ==========================================
help: ## Hiển thị danh sách commands có thể sử dụng
	@echo "$(GREEN)Laravel Docker Commands$(NC)"
	@echo "======================="
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "$(YELLOW)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ==========================================
# DEVELOPMENT COMMANDS - LỆNH PHÁT TRIỂN
# ==========================================

build: ## Build Docker images (không cache - clean build)
	@echo "$(GREEN)Building Docker images...$(NC)"
	# Build tất cả images từ đầu, không sử dụng cache
	# Chậm hơn nhưng đảm bảo images mới nhất
	$(DOCKER_COMPOSE) build --no-cache

build-fast: ## Build Docker images (có cache - nhanh hơn)
	@echo "$(GREEN)Building Docker images (with cache)...$(NC)"
	# Build với cache, nhanh hơn cho lần build tiếp theo
	# Sử dụng khi chỉ có thay đổi nhỏ
	$(DOCKER_COMPOSE) build

up: ## Khởi động development environment
	@echo "$(GREEN)Starting development environment...$(NC)"
	# Khởi động tất cả containers trong background (-d = detached)
	$(DOCKER_COMPOSE) up -d
	@echo "$(GREEN)Application is running at http://localhost:8000$(NC)"
	@echo "$(YELLOW)Waiting for services to be healthy...$(NC)"
	# Hiển thị status của các containers
	@$(DOCKER_COMPOSE) ps

up-nginx: ## Khởi động với Nginx proxy (production-like)
	@echo "$(GREEN)Starting with Nginx proxy...$(NC)"
	# Khởi động với profile nginx (bao gồm Nginx container)
	$(DOCKER_COMPOSE) --profile nginx up -d
	@echo "$(GREEN)Application is running at http://localhost (Nginx) and http://localhost:8000 (Direct)$(NC)"

down: ## Dừng development environment
	@echo "$(YELLOW)Stopping development environment...$(NC)"
	# Dừng và xóa tất cả containers (giữ lại volumes)
	$(DOCKER_COMPOSE) down

restart: ## Restart development environment
	@echo "$(YELLOW)Restarting development environment...$(NC)"
	# Restart tất cả containers (không rebuild)
	$(DOCKER_COMPOSE) restart

# ==========================================
# LOGGING COMMANDS - XEM LOGS
# ==========================================

logs: ## Xem logs của tất cả services (realtime)
	# -f = follow (theo dõi realtime)
	$(DOCKER_COMPOSE) logs -f

logs-app: ## Xem logs của Laravel application
	$(DOCKER_COMPOSE) logs -f app

logs-nginx: ## Xem logs của Nginx server
	$(DOCKER_COMPOSE) logs -f nginx

logs-mysql: ## Xem logs của MySQL database
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
	@curl -f http://localhost:8000 > /dev/null 2>&1 && echo "$(GREEN)✅ Application is healthy$(NC)" || echo "$(RED)❌ Application health check failed$(NC)"

health-all: ## Check all services health
	@echo "$(GREEN)Checking all services health...$(NC)"
	@$(DOCKER_COMPOSE) ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

# Performance optimization
optimize-prod: ## Optimize for production
	@echo "$(GREEN)Optimizing for production...$(NC)"
	$(DOCKER_EXEC) $(APP_CONTAINER) php artisan config:cache
	$(DOCKER_EXEC) $(APP_CONTAINER) php artisan route:cache
	$(DOCKER_EXEC) $(APP_CONTAINER) php artisan view:cache
	$(DOCKER_EXEC) $(APP_CONTAINER) php artisan event:cache
	$(DOCKER_EXEC) $(APP_CONTAINER) composer dump-autoload --optimize --classmap-authoritative
	@echo "$(GREEN)✅ Production optimization completed$(NC)"

# Quick setup for new developers
setup: ## Quick setup for new developers
	@echo "$(GREEN)🚀 Setting up Laravel development environment...$(NC)"
	make build-fast
	make up
	@echo "$(YELLOW)⏳ Waiting for services to start...$(NC)"
	@sleep 10
	make composer-install
	make migrate
	@echo "$(GREEN)✅ Setup completed! Visit http://localhost:8000$(NC)"
