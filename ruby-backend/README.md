# Spotik Ruby Backend

Ruby backend migration for Spotik - a collaborative music listening application with synchronized playback.

## Overview

This Ruby backend replaces the existing Laravel backend while maintaining full compatibility with:
- Existing PostgreSQL database schema
- Vue.js frontend application
- All API endpoints and WebSocket events
- Audio file storage and serving

## Key Features

- **Native WebSocket Support**: Built-in WebSocket handling with Iodine server
- **High Performance**: Optimized for concurrent connections and real-time events
- **Database Compatibility**: Uses existing PostgreSQL database without changes
- **API Compatibility**: Maintains exact same REST API as Laravel version
- **Real-time Synchronization**: Synchronized audio playback across all room participants

## Technology Stack

- **Ruby 3.2+**: Main programming language
- **Iodine**: High-performance HTTP/WebSocket server
- **Sinatra**: Lightweight web framework for REST API
- **Sequel ORM**: Database abstraction layer for PostgreSQL
- **JWT**: Authentication token management
- **BCrypt**: Password hashing (Laravel compatible)

## Project Structure

```
ruby-backend/
├── server.rb              # Main server file
├── Gemfile                 # Ruby dependencies
├── config/
│   ├── database.rb         # Database configuration
│   └── settings.rb         # Application settings
├── app/
│   ├── models/             # Sequel database models
│   ├── controllers/        # HTTP API controllers
│   ├── services/           # Business logic services
│   └── websocket/          # WebSocket handling
├── spec/                   # Test files
├── logs/                   # Application logs
└── public/                 # Static files
```

## Installation

1. **Install Ruby 3.2+**
   ```bash
   # Using rbenv
   rbenv install 3.2.0
   rbenv local 3.2.0
   ```

2. **Install dependencies**
   ```bash
   bundle install
   ```

3. **Configure environment**
   ```bash
   cp .env.example .env
   # Edit .env with your database credentials
   ```

4. **Start the server**
   ```bash
   ruby server.rb
   ```

## Configuration

The application uses environment variables for configuration. Key settings:

### Database
- `DB_HOST`: PostgreSQL host (default: postgres)
- `DB_PORT`: PostgreSQL port (default: 5432)
- `DB_NAME`: Database name (default: spotik)
- `DB_USER`: Database username
- `DB_PASSWORD`: Database password

### Server
- `SERVER_HOST`: Server bind address (default: 0.0.0.0)
- `SERVER_PORT`: Server port (default: 3000)
- `SERVER_THREADS`: Number of threads (default: 4)
- `SERVER_WORKERS`: Number of workers (default: 2)

### Authentication
- `JWT_SECRET`: JWT signing secret (must match Laravel)
- `JWT_TTL`: Token lifetime in minutes (default: 1440)

### Storage
- `AUDIO_STORAGE_PATH`: Path to audio files storage
- `PUBLIC_STORAGE_PATH`: Path to public files

## Development

### Running in Development
```bash
# Auto-restart on file changes
bundle exec rerun ruby server.rb

# Or manually
ruby server.rb
```

### Running Tests
```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/models/user_spec.rb

# Run property-based tests
bundle exec rspec --tag property
```

### Code Style
```bash
# Check code style
bundle exec rubocop

# Auto-fix issues
bundle exec rubocop -a
```

## API Endpoints

The Ruby backend maintains exact compatibility with the Laravel API:

### Authentication
- `POST /api/auth/login` - User login
- `POST /api/auth/register` - User registration
- `GET /api/auth/me` - Get current user

### Rooms
- `GET /api/rooms` - List all rooms
- `POST /api/rooms` - Create new room
- `GET /api/rooms/:id` - Get room details
- `POST /api/rooms/:id/join` - Join room
- `DELETE /api/rooms/:id/leave` - Leave room

### Tracks
- `GET /api/rooms/:id/tracks` - Get room track queue
- `POST /api/rooms/:id/tracks` - Upload new track
- `POST /api/tracks/:id/vote` - Vote for track
- `DELETE /api/tracks/:id/vote` - Remove vote

### Playback
- `POST /api/rooms/:id/play` - Start playback
- `POST /api/rooms/:id/pause` - Pause playback
- `POST /api/rooms/:id/resume` - Resume playback
- `POST /api/rooms/:id/skip` - Skip current track

## WebSocket Events

Real-time events are broadcast to room participants:

### User Events
- `user_joined` - User joins room
- `user_left` - User leaves room

### Track Events
- `track_added` - New track added to queue
- `track_voted` - Track vote count changed
- `queue_updated` - Track queue reordered

### Playback Events
- `playback_started` - Track playback started
- `playback_paused` - Playback paused
- `playback_resumed` - Playback resumed
- `playback_stopped` - Playback stopped
- `track_ended` - Current track finished

## Performance

The Ruby backend is optimized for:
- **High Concurrency**: Handles 1000+ concurrent WebSocket connections
- **Low Latency**: Sub-100ms WebSocket message delivery
- **Memory Efficiency**: Lower memory usage than Laravel + Redis
- **Fast Startup**: Quick server initialization and restart

## Monitoring

Built-in monitoring and health checks:
- `GET /health` - Server health status
- Performance metrics logging
- Slow query detection
- WebSocket connection monitoring

## Migration from Laravel

The Ruby backend is designed for seamless migration:

1. **Database**: Uses existing PostgreSQL schema without changes
2. **Files**: Reads existing audio files from Laravel storage
3. **Authentication**: Compatible with existing user passwords and JWT tokens
4. **API**: Maintains exact same endpoints and response formats
5. **WebSocket**: Replaces Laravel Broadcasting with native WebSocket

## Deployment

### Docker
```bash
# Build image
docker build -t spotik-ruby-backend .

# Run container
docker run -p 3000:3000 --env-file .env spotik-ruby-backend
```

### Production
```bash
# Set production environment
export APP_ENV=production

# Start with multiple workers
ruby server.rb
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Write tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

This project is part of the Spotik application migration.