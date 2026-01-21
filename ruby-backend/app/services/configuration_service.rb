# Configuration Service for Spotik Ruby Backend
# Provides runtime configuration management and validation

require_relative '../../config/configuration_manager'

class ConfigurationService
  class << self
    attr_reader :config_manager
    
    def initialize_configuration
      @config_manager = SpotikConfig::ConfigurationManager
      @config_manager.initialize_configuration
      
      # Validate configuration on startup
      unless @config_manager.configuration_valid?
        raise SpotikConfig::ConfigurationError.new(
          "Configuration validation failed",
          @config_manager.validation_errors,
          @config_manager.validation_warnings
        )
      end
      
      # Log warnings if any
      if @config_manager.validation_warnings.any?
        @config_manager.validation_warnings.each do |warning|
          $logger&.warn "Configuration warning: #{warning}"
        end
      end
      
      @config_manager.config_data
    end
    
    def get(key_path, default_value = nil)
      @config_manager&.get(key_path, default_value)
    end
    
    def set(key_path, value)
      @config_manager&.set(key_path, value)
    end
    
    def reload_configuration
      @config_manager&.reload_configuration
    end
    
    def configuration_health
      @config_manager&.configuration_health || {
        status: 'error',
        message: 'Configuration manager not initialized'
      }
    end
    
    def configuration_summary
      @config_manager&.get_configuration_summary || {}
    end
    
    def validate_runtime_configuration
      validation_results = {
        status: 'valid',
        checks: [],
        errors: [],
        warnings: []
      }
      
      # Check database connectivity
      check_database_connectivity(validation_results)
      
      # Check storage paths accessibility
      check_storage_accessibility(validation_results)
      
      # Check required services
      check_required_services(validation_results)
      
      # Check resource limits
      check_resource_limits(validation_results)
      
      # Set overall status
      if validation_results[:errors].any?
        validation_results[:status] = 'invalid'
      elsif validation_results[:warnings].any?
        validation_results[:status] = 'warning'
      end
      
      validation_results
    end
    
    def get_environment_info
      {
        app_environment: get('app.environment'),
        ruby_version: RUBY_VERSION,
        ruby_platform: RUBY_PLATFORM,
        server_host: get('server.host'),
        server_port: get('server.port'),
        database_host: get('database.host'),
        database_name: get('database.name'),
        storage_paths: {
          audio: get('storage.audio_path'),
          public: get('storage.public_path'),
          temp: get('storage.temp_path')
        },
        monitoring_enabled: get('monitoring.performance.enabled'),
        debug_mode: get('app.debug'),
        timestamp: Time.now.iso8601
      }
    end
    
    def get_security_configuration
      {
        jwt_ttl_minutes: get('security.jwt.ttl'),
        jwt_algorithm: get('security.jwt.algorithm'),
        bcrypt_cost: get('security.bcrypt.cost'),
        rate_limiting_enabled: get('security.rate_limiting.enabled'),
        max_requests_per_hour: get('security.rate_limiting.max_requests_per_hour'),
        websocket_max_connections: get('websocket.max_connections'),
        cors_enabled: get('development.cors_enabled'),
        cors_origins: get('development.cors_origins')
      }
    end
    
    def get_performance_configuration
      {
        server_threads: get('server.threads'),
        server_workers: get('server.workers'),
        database_pool_max: get('database.pool.max'),
        database_pool_timeout: get('database.pool.timeout'),
        slow_query_threshold: get('monitoring.performance.slow_query_threshold'),
        slow_request_threshold: get('monitoring.performance.slow_request_threshold'),
        cache_enabled: get('cache.enabled'),
        cache_ttl: get('cache.ttl'),
        websocket_ping_interval: get('websocket.ping_interval'),
        websocket_activity_timeout: get('websocket.activity_timeout')
      }
    end
    
    def update_runtime_setting(key_path, value)
      # Only allow certain settings to be updated at runtime
      allowed_runtime_settings = [
        'monitoring.logging.level',
        'monitoring.performance.slow_query_threshold',
        'monitoring.performance.slow_request_threshold',
        'security.rate_limiting.max_requests_per_hour',
        'cache.ttl',
        'websocket.ping_interval'
      ]
      
      unless allowed_runtime_settings.include?(key_path)
        raise ArgumentError, "Setting '#{key_path}' cannot be updated at runtime"
      end
      
      old_value = get(key_path)
      set(key_path, value)
      
      # Log the change
      $logger&.info "Runtime configuration updated: #{key_path} changed from #{old_value} to #{value}"
      
      # Apply the change if needed
      apply_runtime_setting_change(key_path, value, old_value)
      
      { success: true, old_value: old_value, new_value: value }
    end
    
    private
    
    def check_database_connectivity(validation_results)
      check_name = 'database_connectivity'
      
      begin
        # Test database connection
        if defined?(SpotikConfig::Database)
          db_health = SpotikConfig::Database.health_check
          
          if db_health[:status] == 'healthy'
            validation_results[:checks] << {
              name: check_name,
              status: 'pass',
              message: 'Database connection successful',
              response_time_ms: db_health[:response_time_ms]
            }
          else
            validation_results[:errors] << "Database connectivity check failed: #{db_health[:error]}"
            validation_results[:checks] << {
              name: check_name,
              status: 'fail',
              message: db_health[:error]
            }
          end
        else
          validation_results[:warnings] << "Database not initialized, skipping connectivity check"
          validation_results[:checks] << {
            name: check_name,
            status: 'skip',
            message: 'Database not initialized'
          }
        end
      rescue => e
        validation_results[:errors] << "Database connectivity check error: #{e.message}"
        validation_results[:checks] << {
          name: check_name,
          status: 'error',
          message: e.message
        }
      end
    end
    
    def check_storage_accessibility(validation_results)
      check_name = 'storage_accessibility'
      
      storage_paths = {
        audio: get('storage.audio_path'),
        public: get('storage.public_path'),
        temp: get('storage.temp_path')
      }
      
      accessible_paths = []
      inaccessible_paths = []
      
      storage_paths.each do |type, path|
        next unless path
        
        begin
          # Create directory if it doesn't exist
          FileUtils.mkdir_p(path) unless File.exist?(path)
          
          # Test write access
          test_file = File.join(path, '.write_test')
          File.write(test_file, 'test')
          File.delete(test_file)
          
          accessible_paths << "#{type}: #{path}"
        rescue => e
          inaccessible_paths << "#{type}: #{path} (#{e.message})"
        end
      end
      
      if inaccessible_paths.empty?
        validation_results[:checks] << {
          name: check_name,
          status: 'pass',
          message: "All storage paths accessible: #{accessible_paths.join(', ')}"
        }
      else
        validation_results[:errors] += inaccessible_paths.map { |path| "Storage path not accessible: #{path}" }
        validation_results[:checks] << {
          name: check_name,
          status: 'fail',
          message: "Inaccessible paths: #{inaccessible_paths.join(', ')}"
        }
      end
    end
    
    def check_required_services(validation_results)
      check_name = 'required_services'
      
      required_services = []
      missing_services = []
      
      # Check if JWT secret is configured
      jwt_secret = get('security.jwt.secret')
      if jwt_secret && !jwt_secret.empty?
        required_services << 'JWT authentication'
      else
        missing_services << 'JWT secret not configured'
      end
      
      # Check if logging is configured
      log_file = get('monitoring.logging.file')
      if log_file
        log_dir = File.dirname(log_file)
        begin
          FileUtils.mkdir_p(log_dir) unless File.exist?(log_dir)
          required_services << 'Logging system'
        rescue => e
          missing_services << "Logging directory not accessible: #{e.message}"
        end
      end
      
      if missing_services.empty?
        validation_results[:checks] << {
          name: check_name,
          status: 'pass',
          message: "All required services available: #{required_services.join(', ')}"
        }
      else
        validation_results[:errors] += missing_services
        validation_results[:checks] << {
          name: check_name,
          status: 'fail',
          message: "Missing services: #{missing_services.join(', ')}"
        }
      end
    end
    
    def check_resource_limits(validation_results)
      check_name = 'resource_limits'
      
      warnings = []
      
      # Check thread/worker configuration
      threads = get('server.threads')
      workers = get('server.workers')
      total_threads = threads * workers
      
      if total_threads > 32
        warnings << "High thread count (#{total_threads}) may consume excessive resources"
      end
      
      # Check database pool size
      db_pool_max = get('database.pool.max')
      if db_pool_max > 50
        warnings << "Large database pool (#{db_pool_max}) may consume excessive connections"
      end
      
      # Check file size limits
      max_file_size = get('storage.max_file_size_mb')
      if max_file_size > 200
        warnings << "Large file size limit (#{max_file_size}MB) may impact performance"
      end
      
      if warnings.empty?
        validation_results[:checks] << {
          name: check_name,
          status: 'pass',
          message: 'Resource limits are within recommended ranges'
        }
      else
        validation_results[:warnings] += warnings
        validation_results[:checks] << {
          name: check_name,
          status: 'warning',
          message: "Resource limit warnings: #{warnings.join(', ')}"
        }
      end
    end
    
    def apply_runtime_setting_change(key_path, new_value, old_value)
      case key_path
      when 'monitoring.logging.level'
        # Update logger level if LoggingService is available
        if defined?(LoggingService)
          LoggingService.set_log_level(new_value.to_sym)
        end
      when 'monitoring.performance.slow_query_threshold'
        # Update performance monitor thresholds
        if defined?(PerformanceMonitor)
          PerformanceMonitor.update_slow_query_threshold(new_value)
        end
      when 'monitoring.performance.slow_request_threshold'
        # Update performance monitor thresholds
        if defined?(PerformanceMonitor)
          PerformanceMonitor.update_slow_request_threshold(new_value)
        end
      end
    end
  end
end