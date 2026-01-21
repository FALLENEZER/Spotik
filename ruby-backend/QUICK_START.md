# Quick Start Guide

## Prerequisites

- Ruby 3.2+ installed
- PostgreSQL database (same as Laravel backend)
- Bundler gem installed

## Setup

1. **Install dependencies:**
   ```bash
   bundle install
   ```

2. **Configure environment:**
   ```bash
   cp .env.example .env
   # Edit .env with your database credentials
   ```

3. **Run setup script:**
   ```bash
   ./bin/setup
   ```

## Running the Server

### Development Mode
```bash
# Basic start
ruby server.rb

# Auto-restart on file changes
bundle exec rerun ruby server.rb
```

### Testing
```bash
# Run all tests
bundle exec rspec

# Run specific test
bundle exec rspec spec/server_spec.rb

# Run with coverage
bundle exec rspec --format documentation
```

### Manual Testing
```bash
# Test server endpoints (requires jq and curl)
./bin/test-server
```

## Endpoints

- `GET /health` - Health check
- `GET /api` - API information
- `GET /ws` - WebSocket upgrade endpoint

## Next Steps

1. Implement database models (Task 2)
2. Add authentication endpoints (Task 3)
3. Create room management (Task 4)
4. Add WebSocket functionality (Task 7)

## Troubleshooting

### Database Connection Issues
- Ensure PostgreSQL is running
- Check database credentials in `.env`
- Verify database exists and is accessible

### Port Already in Use
- Change `SERVER_PORT` in `.env`
- Or kill existing process: `lsof -ti:3000 | xargs kill`

### Ruby Version Issues
- Ensure Ruby 3.2+ is installed
- Use rbenv or rvm to manage Ruby versions