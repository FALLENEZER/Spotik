# Performance Monitoring Middleware
# Implements comprehensive performance monitoring for HTTP requests and WebSocket connections

require_relative '../services/performance_monitor'
require_relative '../services/logging_service'

# Security Headers Middleware
class SecurityHeadersMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    status, headers, response = @app.call(env)
    
    # Add security headers
    headers['X-Frame-Options'] = 'DENY'
    headers['X-Content-Type-Options'] = 'nosniff'
    headers['X-XSS-Protection'] = '1; mode=block'
    headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    headers['Content-Security-Policy'] = "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'"
    
    [status, headers, response]
  end
end

# Rate Limiting Middleware
class RateLimitingMiddleware
  def initialize(app, options = {})
    @app = app
    @max_requests = options[:max_requests] || 1000
    @time_window = options[:time_window] || 3600 # 1 hour
    @client_requests = {}
    @cleanup_interval = 300 # 5 minutes
    @last_cleanup = Time.now
  end
  
  def call(env)
    client_ip = get_client_ip(env)
    current_time = Time.now
    
    # Periodic cleanup of old entries
    cleanup_old_entries(current_time) if should_cleanup?(current_time)
    
    # Check rate limit
    if rate_limited?(client_ip, current_time)
      LoggingService.log_security_event('rate_limit_exceeded', "Rate limit exceeded for IP #{client_ip}", {
        ip_address: client_ip,
        requests_in_window: @client_requests[client_ip][:count],
        max_requests: @max_requests,
        time_window: @time_window
      })
      
      return [429, 
              { 'Content-Type' => 'application/json', 'Retry-After' => @time_window.to_s }, 
              [{ error: 'Rate limit exceeded', retry_after: @time_window }.to_json]]
    end
    
    # Record request
    record_request(client_ip, current_time)
    
    @app.call(env)
  end
  
  private
  
  def get_client_ip(env)
    env['HTTP_X_FORWARDED_FOR'] || env['HTTP_X_REAL_IP'] || env['REMOTE_ADDR'] || 'unknown'
  end
  
  def rate_limited?(client_ip, current_time)
    client_data = @client_requests[client_ip]
    return false unless client_data
    
    # Check if within time window
    if current_time - client_data[:window_start] < @time_window
      client_data[:count] >= @max_requests
    else
      # Reset window
      @client_requests[client_ip] = { count: 0, window_start: current_time }
      false
    end
  end
  
  def record_request(client_ip, current_time)
    if @client_requests[client_ip]
      # Check if we need to reset the window
      if current_time - @client_requests[client_ip][:window_start] >= @time_window
        @client_requests[client_ip] = { count: 1, window_start: current_time }
      else
        @client_requests[client_ip][:count] += 1
      end
    else
      @client_requests[client_ip] = { count: 1, window_start: current_time }
    end
  end
  
  def should_cleanup?(current_time)
    current_time - @last_cleanup > @cleanup_interval
  end
  
  def cleanup_old_entries(current_time)
    @client_requests.reject! do |ip, data|
      current_time - data[:window_start] > @time_window * 2
    end
    @last_cleanup = current_time
  end
end

