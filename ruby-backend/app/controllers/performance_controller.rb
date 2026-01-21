# Performance Controller
# Provides comprehensive performance monitoring and optimization endpoints

require_relative '../services/performance_monitor'
require_relative '../services/database_optimizer'
require_relative '../services/websocket_optimizer'
require_relative '../services/caching_service'
require_relative '../services/auth_service'

class PerformanceController
  # GET /api/performance/dashboard - Comprehensive performance dashboard
  def self.dashboard(token = nil)
    begin
      # Optional authentication for detailed metrics
      detailed_metrics = false
      current_user = nil
      
      if token
        begin
          auth_data = AuthService.validate_jwt(token)
          current_user = auth_data[:user]
          detailed_metrics = true
        rescue AuthenticationError
          # Continue with basic metrics
        end
      end
      
      # Collect performance data from all optimization services
      dashboard_data = {
        server: get_server_metrics,
        performance: PerformanceMonitor.get_performance_statistics,
        database: DatabaseOptimizer.get_optimization_statistics,
        websocket: WebSocketOptimizer.get_optimization_statistics,
        cache: CachingService.get_statistics,
        health: get_overall_health_status
      }
      
      # Add detailed metrics for authenticated users
      if detailed_metrics
        dashboard_data[:detailed] = {
          memory_samples: get_memory_samples,
          slow_queries: get_slow_query_details,
          connection_details: get_connection_details,
          cache_health: CachingService.get_health_status
        }
      end
      
      {
        status: 200,
        body: {
          success: true,
          data: dashboard_data,
          timestamp: Time.now.to_f,
          authenticated: detailed_metrics
        }
      }
      
    rescue => e
      LoggingService.log_error(:performance, "Error generating performance dashboard", {}, e)
      
      {
        status: 500,
        body: {
          success: false,
          error: 'Failed to generate performance dashboard',
          message: SpotikConfig::Settings.app_debug? ? e.message : 'Internal server error'
        }
      }
    end
  end
  
  # GET /api/performance/metrics - Real-time performance metrics
  def self.metrics(token = nil)
    begin
      # Basic metrics available to all
      metrics = {
        timestamp: Time.now.to_f,
        server_time: Time.now.to_f,
        uptime: get_server_uptime,
        memory: {
          current_mb: get_current_memory_usage,
          status: get_memory_status
        },
        connections: {
          websocket: WebSocketOptimizer.get_optimization_statistics[:connections],
          database: DatabaseOptimizer.get_optimization_statistics[:connection_pool]
        },
        performance: {
          health_status: PerformanceMonitor.get_performance_health,
          operations_per_hour: PerformanceMonitor.get_performance_statistics[:operations_per_hour]
        },
        cache: {
          hit_rate: CachingService.get_statistics[:overall_hit_rate],
          total_entries: CachingService.get_statistics[:total_entries]
        }
      }
      
      {
        status: 200,
        body: {
          success: true,
          metrics: metrics
        }
      }
      
    rescue => e
      LoggingService.log_error(:performance, "Error getting performance metrics", {}, e)
      
      {
        status: 500,
        body: {
          success: false,
          error: 'Failed to get performance metrics'
        }
      }
    end
  end
  
  # POST /api/performance/optimize - Trigger performance optimizations
  def self.optimize(params, token)
    begin
      # Authenticate user
      auth_data = AuthService.validate_jwt(token)
      current_user = auth_data[:user]
      
      optimization_type = params['type'] || 'all'
      results = {}
      
      case optimization_type
      when 'database'
        results[:database] = optimize_database
      when 'websocket'
        results[:websocket] = optimize_websocket
      when 'cache'
        results[:cache] = optimize_cache
      when 'memory'
        results[:memory] = optimize_memory
      when 'all'
        results[:database] = optimize_database
        results[:websocket] = optimize_websocket
        results[:cache] = optimize_cache
        results[:memory] = optimize_memory
      else
        return {
          status: 400,
          body: {
            success: false,
            error: 'Invalid optimization type',
            valid_types: ['database', 'websocket', 'cache', 'memory', 'all']
          }
        }
      end
      
      LoggingService.log_info(:performance, "Performance optimization triggered", {
        user_id: current_user.id,
        username: current_user.username,
        optimization_type: optimization_type,
        results: results
      })
      
      {
        status: 200,
        body: {
          success: true,
          message: 'Performance optimization completed',
          optimization_type: optimization_type,
          results: results,
          timestamp: Time.now.to_f
        }
      }
      
    rescue AuthenticationError => e
      {
        status: 401,
        body: {
          success: false,
          message: 'Authentication failed',
          error: e.message
        }
      }
    rescue => e
      LoggingService.log_error(:performance, "Error during performance optimization", {
        optimization_type: params['type']
      }, e)
      
      {
        status: 500,
        body: {
          success: false,
          error: 'Performance optimization failed',
          message: SpotikConfig::Settings.app_debug? ? e.message : 'Internal server error'
        }
      }
    end
  end
  
  # GET /api/performance/health - Performance health check
  def self.health_check(token = nil)
    begin
      health_status = get_overall_health_status
      
      # Determine HTTP status based on health
      http_status = case health_status[:overall_status]
      when 'healthy' then 200
      when 'warning' then 200
      when 'degraded' then 503
      when 'critical' then 503
      else 500
      end
      
      {
        status: http_status,
        body: {
          success: true,
          health: health_status,
          timestamp: Time.now.to_f
        }
      }
      
    rescue => e
      LoggingService.log_error(:performance, "Error during performance health check", {}, e)
      
      {
        status: 500,
        body: {
          success: false,
          error: 'Performance health check failed'
        }
      }
    end
  end
  
  # GET /api/performance/benchmarks - Performance benchmarks
  def self.benchmarks(token)
    begin
      # Authenticate user
      auth_data = AuthService.validate_jwt(token)
      current_user = auth_data[:user]
      
      benchmarks = run_performance_benchmarks
      
      LoggingService.log_info(:performance, "Performance benchmarks executed", {
        user_id: current_user.id,
        username: current_user.username,
        benchmark_results: benchmarks
      })
      
      {
        status: 200,
        body: {
          success: true,
          benchmarks: benchmarks,
          timestamp: Time.now.to_f
        }
      }
      
    rescue AuthenticationError => e
      {
        status: 401,
        body: {
          success: false,
          message: 'Authentication failed',
          error: e.message
        }
      }
    rescue => e
      LoggingService.log_error(:performance, "Error running performance benchmarks", {}, e)
      
      {
        status: 500,
        body: {
          success: false,
          error: 'Performance benchmarks failed',
          message: SpotikConfig::Settings.app_debug? ? e.message : 'Internal server error'
        }
      }
    end
  end
  
  # POST /api/performance/cache/clear - Clear performance caches
  def self.clear_cache(params, token)
    begin
      # Authenticate user
      auth_data = AuthService.validate_jwt(token)
      current_user = auth_data[:user]
      
      cache_type = params['cache_type']
      
      if cache_type && cache_type != 'all'
        success = CachingService.clear(cache_type.to_sym)
        message = success ? "Cache '#{cache_type}' cleared successfully" : "Failed to clear cache '#{cache_type}'"
      else
        success = CachingService.clear_all
        message = success ? "All caches cleared successfully" : "Failed to clear caches"
      end
      
      # Also clear database query cache
      DatabaseOptimizer.invalidate_cache
      
      LoggingService.log_info(:performance, "Performance cache cleared", {
        user_id: current_user.id,
        username: current_user.username,
        cache_type: cache_type || 'all',
        success: success
      })
      
      {
        status: success ? 200 : 500,
        body: {
          success: success,
          message: message,
          cache_type: cache_type || 'all',
          timestamp: Time.now.to_f
        }
      }
      
    rescue AuthenticationError => e
      {
        status: 401,
        body: {
          success: false,
          message: 'Authentication failed',
          error: e.message
        }
      }
    rescue => e
      LoggingService.log_error(:performance, "Error clearing performance cache", {
        cache_type: params['cache_type']
      }, e)
      
      {
        status: 500,
        body: {
          success: false,
          error: 'Failed to clear cache',
          message: SpotikConfig::Settings.app_debug? ? e.message : 'Internal server error'
        }
      }
    end
  end
  
  private
  
  # Get server metrics
  def self.get_server_metrics
    {
      uptime: get_server_uptime,
      ruby_version: RUBY_VERSION,
      environment: SpotikConfig::Settings.app_env,
      threads: SpotikConfig::Settings.server_threads,
      workers: SpotikConfig::Settings.server_workers,
      memory_mb: get_current_memory_usage,
      load_average: get_load_average
    }
  end
  
  # Get overall health status
  def self.get_overall_health_status
    # Collect health data from all services
    performance_health = PerformanceMonitor.get_performance_health
    cache_health = CachingService.get_health_status
    websocket_stats = WebSocketOptimizer.get_optimization_statistics
    database_stats = DatabaseOptimizer.get_optimization_statistics
    
    # Determine overall status
    health_issues = []
    warning_issues = []
    
    # Check performance health
    case performance_health
    when 'critical'
      health_issues << 'Performance monitoring shows critical issues'
    when 'warning', 'degraded'
      warning_issues << 'Performance monitoring shows degraded performance'
    end
    
    # Check cache health
    if cache_health[:status] != 'healthy'
      warning_issues += cache_health[:issues]
    end
    
    # Check WebSocket memory usage
    websocket_memory = websocket_stats[:memory]
    if websocket_memory[:status] == 'critical'
      health_issues << "WebSocket memory usage critical: #{websocket_memory[:current_mb]}MB"
    elsif websocket_memory[:status] == 'warning'
      warning_issues << "WebSocket memory usage high: #{websocket_memory[:current_mb]}MB"
    end
    
    # Check database connection pool
    db_pool = database_stats[:connection_pool]
    if db_pool[:available] && db_pool[:available] < 2
      warning_issues << "Low database connection pool availability: #{db_pool[:available]}"
    end
    
    # Determine overall status
    overall_status = if health_issues.any?
      'critical'
    elsif warning_issues.any?
      'warning'
    else
      'healthy'
    end
    
    {
      overall_status: overall_status,
      health_issues: health_issues,
      warning_issues: warning_issues,
      components: {
        performance: performance_health,
        cache: cache_health[:status],
        websocket_memory: websocket_memory[:status],
        database_pool: db_pool[:available] ? (db_pool[:available] > 2 ? 'healthy' : 'warning') : 'unknown'
      },
      timestamp: Time.now.to_f
    }
  end
  
  # Optimization methods
  def self.optimize_database
    begin
      # Force database maintenance
      DatabaseOptimizer.perform_maintenance
      
      # Get updated statistics
      stats = DatabaseOptimizer.get_optimization_statistics
      
      {
        success: true,
        message: 'Database optimization completed',
        cache_hit_rate: stats[:query_cache][:hit_rate],
        connection_pool: stats[:connection_pool]
      }
    rescue => e
      {
        success: false,
        error: e.message
      }
    end
  end
  
  def self.optimize_websocket
    begin
      # Clean up stale connections
      cleaned_connections = WebSocketOptimizer.cleanup_stale_connections
      
      # Trigger garbage collection
      memory_freed = WebSocketOptimizer.trigger_garbage_collection('manual_optimization')
      
      {
        success: true,
        message: 'WebSocket optimization completed',
        cleaned_connections: cleaned_connections,
        memory_freed_mb: memory_freed
      }
    rescue => e
      {
        success: false,
        error: e.message
      }
    end
  end
  
  def self.optimize_cache
    begin
      # Clean up expired cache entries
      cleaned_entries = CachingService.cleanup_expired_entries
      
      # Get cache statistics
      stats = CachingService.get_statistics
      
      {
        success: true,
        message: 'Cache optimization completed',
        cleaned_entries: cleaned_entries,
        hit_rate: stats[:overall_hit_rate],
        total_entries: stats[:total_entries]
      }
    rescue => e
      {
        success: false,
        error: e.message
      }
    end
  end
  
  def self.optimize_memory
    begin
      # Force garbage collection
      GC.start
      
      memory_after = get_current_memory_usage
      
      {
        success: true,
        message: 'Memory optimization completed',
        memory_after_mb: memory_after
      }
    rescue => e
      {
        success: false,
        error: e.message
      }
    end
  end
  
  # Benchmark methods
  def self.run_performance_benchmarks
    benchmarks = {}
    
    # Database query benchmark
    benchmarks[:database] = benchmark_database_queries
    
    # WebSocket message benchmark
    benchmarks[:websocket] = benchmark_websocket_messages
    
    # Cache performance benchmark
    benchmarks[:cache] = benchmark_cache_operations
    
    # Memory allocation benchmark
    benchmarks[:memory] = benchmark_memory_operations
    
    benchmarks
  end
  
  def self.benchmark_database_queries
    require 'benchmark'
    
    times = Benchmark.measure do
      # Run sample database queries
      10.times do
        User.count
        Room.where(is_playing: true).count
        Track.order(:created_at).limit(10).all
      end
    end
    
    {
      total_time_seconds: times.real.round(4),
      queries_per_second: (30 / times.real).round(2),
      average_query_time_ms: (times.real * 1000 / 30).round(2)
    }
  rescue => e
    { error: e.message }
  end
  
  def self.benchmark_websocket_messages
    # Simulate WebSocket message processing
    start_time = Time.now
    
    100.times do |i|
      message = { type: 'test_message', data: { index: i, timestamp: Time.now.to_f } }
      # Simulate message serialization
      JSON.generate(message)
    end
    
    end_time = Time.now
    duration = end_time - start_time
    
    {
      total_time_seconds: duration.round(4),
      messages_per_second: (100 / duration).round(2),
      average_message_time_ms: (duration * 1000 / 100).round(2)
    }
  rescue => e
    { error: e.message }
  end
  
  def self.benchmark_cache_operations
    start_time = Time.now
    
    # Test cache set operations
    50.times do |i|
      CachingService.set(:api_response, "benchmark_key_#{i}", { data: "test_data_#{i}" })
    end
    
    # Test cache get operations
    50.times do |i|
      CachingService.get(:api_response, "benchmark_key_#{i}")
    end
    
    end_time = Time.now
    duration = end_time - start_time
    
    {
      total_time_seconds: duration.round(4),
      operations_per_second: (100 / duration).round(2),
      average_operation_time_ms: (duration * 1000 / 100).round(2)
    }
  rescue => e
    { error: e.message }
  end
  
  def self.benchmark_memory_operations
    start_time = Time.now
    memory_before = get_current_memory_usage
    
    # Allocate and deallocate memory
    arrays = []
    100.times do |i|
      arrays << Array.new(1000) { |j| "string_#{i}_#{j}" }
    end
    
    memory_peak = get_current_memory_usage
    arrays.clear
    GC.start
    
    memory_after = get_current_memory_usage
    end_time = Time.now
    
    {
      total_time_seconds: (end_time - start_time).round(4),
      memory_before_mb: memory_before,
      memory_peak_mb: memory_peak,
      memory_after_mb: memory_after,
      memory_allocated_mb: memory_peak - memory_before,
      memory_freed_mb: memory_peak - memory_after
    }
  rescue => e
    { error: e.message }
  end
  
  # Helper methods
  def self.get_server_uptime
    return 0 unless defined?($server_start_time) && $server_start_time
    
    (Time.now - $server_start_time).to_i
  end
  
  def self.get_current_memory_usage
    # Get memory usage in MB (Linux/Unix)
    if File.exist?('/proc/self/status')
      status = File.read('/proc/self/status')
      if match = status.match(/VmRSS:\s+(\d+)\s+kB/)
        return match[1].to_i / 1024.0 # Convert KB to MB
      end
    end
    
    # Fallback for other systems
    begin
      if defined?(ObjectSpace)
        ObjectSpace.count_objects[:TOTAL] / 100000.0
      else
        0
      end
    rescue
      0
    end
  end
  
  def self.get_memory_status
    memory_mb = get_current_memory_usage
    
    case memory_mb
    when 0..100
      'normal'
    when 100..250
      'warning'
    else
      'critical'
    end
  end
  
  def self.get_load_average
    if File.exist?('/proc/loadavg')
      loadavg = File.read('/proc/loadavg').split
      {
        one_minute: loadavg[0].to_f,
        five_minutes: loadavg[1].to_f,
        fifteen_minutes: loadavg[2].to_f
      }
    else
      { one_minute: 0, five_minutes: 0, fifteen_minutes: 0 }
    end
  rescue
    { one_minute: 0, five_minutes: 0, fifteen_minutes: 0 }
  end
  
  def self.get_memory_samples
    # This would be implemented by the MemoryMonitoringMiddleware
    []
  end
  
  def self.get_slow_query_details
    # This would be implemented by the DatabaseQueryMiddleware
    []
  end
  
  def self.get_connection_details
    WebSocketOptimizer.get_optimization_statistics
  end
end