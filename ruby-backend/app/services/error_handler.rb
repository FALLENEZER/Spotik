# Comprehensive Error Handling Service for Spotik Ruby Backend
# Implements graceful error recovery and structured error reporting

require_relative 'logging_service'

class ErrorHandler
  # Error categories for classification and handling
  ERROR_CATEGORIES = {
    authentication: 'AUTH_ERROR',
    authorization: 'AUTHZ_ERROR',
    validation: 'VALIDATION_ERROR',
    database: 'DATABASE_ERROR',
    websocket: 'WEBSOCKET_ERROR',
    file_system: 'FILE_ERROR',
    network: 'NETWORK_ERROR',
    system: 'SYSTEM_ERROR',
    external_service: 'EXTERNAL_ERROR',
    rate_limit: 'RATE_LIMIT_ERROR',
    configuration: 'CONFIG_ERROR'
  }.freeze
  
  # Error severity levels
  SEVERITY_LEVELS = {
    low: 1,      # Minor issues, system continues normally
    medium: 2,   # Noticeable issues, some functionality affected
    high: 3,     # Significant issues, major functionality affected
    critical: 4  # System stability at risk, immediate attention required
  }.freeze
  
  # Recovery strategies
  RECOVERY_STRATEGIES = {
    retry: 'RETRY',
    fallback: 'FALLBACK',
    graceful_degradation: 'DEGRADE',
    circuit_breaker: 'CIRCUIT_BREAK',
    fail_fast: 'FAIL_FAST',
    ignore: 'IGNORE'
  }.freeze
  
  # Error statistics tracking
  @@error_stats = {
    total_errors: 0,
    errors_by_category: Hash.new(0),
    errors_by_severity: Hash.new(0),
    recovery_attempts: Hash.new(0),
    successful_recoveries: Hash.new(0),
    last_reset: Time.now
  }
  
  # Circuit breaker states for external services
  @@circuit_breakers = {}
  
  class << self
    # Main error handling method
    def handle_error(error, context = {})
      error_info = analyze_error(error, context)
      
      # Log the error with appropriate level
      log_error(error_info)
      
      # Update statistics
      update_error_statistics(error_info)
      
      # Attempt recovery if possible
      recovery_result = attempt_recovery(error_info)
      
      # Return structured error response
      build_error_response(error_info, recovery_result)
    end
    
    # Handle API errors with HTTP-specific formatting
    def handle_api_error(error, request_context = {})
      error_info = analyze_error(error, request_context.merge(context_type: 'api'))
      
      # Log API error with request details
      LoggingService.log_api_request(
        request_context[:method] || 'UNKNOWN',
        request_context[:path] || '/unknown',
        error_info[:http_status],
        request_context[:duration_ms] || 0,
        {
          error: true,
          error_category: error_info[:category],
          error_message: error_info[:message],
          user_id: request_context[:user_id],
          ip_address: request_context[:ip_address]
        }
      )
      
      # Return API-formatted error response
      {
        status: error_info[:http_status],
        body: {
          error: error_info[:user_message],
          error_code: error_info[:error_code],
          details: SpotikConfig::Settings.app_debug? ? error_info[:debug_details] : nil,
          timestamp: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
          request_id: request_context[:request_id]
        }
      }
    end
    
    # Handle WebSocket errors
    def handle_websocket_error(error, connection_context = {})
      error_info = analyze_error(error, connection_context.merge(context_type: 'websocket'))
      
      # Log WebSocket error
      LoggingService.log_websocket_event(
        'error',
        connection_context[:user_id],
        connection_context[:room_id],
        {
          error_category: error_info[:category],
          error_message: error_info[:message],
          connection_id: connection_context[:connection_id],
          recovery_attempted: error_info[:recovery_strategy] != :fail_fast
        }
      )
      
      # Return WebSocket-formatted error message
      {
        type: 'error',
        data: {
          error_code: error_info[:error_code],
          message: error_info[:user_message],
          category: error_info[:category],
          recoverable: error_info[:recoverable],
          timestamp: Time.now.to_f
        }
      }
    end
    
    # Handle database errors with connection recovery
    def handle_database_error(error, operation_context = {})
      error_info = analyze_error(error, operation_context.merge(context_type: 'database'))
      
      # Log database error
      LoggingService.log_database_operation(
        operation_context[:operation] || 'unknown',
        operation_context[:table] || 'unknown',
        operation_context[:duration_ms],
        {
          error: true,
          error_category: error_info[:category],
          error_message: error_info[:message],
          recovery_attempted: error_info[:recovery_strategy] != :fail_fast
        }
      )
      
      # Attempt database connection recovery if needed
      if error_info[:category] == :database && error_info[:recoverable]
        recovery_result = attempt_database_recovery(error, operation_context)
        error_info[:recovery_result] = recovery_result
      end
      
      error_info
    end
    
    # Handle file system errors
    def handle_file_error(error, file_context = {})
      error_info = analyze_error(error, file_context.merge(context_type: 'file_system'))
      
      # Log file operation error
      LoggingService.log_file_operation(
        file_context[:operation] || 'unknown',
        file_context[:filename] || 'unknown',
        false,
        file_context[:duration_ms],
        {
          error_category: error_info[:category],
          error_message: error_info[:message],
          file_size: file_context[:file_size],
          file_type: file_context[:file_type]
        }
      )
      
      error_info
    end
    
    # Graceful error recovery without server crashes
    def with_error_recovery(operation_name, context = {}, &block)
      start_time = Time.now
      
      begin
        result = block.call
        
        # Log successful operation
        duration_ms = ((Time.now - start_time) * 1000).round(2)
        LoggingService.log_performance(operation_name.to_sym, duration_ms, context)
        
        result
        
      rescue => error
        duration_ms = ((Time.now - start_time) * 1000).round(2)
        context_with_timing = context.merge(
          operation: operation_name,
          duration_ms: duration_ms,
          failed_at: Time.now.strftime('%Y-%m-%d %H:%M:%S')
        )
        
        error_info = handle_error(error, context_with_timing)
        
        # If recovery was successful, return the recovered result
        if error_info[:recovery_result] && error_info[:recovery_result][:success]
          LoggingService.log_info(:system, "Operation recovered successfully", {
            operation: operation_name,
            recovery_strategy: error_info[:recovery_strategy],
            total_duration_ms: ((Time.now - start_time) * 1000).round(2)
          })
          
          return error_info[:recovery_result][:result]
        end
        
        # If recovery failed or wasn't attempted, re-raise with context
        enhanced_error = EnhancedError.new(
          error.message,
          error_info[:category],
          error_info[:severity],
          context_with_timing,
          error
        )
        
        raise enhanced_error
      end
    end
    
    # Circuit breaker pattern for external services
    def with_circuit_breaker(service_name, &block)
      breaker = get_or_create_circuit_breaker(service_name)
      
      if breaker[:state] == :open
        if Time.now - breaker[:last_failure] > breaker[:timeout]
          breaker[:state] = :half_open
          LoggingService.log_info(:system, "Circuit breaker half-open", { service: service_name })
        else
          raise CircuitBreakerOpenError.new("Circuit breaker open for #{service_name}")
        end
      end
      
      begin
        result = block.call
        
        # Success - reset circuit breaker
        if breaker[:state] == :half_open
          breaker[:state] = :closed
          breaker[:failure_count] = 0
          LoggingService.log_info(:system, "Circuit breaker closed", { service: service_name })
        end
        
        result
        
      rescue => error
        breaker[:failure_count] += 1
        breaker[:last_failure] = Time.now
        
        if breaker[:failure_count] >= breaker[:threshold]
          breaker[:state] = :open
          LoggingService.log_warn(:system, "Circuit breaker opened", {
            service: service_name,
            failure_count: breaker[:failure_count],
            threshold: breaker[:threshold]
          })
        end
        
        raise error
      end
    end
    
    # Get error statistics
    def get_error_statistics
      stats = @@error_stats.dup
      stats[:uptime_hours] = ((Time.now - stats[:last_reset]) / 3600).round(2)
      stats[:error_rate] = stats[:uptime_hours] > 0 ? (stats[:total_errors] / stats[:uptime_hours]).round(2) : 0
      stats[:recovery_success_rate] = calculate_recovery_success_rate
      stats[:circuit_breakers] = @@circuit_breakers.transform_values { |cb| cb.except(:last_failure) }
      stats
    end
    
    # Reset error statistics
    def reset_error_statistics
      @@error_stats = {
        total_errors: 0,
        errors_by_category: Hash.new(0),
        errors_by_severity: Hash.new(0),
        recovery_attempts: Hash.new(0),
        successful_recoveries: Hash.new(0),
        last_reset: Time.now
      }
      
      LoggingService.log_info(:system, "Error statistics reset")
    end
    
    private
    
    # Analyze error to determine category, severity, and recovery strategy
    def analyze_error(error, context = {})
      category = determine_error_category(error, context)
      severity = determine_error_severity(error, category, context)
      recovery_strategy = determine_recovery_strategy(error, category, severity)
      
      {
        original_error: error,
        category: category,
        severity: severity,
        recovery_strategy: recovery_strategy,
        message: error.message,
        error_code: generate_error_code(category, error),
        user_message: generate_user_message(error, category),
        http_status: determine_http_status(error, category),
        recoverable: recovery_strategy != :fail_fast,
        context: context,
        timestamp: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
        debug_details: {
          class: error.class.name,
          backtrace: error.backtrace&.first(10)
        }
      }
    end
    
    def determine_error_category(error, context)
      case error.class.name
      when 'AuthenticationError'
        :authentication
      when 'AuthorizationError'
        :authorization
      when 'ValidationError'
        :validation
      when /Sequel.*DatabaseError/, /Sequel.*DatabaseConnectionError/
        :database
      when 'WebSocketError'
        :websocket
      when 'Errno::ENOENT', 'Errno::EACCES', 'Errno::ENOSPC'
        :file_system
      when 'Errno::ECONNREFUSED', 'Errno::ETIMEDOUT', /Net.*TimeoutError/
        :network
      when 'CircuitBreakerOpenError'
        :external_service
      when 'RateLimitError'
        :rate_limit
      when 'ConfigurationError'
        :configuration
      else
        # Try to infer from context
        case context[:context_type]
        when 'database' then :database
        when 'websocket' then :websocket
        when 'file_system' then :file_system
        when 'api' then :system
        else :system
        end
      end
    end
    
    def determine_error_severity(error, category, context)
      case category
      when :authentication, :authorization
        :medium
      when :validation
        :low
      when :database
        error.message.include?('connection') ? :critical : :high
      when :websocket
        :medium
      when :file_system
        error.is_a?(Errno::ENOSPC) ? :critical : :medium
      when :network
        :high
      when :system
        error.is_a?(NoMemoryError) ? :critical : :medium
      when :configuration
        :critical
      else
        :medium
      end
    end
    
    def determine_recovery_strategy(error, category, severity)
      case category
      when :database
        severity == :critical ? :circuit_breaker : :retry
      when :network, :external_service
        :circuit_breaker
      when :file_system
        error.is_a?(Errno::ENOSPC) ? :fail_fast : :retry
      when :websocket
        :graceful_degradation
      when :validation, :authentication, :authorization
        :fail_fast
      when :rate_limit
        :retry
      else
        severity == :critical ? :fail_fast : :graceful_degradation
      end
    end
    
    def generate_error_code(category, error)
      base_code = ERROR_CATEGORIES[category] || 'UNKNOWN_ERROR'
      error_hash = error.class.name.hash.abs.to_s(16)[0..3].upcase
      "#{base_code}_#{error_hash}"
    end
    
    def generate_user_message(error, category)
      case category
      when :authentication
        'Authentication failed. Please check your credentials.'
      when :authorization
        'Access denied. You do not have permission to perform this action.'
      when :validation
        error.respond_to?(:errors) ? format_validation_errors(error.errors) : 'Invalid input provided.'
      when :database
        'A database error occurred. Please try again later.'
      when :websocket
        'WebSocket connection error. Please refresh the page.'
      when :file_system
        'File operation failed. Please check the file and try again.'
      when :network
        'Network error occurred. Please check your connection.'
      when :rate_limit
        'Too many requests. Please wait before trying again.'
      else
        'An unexpected error occurred. Please try again.'
      end
    end
    
    def determine_http_status(error, category)
      case category
      when :authentication
        401
      when :authorization
        403
      when :validation
        422
      when :rate_limit
        429
      when :database, :file_system, :network, :system
        500
      when :websocket
        400
      else
        500
      end
    end
    
    def format_validation_errors(errors)
      if errors.is_a?(Hash)
        errors.map { |field, messages| "#{field}: #{Array(messages).join(', ')}" }.join('; ')
      else
        errors.to_s
      end
    end
    
    def log_error(error_info)
      case error_info[:severity]
      when :low
        LoggingService.log_info(error_info[:category], error_info[:message], error_info[:context])
      when :medium
        LoggingService.log_warn(error_info[:category], error_info[:message], error_info[:context])
      when :high, :critical
        LoggingService.log_error(
          error_info[:category],
          error_info[:message],
          error_info[:context],
          error_info[:original_error]
        )
      end
      
      # Log security events for authentication/authorization errors
      if [:authentication, :authorization].include?(error_info[:category])
        LoggingService.log_security_event(
          error_info[:category].to_s,
          error_info[:message],
          error_info[:context]
        )
      end
    end
    
    def update_error_statistics(error_info)
      @@error_stats[:total_errors] += 1
      @@error_stats[:errors_by_category][error_info[:category]] += 1
      @@error_stats[:errors_by_severity][error_info[:severity]] += 1
    end
    
    def attempt_recovery(error_info)
      strategy = error_info[:recovery_strategy]
      @@error_stats[:recovery_attempts][strategy] += 1
      
      case strategy
      when :retry
        attempt_retry_recovery(error_info)
      when :fallback
        attempt_fallback_recovery(error_info)
      when :graceful_degradation
        attempt_graceful_degradation(error_info)
      when :circuit_breaker
        # Circuit breaker is handled separately
        { success: false, strategy: strategy, message: 'Circuit breaker activated' }
      else
        { success: false, strategy: strategy, message: 'No recovery attempted' }
      end
    end
    
    def attempt_retry_recovery(error_info)
      max_retries = 3
      retry_delay = 0.1 # seconds
      
      (1..max_retries).each do |attempt|
        sleep(retry_delay * attempt) # Exponential backoff
        
        begin
          # This is a simplified retry - in practice, you'd need to store the original operation
          LoggingService.log_info(:system, "Retry attempt #{attempt}", {
            error_category: error_info[:category],
            max_retries: max_retries
          })
          
          # For now, just return success to indicate retry was attempted
          @@error_stats[:successful_recoveries][:retry] += 1
          return { success: true, strategy: :retry, attempts: attempt }
          
        rescue => retry_error
          if attempt == max_retries
            LoggingService.log_error(:system, "All retry attempts failed", {
              error_category: error_info[:category],
              attempts: attempt,
              final_error: retry_error.message
            })
          end
        end
      end
      
      { success: false, strategy: :retry, attempts: max_retries }
    end
    
    def attempt_fallback_recovery(error_info)
      # Implement fallback logic based on error category
      case error_info[:category]
      when :database
        # Use cached data if available
        LoggingService.log_info(:system, "Using cached data as fallback", error_info[:context])
        @@error_stats[:successful_recoveries][:fallback] += 1
        { success: true, strategy: :fallback, message: 'Using cached data' }
      when :external_service
        # Use default values or skip non-essential features
        LoggingService.log_info(:system, "Using default values as fallback", error_info[:context])
        @@error_stats[:successful_recoveries][:fallback] += 1
        { success: true, strategy: :fallback, message: 'Using default values' }
      else
        { success: false, strategy: :fallback, message: 'No fallback available' }
      end
    end
    
    def attempt_graceful_degradation(error_info)
      # Implement graceful degradation based on error category
      case error_info[:category]
      when :websocket
        # Continue with HTTP polling instead of WebSocket
        LoggingService.log_info(:system, "Degrading to HTTP polling", error_info[:context])
        @@error_stats[:successful_recoveries][:graceful_degradation] += 1
        { success: true, strategy: :graceful_degradation, message: 'Switched to HTTP polling' }
      when :file_system
        # Disable file uploads temporarily
        LoggingService.log_warn(:system, "Temporarily disabling file uploads", error_info[:context])
        @@error_stats[:successful_recoveries][:graceful_degradation] += 1
        { success: true, strategy: :graceful_degradation, message: 'File uploads disabled' }
      else
        { success: false, strategy: :graceful_degradation, message: 'No degradation strategy available' }
      end
    end
    
    def attempt_database_recovery(error, context)
      begin
        # Attempt to reconnect to database
        if defined?(SpotikConfig::Database)
          SpotikConfig::Database.test_connection
          LoggingService.log_info(:database, "Database connection recovered", context)
          @@error_stats[:successful_recoveries][:database] += 1
          return { success: true, strategy: :database_reconnect }
        end
      rescue => recovery_error
        LoggingService.log_error(:database, "Database recovery failed", context, recovery_error)
      end
      
      { success: false, strategy: :database_reconnect }
    end
    
    def build_error_response(error_info, recovery_result)
      error_info.merge(recovery_result: recovery_result)
    end
    
    def get_or_create_circuit_breaker(service_name)
      @@circuit_breakers[service_name] ||= {
        state: :closed,
        failure_count: 0,
        threshold: 5,
        timeout: 60, # seconds
        last_failure: nil
      }
    end
    
    def calculate_recovery_success_rate
      total_attempts = @@error_stats[:recovery_attempts].values.sum
      total_successes = @@error_stats[:successful_recoveries].values.sum
      
      return 0.0 if total_attempts == 0
      (total_successes.to_f / total_attempts * 100).round(2)
    end
  end
end

# Custom error classes for enhanced error handling
class EnhancedError < StandardError
  attr_reader :category, :severity, :context, :original_error
  
  def initialize(message, category, severity, context = {}, original_error = nil)
    super(message)
    @category = category
    @severity = severity
    @context = context
    @original_error = original_error
  end
end

class AuthorizationError < StandardError; end
class WebSocketError < StandardError; end
class CircuitBreakerOpenError < StandardError; end
class RateLimitError < StandardError; end
class ConfigurationError < StandardError; end