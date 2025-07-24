#!/bin/bash
set -e

echo "🚀 Starting MetaMCP Backend for Cloud Run..."

# Set Cloud Run specific environment variables
export PORT=${PORT:-8080}
export NODE_ENV=${NODE_ENV:-production}

# Database connection setup
echo "🗄️ Setting up database connection..."

# Check if we need to use Cloud SQL Proxy
if [ -n "$INSTANCE_CONNECTION_NAME" ] && [ "$USE_CLOUD_SQL_PROXY" = "true" ]; then
    echo "🔗 Starting Cloud SQL Proxy for connection: $INSTANCE_CONNECTION_NAME"
    
    # Start Cloud SQL Proxy in background
    /usr/local/bin/cloud_sql_proxy -instances=$INSTANCE_CONNECTION_NAME=tcp:5432 &
    
    # Wait for Cloud SQL Proxy to be ready
    until nc -z localhost 5432; do
        echo "⏳ Waiting for Cloud SQL Proxy to be ready..."
        sleep 2
    done
    
    echo "✅ Cloud SQL Proxy is ready"
fi

# Wait for database to be available
echo "🔍 Checking database connectivity..."
until PGPASSWORD=$DB_PASSWORD psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c '\q' 2>/dev/null; do
    echo "⏳ Waiting for database to be ready..."
    sleep 2
done

echo "✅ Database connection established"

# Run database migrations
echo "🏗️ Running database migrations..."
cd /app/apps/backend

if command -v pnpm &> /dev/null; then
    pnpm drizzle-kit push --verbose
elif command -v npm &> /dev/null; then
    npm run db:push
else
    echo "❌ Error: Neither pnpm nor npm found"
    exit 1
fi

echo "✅ Database migrations completed"

# Log startup information
echo "📋 Backend Configuration:"
echo "   - Port: $PORT"
echo "   - Node Environment: $NODE_ENV"
echo "   - Database Host: ${DB_HOST:-'Not Set'}"
echo "   - Database Name: ${DB_NAME:-'Not Set'}"
echo "   - Container: Backend Only"

# Change back to the application root
cd /app

# Create necessary directories for MCP server management
mkdir -p /app/data/mcp-sessions
mkdir -p /app/logs

# Set proper permissions
chmod -R 755 /app/data 2>/dev/null || true
chmod -R 755 /app/logs 2>/dev/null || true

# Health check endpoint setup
echo "🏥 Health check available at: http://localhost:$PORT/api/health"

# Start the backend server
echo "⚙️ Starting MetaMCP backend server on port $PORT..."

# Use the existing start command from package.json but for backend only
# This assumes the package.json has a "start:backend" script
if command -v pnpm &> /dev/null; then
    exec pnpm run start:backend
elif command -v npm &> /dev/null; then
    exec npm run start:backend
else
    echo "❌ Error: Neither pnpm nor npm found"
    exit 1
fi