#!/bin/sh

set -e

echo "Starting MetaMCP services..."

APP_URL=https://metamcp-frontend-555166161772.us-central1.run.app
DATABASE_URL=$DATABASE_URL
BETTER_AUTH_SECRET=$BETTER_AUTH_SECRET

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

## Start frontend
#echo "Starting frontend server..."
#cd /app/apps/frontend
#PORT=12008 pnpm start &
#FRONTEND_PID=$!
#
## Wait a moment for frontend to start
#sleep 3
#
## Check if frontend is still running
#if ! kill -0 $FRONTEND_PID 2>/dev/null; then
#    echo "❌ Frontend server died! Exiting..."
#    kill $BACKEND_PID 2>/dev/null
#    exit 1
#fi
#echo "✅ Frontend server started successfully (PID: $FRONTEND_PID)"

# Function to cleanup on exit
cleanup() {
    echo "Shutting down services..."
    kill $BACKEND_PID 2>/dev/null || true
#    kill $FRONTEND_PID 2>/dev/null || true
    wait $BACKEND_PID 2>/dev/null || true
#    wait $FRONTEND_PID 2>/dev/null || true
    echo "Services stopped"
}

# Trap signals for graceful shutdown
trap cleanup TERM INT

echo "Services started successfully!"
echo "Backend running on port 12009"
#echo "Frontend running on port 12008"

# Wait for both processes
wait $BACKEND_PID
#wait $FRONTEND_PID