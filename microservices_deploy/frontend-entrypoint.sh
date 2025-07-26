#!/bin/sh

set -e

echo "Starting MetaMCP Frontend service..."

# Start frontend in the background
echo "Starting frontend server..."
cd /app/apps/frontend
PORT=12008 pnpm start &
FRONTEND_PID=$!

# Wait a moment for frontend to start
sleep 3

# Check if frontend is still running
if ! kill -0 $FRONTEND_PID 2>/dev/null; then
    echo "❌ Frontend server died! Exiting..."
    exit 1
fi
echo "✅ Frontend server started successfully (PID: $FRONTEND_PID)"

# Function to cleanup on exit
cleanup() {
    echo "Shutting down frontend service..."
    kill $FRONTEND_PID 2>/dev/null || true
    wait $FRONTEND_PID 2>/dev/null || true
    echo "Frontend service stopped"
}

# Trap signals for graceful shutdown
trap cleanup TERM INT

echo "Frontend service started successfully!"
echo "Frontend running on port 12008"

# Wait for frontend process
wait $FRONTEND_PID