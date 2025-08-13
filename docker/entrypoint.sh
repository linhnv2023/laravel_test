#!/bin/sh
set -e

echo "Starting Laravel container..."

# Change to application directory
cd /app

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    echo "Creating .env file from .env.example..."
    cp .env.example .env
fi

# Generate application key if not set
if ! grep -q "APP_KEY=base64:" .env 2>/dev/null; then
    echo "Generating application key..."
    php artisan key:generate --force
fi

# Set proper permissions
chown -R application:application /app || true
chmod -R 755 /app/storage || true
chmod -R 755 /app/bootstrap/cache || true

# Handle different container roles
case "${CONTAINER_ROLE:-app}" in
    app)
        echo "Starting Laravel development server..."
        exec php artisan serve --host=0.0.0.0 --port=8000
        ;;
    queue)
        echo "Starting Laravel queue worker..."
        exec php artisan queue:work --verbose --tries=3 --timeout=90
        ;;
    scheduler)
        echo "Starting Laravel scheduler..."
        # Run scheduler every minute
        while true; do
            php artisan schedule:run --verbose --no-interaction
            sleep 60
        done
        ;;
    *)
        echo "Unknown container role: ${CONTAINER_ROLE}"
        exit 1
        ;;
esac
