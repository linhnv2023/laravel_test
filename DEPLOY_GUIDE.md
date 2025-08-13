# 🚀 Laravel Docker Deploy Guide

## 📋 Tổng quan
Hướng dẫn deploy Laravel application sử dụng Docker với đầy đủ chú thích từng bước.

## 🏗️ Kiến trúc hệ thống
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Laravel App   │    │     MySQL       │    │     Redis       │
│   (PHP 8.3)     │◄──►│   Database      │    │   Cache/Queue   │
│   Port: 8000    │    │   Port: 3306    │    │   Port: 6379    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         ▲                       ▲                       ▲
         │                       │                       │
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Queue Worker   │    │   Scheduler     │    │   Nginx Proxy   │
│  (Background)   │    │   (Cron Jobs)   │    │   Port: 80/443  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🚀 Quick Deploy (30 giây)

### Bước 1: Chuẩn bị môi trường
```bash
# Clone source code từ repository
git clone <your-repository-url>
cd <project-directory>

# Copy file environment template và chỉnh sửa
cp .env.example .env
# Chỉnh sửa .env với thông tin database, cache, v.v.
```

### Bước 2: Deploy một lệnh
```bash
# Khởi động toàn bộ hệ thống (build + start + migrate)
make setup
```

### Bước 3: Truy cập ứng dụng
```bash
# Mở trình duyệt tại địa chỉ:
# http://localhost:8000
```

## 🔧 Deploy Manual (Chi tiết từng bước)

### Bước 1: Build Docker Images
```bash
# Build tất cả Docker images từ Dockerfile
# Quá trình này sẽ:
# - Tải base image (webdevops/php-nginx:8.3-alpine)
# - Cài đặt dependencies (composer, npm)
# - Copy source code vào container
# - Thiết lập permissions
make build

# Hoặc build nhanh với cache (nếu đã build trước đó)
make build-fast
```

### Bước 2: Khởi động Services
```bash
# Khởi động tất cả containers trong background (-d = detached)
# Bao gồm: app, mysql, redis, queue, scheduler
make up

# Kiểm tra trạng thái các containers
make status
```

### Bước 3: Cài đặt Dependencies
```bash
# Cài đặt PHP dependencies thông qua Composer
# Chạy bên trong app container
make composer-install

# Cài đặt JavaScript dependencies thông qua NPM
# Cần thiết cho frontend assets (CSS, JS)
make npm-install
```

### Bước 4: Thiết lập Database
```bash
# Tạo application key cho Laravel (bảo mật sessions, encryption)
make artisan cmd="key:generate"

# Chạy database migrations (tạo tables)
make migrate

# (Tùy chọn) Chạy database seeders (dữ liệu mẫu)
make seed
```

### Bước 5: Build Frontend Assets
```bash
# Build CSS và JavaScript cho development
make npm-dev

# Hoặc build cho production (minified, optimized)
make npm-build
```

## 📊 Kiểm tra hệ thống

### Kiểm tra trạng thái containers
```bash
# Xem danh sách containers và trạng thái
make status
# Output: Container name, status, ports, health

# Kiểm tra health của ứng dụng
make health
# Gửi HTTP request đến app để kiểm tra

# Kiểm tra tất cả services
make health-all
```

### Xem logs để debug
```bash
# Xem logs của tất cả services
make logs

# Xem logs của app container (Laravel)
make logs-app

# Xem logs của MySQL database
make logs-mysql

# Xem logs realtime (theo dõi liên tục)
docker-compose logs -f app
```

## 🛠️ Quản lý hệ thống

### Truy cập containers
```bash
# Truy cập shell của app container
# Để chạy commands Laravel, debug, xem files
make shell

# Truy cập MySQL database
# Để chạy SQL queries, kiểm tra data
make mysql
```

### Laravel Commands
```bash
# Chạy bất kỳ artisan command nào
make artisan cmd="route:list"        # Xem danh sách routes
make artisan cmd="cache:clear"       # Xóa cache
make artisan cmd="config:clear"      # Xóa config cache
make artisan cmd="queue:work"        # Chạy queue worker manual

# Chạy database operations
make migrate                         # Chạy migrations mới
make migrate-fresh                   # Reset database và chạy lại tất cả
make seed                           # Chạy seeders

# Truy cập Laravel Tinker (interactive shell)
make tinker
```

### Composer & NPM Management
```bash
# Cài đặt package PHP mới
make composer cmd="require package-name"

# Update PHP dependencies
make composer-update

# Cài đặt package JavaScript mới
make npm cmd="install package-name"

# Chạy npm scripts
make npm cmd="run dev"              # Development build
make npm cmd="run build"            # Production build
make npm cmd="run watch"            # Watch for changes
```

