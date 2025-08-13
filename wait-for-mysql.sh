#!/bin/bash

# Wait for MySQL to be ready
echo "Waiting for MySQL to be ready..."

# Wait for MySQL container to be running
while ! docker ps | grep -q "laravel-mysql.*Up"; do
    echo "MySQL container not running yet..."
    sleep 2
done

echo "MySQL container is running, checking connection..."

# Wait for MySQL to accept connections
max_attempts=30
attempt=1

while [ $attempt -le $max_attempts ]; do
    echo "Attempt $attempt/$max_attempts: Testing MySQL connection..."
    
    if docker exec laravel-mysql mysql -u laravel -psecret -e "SELECT 1;" >/dev/null 2>&1; then
        echo "✅ MySQL is ready!"
        break
    fi
    
    if [ $attempt -eq $max_attempts ]; then
        echo "❌ MySQL failed to become ready after $max_attempts attempts"
        exit 1
    fi
    
    echo "MySQL not ready yet, waiting..."
    sleep 3
    attempt=$((attempt + 1))
done

echo "🚀 MySQL is ready for connections!"
