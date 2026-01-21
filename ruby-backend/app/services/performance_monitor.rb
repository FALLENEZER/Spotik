# Performance Monitoring Service for Spotik Ruby Backend
# Tracks and logs performance metrics for critical operations

require_relative 'logging_service'

class PerformanceMonitor
  # Performance metric types
  METRIC_TYPES = {
    request_duration: 'REQUEST_DURATION',
    database_query: 'DB_QUERY',
    websocket_message: 'WS_MESSAGE',
    file_operation: 'FILE_OP',
    authentication: 'AUTH',
    room_operation: 'ROOM_OP',
    playback_operation: 'PLAYBACK_OP',
    memory_usage: 'MEMORY',
    cpu_usage: 'CPU',
    connection_count: 'CONNECTIONS'
  }.freeze
  
  # Performance thresholds (in milliseconds unless specified)
  PERFORMANCE_THRESHOLDS = {
    api_request_fast: 100,
    api_request_slow: 1000,
    database_query_fast: 50,
    database_query_slow: 500,
    websocket_message_fast: 10,
    websocket_message_slow: 100,
    file_upload_fast: 1000,
    file_upload_slow: 5000,
    authentication_fast: 100,
    authentication_slow: 500,
    room_operation_fast: 50,
    room_operation_slow: 200,
    playback_operation_fast: 20,
    playback_operation_slow: 100
  }.freeze
  
  # Memory thresholds (in MB)
  MEMORY_THRESHOLDS = {
    normal: 100,
    warning: 250,
    critical: 500
  }.freeze
  
  # Performance statistics
  @@performance_stats = {
    total_operations: 0,
    operations_by_type: Hash.new(0),
    slow_operations: Hash.new(0),
    average_durations: Hash.new { |h, k| h[k] = [] },
    peak_memory_usage: 0,
    peak_connection_count: 0,
    monitoring_started: Time.now
  }
  
  # Real-time metrics (sliding window)
  @@recent_metrics = {
    window_size: 100,
    metrics: []
  }
  
  class << self
    # Initialize performance monitoring
    def initialize_monitoring
      @monitoring_enabled = SpotikConfig::Settings.performance_monitoring_enabled?
      
      if @monitoring_enabled
        start_background_monitoring
        LoggingService.log_info(:performance, "Performance monitoring initialized", {
          thresholds: PERFORMANCE_THRESHOLDS,
          memory_thresholds: MEMORY_THRESHOLDS
        })
      end
    end
    
    # Measure and log operation performance
    def measure_operation(operation_type, operation_name, context = {}, &block)
      return block.call unless @monitoring_enabled
      
      start_time = Time.now
      start_memory = get_memory_usage
      
      begin
        result = block.call
        
        # Calculate metrics
        duration_ms = ((Time.now - start_time) * 1000).round(2)
        memory_delta = get_memory_usage - start_memory
        
        # Record performance metrics
        record_performance_metric(operation_type, operation_name, duration_ms, {
          success: true,
          memory_delta_mb: memory_delta,
          context: context
        })
        
        # Log slow operations
        if slow_operation?(operation_type, duration_ms)
          LoggingService.log_warn(:performance, "Slow operation detected", {
            operation_type: operation_type,
            operation_name: operation_name,
            duration_ms: duration_ms,
            threshold_ms: get_slow_threshold(operation_type),
            context: context
          })
        end
        
        result
        
      rescue => error
        duration_ms = ((Time.now - start_time) * 1000).round(2)
        memory_delta = get_memory_usage - start_memory
        
        # Record failed operation metrics
        record_performance_metric(operation_type, operation_name, duration_ms, {
          success: false,
          error: error.class.name,
          memory_delta_mb: memory_delta,
          context: context
        })
        
        raise error
      end
    end
    
    # Track API request performance
    def track_api_request(method, path, status, duration_ms, context = {})
      return unless @monitoring_enabled
      
      operation_name = "#{method} #{path}"
      
      record_performance_metric(:request_duration, operation_name, duration_ms, {
        method: method,
        path: path,
        status: status,
        success: status < 400,
        context: context
      })
      
      # Log slow API requests
      if duration_ms > PERFORMANCE_THRESHOLDS[:api_request_slow]
        LoggingService.log_warn(:performance, "Slow API request", {
          method: method,
          path: path,
          status: status,
          duration_ms: duration_ms,
          threshold_ms: PERFORMANCE_THRESHOLDS[:api_request_slow],
          context: context
        })
      end
    end
    
    # Track database query performance
    def track_database_query(operation, table, duration_ms, context = {})
      return unless @monitoring_enabled
      
      operation_name = "#{operation}_#{table}"
      
      record_performance_metric(:database_query, operation_name, duration_ms, {
        operation: operation,
        table: table,
        success: !context[:error],
        context: context
      })
      
      # Log slow database queries
      if duration_ms > PERFORMANCE_THRESHOLDS[:database_query_slow]
        LoggingService.log_warn(:performance, "Slow database query", {
          operation: operation,
          table: table,
          duration_ms: duration_ms,
          threshold_ms: PERFORMANCE_THRESHOLDS[:database_query_slow],
          context: context
        })
      end
    end
    
    # Track WebSocket message performance
    def track_websocket_message(message_type, duration_ms, context = {})
      return unless @monitoring_enabled
      
      record_performance_metric(:websocket_message, message_type, duration_ms, {
        message_type: message_type,
        success: !context[:error],
        context: context
      })
      
      # Log slow WebSocket messages
      if duration_ms > PERFORMANCE_THRESHOLDS[:websocket_message_slow]
        LoggingService.log_warn(:performance, "Slow WebSocket message", {
          message_type: message_type,
          duration_ms: duration_ms,
          threshold_ms: PERFORMANCE_THRESHOLDS[:websocket_message_slow],
          context: context
        })
      end
    end
    
    # Track file operation performance
    def track_file_operation(operation, filename, duration_ms, file_size_mb = nil, context = {})
      return unless @monitoring_enabled
      
      operation_name = "#{operation}_file"
      
      record_performance_metric(:file_operation, operation_name, duration_ms, {
        operation: operation,
        filename: filename,
        file_size_mb: file_size_mb,
        success: !context[:error],
        context: context
      })
      
      # Log slow file operations
      if duration_ms > PERFORMANCE_THRESHOLDS[:file_upload_slow]
        LoggingService.log_warn(:performance, "Slow file operation", {
          operation: operation,
          filename: filename,
          duration_ms: duration_ms,
          file_size_mb: file_size_mb,
          threshold_ms: PERFORMANCE_THRESHOLDS[:file_upload_slow],
          context: context
        })
      end
    end
    
    # Track authentication performance
    def track_authentication(auth_type, duration_ms, success, context = {})
      return unless @monitoring_enabled
      
      record_performance_metric(:authentication, auth_type, duration_ms, {
        auth_type: auth_type,
        success: success,
        context: context
      })
      
      # Log slow authentication
      if duration_ms > PERFORMANCE_THRESHOLDS[:authentication_slow]
        LoggingService.log_warn(:performance, "Slow authentication", {
          auth_type: auth_type,
          duration_ms: duration_ms,
          success: success,
          threshold_ms: PERFORMANCE_THRESHOLDS[:authentication_slow],
          context: context
        })
      end
    end
    
    # Track room operation performance
    def track_room_operation(operation, room_id, duration_ms, context = {})
      return unless @monitoring_enabled
      
      record_performance_metric(:room_operation, operation, duration_ms, {
        operation: operation,
        room_id: room_id,
        success: !context[:error],
        context: context
      })
      
      # Log slow room operations
      if duration_ms > PERFORMANCE_THRESHOLDS[:room_operation_slow]
        LoggingService.log_warn(:performance, "Slow room operation", {
          operation: operation,
          room_id: room_id,
          duration_ms: duration_ms,
          threshold_ms: PERFORMANCE_THRESHOLDS[:room_operation_slow],
          context: context
        })
      end
    end
    
    # Track playback operation performance
    def track_playback_operation(operation, room_id, track_id, duration_ms, context = {})
      return unless @monitoring_enabled
      
      operation_name = "playback_#{operation}"
      
      record_performance_metric(:playback_operation, operation_name, duration_ms, {
        operation: operation,
        room_id: room_id,
        track_id: track_id,
        success: !context[:error],
        context: context
      })
      
      # Log slow playback operations
      if duration_ms > PERFORMANCE_THRESHOLDS[:playback_operation_slow]
        LoggingService.log_warn(:performance, "Slow playback operation", {
          operation: operation,
          room_id: room_id,
          track_id: track_id,
          duration_ms: duration_ms,
          threshold_ms: PERFORMANCE_THRESHOLDS[:playback_operation_slow],
          context: context
        })
      end
    end
    
    # Get current performance statistics
    def get_performance_statistics
      return {} unless @monitoring_enabled
      
      current_memory = get_memory_usage
      current_connections = get_connection_count
      uptime = Time.now - @@performance_stats[:monitoring_started]
      
      stats = @@performance_stats.dup
      stats[:current_memory_mb] = current_memory
      stats[:current_connections] = current_connections
      stats[:uptime_hours] = (uptime / 3600).round(2)
      stats[:operations_per_hour] = uptime > 0 ? (stats[:total_operations] / (uptime / 3600)).round(2) : 0
      
      # Calculate average durations
      stats[:average_durations_ms] = {}
      @@performance_stats[:average_durations].each do |operation, durations|
        if durations.any?
          stats[:average_durations_ms][operation] = (durations.sum / durations.length).round(2)
        end
      end
      
      # Add recent metrics summary
      stats[:recent_metrics] = get_recent_metrics_summary
      
      # Add performance health status
      stats[:health_status] = calculate_performance_health
      
      stats
    end
    
    # Get performance health status
    def get_performance_health
      return 'unknown' unless @monitoring_enabled
      
      calculate_performance_health
    end
    
    # Reset performance statistics
    def reset_performance_statistics
      @@performance_stats = {
        total_operations: 0,
        operations_by_type: Hash.new(0),
        slow_operations: Hash.new(0),
        average_durations: Hash.new { |h, k| h[k] = [] },
        peak_memory_usage: get_memory_usage,
        peak_connection_count: get_connection_count,
        monitoring_started: Time.now
      }
      
      @@recent_metrics[:metrics].clear
      
      LoggingService.log_info(:performance, "Performance statistics reset")
    end
    
    # Generate performance report
    def generate_performance_report
      return {} unless @monitoring_enabled
      
      stats = get_performance_statistics
      
      {
        summary: {
          monitoring_enabled: @monitoring_enabled,
          uptime_hours: stats[:uptime_hours],
          total_operations: stats[:total_operations],
          operations_per_hour: stats[:operations_per_hour],
          health_status: stats[:health_status]
        },
        memory: {
          current_mb: stats[:current_memory_mb],
          peak_mb: stats[:peak_memory_usage],
          status: get_memory_status(stats[:current_memory_mb])
        },
        connections: {
          current: stats[:current_connections],
          peak: stats[:peak_connection_count]
        },
        operations: {
          by_type: stats[:operations_by_type],
          slow_operations: stats[:slow_operations],
          average_durations_ms: stats[:average_durations_ms]
        },
        thresholds: PERFORMANCE_THRESHOLDS,
        recent_activity: stats[:recent_metrics]
      }
    end
    
    private
    
    def start_background_monitoring
      # Start background thread for periodic monitoring
      Thread.new do
        loop do
          begin
            sleep(60) # Monitor every minute
            collect_system_metrics
          rescue => error
            LoggingService.log_error(:performance, "Background monitoring error", {}, error)
          end
        end
      end
    end
    
    def collect_system_metrics
      current_memory = get_memory_usage
      current_connections = get_connection_count
      
      # Update peak values
      @@performance_stats[:peak_memory_usage] = [@@performance_stats[:peak_memory_usage], current_memory].max
      @@performance_stats[:peak_connection_count] = [@@performance_stats[:peak_connection_count], current_connections].max
      
      # Record system metrics
      record_performance_metric(:memory_usage, 'system_memory', 0, {
        memory_mb: current_memory,
        memory_status: get_memory_status(current_memory)
      })
      
      record_performance_metric(:connection_count, 'websocket_connections', 0, {
        connection_count: current_connections
      })
      
      # Log memory warnings
      memory_status = get_memory_status(current_memory)
      if memory_status != 'normal'
        LoggingService.log_warn(:performance, "Memory usage #{memory_status}", {
          current_memory_mb: current_memory,
          threshold: MEMORY_THRESHOLDS[memory_status.to_sym],
          peak_memory_mb: @@performance_stats[:peak_memory_usage]
        })
      end
    end
    
    def record_performance_metric(operation_type, operation_name, duration_ms, data = {})
      # Update statistics
      @@performance_stats[:total_operations] += 1
      @@performance_stats[:operations_by_type][operation_type] += 1
      
      # Track slow operations
      if slow_operation?(operation_type, duration_ms)
        @@performance_stats[:slow_operations][operation_type] += 1
      end
      
      # Update average durations (keep last 100 measurements)
      durations = @@performance_stats[:average_durations][operation_name]
      durations << duration_ms
      durations.shift if durations.length > 100
      
      # Add to recent metrics (sliding window)
      metric = {
        timestamp: Time.now.to_f,
        operation_type: operation_type,
        operation_name: operation_name,
        duration_ms: duration_ms,
        data: data
      }
      
      @@recent_metrics[:metrics] << metric
      if @@recent_metrics[:metrics].length > @@recent_metrics[:window_size]
        @@recent_metrics[:metrics].shift
      end
      
      # Log performance metric
      LoggingService.log_performance(operation_name.to_sym, duration_ms, data.merge({
        operation_type: operation_type
      }))
    end
    
    def slow_operation?(operation_type, duration_ms)
      threshold = get_slow_threshold(operation_type)
      duration_ms > threshold
    end
    
    def get_slow_threshold(operation_type)
      case operation_type
      when :request_duration then PERFORMANCE_THRESHOLDS[:api_request_slow]
      when :database_query then PERFORMANCE_THRESHOLDS[:database_query_slow]
      when :websocket_message then PERFORMANCE_THRESHOLDS[:websocket_message_slow]
      when :file_operation then PERFORMANCE_THRESHOLDS[:file_upload_slow]
      when :authentication then PERFORMANCE_THRESHOLDS[:authentication_slow]
      when :room_operation then PERFORMANCE_THRESHOLDS[:room_operation_slow]
      when :playback_operation then PERFORMANCE_THRESHOLDS[:playback_operation_slow]
      else 1000 # Default 1 second
      end
    end
    
    def get_memory_usage
      # Get memory usage in MB (Linux/Unix)
      if File.exist?('/proc/self/status')
        status = File.read('/proc/self/status')
        if match = status.match(/VmRSS:\s+(\d+)\s+kB/)
          return match[1].to_i / 1024.0 # Convert KB to MB
        end
      end
      
      # Fallback for other systems (simplified)
      begin
        # Use Ruby's ObjectSpace if available
        if defined?(ObjectSpace)
          # This is a rough approximation
          ObjectSpace.count_objects[:TOTAL] / 100000.0
        else
          0
        end
      rescue
        0
      end
    end
    
    def get_connection_count
      begin
        if defined?(WebSocketConnection)
          WebSocketConnection.connection_stats[:total_connections] || 0
        else
          0
        end
      rescue
        0
      end
    end
    
    def get_memory_status(memory_mb)
      case memory_mb
      when 0..MEMORY_THRESHOLDS[:normal]
        'normal'
      when MEMORY_THRESHOLDS[:normal]..MEMORY_THRESHOLDS[:warning]
        'warning'
      else
        'critical'
      end
    end
    
    def get_recent_metrics_summary
      return {} if @@recent_metrics[:metrics].empty?
      
      recent = @@recent_metrics[:metrics].last(10)
      
      {
        count: recent.length,
        average_duration_ms: recent.map { |m| m[:duration_ms] }.sum / recent.length.to_f,
        operation_types: recent.map { |m| m[:operation_type] }.uniq,
        time_range: {
          start: recent.first[:timestamp],
          end: recent.last[:timestamp]
        }
      }
    end
    
    def calculate_performance_health
      current_memory = get_memory_usage
      memory_status = get_memory_status(current_memory)
      
      # Calculate slow operation percentage
      total_ops = @@performance_stats[:total_operations]
      slow_ops = @@performance_stats[:slow_operations].values.sum
      slow_percentage = total_ops > 0 ? (slow_ops.to_f / total_ops * 100) : 0
      
      # Determine overall health
      if memory_status == 'critical' || slow_percentage > 50
        'critical'
      elsif memory_status == 'warning' || slow_percentage > 25
        'warning'
      elsif slow_percentage > 10
        'degraded'
      else
        'healthy'
      end
    end
  end
end

# Initialize performance monitoring when loaded
PerformanceMonitor.initialize_monitoring