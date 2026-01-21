# Makefile for Spotik Ruby Backend Docker Management

.PHONY: help build up down logs shell test clean dev prod backup restore

# Default target
help: ## Show this help message
	@echo "Spotik Ruby Backend Docker Management"
	@echo "====================================="
	@echo ""
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# Development commands
dev: ## Start development environment
	docker-compose up -d
	@echo "Development environment started!"
	@echo "Ruby Backend: http://localhost:3000"
	@echo "Health Check: http://localhost:3000/health"
	@echo "PostgreSQL: localhost:5433"
	@echo "Redis: localhost:6380"

dev-build: ## Build and start development environment
	docker-compose build --no-cache
	docker-compose up -d

dev-logs: ## Show development logs
	docker-compose logs -f ruby-backend

dev-shell: ## Open shell in development container
	docker-compose exec ruby-backend sh

dev-db-shell: ## Open PostgreSQL shell in development
	docker-compose exec postgres psql -U spotik_user -d spotik_development

dev-redis-shell: ## Open Redis shell in development
	docker-compose exec redis redis-cli

dev-tools: ## Start development tools (pgAdmin, Redis Commander, Dozzle)
	docker-compose --profile tools up -d pgadmin redis-commander dozzle
	@echo "Development tools started:"
	@echo "pgAdmin: http://localhost:5050 (admin@spotik.local / admin123)"
	@echo "Redis Commander: http://localhost:8081"
	@echo "Dozzle (Logs): http://localhost:9999"

dev-stop: ## Stop development environment
	docker-compose down

dev-clean: ## Clean development environment (removes volumes)
	docker-compose down -v
	docker system prune -f

# Production commands
prod: ## Start production environment
	docker-compose -f docker-compose.prod.yml up -d
	@echo "Production environment started!"
	@echo "Application: http://localhost"
	@echo "Health Check: http://localhost/health"

prod-build: ## Build and start production environment
	docker-compose -f docker-compose.prod.yml build --no-cache
	docker-compose -f docker-compose.prod.yml up -d

prod-logs: ## Show production logs
	docker-compose -f docker-compose.prod.yml logs -f

prod-shell: ## Open shell in production container
	docker-compose -f docker-compose.prod.yml exec ruby-backend sh

prod-scale: ## Scale production backend (usage: make prod-scale REPLICAS=3)
	docker-compose -f docker-compose.prod.yml up -d --scale ruby-backend=$(REPLICAS)

prod-stop: ## Stop production environment
	docker-compose -f docker-compose.prod.yml down

prod-clean: ## Clean production environment (removes volumes)
	docker-compose -f docker-compose.prod.yml down -v
	docker system prune -f

# Database commands
db-backup: ## Create database backup
	docker-compose exec postgres-backup /backup.sh

db-restore: ## Restore database from backup (usage: make db-restore BACKUP_FILE=backup_20231201_120000.sql.gz)
	@if [ -z "$(BACKUP_FILE)" ]; then \
		echo "Usage: make db-restore BACKUP_FILE=backup_20231201_120000.sql.gz"; \
		exit 1; \
	fi
	docker-compose exec postgres sh -c "gunzip -c /backups/$(BACKUP_FILE) | psql -U $$DB_USER -d $$DB_NAME"

db-reset-dev: ## Reset development database with test data
	docker-compose exec postgres psql -U spotik_user -d spotik_development -c "SELECT reset_dev_data();"

db-generate-test-data: ## Generate test data for development (usage: make db-generate-test-data ROOM_ID=dev-room-1 COUNT=5)
	docker-compose exec postgres psql -U spotik_user -d spotik_development -c "SELECT generate_test_tracks('$(ROOM_ID)', $(COUNT));"

# Testing commands
test: ## Run tests in development environment
	docker-compose exec ruby-backend bundle exec rspec

test-unit: ## Run unit tests only
	docker-compose exec ruby-backend bundle exec rspec --tag ~property

test-property: ## Run property-based tests only
	docker-compose exec ruby-backend bundle exec rspec --tag property

test-coverage: ## Run tests with coverage report
	docker-compose exec ruby-backend bundle exec rspec --format documentation --format html --out coverage/rspec_results.html

# Utility commands
build: ## Build all images
	docker-compose build

up: ## Start services
	docker-compose up -d

down: ## Stop services
	docker-compose down

logs: ## Show logs for all services
	docker-compose logs -f

shell: ## Open shell in Ruby backend container
	docker-compose exec ruby-backend sh

clean: ## Clean up containers, networks, and volumes
	docker-compose down -v
	docker system prune -f
	docker volume prune -f

health: ## Check health of all services
	@echo "Checking service health..."
	@docker-compose ps
	@echo ""
	@echo "Ruby Backend Health:"
	@curl -s http://localhost:3000/health | jq . || echo "Ruby Backend not responding"
	@echo ""
	@echo "Database Health:"
	@docker-compose exec postgres pg_isready -U spotik_user -d spotik || echo "Database not ready"

status: ## Show status of all services
	docker-compose ps

restart: ## Restart all services
	docker-compose restart

# Monitoring commands
monitor: ## Show real-time resource usage
	docker stats

monitor-logs: ## Monitor logs in real-time
	docker-compose logs -f --tail=100

# Security commands
security-scan: ## Run security scan on images
	@echo "Scanning Ruby Backend image for vulnerabilities..."
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
		aquasec/trivy image ruby-backend_ruby-backend:latest

# Maintenance commands
update: ## Update all images to latest versions
	docker-compose pull
	docker-compose build --pull

prune: ## Remove unused Docker resources
	docker system prune -a -f
	docker volume prune -f

# Environment setup
setup-env: ## Setup environment files from templates
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "Created .env from .env.example"; \
	fi
	@if [ ! -f .env.production ]; then \
		echo ".env.production already exists"; \
	else \
		echo "Please configure .env.production for production deployment"; \
	fi

# Quick commands
quick-start: setup-env dev ## Quick start development environment
	@echo "Development environment is ready!"

quick-test: ## Quick test run
	docker-compose exec ruby-backend bundle exec rspec --format progress

quick-deploy: prod ## Quick production deployment
	@echo "Production environment deployed!"

# Variables
REPLICAS ?= 2
ROOM_ID ?= dev-room-1
COUNT ?= 5