# Spotik Development Makefile

.PHONY: help setup start stop restart logs clean test up build up-ruby down-ruby status-ruby

# Default target
help:
	@echo "Spotik Development Commands:"
	@echo ""
	@echo "  setup     - Initial project setup"
	@echo "  start     - Start all services (Laravel backend)"
	@echo "  up-ruby   - Start Ruby backend server"
	@echo "  stop      - Stop all services"
	@echo "  down-ruby - Stop Ruby backend server"
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
	@echo "Ruby Backend Commands:"
	@echo "  up-ruby          - Start Ruby backend server"
	@echo "  down-ruby        - Stop Ruby backend server"
	@echo "  status-ruby      - Check Ruby backend status"
	@echo "  ruby-test        - Run Ruby backend tests"
	@echo "  ruby-shell       - Access Ruby backend directory"
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

# Ruby Backend Commands
up-ruby:
	@echo "🚀 Starting Ruby backend server..."
	@echo "Checking if Ruby backend is already running..."
	@if pgrep -f "ruby.*server.rb" > /dev/null; then \
		echo "✅ Ruby backend is already running on port 4000"; \
		echo "PID: $$(pgrep -f 'ruby.*server.rb')"; \
	else \
		echo "📦 Installing Ruby dependencies..."; \
		cd ruby-backend && bundle install --quiet; \
		echo "🔧 Starting Ruby backend server..."; \
		cd ruby-backend && nohup ruby server.rb > server_output.log 2>&1 & \
		sleep 2; \
		if pgrep -f "ruby.*server.rb" > /dev/null; then \
			echo "✅ Ruby backend started successfully on port 4000"; \
			echo "PID: $$(pgrep -f 'ruby.*server.rb')"; \
			echo "📊 Health check: http://localhost:4000/health"; \
			echo "📋 API info: http://localhost:4000/api"; \
			echo "🔌 WebSocket: ws://localhost:4000/ws"; \
		else \
			echo "❌ Failed to start Ruby backend"; \
			echo "Check logs: tail -f ruby-backend/server_output.log"; \
		fi; \
	fi

down-ruby:
	@echo "🛑 Stopping Ruby backend server..."
	@if pgrep -f "ruby.*server.rb" > /dev/null; then \
		pkill -f "ruby.*server.rb"; \
		echo "✅ Ruby backend stopped"; \
	else \
		echo "ℹ️  Ruby backend was not running"; \
	fi
	@if pgrep -f "iodine" > /dev/null; then \
		pkill -f "iodine"; \
		echo "✅ Iodine processes stopped"; \
	fi

status-ruby:
	@echo "📊 Ruby backend status:"
	@if pgrep -f "ruby.*server.rb" > /dev/null; then \
		echo "✅ Ruby backend is running on port 4000"; \
		echo "PID: $$(pgrep -f 'ruby.*server.rb')"; \
		echo "📊 Testing health endpoint..."; \
		curl -s http://localhost:4000/health | jq . || echo "Health check failed or jq not installed"; \
	else \
		echo "❌ Ruby backend is not running"; \
	fi

ruby-test:
	@echo "🧪 Running Ruby backend tests..."
	@cd ruby-backend && bundle exec rspec --format documentation

ruby-shell:
	@echo "🐚 Entering Ruby backend directory..."
	@cd ruby-backend && bash

ruby-logs:
	@echo "📋 Ruby backend logs:"
	@if [ -f ruby-backend/server_output.log ]; then \
		tail -f ruby-backend/server_output.log; \
	else \
		echo "No log file found. Start the server first with 'make up-ruby'"; \
	fi

ruby-restart:
	@echo "🔄 Restarting Ruby backend..."
	@make down-ruby
	@sleep 1
	@make up-ruby