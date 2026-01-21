# Comprehensive Logging Service for Spotik Ruby Backend
# Implements structured logging for all important events with multiple output formats

require 'logger'
require 'fileutils'

class LoggingService
  # Log levels with numeric values for filtering
  LOG_LEVELS = {
    debug: 0,
    info: 1,
    warn: 2,
    error: 3,
    fatal: 4
  }.freeze
  
  # Event categories for structured logging
  EVENT_CATEGORIES = {
    authentication: 'AUTH',
    websocket: 'WS',
    database: 'DB',
    api: 'API',
    playback: 'PLAYBACK',
    file_upload: 'FILE',
    room_management: 'ROOM',
    performance: 'PERF',
    security: 'SEC',
    system: 'SYS',
    error: 'ERR'
  }.freeze
  
  # Performance thresholds (in milliseconds)
  PERFORMANCE_THRESHOLDS = {
    database_query: 100,
    api_request: 500,
    websocket_message: 50,
    file_operation: 1000,
    authentication: 200
  }.freeze
  
  class << self
    attr_reader :logger, :performance_logger, :error_logger, :security_logger
    
    # Initialize logging service with multiple loggers
    def initialize_logging
      setup_log_directories
      setup_main_logger
      setup_specialized_loggers
      setup_performance_monitoring
      
      @initialized = true
      log_info(:system, "Logging service initialized", {
        log_level: SpotikConfig::Settings.log_level,
        log_file: SpotikConfig::Settings.log_file,
        environment: SpotikConfig::Settings.app_env
      })
    end
    
    # Main logging methods with structured format
    def log_debug(category, message, data = {})
      log_structured(:debug, category, message, data)
    end
    
    def log_info(category, message, data = {})
      log_structured(:info, category, message, data)
    end
    
    def log_warn(category, message, data = {})
      log_structured(:warn, category, message, data)
    end
    
    def log_error(category, message, data = {}, exception = nil)
      # Add exception details if provided
      if exception
        data = data.merge({
          exception_class: exception.class.name,
          exception_message: exception.message,
          backtrace: exception.backtrace&.first(10)
        })
      end
      
      log_structured(:error, category, message, data)
      
      # Also log to specialized error logger
      error_msg = format_error_log(category, message, data, exception)
      @error_logger&.error(error_msg)
    end
    
    def log_fatal(category, message, data = {}, exception = nil)
      if exception
        data = data.merge({
          exception_class: exception.class.name,
          exception_message: exception.message,
          backtrace: exception.backtrace
        })
      end
      
      log_structured(:fatal, category, message, data)
      
      # Also log to specialized error logger
      error_msg = format_error_log(category, message, data, exception)
      @error_logger&.fatal(error_msg)
    end
    
    # Performance logging methods
    def log_performance(operation, duration_ms, data = {})
      threshold = PERFORMANCE_THRESHOLDS[operation] || 1000
      level = duration_ms > threshold ? :warn : :info
      
      performance_data = {
        operation: operation,
        duration_ms: duration_ms,
        threshold_ms: threshold,
        slow_operation: duration_ms > threshold
      }.merge(data)
      
      log_structured(level, :performance, "Performance: #{operation}", performance_data)
      
      # Log to specialized performance logger
      perf_msg = format_performance_log(operation, duration_ms, data)
      @performance_logger&.info(perf_msg)
    end
    
    # Security event logging
    def log_security_event(event_type, message, data = {})
      security_data = {
        event_type: event_type,
        timestamp: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
        server_time: Time.now.to_f
      }.merge(data)
      
      log_structured(:warn, :security, message, security_data)
      
      # Log to specialized security logger
      security_msg = format_security_log(event_type, message, data)
      @security_logger&.warn(security_msg)
    end
    
    # Database operation logging
    def log_database_operation(operation, table, duration_ms = nil, data = {})
      db_data = {
        operation: operation,
        table: table,
        duration_ms: duration_ms
      }.merge(data)
      
      level = duration_ms && duration_ms > PERFORMANCE_THRESHOLDS[:database_query] ? :warn : :debug
      log_structured(level, :database, "DB: #{operation} on #{table}", db_data)
    end
    
    # API request logging
    def log_api_request(method, path, status, duration_ms, data = {})
      api_data = {
        method: method,
        path: path,
        status: status,
        duration_ms: duration_ms,
        slow_request: duration_ms > PERFORMANCE_THRESHOLDS[:api_request]
      }.merge(data)
      
      level = case status
      when 200..299 then duration_ms > PERFORMANCE_THRESHOLDS[:api_request] ? :warn : :info
      when 400..499 then :warn
      when 500..599 then :error
      else :info
      end
      
      log_structured(level, :api, "API: #{method} #{path} -> #{status}", api_data)
    end
    
    # WebSocket event logging
    def log_websocket_event(event_type, user_id, room_id = nil, data = {})
      ws_data = {
        event_type: event_type,
        user_id: user_id,
        room_id: room_id
      }.merge(data)
      
      log_structured(:info, :websocket, "WebSocket: #{event_type}", ws_data)
    end
    
    # Authentication event logging
    def log_auth_event(event_type, user_identifier, success, data = {})
      auth_data = {
        event_type: event_type,
        user_identifier: user_identifier,
        success: success,
        ip_address: data[:ip_address],
        user_agent: data[:user_agent]
      }
      
      # Add other data except the ones we already extracted
      data.each do |key, value|
        unless [:ip_address, :user_agent].include?(key)
          auth_data[key] = value
        end
      end
      
      level = success ? :info : :warn
      message = "Auth: #{event_type} #{success ? 'succeeded' : 'failed'} for #{user_identifier}"
      
      log_structured(level, :authentication, message, auth_data)
      
      # Log failed authentication attempts to security logger
      if !success
        log_security_event('failed_authentication', message, auth_data)
      end
    end
    
    # File operation logging
    def log_file_operation(operation, filename, success, duration_ms = nil, data = {})
      file_data = {
        operation: operation,
        filename: filename,
        success: success,
        duration_ms: duration_ms
      }.merge(data)
      
      level = success ? :info : :error
      message = "File: #{operation} #{filename} #{success ? 'succeeded' : 'failed'}"
      
      log_structured(level, :file_upload, message, file_data)
    end
    
    # Room management logging
    def log_room_event(event_type, room_id, user_id, data = {})
      room_data = {
        event_type: event_type,
        room_id: room_id,
        user_id: user_id
      }.merge(data)
      
      log_structured(:info, :room_management, "Room: #{event_type} in #{room_id}", room_data)
    end
    
    # Playback event logging
    def log_playback_event(event_type, room_id, track_id, user_id, data = {})
      playback_data = {
        event_type: event_type,
        room_id: room_id,
        track_id: track_id,
        user_id: user_id
      }.merge(data)
      
      log_structured(:info, :playback, "Playback: #{event_type} in #{room_id}", playback_data)
    end
    
    # System event logging
    def log_system_event(event_type, message, data = {})
      system_data = {
        event_type: event_type,
        pid: Process.pid,
        memory_usage: get_memory_usage,
        uptime: get_uptime
      }.merge(data)
      
      log_structured(:info, :system, message, system_data)
    end
    
    # Measure and log execution time
    def measure_execution(operation, category = :performance, &block)
      start_time = Time.now
      result = block.call
      duration_ms = ((Time.now - start_time) * 1000).round(2)
      
      log_performance(operation, duration_ms, { category: category })
      
      result
    rescue => e
      duration_ms = ((Time.now - start_time) * 1000).round(2)
      log_error(category, "#{operation} failed after #{duration_ms}ms", {
        operation: operation,
        duration_ms: duration_ms
      }, e)
      raise
    end
    
    # Format methods for different log types
    def format_performance_log(operation, duration_ms, data)
      "#{Time.now.strftime('%Y-%m-%d %H:%M:%S')} PERF: #{operation} #{duration_ms}ms #{data.inspect}"
    end
    
    def format_error_log(category, message, data, exception)
      error_str = "#{Time.now.strftime('%Y-%m-%d %H:%M:%S')} ERROR: #{EVENT_CATEGORIES[category] || category.to_s.upcase} - #{message}"
      if exception
        error_str += " - #{exception.class.name}: #{exception.message}"
        if exception.backtrace
          error_str += " - Backtrace: #{exception.backtrace.first(5).join('; ')}"
        end
      end
      if data && !data.empty?
        error_str += " - Data: #{data.inspect}"
      end
      error_str
    end
    
    def format_security_log(event_type, message, data)
      security_str = "#{Time.now.strftime('%Y-%m-%d %H:%M:%S')} SECURITY: #{event_type} - #{message}"
      if data && !data.empty?
        security_str += " - #{data.inspect}"
      end
      security_str
    end
    
    # Get logging statistics
    def get_statistics
      return {} unless @initialized
      
      {
        log_level: SpotikConfig::Settings.log_level,
        log_files: {
          main: SpotikConfig::Settings.log_file,
          performance: 'logs/performance.log',
          error: 'logs/error.log',
          security: 'logs/security.log'
        },
        performance_thresholds: PERFORMANCE_THRESHOLDS,
        categories: EVENT_CATEGORIES.keys,
        initialized_at: @initialized_at,
        uptime: get_uptime
      }
    end
    
    # Rotate log files (for production use)
    def rotate_logs
      return unless @initialized
      
      [@logger, @performance_logger, @error_logger, @security_logger].compact.each do |logger|
        # Ruby Logger doesn't have built-in rotation, but we can implement basic rotation
        if logger.respond_to?(:logdev) && logger.logdev.respond_to?(:filename)
          filename = logger.logdev.filename
          if File.exist?(filename) && File.size(filename) > 100 * 1024 * 1024 # 100MB
            backup_filename = "#{filename}.#{Time.now.strftime('%Y%m%d_%H%M%S')}"
            File.rename(filename, backup_filename)
            logger.reopen
            log_info(:system, "Log file rotated", { 
              original: filename, 
              backup: backup_filename 
            })
          end
        end
      end
    end
    
    private
    
    def setup_log_directories
      log_dir = File.dirname(SpotikConfig::Settings.log_file)
      FileUtils.mkdir_p(log_dir) unless Dir.exist?(log_dir)
      
      # Create additional log directories
      ['performance', 'error', 'security'].each do |subdir|
        dir_path = File.join(log_dir, subdir)
        FileUtils.mkdir_p(dir_path) unless Dir.exist?(dir_path)
      end
    end
    
    def setup_main_logger
      @logger = Logger.new(SpotikConfig::Settings.log_file)
      @logger.level = Logger.const_get(SpotikConfig::Settings.log_level.upcase)
      @logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime}] #{severity}: #{msg}\n"
      end
      @initialized_at = Time.now
    end
    
    def setup_specialized_loggers
      log_dir = File.dirname(SpotikConfig::Settings.log_file)
      
      # Performance logger
      @performance_logger = Logger.new(File.join(log_dir, 'performance.log'))
      @performance_logger.level = Logger::INFO
      @performance_logger.formatter = proc { |severity, datetime, progname, msg| "#{msg}\n" }
      
      # Error logger
      @error_logger = Logger.new(File.join(log_dir, 'error.log'))
      @error_logger.level = Logger::WARN
      @error_logger.formatter = proc { |severity, datetime, progname, msg| "#{msg}\n" }
      
      # Security logger
      @security_logger = Logger.new(File.join(log_dir, 'security.log'))
      @security_logger.level = Logger::WARN
      @security_logger.formatter = proc { |severity, datetime, progname, msg| "#{msg}\n" }
    end
    
    def setup_performance_monitoring
      # Set up periodic performance logging
      if SpotikConfig::Settings.performance_monitoring_enabled?
        Thread.new do
          loop do
            sleep(60) # Log performance stats every minute
            log_system_performance
          end
        rescue => e
          log_error(:system, "Performance monitoring thread error", {}, e)
        end
      end
    end
    
    def log_structured(level, category, message, data)
      return unless @logger && should_log?(level)
      
      log_entry = {
        timestamp: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
        level: level.to_s.upcase,
        category: EVENT_CATEGORIES[category] || category.to_s.upcase,
        message: message,
        data: data,
        pid: Process.pid,
        thread_id: Thread.current.object_id
      }
      
      # Use simple string format instead of JSON for compatibility
      log_string = "#{log_entry[:timestamp]} [#{log_entry[:level]}] #{log_entry[:category]}: #{log_entry[:message]}"
      if log_entry[:data] && !log_entry[:data].empty?
        log_string += " - #{log_entry[:data].inspect}"
      end
      
      @logger.send(level, log_string)
    rescue => e
      # Fallback to even simpler logging if there are issues
      @logger.send(level, "#{Time.now} [#{level.upcase}] #{category}: #{message}")
    end
    
    def should_log?(level)
      current_level = LOG_LEVELS[SpotikConfig::Settings.log_level.to_sym] || 1
      message_level = LOG_LEVELS[level] || 1
      message_level >= current_level
    end
    
    def format_security_log(event_type, message, data)
      security_str = "#{Time.now.strftime('%Y-%m-%d %H:%M:%S')} SECURITY: #{event_type} - #{message}"
      if data && !data.empty?
        security_str += " - #{data.inspect}"
      end
      security_str
    end
    
    def format_security_log_entry(severity, datetime, progname, msg)
      "#{msg}\n"
    end
    
    def log_system_performance
      memory_usage = get_memory_usage
      cpu_usage = get_cpu_usage
      
      log_performance(:system_performance, 0, {
        memory_mb: memory_usage,
        cpu_percent: cpu_usage,
        active_threads: Thread.list.count,
        websocket_connections: WebSocketConnection.connection_stats[:total_connections],
        database_pool: get_database_pool_stats
      })
    end
    
    def get_memory_usage
      # Get memory usage in MB (Linux/Unix)
      if File.exist?('/proc/self/status')
        status = File.read('/proc/self/status')
        if match = status.match(/VmRSS:\s+(\d+)\s+kB/)
          return match[1].to_i / 1024.0 # Convert KB to MB
        end
      end
      
      # Fallback for other systems
      0
    rescue
      0
    end
    
    def get_cpu_usage
      # Basic CPU usage estimation (not precise, but useful for monitoring)
      # This is a simplified implementation
      0
    rescue
      0
    end
    
    def get_uptime
      return 0 unless @initialized_at
      Time.now - @initialized_at
    end
    
    def get_database_pool_stats
      return {} unless defined?(SpotikConfig::Database)
      
      begin
        SpotikConfig::Database.get_pool_stats
      rescue
        {}
      end
    end
  end
end