# Health Check Controller for Spotik Ruby Backend
# Provides comprehensive health monitoring endpoints

require_relative '../services/configuration_service'
require_relative '../services/performance_monitor'
require_relative '../services/error_handler'

class HealthController
  class << self
    # Basic health check endpoint
    def basic_health
      begin
        health_status = {
          status: 'healthy',
          timestamp: Time.now.iso8601,
          version: ConfigurationService.get('app.version', '1.0.0'),
          environment: ConfigurationService.get('app.environment', 'unknown'),
          uptime: get_uptime_info,
          server: {
            host: ConfigurationService.get('server.host'),
            port: ConfigurationService.get('server.port'),
            threads: ConfigurationService.get('server.threads'),
            workers: ConfigurationService.get('server.workers')
          }
        }
        
        { status: 200, body: health_status }
      rescue => e
        error_response = {
          status: 'unhealthy',
          timestamp: Time.now.iso8601,
          error: e.message
        }
        
        { status: 503, body: error_response }
      end
    end
    
    # Comprehensive health check with all components
    def comprehensive_health
      begin
        health_status = {
          status: 'healthy',
          timestamp: Time.now.iso8601,
          version: ConfigurationService.get('app.version', '1.0.0'),
          environment: ConfigurationService.get('app.environment', 'unknown'),
          uptime: get_uptime_info
        }
        
        # Check configuration health
        config_health = check_configuration_health
        health_status[:configuration] = config_health
        
        # Check database health (skip in test environment)
        unless ConfigurationService.get('app.environment') == 'test'
          db_health = check_database_health
          health_status[:database] = db_health
          
          if db_health[:status] != 'healthy'
            health_status[:status] = 'unhealthy'
          end
        else
          health_status[:database] = { status: 'skipped', message: 'test environment' }
        end
        
        # Check storage health
        storage_health = check_storage_health
        health_status[:storage] = storage_health
        
        if storage_health[:status] != 'healthy'
          health_status[:status] = 'degraded'
        end
        
        # Check services health
        services_health = check_services_health
        health_status[:services] = services_health
        
        # Check performance health
        if ConfigurationService.get('monitoring.performance.enabled')
          performance_health = check_performance_health
          health_status[:performance] = performance_health
        end
        
        # Check error statistics
        error_health = check_error_health
        health_status[:errors] = error_health
        
        # Determine overall status
        overall_status = determine_overall_status(health_status)
        health_status[:status] = overall_status
        
        status_code = case overall_status
        when 'healthy' then 200
        when 'degraded' then 200
        when 'unhealthy' then 503
        else 503
        end
        
        { status: status_code, body: health_status }
      rescue => e
        LoggingService.log_error(:health, "Health check error", {}, e) if defined?(LoggingService)
        
        error_response = {
          status: 'error',
          timestamp: Time.now.iso8601,
          error: e.message,
          error_class: e.class.name
        }
        
        { status: 503, body: error_response }
      end
    end
    
    # Configuration-specific health check
    def configuration_health
      begin
        config_health = ConfigurationService.configuration_health
        runtime_validation = ConfigurationService.validate_runtime_configuration
        
        health_status = {
          timestamp: Time.now.iso8601,
          configuration: config_health,
          runtime_validation: runtime_validation,
          environment_info: ConfigurationService.get_environment_info
        }
        
        overall_status = if config_health[:status] == 'healthy' && runtime_validation[:status] == 'valid'
          'healthy'
        elsif config_health[:status] == 'healthy' && runtime_validation[:status] == 'warning'
          'degraded'
        else
          'unhealthy'
        end
        
        health_status[:status] = overall_status
        
        status_code = case overall_status
        when 'healthy' then 200
        when 'degraded' then 200
        when 'unhealthy' then 503
        else 503
        end
        
        { status: status_code, body: health_status }
      rescue => e
        error_response = {
          status: 'error',
          timestamp: Time.now.iso8601,
          error: e.message
        }
        
        { status: 503, body: error_response }
      end
    end
    
    # Database-specific health check
    def database_health
      begin
        unless ConfigurationService.get('app.environment') == 'test'
          db_health = SpotikConfig::Database.health_check
          schema_validation = SpotikConfig::Database.validate_schema_compatibility
          
          detailed_health = {
            timestamp: Time.now.iso8601,
            database: db_health,
            schema: schema_validation,
            pool_stats: SpotikConfig::Database.get_pool_stats,
            configuration: {
              host: ConfigurationService.get('database.host'),
              port: ConfigurationService.get('database.port'),
              name: ConfigurationService.get('database.name'),
              pool_max: ConfigurationService.get('database.pool.max'),
              pool_timeout: ConfigurationService.get('database.pool.timeout')
            }
          }
          
          overall_status = if db_health[:status] == 'healthy' && schema_validation[:status] != 'invalid'
            'healthy'
          else
            'unhealthy'
          end
          
          detailed_health[:status] = overall_status
          
          status_code = overall_status == 'healthy' ? 200 : 503
          
          { status: status_code, body: detailed_health }
        else
          test_response = {
            status: 'skipped',
            timestamp: Time.now.iso8601,
            message: 'Database health check skipped in test environment'
          }
          
          { status: 200, body: test_response }
        end
      rescue => e
        error_response = {
          status: 'error',
          timestamp: Time.now.iso8601,
          error: e.message
        }
        
        { status: 503, body: error_response }
      end
    end
    
    # Storage-specific health check
    def storage_health
      begin
        storage_paths = {
          audio: ConfigurationService.get('storage.audio_path'),
          public: ConfigurationService.get('storage.public_path'),
          temp: ConfigurationService.get('storage.temp_path')
        }
        
        storage_status = {}
        overall_healthy = true
        
        storage_paths.each do |type, path|
          next unless path
          
          begin
            # Check if directory exists and is writable
            FileUtils.mkdir_p(path) unless File.exist?(path)
            
            # Test write access
            test_file = File.join(path, '.health_check')
            File.write(test_file, Time.now.to_s)
            File.delete(test_file)
            
            # Get directory info
            dir_info = {
              status: 'healthy',
              path: path,
              exists: File.exist?(path),
              writable: File.writable?(path),
              free_space_mb: get_free_space_mb(path)
            }
            
            storage_status[type] = dir_info
          rescue => e
            storage_status[type] = {
              status: 'unhealthy',
              path: path,
              error: e.message
            }
            overall_healthy = false
          end
        end
        
        health_status = {
          status: overall_healthy ? 'healthy' : 'unhealthy',
          timestamp: Time.now.iso8601,
          storage_paths: storage_status,
          configuration: {
            max_file_size_mb: ConfigurationService.get('storage.max_file_size_mb'),
            allowed_formats: ConfigurationService.get('storage.allowed_audio_formats')
          }
        }
        
        status_code = overall_healthy ? 200 : 503
        
        { status: status_code, body: health_status }
      rescue => e
        error_response = {
          status: 'error',
          timestamp: Time.now.iso8601,
          error: e.message
        }
        
        { status: 503, body: error_response }
      end
    end
    
    # Performance monitoring health check
    def performance_health
      begin
        if ConfigurationService.get('monitoring.performance.enabled')
          performance_stats = PerformanceMonitor.get_performance_statistics
          performance_health_status = PerformanceMonitor.get_performance_health
          
          health_status = {
            status: performance_health_status,
            timestamp: Time.now.iso8601,
            statistics: performance_stats,
            thresholds: {
              slow_query_ms: ConfigurationService.get('monitoring.performance.slow_query_threshold'),
              slow_request_ms: ConfigurationService.get('monitoring.performance.slow_request_threshold')
            }
          }
          
          status_code = performance_health_status == 'healthy' ? 200 : 503
          
          { status: status_code, body: health_status }
        else
          disabled_response = {
            status: 'disabled',
            timestamp: Time.now.iso8601,
            message: 'Performance monitoring is disabled'
          }
          
          { status: 200, body: disabled_response }
        end
      rescue => e
        error_response = {
          status: 'error',
          timestamp: Time.now.iso8601,
          error: e.message
        }
        
        { status: 503, body: error_response }
      end
    end
    
    # System readiness check (for Kubernetes/Docker health checks)
    def readiness_check
      begin
        # Check critical components for readiness
        ready = true
        checks = {}
        
        # Configuration must be valid
        config_health = ConfigurationService.configuration_health
        checks[:configuration] = config_health[:status] == 'healthy'
        ready = false unless checks[:configuration]
        
        # Database must be accessible (skip in test)
        unless ConfigurationService.get('app.environment') == 'test'
          begin
            db_health = SpotikConfig::Database.health_check
            checks[:database] = db_health[:status] == 'healthy'
            ready = false unless checks[:database]
          rescue
            checks[:database] = false
            ready = false
          end
        else
          checks[:database] = true  # Skip in test
        end
        
        # Storage must be accessible
        storage_paths = [
          ConfigurationService.get('storage.audio_path'),
          ConfigurationService.get('storage.public_path'),
          ConfigurationService.get('storage.temp_path')
        ].compact
        
        storage_ready = storage_paths.all? do |path|
          File.exist?(path) && File.writable?(path)
        end
        
        checks[:storage] = storage_ready
        ready = false unless storage_ready
        
        readiness_status = {
          ready: ready,
          timestamp: Time.now.iso8601,
          checks: checks
        }
        
        status_code = ready ? 200 : 503
        
        { status: status_code, body: readiness_status }
      rescue => e
        error_response = {
          ready: false,
          timestamp: Time.now.iso8601,
          error: e.message
        }
        
        { status: 503, body: error_response }
      end
    end
    
    # Liveness check (for Kubernetes/Docker health checks)
    def liveness_check
      begin
        # Simple check that the application is running
        liveness_status = {
          alive: true,
          timestamp: Time.now.iso8601,
          uptime: get_uptime_info,
          memory_usage_mb: get_memory_usage_mb
        }
        
        { status: 200, body: liveness_status }
      rescue => e
        error_response = {
          alive: false,
          timestamp: Time.now.iso8601,
          error: e.message
        }
        
        { status: 503, body: error_response }
      end
    end
    
    private
    
    def check_configuration_health
      config_health = ConfigurationService.configuration_health
      runtime_validation = ConfigurationService.validate_runtime_configuration
      
      {
        status: config_health[:status] == 'healthy' && runtime_validation[:status] != 'invalid' ? 'healthy' : 'unhealthy',
        config_files: config_health[:config_files_loaded]&.length || 0,
        environment_variables: config_health[:environment_variables_loaded]&.length || 0,
        validation_errors: config_health[:errors]&.length || 0,
        validation_warnings: config_health[:warnings]&.length || 0,
        runtime_checks: runtime_validation[:checks]&.length || 0
      }
    end
    
    def check_database_health
      return { status: 'skipped', message: 'test environment' } if ConfigurationService.get('app.environment') == 'test'
      
      begin
        db_health = SpotikConfig::Database.health_check
        schema_validation = SpotikConfig::Database.validate_schema_compatibility
        
        {
          status: db_health[:status] == 'healthy' && schema_validation[:status] != 'invalid' ? 'healthy' : 'unhealthy',
          response_time_ms: db_health[:response_time_ms],
          pool_size: db_health[:pool_stats]&.dig(:size) || 0,
          pool_available: db_health[:pool_stats]&.dig(:available) || 0,
          schema_status: schema_validation[:status],
          schema_errors: schema_validation[:errors]&.length || 0
        }
      rescue => e
        {
          status: 'unhealthy',
          error: e.message
        }
      end
    end
    
    def check_storage_health
      storage_paths = {
        audio: ConfigurationService.get('storage.audio_path'),
        public: ConfigurationService.get('storage.public_path'),
        temp: ConfigurationService.get('storage.temp_path')
      }
      
      accessible_count = 0
      total_count = 0
      
      storage_paths.each do |type, path|
        next unless path
        total_count += 1
        
        begin
          FileUtils.mkdir_p(path) unless File.exist?(path)
          if File.exist?(path) && File.writable?(path)
            accessible_count += 1
          end
        rescue
          # Path not accessible
        end
      end
      
      {
        status: accessible_count == total_count ? 'healthy' : 'unhealthy',
        accessible_paths: accessible_count,
        total_paths: total_count
      }
    end
    
    def check_services_health
      services = {}
      
      # Check JWT service
      jwt_secret = ConfigurationService.get('security.jwt.secret')
      services[:jwt] = !jwt_secret.nil? && !jwt_secret.empty?
      
      # Check logging service
      services[:logging] = defined?(LoggingService)
      
      # Check performance monitoring
      services[:performance_monitoring] = defined?(PerformanceMonitor) && ConfigurationService.get('monitoring.performance.enabled')
      
      # Check error handling
      services[:error_handling] = defined?(ErrorHandler)
      
      healthy_services = services.values.count(true)
      total_services = services.length
      
      {
        status: healthy_services == total_services ? 'healthy' : 'degraded',
        services: services,
        healthy_count: healthy_services,
        total_count: total_services
      }
    end
    
    def check_performance_health
      return { status: 'disabled' } unless ConfigurationService.get('monitoring.performance.enabled')
      
      begin
        performance_health = PerformanceMonitor.get_performance_health
        performance_stats = PerformanceMonitor.get_performance_statistics
        
        {
          status: performance_health,
          memory_usage_mb: performance_stats[:current_memory_mb],
          operations_per_hour: performance_stats[:operations_per_hour],
          average_response_time_ms: performance_stats[:average_response_time_ms]
        }
      rescue => e
        {
          status: 'error',
          error: e.message
        }
      end
    end
    
    def check_error_health
      begin
        error_stats = ErrorHandler.get_error_statistics
        
        # Consider error rate healthy if less than 5% of requests result in errors
        error_rate = error_stats[:total_operations] > 0 ? 
          (error_stats[:total_errors].to_f / error_stats[:total_operations]) * 100 : 0
        
        {
          status: error_rate < 5.0 ? 'healthy' : 'degraded',
          total_errors: error_stats[:total_errors],
          error_rate_percent: error_rate.round(2),
          recovery_success_rate: error_stats[:recovery_success_rate]
        }
      rescue => e
        {
          status: 'error',
          error: e.message
        }
      end
    end
    
    def determine_overall_status(health_status)
      # Check for any unhealthy components
      unhealthy_components = []
      degraded_components = []
      
      health_status.each do |component, status|
        next if component == :status || component == :timestamp || component == :version || component == :environment || component == :uptime
        
        if status.is_a?(Hash) && status[:status]
          case status[:status]
          when 'unhealthy', 'error'
            unhealthy_components << component
          when 'degraded', 'warning'
            degraded_components << component
          end
        end
      end
      
      if unhealthy_components.any?
        'unhealthy'
      elsif degraded_components.any?
        'degraded'
      else
        'healthy'
      end
    end
    
    def get_uptime_info
      return { seconds: 0, formatted: '0s' } unless defined?($server_start_time) && $server_start_time
      
      uptime_seconds = (Time.now - $server_start_time).to_i
      {
        seconds: uptime_seconds,
        formatted: format_uptime(uptime_seconds)
      }
    end
    
    def format_uptime(seconds)
      days = seconds / 86400
      hours = (seconds % 86400) / 3600
      minutes = (seconds % 3600) / 60
      secs = seconds % 60

      if days > 0
        "#{days}d #{hours}h #{minutes}m #{secs}s"
      elsif hours > 0
        "#{hours}h #{minutes}m #{secs}s"
      elsif minutes > 0
        "#{minutes}m #{secs}s"
      else
        "#{secs}s"
      end
    end
    
    def get_memory_usage_mb
      begin
        # Get memory usage in MB
        memory_kb = `ps -o rss= -p #{Process.pid}`.to_i
        (memory_kb / 1024.0).round(2)
      rescue
        0
      end
    end
    
    def get_free_space_mb(path)
      begin
        stat = File.statvfs(path)
        free_bytes = stat.bavail * stat.frsize
        (free_bytes / (1024 * 1024)).round(2)
      rescue
        0
      end
    end
  end
end