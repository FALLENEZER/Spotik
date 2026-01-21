# Application settings and configuration
# Legacy compatibility layer for existing code
# New code should use ConfigurationService instead

require 'dotenv/load'
require_relative '../app/services/configuration_service'

module SpotikConfig
  class Settings
    class << self
      # Initialize configuration on first access
      def ensure_configuration_loaded
        return if @configuration_loaded
        
        begin
          ConfigurationService.initialize_configuration
          @configuration_loaded = true
        rescue => e
          # Fall back to environment variables if configuration system fails
          puts "Warning: Configuration system failed, falling back to environment variables: #{e.message}"
          @configuration_loaded = false
        end
      end
      
      def app_name
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('app.name', 'Spotik') : ENV.fetch('APP_NAME', 'Spotik')
      end

      def app_env
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('app.environment', 'development') : ENV.fetch('APP_ENV', 'development')
      end

      def app_debug?
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('app.debug', false) : (ENV.fetch('APP_DEBUG', 'false') == 'true')
      end

      def server_host
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('server.host', '0.0.0.0') : ENV.fetch('SERVER_HOST', '0.0.0.0')
      end

      def server_port
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('server.port', 3000) : ENV.fetch('SERVER_PORT', 3000).to_i
      end

      def server_threads
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('server.threads', 4) : ENV.fetch('SERVER_THREADS', 4).to_i
      end

      def server_workers
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('server.workers', 2) : ENV.fetch('SERVER_WORKERS', 2).to_i
      end

      def jwt_secret
        ensure_configuration_loaded
        secret = @configuration_loaded ? ConfigurationService.get('security.jwt.secret') : ENV['JWT_SECRET']
        
        if secret.nil? || secret.empty?
          raise 'JWT_SECRET environment variable is required'
        end
        
        secret
      end

      def jwt_ttl
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('security.jwt.ttl', 1440) : ENV.fetch('JWT_TTL', 1440).to_i
      end

      def audio_storage_path
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('storage.audio_path', './storage/audio') : ENV.fetch('AUDIO_STORAGE_PATH', './storage/audio')
      end

      def public_storage_path
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('storage.public_path', './storage/public') : ENV.fetch('PUBLIC_STORAGE_PATH', './storage/public')
      end

      def log_level
        ensure_configuration_loaded
        level = @configuration_loaded ? ConfigurationService.get('monitoring.logging.level', 'info') : ENV.fetch('LOG_LEVEL', 'info')
        level.to_sym
      end

      def log_file
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('monitoring.logging.file', 'logs/spotik.log') : ENV.fetch('LOG_FILE', 'logs/spotik.log')
      end

      def websocket_ping_interval
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('websocket.ping_interval', 30) : ENV.fetch('WS_PING_INTERVAL', 30).to_i
      end

      def websocket_activity_timeout
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('websocket.activity_timeout', 120) : ENV.fetch('WS_ACTIVITY_TIMEOUT', 120).to_i
      end

      def performance_monitoring_enabled?
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('monitoring.performance.enabled', true) : (ENV.fetch('ENABLE_PERFORMANCE_MONITORING', 'true') == 'true')
      end

      def slow_query_threshold
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('monitoring.performance.slow_query_threshold', 1000) : ENV.fetch('SLOW_QUERY_THRESHOLD', 1000).to_i
      end

      def slow_request_threshold
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('monitoring.performance.slow_request_threshold', 2000) : ENV.fetch('SLOW_REQUEST_THRESHOLD', 2000).to_i
      end

      def health_check_enabled?
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('monitoring.health_check.enabled', true) : (ENV.fetch('HEALTH_CHECK_ENABLED', 'true') == 'true')
      end

      def health_check_endpoint
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('monitoring.health_check.endpoint', '/health') : ENV.fetch('HEALTH_CHECK_ENDPOINT', '/health')
      end

      def development?
        app_env == 'development'
      end

      def production?
        app_env == 'production'
      end

      def test?
        app_env == 'test'
      end
      
      # Additional configuration methods for new features
      def max_file_size_mb
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('storage.max_file_size_mb', 50) : ENV.fetch('MAX_FILE_SIZE_MB', 50).to_i
      end
      
      def rate_limiting_enabled?
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('security.rate_limiting.enabled', true) : (ENV.fetch('RATE_LIMITING_ENABLED', 'true') == 'true')
      end
      
      def max_requests_per_hour
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('security.rate_limiting.max_requests_per_hour', 1000) : ENV.fetch('MAX_REQUESTS_PER_HOUR', 1000).to_i
      end
      
      def websocket_max_connections
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('websocket.max_connections', 1000) : ENV.fetch('WS_MAX_CONNECTIONS', 1000).to_i
      end
      
      def bcrypt_cost
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('security.bcrypt.cost', 12) : ENV.fetch('BCRYPT_COST', 12).to_i
      end
      
      def cache_enabled?
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('cache.enabled', true) : (ENV.fetch('CACHE_ENABLED', 'true') == 'true')
      end
      
      def cache_ttl
        ensure_configuration_loaded
        @configuration_loaded ? ConfigurationService.get('cache.ttl', 300) : ENV.fetch('CACHE_TTL', 300).to_i
      end
    end
  end
end