# Performance Monitoring Middleware
class PerformanceMonitoringMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    return @app.call(env) unless SpotikConfig::Settings.performance_monitoring_enabled?
    
    request_start_time = Time.now
    request_method = env['REQUEST_METHOD']
    request_path = env['PATH_INFO']
    client_ip = get_client_ip(env)
    user_agent = env['HTTP_USER_AGENT']
    
    # Extract user information if available
    user_id = extract_user_id_from_request(env)
    
    # Measure request processing time
    status, headers, response = PerformanceMonitor.measure_operation(
      :request_duration,
      "#{request_method} #{request_path}",
      {
        method: request_method,
        path: request_path,
        client_ip: client_ip,
        user_agent: user_agent,
        user_id: user_id
      }
    ) do
      @app.call(env)
    end
    
    # Calculate request duration
    request_duration = ((Time.now - request_start_time) * 1000).round(2)
    
    # Track API request performance
    PerformanceMonitor.track_api_request(
      request_method,
      request_path,
      status,
      request_duration,
      {
        client_ip: client_ip,
        user_agent: user_agent,
        user_id: user_id,
        response_size: calculate_response_size(response)
      }
    )
    
    # Add performance headers
    headers['X-Response-Time'] = "#{request_duration}ms"
    headers['X-Request-ID'] = generate_request_id
    
    # Log slow requests
    if request_duration > SpotikConfig::Settings.slow_request_threshold
      LoggingService.log_warn(:performance, "Slow HTTP request detected", {
        method: request_method,
        path: request_path,
        duration_ms: request_duration,
        status: status,
        client_ip: client_ip,
        user_id: user_id,
        threshold_ms: SpotikConfig::Settings.slow_request_threshold
      })
    end
    
    # Log request details
    LoggingService.log_api_request(request_method, request_path, status, request_duration, {
      client_ip: client_ip,
      user_agent: user_agent,
      user_id: user_id
    })
    
    [status, headers, response]
  end
  
  private
  
  def get_client_ip(env)
    env['HTTP_X_FORWARDED_FOR'] || env['HTTP_X_REAL_IP'] || env['REMOTE_ADDR'] || 'unknown'
  end
  
  def extract_user_id_from_request(env)
    # Try to extract user ID from Authorization header
    auth_header = env['HTTP_AUTHORIZATION']
    return nil unless auth_header && auth_header.start_with?('Bearer ')
    
    token = auth_header[7..-1]
    begin
      auth_data = AuthService.validate_jwt(token)
      auth_data[:user]&.id
    rescue
      nil
    end
  end
  
  def calculate_response_size(response)
    return 0 unless response.respond_to?(:each)
    
    size = 0
    response.each { |chunk| size += chunk.bytesize if chunk.respond_to?(:bytesize) }
    size
  rescue
    0
  end
  
  def generate_request_id
    SecureRandom.hex(8)
  end
end

# Database Query Performance Middleware
class DatabaseQueryMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    return @app.call(env) unless SpotikConfig::Settings.performance_monitoring_enabled?
    
    # Hook into Sequel to monitor database queries
    setup_database_monitoring if defined?(Sequel)
    
    @app.call(env)
  end
  
  private
  
  def setup_database_monitoring
    return if @monitoring_setup
    
    # Add query logging to Sequel
    if defined?(SpotikConfig::Database) && SpotikConfig::Database.connection
      db = SpotikConfig::Database.connection
      
      # Add query timing
      db.extension :query_literals
      
      # Hook into query execution
      db.define_singleton_method(:log_connection_yield) do |sql, conn, args = nil|
        start_time = Time.now
        
        begin
          result = super(sql, conn, args)
          duration_ms = ((Time.now - start_time) * 1000).round(2)
          
          # Extract table name from SQL
          table_name = extract_table_name(sql)
          operation = extract_operation(sql)
          
          # Track database query performance
          PerformanceMonitor.track_database_query(
            operation,
            table_name,
            duration_ms,
            {
              sql: sql.length > 200 ? "#{sql[0..200]}..." : sql,
              args: args
            }
          )
          
          result
        rescue => e
          duration_ms = ((Time.now - start_time) * 1000).round(2)
          
          # Track failed query
          PerformanceMonitor.track_database_query(
            extract_operation(sql),
            extract_table_name(sql),
            duration_ms,
            {
              error: e.class.name,
              sql: sql.length > 200 ? "#{sql[0..200]}..." : sql
            }
          )
          
          raise e
        end
      end
    end
    
    @monitoring_setup = true
  end
  
  def extract_table_name(sql)
    # Simple table name extraction from SQL
    case sql.upcase
    when /FROM\s+(\w+)/i
      $1.downcase
    when /UPDATE\s+(\w+)/i
      $1.downcase
    when /INSERT\s+INTO\s+(\w+)/i
      $1.downcase
    when /DELETE\s+FROM\s+(\w+)/i
      $1.downcase
    else
      'unknown'
    end
  end
  
  def extract_operation(sql)
    case sql.upcase.strip
    when /^SELECT/
      'SELECT'
    when /^INSERT/
      'INSERT'
    when /^UPDATE/
      'UPDATE'
    when /^DELETE/
      'DELETE'
    when /^CREATE/
      'CREATE'
    when /^DROP/
      'DROP'
    when /^ALTER/
      'ALTER'
    else
      'OTHER'
    end
  end
