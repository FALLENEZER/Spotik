#!/bin/bash

# Spotik - Collaborative Music Streaming Application
# Startup script

echo "🎵 Запуск Spotik - Collaborative Music Streaming Application"
echo "=================================================="

# Проверяем наличие Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker не установлен. Пожалуйста, установите Docker и Docker Compose."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose не установлен. Пожалуйста, установите Docker Compose."
    exit 1
fi

echo "✅ Docker и Docker Compose найдены"

# Создаем необходимые директории
echo "📁 Создание необходимых директорий..."
mkdir -p backend/storage/logs
mkdir -p backend/storage/app/audio/tracks
mkdir -p backend/bootstrap/cache

# Копируем файлы окружения если они не существуют
if [ ! -f backend/.env ]; then
    echo "📝 Создание файла окружения backend..."
    cp backend/.env.example backend/.env 2>/dev/null || echo "Файл .env.example не найден"
fi

if [ ! -f frontend/.env ]; then
    echo "📝 Создание файла окружения frontend..."
    cp frontend/.env.example frontend/.env 2>/dev/null || echo "Файл .env.example не найден"
fi

# Останавливаем существующие контейнеры
echo "🛑 Остановка существующих контейнеров..."
docker-compose down

# Собираем и запускаем контейнеры
echo "🔨 Сборка и запуск контейнеров..."
docker-compose up --build -d

# Ждем запуска базы данных
echo "⏳ Ожидание запуска базы данных..."
sleep 10

# Выполняем миграции
echo "🗄️ Выполнение миграций базы данных..."
docker-compose exec backend php artisan migrate --force

# Устанавливаем зависимости frontend
echo "📦 Установка зависимостей frontend..."
docker-compose exec frontend npm install

echo ""
echo "🎉 Spotik успешно запущен!"
echo "=================================================="
echo "🌐 Frontend: http://localhost:3000"
echo "🔧 Backend API: http://localhost:8000"
echo "🔌 WebSocket: ws://localhost:8080"
echo "🗄️ PostgreSQL: localhost:5432"
echo "🔴 Redis: localhost:6379"
echo ""
echo "📋 Полезные команды:"
echo "  docker-compose logs -f          # Просмотр логов"
echo "  docker-compose down             # Остановка"
echo "  docker-compose exec backend php artisan tinker  # Laravel консоль"
echo ""
echo "📖 Документация: README.md"