# Spotik - Collaborative Music Streaming

Spotik is a web application that provides collaborative music listening experiences through shared rooms. Users can create or join rooms, upload audio files, and listen to music synchronously with other participants.

## Features

- **Real-time Synchronized Playback**: All users hear the same audio at the same time
- **Room Management**: Create and join music rooms with other users
- **File Upload**: Upload and share audio files (MP3, WAV, M4A)
- **Voting System**: Vote for tracks to influence queue ordering
- **WebSocket Communication**: Real-time updates for all room activities
- **JWT Authentication**: Secure user authentication and session management

## Technology Stack

### Backend
- **Laravel 12** - API framework with WebSocket broadcasting
- **PostgreSQL** - Primary database for users, rooms, and tracks
- **Redis** - WebSocket message broadcasting and caching
- **JWT Authentication** - Stateless user authentication
- **Laravel Reverb** - Real-time WebSocket server

### Frontend
- **Vue 3** - Reactive user interface with Composition API
- **Pinia** - State management
- **Vue Router** - Client-side routing
- **Tailwind CSS** - Utility-first CSS framework
- **Vite** - Fast build tool and development server

### Infrastructure
- **Docker** - Containerization for all services
- **docker-compose** - Multi-container orchestration
- **Nginx** - Reverse proxy and static file serving (production)

## 🚀 Быстрый запуск

### Требования
- Docker и Docker Compose
- Git

### Автоматический запуск

1. **Клонируйте репозиторий**
   ```bash
   git clone <repository-url>
   cd spotik
   ```

2. **Запустите приложение одной командой**
   ```bash
   ./start.sh
   ```

   Скрипт автоматически:
   - Проверит наличие Docker
   - Создаст необходимые директории
   - Скопирует файлы окружения
   - Соберет и запустит все контейнеры
   - Выполнит миграции базы данных
   - Установит зависимости

3. **Откройте приложение**
   - Frontend: http://localhost:3000
   - Backend API: http://localhost:8000
   - WebSocket: ws://localhost:8080

### Ручная настройка

Если предпочитаете ручную настройку:

1. **Настройте файлы окружения**
   ```bash
   cp .env.example .env
   cp backend/.env.example backend/.env
   ```

3. **Start the development environment**
   ```bash
   docker-compose up -d
   ```

4. **Install dependencies and set up the backend**
   ```bash
   # Install Laravel dependencies
   docker-compose exec backend composer install
   
   # Generate application key
   docker-compose exec backend php artisan key:generate
   
   # Generate JWT secret
   docker-compose exec backend php artisan jwt:secret
   
   # Run database migrations
   docker-compose exec backend php artisan migrate
   ```

5. **Install frontend dependencies**
   ```bash
   # Install Node.js dependencies
   docker-compose exec frontend npm install
   ```

6. **Access the application**
   - Frontend: http://localhost:3000
   - Backend API: http://localhost:8000
   - WebSocket: ws://localhost:6001

### Production Deployment

1. **Set up production environment**
   ```bash
   cp .env.production.example .env
   # Edit .env with your production values
   ```

2. **Deploy with production compose file**
   ```bash
   docker-compose -f docker-compose.prod.yml up -d
   ```

## Development

### Project Structure

```
spotik/
├── backend/                 # Laravel API backend
│   ├── app/                # Application code
│   ├── config/             # Configuration files
│   ├── database/           # Migrations and seeders
│   ├── routes/             # API routes
│   └── docker/             # Docker configuration
├── frontend/               # Vue.js frontend
│   ├── src/                # Source code
│   │   ├── components/     # Vue components
│   │   ├── views/          # Page components
│   │   ├── stores/         # Pinia stores
│   │   └── services/       # API services
│   └── docker/             # Docker configuration
├── docker/                 # Shared Docker configs
└── .kiro/                  # Project specifications
```

### Available Commands

**Backend (Laravel)**
```bash
# Run migrations
docker-compose exec backend php artisan migrate

# Create new migration
docker-compose exec backend php artisan make:migration create_table_name

# Run tests
docker-compose exec backend php artisan test

# Clear caches
docker-compose exec backend php artisan cache:clear
docker-compose exec backend php artisan config:clear
```

**Frontend (Vue.js)**
```bash
# Install dependencies
docker-compose exec frontend npm install

# Run development server
docker-compose exec frontend npm run dev

# Build for production
docker-compose exec frontend npm run build

# Run tests
docker-compose exec frontend npm run test
```

**WebSocket Server**
```bash
# Start WebSocket server
docker-compose exec backend php artisan websockets:serve
```

### API Documentation

The API follows RESTful conventions. Key endpoints:

- `POST /api/auth/register` - User registration
- `POST /api/auth/login` - User login
- `GET /api/rooms` - List rooms
- `POST /api/rooms` - Create room
- `POST /api/rooms/{id}/join` - Join room
- `POST /api/rooms/{id}/tracks` - Upload track
- `POST /api/rooms/{id}/tracks/{track}/vote` - Vote for track

### WebSocket Events

Real-time events broadcasted to room participants:

- `UserJoined` - User joins room
- `UserLeft` - User leaves room
- `TrackAdded` - New track added to queue
- `TrackVoted` - Track receives vote
- `PlaybackStarted` - Track playback begins
- `PlaybackPaused` - Track playback paused
- `PlaybackResumed` - Track playback resumed
- `TrackSkipped` - Track skipped to next

## Testing

The project uses both unit tests and property-based tests:

### Backend Testing
```bash
# Run all tests
docker-compose exec backend php artisan test

# Run specific test
docker-compose exec backend php artisan test --filter=AuthenticationTest
```

### Frontend Testing
```bash
# Run unit tests
docker-compose exec frontend npm run test

# Run tests with coverage
docker-compose exec frontend npm run test:coverage
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

For support, please open an issue in the GitHub repository or contact the development team.# Spotik
