# Configuration Management System for Spotik Ruby Backend
# Provides centralized configuration loading, validation, and management

require 'yaml'
require 'fileutils'
require 'dotenv/load'

module SpotikConfig
  class ConfigurationManager
    class << self
      attr_reader :config_data, :validation_errors, :validation_warnings
      
      # Configuration file paths
      CONFIG_DIR = File.join(File.dirname(__FILE__))
      DEFAULT_CONFIG_FILE = File.join(CONFIG_DIR, 'default.yml')
      ENVIRONMENT_CONFIG_FILE = File.join(CONFIG_DIR, "#{ENV.fetch('APP_ENV', 'development')}.yml")
      LOCAL_CONFIG_FILE = File.join(CONFIG_DIR, 'local.yml')
      
      def initialize_configuration
        @config_data = {}
        @validation_errors = []
        @validation_warnings = []
        
        # Load configuration in order of precedence
        load_default_configuration
        load_environment_configuration
        load_local_configuration
        load_environment_variables
        
        # Validate configuration
        validate_configuration
        
        # Log configuration status
        log_configuration_status
        
        @config_data
      end
      
      def get(key_path, default_value = nil)
        keys = key_path.to_s.split('.')
        value = @config_data
        
        keys.each do |key|
          if value.is_a?(Hash) && value.key?(key)
            value = value[key]
          else
            return default_value
          end
        end
        
        value
      end
      
      def set(key_path, value)
        keys = key_path.to_s.split('.')
        target = @config_data
        
        keys[0..-2].each do |key|
          target[key] ||= {}
          target = target[key]
        end
        
        target[keys.last] = value
      end
      
      def reload_configuration
        initialize_configuration
      end
      
      def configuration_valid?
        @validation_errors.empty?
      end
      
      def configuration_health
        {
          status: configuration_valid? ? 'healthy' : 'unhealthy',
          errors: @validation_errors,
          warnings: @validation_warnings,
          config_files_loaded: get_loaded_config_files,
          environment_variables_loaded: get_loaded_environment_variables,
          timestamp: Time.now.strftime('%Y-%m-%dT%H:%M:%S%z')
        }
      end
      
      def get_configuration_summary
        {
          app: {
            name: get('app.name'),
            environment: get('app.environment'),
            debug: get('app.debug'),
            version: get('app.version')
          },
          server: {
            host: get('server.host'),
            port: get('server.port'),
            threads: get('server.threads'),
            workers: get('server.workers')
          },
          database: {
            host: get('database.host'),
            port: get('database.port'),
            name: get('database.name'),
            pool_max: get('database.pool.max'),
            pool_timeout: get('database.pool.timeout')
          },
          storage: {
            audio_path: get('storage.audio_path'),
            public_path: get('storage.public_path'),
            temp_path: get('storage.temp_path')
          },
          security: {
            jwt_ttl: get('security.jwt.ttl'),
            rate_limiting_enabled: get('security.rate_limiting.enabled'),
            max_requests_per_hour: get('security.rate_limiting.max_requests_per_hour')
          },
          monitoring: {
            health_check_enabled: get('monitoring.health_check.enabled'),
            performance_monitoring_enabled: get('monitoring.performance.enabled'),
            logging_level: get('monitoring.logging.level')
          }
        }
      end
      
      private
      
      def load_default_configuration
        if File.exist?(DEFAULT_CONFIG_FILE)
          begin
            default_config = YAML.load_file(DEFAULT_CONFIG_FILE)
            @config_data = deep_merge(@config_data, default_config) if default_config
            @loaded_files ||= []
            @loaded_files << DEFAULT_CONFIG_FILE
          rescue => e
            @validation_errors << "Failed to load default configuration: #{e.message}"
          end
        else
          # Create default configuration if it doesn't exist
          create_default_configuration_file
        end
      end
      
      def load_environment_configuration
        if File.exist?(ENVIRONMENT_CONFIG_FILE)
          begin
            env_config = YAML.load_file(ENVIRONMENT_CONFIG_FILE)
            @config_data = deep_merge(@config_data, env_config) if env_config
            @loaded_files ||= []
            @loaded_files << ENVIRONMENT_CONFIG_FILE
          rescue => e
            @validation_errors << "Failed to load environment configuration: #{e.message}"
          end
        end
      end
      
      def load_local_configuration
        if File.exist?(LOCAL_CONFIG_FILE)
          begin
            local_config = YAML.load_file(LOCAL_CONFIG_FILE)
            @config_data = deep_merge(@config_data, local_config) if local_config
            @loaded_files ||= []
            @loaded_files << LOCAL_CONFIG_FILE
          rescue => e
            @validation_errors << "Failed to load local configuration: #{e.message}"
          end
        end
      end
      
      def load_environment_variables
        @loaded_env_vars = []
        
        # Application settings
        load_env_var('APP_NAME', 'app.name', 'Spotik')
        load_env_var('APP_ENV', 'app.environment', 'development')
        load_env_var('APP_DEBUG', 'app.debug', false, :boolean)
        load_env_var('APP_VERSION', 'app.version', '1.0.0')
        load_env_var('APP_URL', 'app.url', 'http://localhost:3000')
        
        # Server settings
        load_env_var('SERVER_HOST', 'server.host', '0.0.0.0')
        load_env_var('SERVER_PORT', 'server.port', 3000, :integer)
        load_env_var('SERVER_THREADS', 'server.threads', 4, :integer)
        load_env_var('SERVER_WORKERS', 'server.workers', 2, :integer)
        
        # Database settings
        load_env_var('DB_HOST', 'database.host', 'localhost')
        load_env_var('DB_PORT', 'database.port', 5432, :integer)
        load_env_var('DB_NAME', 'database.name', 'spotik')
        load_env_var('DB_USER', 'database.user', 'spotik_user')
        load_env_var('DB_PASSWORD', 'database.password', 'spotik_password')
        load_env_var('DB_POOL_MIN', 'database.pool.min', 2, :integer)
        load_env_var('DB_POOL_MAX', 'database.pool.max', 10, :integer)
        load_env_var('DB_POOL_TIMEOUT', 'database.pool.timeout', 5, :integer)
        load_env_var('DB_CONNECT_TIMEOUT', 'database.connect_timeout', 10, :integer)
        load_env_var('DB_READ_TIMEOUT', 'database.read_timeout', 30, :integer)
        
        # Storage settings
        load_env_var('AUDIO_STORAGE_PATH', 'storage.audio_path', './storage/audio')
        load_env_var('PUBLIC_STORAGE_PATH', 'storage.public_path', './storage/public')
        load_env_var('TEMP_STORAGE_PATH', 'storage.temp_path', './storage/temp')
        load_env_var('MAX_FILE_SIZE_MB', 'storage.max_file_size_mb', 50, :integer)
        load_env_var('ALLOWED_AUDIO_FORMATS', 'storage.allowed_audio_formats', 'mp3,wav,m4a,flac')
        
        # Security settings
        load_env_var('JWT_SECRET', 'security.jwt.secret', nil, :required)
        load_env_var('JWT_TTL', 'security.jwt.ttl', 1440, :integer)
        load_env_var('JWT_ALGORITHM', 'security.jwt.algorithm', 'HS256')
        load_env_var('BCRYPT_COST', 'security.bcrypt.cost', 12, :integer)
        
        # Rate limiting
        load_env_var('RATE_LIMITING_ENABLED', 'security.rate_limiting.enabled', true, :boolean)
        load_env_var('MAX_REQUESTS_PER_HOUR', 'security.rate_limiting.max_requests_per_hour', 1000, :integer)
        load_env_var('RATE_LIMIT_TIME_WINDOW', 'security.rate_limiting.time_window', 3600, :integer)
        
        # WebSocket settings
        load_env_var('WS_PING_INTERVAL', 'websocket.ping_interval', 30, :integer)
        load_env_var('WS_ACTIVITY_TIMEOUT', 'websocket.activity_timeout', 120, :integer)
        load_env_var('WS_MAX_CONNECTIONS', 'websocket.max_connections', 1000, :integer)
        
        # Monitoring settings
        load_env_var('HEALTH_CHECK_ENABLED', 'monitoring.health_check.enabled', true, :boolean)
        load_env_var('HEALTH_CHECK_ENDPOINT', 'monitoring.health_check.endpoint', '/health')
        load_env_var('PERFORMANCE_MONITORING_ENABLED', 'monitoring.performance.enabled', true, :boolean)
        load_env_var('SLOW_QUERY_THRESHOLD', 'monitoring.performance.slow_query_threshold', 1000, :integer)
        load_env_var('SLOW_REQUEST_THRESHOLD', 'monitoring.performance.slow_request_threshold', 2000, :integer)
        
        # Logging settings
        load_env_var('LOG_LEVEL', 'monitoring.logging.level', 'info')
        load_env_var('LOG_FILE', 'monitoring.logging.file', 'logs/spotik.log')
        load_env_var('LOG_MAX_SIZE_MB', 'monitoring.logging.max_size_mb', 100, :integer)
        load_env_var('LOG_MAX_FILES', 'monitoring.logging.max_files', 5, :integer)
        load_env_var('LOG_FORMAT', 'monitoring.logging.format', 'json')
        
        # Cache settings
        load_env_var('CACHE_ENABLED', 'cache.enabled', true, :boolean)
        load_env_var('CACHE_TTL', 'cache.ttl', 300, :integer)
        load_env_var('CACHE_MAX_SIZE', 'cache.max_size', 1000, :integer)
        
        # Development settings
        load_env_var('HOT_RELOAD_ENABLED', 'development.hot_reload', false, :boolean)
        load_env_var('DEBUG_SQL', 'development.debug_sql', false, :boolean)
        load_env_var('CORS_ENABLED', 'development.cors_enabled', true, :boolean)
        load_env_var('CORS_ORIGINS', 'development.cors_origins', '*')
      end
      
      def load_env_var(env_key, config_key, default_value, type = :string)
        env_value = ENV[env_key]
        
        if env_value.nil?
          if type == :required
            @validation_errors << "Required environment variable #{env_key} is not set"
            return
          else
            set(config_key, default_value)
            return
          end
        end
        
        # Convert value based on type
        converted_value = case type
        when :integer
          begin
            Integer(env_value)
          rescue ArgumentError
            @validation_warnings << "Invalid integer value for #{env_key}: #{env_value}, using default: #{default_value}"
            default_value
          end
        when :boolean
          case env_value.downcase
          when 'true', '1', 'yes', 'on'
            true
          when 'false', '0', 'no', 'off'
            false
          else
            @validation_warnings << "Invalid boolean value for #{env_key}: #{env_value}, using default: #{default_value}"
            default_value
          end
        when :float
          begin
            Float(env_value)
          rescue ArgumentError
            @validation_warnings << "Invalid float value for #{env_key}: #{env_value}, using default: #{default_value}"
            default_value
          end
        when :array
          env_value.split(',').map(&:strip)
        else
          env_value
        end
        
        set(config_key, converted_value)
        @loaded_env_vars << { key: env_key, config_path: config_key, value: converted_value }
      end
      
      def validate_configuration
        validate_required_settings
        validate_database_configuration
        validate_storage_configuration
        validate_security_configuration
        validate_server_configuration
        validate_monitoring_configuration
      end
      
      def validate_required_settings
        required_settings = [
          'app.name',
          'app.environment',
          'server.host',
          'server.port',
          'database.host',
          'database.name',
          'database.user',
          'security.jwt.secret'
        ]
        
        required_settings.each do |setting|
          value = get(setting)
          if value.nil? || (value.is_a?(String) && value.empty?)
            @validation_errors << "Required setting '#{setting}' is missing or empty"
          end
        end
      end
      
      def validate_database_configuration
        # Validate database connection parameters
        db_host = get('database.host')
        db_port = get('database.port')
        db_name = get('database.name')
        
        if db_port && (db_port < 1 || db_port > 65535)
          @validation_errors << "Database port must be between 1 and 65535, got: #{db_port}"
        end
        
        # Validate connection pool settings
        pool_min = get('database.pool.min')
        pool_max = get('database.pool.max')
        
        if pool_min && pool_max && pool_min > pool_max
          @validation_errors << "Database pool min (#{pool_min}) cannot be greater than max (#{pool_max})"
        end
        
        if pool_max && pool_max < 1
          @validation_errors << "Database pool max must be at least 1, got: #{pool_max}"
        end
        
        # Validate timeout settings
        connect_timeout = get('database.connect_timeout')
        read_timeout = get('database.read_timeout')
        
        if connect_timeout && connect_timeout < 1
          @validation_warnings << "Database connect timeout is very low: #{connect_timeout}s"
        end
        
        if read_timeout && read_timeout < 1
          @validation_warnings << "Database read timeout is very low: #{read_timeout}s"
        end
      end
      
      def validate_storage_configuration
        # Validate storage paths
        audio_path = get('storage.audio_path')
        public_path = get('storage.public_path')
        temp_path = get('storage.temp_path')
        
        [audio_path, public_path, temp_path].each do |path|
          next unless path
          
          begin
            # Create directory if it doesn't exist
            FileUtils.mkdir_p(path) unless File.exist?(path)
            
            # Check if directory is writable
            unless File.writable?(path)
              @validation_errors << "Storage path is not writable: #{path}"
            end
          rescue => e
            @validation_errors << "Cannot create or access storage path #{path}: #{e.message}"
          end
        end
        
        # Validate file size limits
        max_file_size = get('storage.max_file_size_mb')
        if max_file_size && max_file_size < 1
          @validation_warnings << "Maximum file size is very small: #{max_file_size}MB"
        end
        
        # Validate audio formats
        allowed_formats = get('storage.allowed_audio_formats')
        if allowed_formats.is_a?(String)
          formats = allowed_formats.split(',').map(&:strip)
          valid_formats = %w[mp3 wav m4a flac aac ogg]
          
          invalid_formats = formats - valid_formats
          if invalid_formats.any?
            @validation_warnings << "Unknown audio formats configured: #{invalid_formats.join(', ')}"
          end
        end
      end
      
      def validate_security_configuration
        # Validate JWT settings
        jwt_secret = get('security.jwt.secret')
        if jwt_secret && jwt_secret.length < 32
          @validation_warnings << "JWT secret is shorter than recommended 32 characters"
        end
        
        jwt_ttl = get('security.jwt.ttl')
        if jwt_ttl && jwt_ttl < 60
          @validation_warnings << "JWT TTL is very short: #{jwt_ttl} minutes"
        end
        
        # Validate bcrypt cost
        bcrypt_cost = get('security.bcrypt.cost')
        if bcrypt_cost && (bcrypt_cost < 10 || bcrypt_cost > 15)
          @validation_warnings << "BCrypt cost should be between 10-15 for security/performance balance, got: #{bcrypt_cost}"
        end
        
        # Validate rate limiting
        max_requests = get('security.rate_limiting.max_requests_per_hour')
        if max_requests && max_requests < 10
          @validation_warnings << "Rate limit is very restrictive: #{max_requests} requests per hour"
        end
      end
      
      def validate_server_configuration
        # Validate server settings
        port = get('server.port')
        if port && (port < 1024 || port > 65535)
          @validation_warnings << "Server port #{port} may require elevated privileges or is invalid"
        end
        
        threads = get('server.threads')
        workers = get('server.workers')
        
        if threads && threads < 1
          @validation_errors << "Server threads must be at least 1, got: #{threads}"
        end
        
        if workers && workers < 1
          @validation_errors << "Server workers must be at least 1, got: #{workers}"
        end
        
        if threads && workers && (threads * workers) > 50
          @validation_warnings << "High thread/worker combination (#{threads}x#{workers}=#{threads*workers}) may consume excessive resources"
        end
      end
      
      def validate_monitoring_configuration
        # Validate logging settings
        log_level = get('monitoring.logging.level')
        valid_levels = %w[debug info warn error fatal]
        
        if log_level && !valid_levels.include?(log_level.downcase)
          @validation_errors << "Invalid log level: #{log_level}. Valid levels: #{valid_levels.join(', ')}"
        end
        
        # Validate log file settings
        log_file = get('monitoring.logging.file')
        if log_file
          log_dir = File.dirname(log_file)
          begin
            FileUtils.mkdir_p(log_dir) unless File.exist?(log_dir)
          rescue => e
            @validation_errors << "Cannot create log directory #{log_dir}: #{e.message}"
          end
        end
        
        # Validate performance thresholds
        slow_query = get('monitoring.performance.slow_query_threshold')
        slow_request = get('monitoring.performance.slow_request_threshold')
        
        if slow_query && slow_query < 100
          @validation_warnings << "Slow query threshold is very low: #{slow_query}ms"
        end
        
        if slow_request && slow_request < 500
          @validation_warnings << "Slow request threshold is very low: #{slow_request}ms"
        end
      end
      
      def create_default_configuration_file
        default_config = {
          'app' => {
            'name' => 'Spotik',
            'environment' => 'development',
            'debug' => false,
            'version' => '1.0.0'
          },
          'server' => {
            'host' => '0.0.0.0',
            'port' => 3000,
            'threads' => 4,
            'workers' => 2
          },
          'database' => {
            'host' => 'localhost',
            'port' => 5432,
            'name' => 'spotik',
            'user' => 'spotik_user',
            'pool' => {
              'min' => 2,
              'max' => 10,
              'timeout' => 5
            },
            'connect_timeout' => 10,
            'read_timeout' => 30
          },
          'storage' => {
            'audio_path' => './storage/audio',
            'public_path' => './storage/public',
            'temp_path' => './storage/temp',
            'max_file_size_mb' => 50,
            'allowed_audio_formats' => 'mp3,wav,m4a,flac'
          },
          'security' => {
            'jwt' => {
              'ttl' => 1440,
              'algorithm' => 'HS256'
            },
            'bcrypt' => {
              'cost' => 12
            },
            'rate_limiting' => {
              'enabled' => true,
              'max_requests_per_hour' => 1000,
              'time_window' => 3600
            }
          },
          'websocket' => {
            'ping_interval' => 30,
            'activity_timeout' => 120,
            'max_connections' => 1000
          },
          'monitoring' => {
            'health_check' => {
              'enabled' => true,
              'endpoint' => '/health'
            },
            'performance' => {
              'enabled' => true,
              'slow_query_threshold' => 1000,
              'slow_request_threshold' => 2000
            },
            'logging' => {
              'level' => 'info',
              'file' => 'logs/spotik.log',
              'max_size_mb' => 100,
              'max_files' => 5,
              'format' => 'json'
            }
          },
          'cache' => {
            'enabled' => true,
            'ttl' => 300,
            'max_size' => 1000
          },
          'development' => {
            'hot_reload' => false,
            'debug_sql' => false,
            'cors_enabled' => true,
            'cors_origins' => '*'
          }
        }
        
        begin
          File.write(DEFAULT_CONFIG_FILE, default_config.to_yaml)
          @loaded_files ||= []
          @loaded_files << DEFAULT_CONFIG_FILE
          @config_data = deep_merge(@config_data, default_config)
        rescue => e
          @validation_errors << "Failed to create default configuration file: #{e.message}"
        end
      end
      
      def deep_merge(hash1, hash2)
        result = hash1.dup
        
        hash2.each do |key, value|
          if result[key].is_a?(Hash) && value.is_a?(Hash)
            result[key] = deep_merge(result[key], value)
          else
            result[key] = value
          end
        end
        
        result
      end
      
      def get_loaded_config_files
        @loaded_files || []
      end
      
      def get_loaded_environment_variables
        @loaded_env_vars || []
      end
      
      def log_configuration_status
        return unless defined?($logger) && $logger
        
        if configuration_valid?
          $logger.info "Configuration loaded successfully"
          $logger.info "Config files: #{get_loaded_config_files.join(', ')}"
          $logger.info "Environment variables: #{@loaded_env_vars.length} loaded"
          
          if @validation_warnings.any?
            $logger.warn "Configuration warnings:"
            @validation_warnings.each { |warning| $logger.warn "  - #{warning}" }
          end
        else
          $logger.error "Configuration validation failed:"
          @validation_errors.each { |error| $logger.error "  - #{error}" }
          
          if @validation_warnings.any?
            $logger.warn "Configuration warnings:"
            @validation_warnings.each { |warning| $logger.warn "  - #{warning}" }
          end
        end
      end
    end
  end
  
  # Configuration validation error
  class ConfigurationError < StandardError
    attr_reader :validation_errors, :validation_warnings
    
    def initialize(message, validation_errors = [], validation_warnings = [])
      super(message)
      @validation_errors = validation_errors
      @validation_warnings = validation_warnings
    end
  end
end