## 🔄 Maintenance Commands

### Cache Management
```bash
# Xóa tất cả Laravel caches
# Bao gồm: application cache, config, routes, views
make clear-cache

# Tối ưu hóa cho production
# Cache configs, routes, views để tăng tốc
make optimize
```

### System Cleanup
```bash
# Dừng tất cả containers
make down

# Restart tất cả services
make restart

# Dọn dẹp Docker resources (images, containers cũ)
make clean

# Dọn dẹp toàn bộ (bao gồm images)
# ⚠️ Cẩn thận: sẽ xóa tất cả images không sử dụng
make clean-all
```

### Database Backup
```bash
# Tạo backup database
# File backup sẽ được lưu với timestamp
make backup-db

# Restore database từ backup (manual)
docker exec laravel-mysql mysql -u laravel -psecret laravel < backup_file.sql
```

## 🔧 Configuration Files

### Environment Variables (.env)
```bash
# Application settings
APP_NAME="Laravel Docker App"        # Tên ứng dụng
APP_ENV=local                        # Môi trường (local/staging/production)
APP_DEBUG=true                       # Bật debug mode (false cho production)
APP_URL=http://localhost:8000        # URL của ứng dụng

# Database connection
DB_CONNECTION=mysql                  # Loại database
DB_HOST=mysql                       # Hostname (tên container)
DB_PORT=3306                        # Port database
DB_DATABASE=laravel                 # Tên database
DB_USERNAME=laravel                 # Username database
DB_PASSWORD=secret                  # Password database

# Redis configuration
REDIS_HOST=redis                    # Hostname Redis (tên container)
REDIS_PORT=6379                     # Port Redis
CACHE_DRIVER=redis                  # Sử dụng Redis cho cache
SESSION_DRIVER=redis                # Sử dụng Redis cho sessions
QUEUE_CONNECTION=redis              # Sử dụng Redis cho queue
```

### Docker Compose Services
```yaml
# docker-compose.yml chứa định nghĩa các services:

app:          # Laravel application container
  - Port: 8000
  - Base: webdevops/php-nginx:8.3-alpine
  - Volumes: Source code, configs

mysql:        # MySQL database container
  - Port: 3306
  - Version: 8.0
  - Persistent data volume

redis:        # Redis cache container
  - Port: 6379
  - Version: 7-alpine
  - Persistent data volume

queue:        # Background job processor
  - Command: php artisan queue:work
  - Processes jobs from Redis queue

scheduler:    # Cron job processor
  - Command: php artisan schedule:run
  - Runs every minute
```

## 🐛 Troubleshooting

### Container không khởi động
```bash
# Kiểm tra logs để xem lỗi
make logs

# Rebuild images nếu có thay đổi
make build

# Reset hoàn toàn
make down && make clean && make up
```

### Database connection lỗi
```bash
# Kiểm tra MySQL container có chạy không
docker ps | grep mysql

# Kiểm tra MySQL logs
make logs-mysql

# Test connection từ app container
make shell
php artisan tinker
DB::connection()->getPdo();
```

### Permission issues
```bash
# Vào app container và fix permissions
make shell
chown -R application:application /app/storage
chmod -R 775 /app/storage /app/bootstrap/cache
```

### Port conflicts
```bash
# Nếu port 8000 đã được sử dụng, thay đổi trong docker-compose.yml:
ports:
  - "8001:8000"  # Thay 8000 thành 8001
```

## 📈 Production Deployment

### Chuẩn bị production
```bash
# Thay đổi environment variables
APP_ENV=production
APP_DEBUG=false
DB_PASSWORD=secure-production-password

# Tối ưu hóa cho production
make optimize-prod

# Build production assets
make npm-build
```

### SSL/HTTPS Setup
```bash
# Thêm SSL certificates vào docker/ssl/
# Cập nhật nginx config để enable HTTPS
# Restart nginx container
```

---

## 🎯 Tóm tắt Commands quan trọng

```bash
# 🚀 DEPLOY
make setup              # Deploy hoàn chỉnh (một lệnh)
make up                 # Khởi động services
make down               # Dừng services

# 🔧 DEVELOPMENT  
make shell              # Truy cập container
make logs               # Xem logs
make artisan cmd=""     # Chạy Laravel commands

# 🗄️ DATABASE
make migrate            # Chạy migrations
make seed               # Chạy seeders
make mysql              # Truy cập MySQL

# 🧹 MAINTENANCE
make clean              # Dọn dẹp Docker
make restart            # Restart services
make health             # Kiểm tra health
```

**🎉 Happy Deploying!**
