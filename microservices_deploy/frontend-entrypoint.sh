#!/bin/bash
set -e

echo "🚀 Starting MetaMCP Frontend for Cloud Run..."

# Set Cloud Run specific environment variables
export PORT=${PORT:-8080}
export NODE_ENV=${NODE_ENV:-production}

# Ensure backend URL is set
if [ -z "$NEXT_PUBLIC_BACKEND_URL" ]; then
    echo "⚠️ Warning: NEXT_PUBLIC_BACKEND_URL not set. Frontend may not be able to communicate with backend."
fi

# Log startup information
echo "📋 Frontend Configuration:"
echo "   - Port: $PORT"
echo "   - Node Environment: $NODE_ENV"
echo "   - Backend URL: ${NEXT_PUBLIC_BACKEND_URL:-'Not Set'}"
echo "   - Container: Frontend Only"

# Change to the application directory
cd /app

# Create necessary directories
mkdir -p /app/.next/cache
mkdir -p /app/public

# Set proper permissions for Next.js cache
chmod -R 755 /app/.next/cache 2>/dev/null || true

# Health check endpoint setup
echo "🏥 Health check available at: http://localhost:$PORT/api/health"

# Start the Next.js frontend server
echo "🌐 Starting Next.js frontend server on port $PORT..."

# Change to the frontend directory and use the frontend's start script
cd /app/apps/frontend

# Use the frontend start command from package.json
if command -v pnpm &> /dev/null; then
    exec pnpm run start
elif command -v npm &> /dev/null; then
    exec npm run start
else
    echo "❌ Error: Neither pnpm nor npm found"
    exit 1
fi