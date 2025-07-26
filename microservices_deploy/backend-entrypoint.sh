#!/bin/bash
set -e

echo "🚀 Starting MetaMCP Backend for Cloud Run..."

# Set Cloud Run specific environment variables
export PORT=${PORT:-12009}
export NODE_ENV=${NODE_ENV:-production}
export APP_URL=${APP_URL}
export DATABASE_URL=${DATABASE_URL}
export BETTER_AUTH_SECRET=${BETTER_AUTH_SECRET}

# Log startup information
echo "📋 Backend Configuration:"
echo "   - Port: $PORT"
echo "   - Node Environment: $NODE_ENV"
echo "   - App URL: $APP_URL"
echo "   - Database: Supabase PostgreSQL"

# Change to the backend directory
cd /app/apps/backend

# Build the application if not already built
if [ ! -d "dist" ]; then
    echo "🔨 Building backend application..."
    npm run build
fi

# Create necessary directories for MCP server management
mkdir -p /app/data/mcp-sessions
mkdir -p /app/logs

# Set proper permissions
chmod -R 755 /app/data 2>/dev/null || true
chmod -R 755 /app/logs 2>/dev/null || true

# Health check endpoint setup
echo "🏥 Health check available at: http://localhost:$PORT/health"

# Start the backend server
echo "⚙️ Starting MetaMCP backend server on port $PORT..."

# Use npm to start the backend
exec npm run start