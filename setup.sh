#!/bin/bash

# Spotik Development Setup Script
set -e

echo "🎵 Setting up Spotik development environment..."

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Create environment files if they don't exist
echo "📝 Setting up environment files..."
if [ ! -f .env ]; then
    cp .env.example .env
    echo "✅ Created .env file"
fi

if [ ! -f backend/.env ]; then
    cp backend/.env.example backend/.env
    echo "✅ Created backend/.env file"
fi

# Start database and Redis first
echo "🗄️ Starting database and Redis..."
docker-compose up -d postgres redis

# Wait for database to be ready
echo "⏳ Waiting for database to be ready..."
sleep 15

# Start backend
echo "🚀 Starting backend..."
docker-compose up -d backend

# Wait for backend to be ready
echo "⏳ Waiting for backend to be ready..."
sleep 10

# Install backend dependencies
echo "📦 Installing backend dependencies..."
docker-compose exec backend composer install

# Generate application key
echo "🔑 Generating application key..."
docker-compose exec backend php artisan key:generate

# Generate JWT secret
echo "🔐 Generating JWT secret..."
docker-compose exec backend php artisan jwt:secret --force

# Run database migrations
echo "🗃️ Running database migrations..."
docker-compose exec backend php artisan migrate

# Start frontend
echo "🎨 Starting frontend..."
docker-compose up -d frontend

# Install frontend dependencies
echo "📦 Installing frontend dependencies..."
docker-compose exec frontend npm install

# Start WebSocket server
echo "🔌 Starting WebSocket server..."
docker-compose up -d websocket

echo ""
echo "🎉 Setup complete!"
echo ""
echo "🌐 Access your application:"
echo "   Frontend: http://localhost:3000"
echo "   Backend API: http://localhost:8000"
echo "   WebSocket: ws://localhost:6001"
echo ""
echo "📋 Useful commands:"
echo "   make start    - Start all services"
echo "   make stop     - Stop all services"
echo "   make logs     - View logs"
echo "   make test     - Run tests"
echo ""
echo "🔧 Development commands:"
echo "   make backend-shell   - Access backend container"
echo "   make frontend-shell  - Access frontend container"
echo "   make backend-migrate - Run migrations"
echo ""