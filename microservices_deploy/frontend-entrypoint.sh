#!/bin/bash
set -e

echo "🚀 Starting MetaMCP Frontend for Cloud Run..."

# Set Cloud Run specific environment variables
export PORT=${PORT:-12008}
export NODE_ENV=${NODE_ENV:-production}

# Add pnpm binaries to PATH for monorepo setup
export PATH="/app/node_modules/.pnpm/node_modules/.bin:$PATH"

# Log startup information
echo "📋 Frontend Configuration:"
echo "   - Port: $PORT"
echo "   - Node Environment: $NODE_ENV"
echo "   - Backend URL: ${NEXT_PUBLIC_API_URL:-'Not Set'}"
echo "   - Frontend URL: ${NEXT_PUBLIC_APP_URL:-'Not Set'}"
echo "   - Container: Frontend Only"

# Build the application if not already built
if [ ! -d "/app/apps/frontend/.next" ]; then
    echo "🔨 Building frontend application..."
    cd /app
    pnpm run build --filter=frontend
fi

# Health check endpoint setup
echo "🏥 Health check available at: http://localhost:$PORT/api/health"

# Start the Next.js frontend server
echo "🌐 Starting Next.js frontend server on port $PORT..."

# Change to root directory to run pnpm workspace command
cd /app

# Use pnpm workspace command to start frontend
if command -v pnpm &> /dev/null; then
    exec pnpm --filter=frontend run start
elif command -v npm &> /dev/null; then
    echo "⚠️  Using npm fallback - changing to frontend directory"
    cd /app/apps/frontend
    exec npm run start
else
    echo "❌ Error: Neither pnpm nor npm found"
    exit 1
fi