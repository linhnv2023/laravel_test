# Use a simpler base image with PHP extensions already built
FROM webdevops/php-nginx:8.3-alpine

# Set working directory
WORKDIR /app

# Install additional packages
RUN apk add --no-cache \
    mysql-client \
    redis \
    supervisor \
    nodejs \
    npm

# Copy application files
COPY . /app

# Install Composer dependencies
RUN composer install --no-dev --optimize-autoloader

# Install npm dependencies
RUN npm install

# Copy configuration files
COPY docker/nginx/default.conf /opt/docker/etc/nginx/vhost.conf
COPY docker/php/php.ini /usr/local/etc/php/conf.d/custom.ini
COPY docker/supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy entrypoint script
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Create necessary directories for volume mounts
RUN mkdir -p /app/storage/logs \
    && mkdir -p /app/storage/app \
    && mkdir -p /app/storage/framework/cache \
    && mkdir -p /app/storage/framework/sessions \
    && mkdir -p /app/storage/framework/views \
    && mkdir -p /app/bootstrap/cache

# Set proper permissions
RUN chown -R application:application /app \
    && chmod -R 755 /app/storage \
    && chmod -R 755 /app/bootstrap/cache

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000 || exit 1

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
