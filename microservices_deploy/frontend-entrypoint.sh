#!/bin/bash
set -e

echo "🚀 Starting MetaMCP Frontend for Cloud Run..."

# Set Cloud Run specific environment variables
export PORT=${PORT:-12008}
export NODE_ENV=${NODE_ENV:-production}

# Log startup information
echo "📋 Frontend Configuration:"
echo "   - Port: $PORT"
echo "   - Node Environment: $NODE_ENV"
echo "   - Backend URL: ${NEXT_PUBLIC_API_URL:-'Not Set'}"
echo "   - Frontend URL: ${NEXT_PUBLIC_APP_URL:-'Not Set'}"
echo "   - Container: Frontend Only"

# Change to the frontend directory
cd /app/apps/frontend

# Build the application if not already built
if [ ! -d ".next" ]; then
    echo "🔨 Building frontend application..."
    npm run build
fi

# Health check endpoint setup
echo "🏥 Health check available at: http://localhost:$PORT/api/health"

# Start the Next.js frontend server
echo "🌐 Starting Next.js frontend server on port $PORT..."

# Use the frontend start command from package.json
if command -v pnpm &> /dev/null; then
    exec pnpm run start
elif command -v npm &> /dev/null; then
    exec npm run start
else
    echo "❌ Error: Neither pnpm nor npm found"
    exit 1
fi