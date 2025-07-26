#!/bin/sh

set -e

echo "Starting MetaMCP Backend service..."

APP_URL=https://metamcp-backend-555166161772.us-central1.run.app

# Start backend in the background
echo "Starting backend server..."
cd /app/apps/backend
PORT=12009 node dist/index.js &
BACKEND_PID=$!

# Wait a moment for backend to start
sleep 3

# Check if backend is still running
if ! kill -0 $BACKEND_PID 2>/dev/null; then
    echo "❌ Backend server died! Exiting..."
    exit 1
fi
echo "✅ Backend server started successfully (PID: $BACKEND_PID)"

# Function to cleanup on exit
cleanup() {
    echo "Shutting down backend service..."
    kill $BACKEND_PID 2>/dev/null || true
    wait $BACKEND_PID 2>/dev/null || true
    echo "Backend service stopped"
}

# Trap signals for graceful shutdown
trap cleanup TERM INT

echo "Backend service started successfully!"
echo "Backend running on port 12009"

# Wait for backend process
wait $BACKEND_PID