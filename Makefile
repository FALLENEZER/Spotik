# Spotik Development Makefile

.PHONY: help setup start stop restart logs clean test up build

# Default target
help:
	@echo "Spotik Development Commands:"
	@echo ""
	@echo "  setup     - Initial project setup"
	@echo "  start     - Start all services"
	@echo "  stop      - Stop all services"
	@echo "  restart   - Restart all services"
	@echo "  logs      - Show logs for all services"
	@echo "  clean     - Clean up containers and volumes"
	@echo "  test      - Run all tests"
	@echo ""
	@echo "Backend Commands:"
	@echo "  backend-shell    - Access backend container shell"
	@echo "  backend-migrate  - Run database migrations"
	@echo "  backend-seed     - Seed database with test data"
	@echo "  backend-test     - Run backend tests"
	@echo ""
	@echo "Frontend Commands:"
	@echo "  frontend-shell   - Access frontend container shell"
	@echo "  frontend-install - Install frontend dependencies"
	@echo "  frontend-test    - Run frontend tests"

# Initial setup
setup:
	@echo "Setting up Spotik development environment..."
	@cp -n .env.example .env || true
	@cp -n backend/.env.example backend/.env || true
	@docker-compose up -d postgres redis
	@echo "Waiting for database to be ready..."
	@sleep 10
	@docker-compose up -d backend
	@echo "Installing backend dependencies..."
	@docker-compose exec backend composer install
	@docker-compose exec backend php artisan key:generate
	@docker-compose exec backend php artisan jwt:secret --force
	@echo "Running database migrations..."
	@docker-compose exec backend php artisan migrate
	@docker-compose up -d frontend
	@echo "Installing frontend dependencies..."
	@docker-compose exec frontend npm install
	@echo "Setup complete! Run 'make start' to start all services."

# Start services
start:
	@echo "Starting Spotik services..."
	@docker-compose up -d
	@echo "Services started!"
	@echo "Frontend: http://localhost:3000"
	@echo "Backend API: http://localhost:8000"
	@echo "WebSocket: ws://localhost:6001"

# Alias for start (for consistency)
up: start

# Build all images
build:
	@echo "Building Docker images..."
	@docker-compose build

# Stop services
stop:
	@echo "Stopping Spotik services..."
	@docker-compose down

# Restart services
restart:
	@echo "Restarting Spotik services..."
	@docker-compose restart

# Show logs
logs:
	@docker-compose logs -f

# Clean up
clean:
	@echo "Cleaning up containers and volumes..."
	@docker-compose down -v
	@docker system prune -f

# Run all tests
test: backend-test frontend-test

# Backend commands
backend-shell:
	@docker-compose exec backend bash

backend-migrate:
	@docker-compose exec backend php artisan migrate

backend-seed:
	@docker-compose exec backend php artisan db:seed

backend-test:
	@docker-compose exec backend php artisan test

backend-fresh:
	@docker-compose exec backend php artisan migrate:fresh --seed

# Frontend commands
frontend-shell:
	@docker-compose exec frontend sh

frontend-install:
	@docker-compose exec frontend npm install

frontend-test:
	@docker-compose exec frontend npm run test

frontend-build:
	@docker-compose exec frontend npm run build

# Database commands
db-reset:
	@docker-compose exec backend php artisan migrate:fresh
	@docker-compose exec backend php artisan db:seed

# Production commands
prod-deploy:
	@echo "Deploying to production..."
	@docker-compose -f docker-compose.prod.yml up -d

prod-logs:
	@docker-compose -f docker-compose.prod.yml logs -f

prod-stop:
	@docker-compose -f docker-compose.prod.yml down