#!/bin/bash
set -e

echo "🚀 Starting MetaMCP Backend for Cloud Run..."

# Set Cloud Run specific environment variables
export PORT=${PORT:-12009}
export NODE_ENV=${NODE_ENV:-production}
export APP_URL=https://metamcp-backend-555166161772.us-central1.run.app

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

# Health check endpoint setup
echo "🏥 Health check available at: http://localhost:$PORT/health"

# Start the backend server
echo "⚙️ Starting MetaMCP backend server on port $PORT..."

# Use npm to start the backend
exec npm run start