end

# Memory Usage Monitoring Middleware
class MemoryMonitoringMiddleware
  def initialize(app)
    @app = app
    @memory_samples = []
    @sample_interval = 10 # Sample every 10 requests
    @request_count = 0
  end
  
  def call(env)
    return @app.call(env) unless SpotikConfig::Settings.performance_monitoring_enabled?
    
    @request_count += 1
    
    # Sample memory usage periodically
    if @request_count % @sample_interval == 0
      memory_before = get_memory_usage
    end
    
    status, headers, response = @app.call(env)
    
    # Sample memory after request if we sampled before
    if memory_before
      memory_after = get_memory_usage
      memory_delta = memory_after - memory_before
      
      # Track memory usage
      @memory_samples << {
        timestamp: Time.now,
        memory_before: memory_before,
        memory_after: memory_after,
        memory_delta: memory_delta,
        request_path: env['PATH_INFO']
      }
      
      # Keep only last 100 samples
      @memory_samples = @memory_samples.last(100)
      
      # Log significant memory increases
      if memory_delta > 10 # More than 10MB increase
        LoggingService.log_warn(:performance, "Significant memory increase detected", {
          path: env['PATH_INFO'],
          memory_before_mb: memory_before,
          memory_after_mb: memory_after,
          memory_delta_mb: memory_delta
        })
      end
    end
    
    [status, headers, response]
  end
  
  def get_memory_samples
    @memory_samples.dup
  end
  
  private
  
  def get_memory_usage
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
end

# Request/Response Compression Middleware
class CompressionMiddleware
  def initialize(app, options = {})
    @app = app
    @min_size = options[:min_size] || 1024 # Only compress responses larger than 1KB
    @compression_level = options[:level] || 6
  end
  
  def call(env)
    status, headers, response = @app.call(env)
    
    # Check if client accepts compression
    accept_encoding = env['HTTP_ACCEPT_ENCODING']
    return [status, headers, response] unless accept_encoding
    
    # Check if response should be compressed
    content_type = headers['Content-Type']
    return [status, headers, response] unless compressible_content_type?(content_type)
    
    # Calculate response size
    response_body = []
    response.each { |chunk| response_body << chunk }
    response_size = response_body.join.bytesize
    
    return [status, headers, response_body] if response_size < @min_size
    
    # Compress response
    if accept_encoding.include?('gzip')
      compressed_body = compress_gzip(response_body.join)
      
      if compressed_body.bytesize < response_size
        headers['Content-Encoding'] = 'gzip'
        headers['Content-Length'] = compressed_body.bytesize.to_s
        headers['Vary'] = 'Accept-Encoding'
        
        LoggingService.log_debug(:performance, "Response compressed", {
          original_size: response_size,
          compressed_size: compressed_body.bytesize,
          compression_ratio: (compressed_body.bytesize.to_f / response_size * 100).round(2)
        })
        
        return [status, headers, [compressed_body]]
      end
    end
    
    [status, headers, response_body]
  end
  
  private
  
  def compressible_content_type?(content_type)
    return false unless content_type
    
    compressible_types = [
      'application/json',
      'text/html',
      'text/css',
      'text/javascript',
      'application/javascript',
      'text/plain',
      'application/xml',
      'text/xml'
    ]
    
    compressible_types.any? { |type| content_type.include?(type) }
  end
  
  def compress_gzip(content)
    require 'zlib'
    
    io = StringIO.new
    gzip_writer = Zlib::GzipWriter.new(io, @compression_level)
    gzip_writer.write(content)
    gzip_writer.close
    
    io.string
  rescue => e
    LoggingService.log_warn(:performance, "Failed to compress response", { error: e.message })
    content
  end
end