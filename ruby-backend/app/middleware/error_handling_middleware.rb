# Error Handling Middleware for Spotik Ruby Backend
# Provides comprehensive error handling and logging for all HTTP requests

require_relative '../services/error_handler'
require_relative '../services/logging_service'
require_relative '../services/performance_monitor'

class ErrorHandlingMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    request_start_time = Time.now
    request_id = generate_request_id
    
    # Add request ID to environment for downstream use
    env['HTTP_X_REQUEST_ID'] = request_id
    
    # Extract request information
    request_info = extract_request_info(env, request_id)
    
    # Log incoming request
    log_request_start(request_info)
    
    begin
      # Call the next middleware/application
      status, headers, response = @app.call(env)
      
      # Calculate request duration
      duration_ms = ((Time.now - request_start_time) * 1000).round(2)
      
      # Add request ID to response headers
      headers['X-Request-ID'] = request_id
      
      # Log successful request
      log_request_completion(request_info, status, duration_ms, nil)
      
      # Track performance
      PerformanceMonitor.track_api_request(
        request_info[:method],
        request_info[:path],
        status,
        duration_ms,
        {
          request_id: request_id,
          user_id: request_info[:user_id],
          ip_address: request_info[:ip_address]
        }
      )
      
      [status, headers, response]
      
    rescue => error
      # Calculate request duration for failed request
      duration_ms = ((Time.now - request_start_time) * 1000).round(2)
      
      # Handle the error using ErrorHandler
      error_response = ErrorHandler.handle_api_error(error, request_info.merge(
        duration_ms: duration_ms,
        request_id: request_id
      ))
      
      # Log failed request
      log_request_completion(request_info, error_response[:status], duration_ms, error)
      
      # Track performance for failed request
      PerformanceMonitor.track_api_request(
        request_info[:method],
        request_info[:path],
        error_response[:status],
        duration_ms,
        {
          request_id: request_id,
          user_id: request_info[:user_id],
          ip_address: request_info[:ip_address],
          error: true,
          error_class: error.class.name
        }
      )
      
      # Return error response
      headers = {
        'Content-Type' => 'application/json',
        'X-Request-ID' => request_id
      }
      
      [error_response[:status], headers, [error_response[:body].to_json]]
    end
  end
  
  private
  
  def generate_request_id
    "req_#{Time.now.to_i}_#{SecureRandom.hex(8)}"
  end
  
  def extract_request_info(env, request_id)
    request = Rack::Request.new(env)
    
    {
      request_id: request_id,
      method: request.request_method,
      path: request.path_info,
      query_string: request.query_string,
      ip_address: get_client_ip(env),
      user_agent: env['HTTP_USER_AGENT'],
      content_type: env['CONTENT_TYPE'],
      content_length: env['CONTENT_LENGTH']&.to_i,
      user_id: extract_user_id_from_request(env),
      timestamp: Time.now.iso8601
    }
  end
  
  def get_client_ip(env)
    # Check for forwarded IP addresses (load balancer, proxy)
    forwarded_for = env['HTTP_X_FORWARDED_FOR']
    if forwarded_for
      # Take the first IP if multiple are present
      return forwarded_for.split(',').first.strip
    end
    
    # Check for real IP header
    real_ip = env['HTTP_X_REAL_IP']
    return real_ip if real_ip
    
    # Fall back to remote address
    env['REMOTE_ADDR'] || 'unknown'
  end
  
  def extract_user_id_from_request(env)
    # Try to extract user ID from JWT token
    begin
      auth_header = env['HTTP_AUTHORIZATION']
      if auth_header && auth_header.start_with?('Bearer ')
        token = auth_header[7..-1]
        
        # Quick decode without full validation (for logging purposes only)
        decoded = JWT.decode(token, nil, false)
        payload = decoded[0]
        
        return payload['sub'] || payload['user_id']
      end
    rescue
      # Ignore errors in user ID extraction for logging
    end
    
    nil
  end
  
  def log_request_start(request_info)
    LoggingService.log_info(:api, "Request started", {
      request_id: request_info[:request_id],
      method: request_info[:method],
      path: request_info[:path],
      ip_address: request_info[:ip_address],
      user_agent: request_info[:user_agent],
      user_id: request_info[:user_id],
      content_length: request_info[:content_length]
    })
  end
  
  def log_request_completion(request_info, status, duration_ms, error = nil)
    log_data = {
      request_id: request_info[:request_id],
      method: request_info[:method],
      path: request_info[:path],
      status: status,
      duration_ms: duration_ms,
      ip_address: request_info[:ip_address],
      user_id: request_info[:user_id]
    }
    
    if error
      log_data[:error] = {
        class: error.class.name,
        message: error.message
      }
      
      LoggingService.log_error(:api, "Request failed", log_data, error)
    else
      level = case status
      when 200..299 then :info
      when 300..399 then :info
      when 400..499 then :warn
      when 500..599 then :error
      else :info
      end
      
      LoggingService.log_structured(level, :api, "Request completed", log_data)
    end
  end
end

# Request Logging Middleware - Simpler middleware for basic request logging
class RequestLoggingMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    start_time = Time.now
    
    # Extract basic request info
    method = env['REQUEST_METHOD']
    path = env['PATH_INFO']
    ip = env['REMOTE_ADDR'] || 'unknown'
    
    begin
      status, headers, response = @app.call(env)
      duration_ms = ((Time.now - start_time) * 1000).round(2)
      
      # Log request with appropriate level based on status
      level = case status
      when 200..299 then :debug
      when 400..499 then :info
      when 500..599 then :warn
      else :info
      end
      
      LoggingService.log_structured(level, :api, "#{method} #{path} -> #{status}", {
        method: method,
        path: path,
        status: status,
        duration_ms: duration_ms,
        ip_address: ip
      })
      
      [status, headers, response]
      
    rescue => error
      duration_ms = ((Time.now - start_time) * 1000).round(2)
      
      LoggingService.log_error(:api, "#{method} #{path} -> ERROR", {
        method: method,
        path: path,
        duration_ms: duration_ms,
        ip_address: ip
      }, error)
      
      raise error
    end
  end
end

# Performance Monitoring Middleware
class PerformanceMonitoringMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    return @app.call(env) unless SpotikConfig::Settings.performance_monitoring_enabled?
    
    request = Rack::Request.new(env)
    operation_name = "#{request.request_method}_#{request.path_info}"
    
    PerformanceMonitor.measure_operation(:request_duration, operation_name, {
      method: request.request_method,
      path: request.path_info,
      ip_address: env['REMOTE_ADDR']
    }) do
      @app.call(env)
    end
  end
end

# Security Headers Middleware
class SecurityHeadersMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    status, headers, response = @app.call(env)
    
    # Add security headers
    headers.merge!({
      'X-Content-Type-Options' => 'nosniff',
      'X-Frame-Options' => 'DENY',
      'X-XSS-Protection' => '1; mode=block',
      'Referrer-Policy' => 'strict-origin-when-cross-origin',
      'Content-Security-Policy' => "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline';"
    })
    
    [status, headers, response]
  end
end

# Rate Limiting Middleware (basic implementation)
class RateLimitingMiddleware
  def initialize(app, options = {})
    @app = app
    @max_requests = options[:max_requests] || 100
    @time_window = options[:time_window] || 3600 # 1 hour
    @requests = {}
  end
  
  def call(env)
    client_ip = env['REMOTE_ADDR'] || 'unknown'
    current_time = Time.now.to_i
    
    # Clean up old entries
    cleanup_old_entries(current_time)
    
    # Check rate limit
    @requests[client_ip] ||= []
    @requests[client_ip] << current_time
    
    if @requests[client_ip].length > @max_requests
      # Rate limit exceeded
      LoggingService.log_security_event('rate_limit_exceeded', 'Rate limit exceeded', {
        ip_address: client_ip,
        request_count: @requests[client_ip].length,
        max_requests: @max_requests,
        time_window: @time_window
      })
      
      error_response = {
        error: 'Rate limit exceeded',
        message: "Too many requests. Maximum #{@max_requests} requests per hour allowed.",
        retry_after: @time_window
      }
      
      headers = {
        'Content-Type' => 'application/json',
        'Retry-After' => @time_window.to_s,
        'X-RateLimit-Limit' => @max_requests.to_s,
        'X-RateLimit-Remaining' => '0',
        'X-RateLimit-Reset' => (current_time + @time_window).to_s
      }
      
      return [429, headers, [error_response.to_json]]
    end
    
    # Add rate limit headers to response
    status, headers, response = @app.call(env)
    
    remaining = [@max_requests - @requests[client_ip].length, 0].max
    headers.merge!({
      'X-RateLimit-Limit' => @max_requests.to_s,
      'X-RateLimit-Remaining' => remaining.to_s,
      'X-RateLimit-Reset' => (current_time + @time_window).to_s
    })
    
    [status, headers, response]
  end
  
  private
  
  def cleanup_old_entries(current_time)
    cutoff_time = current_time - @time_window
    
    @requests.each do |ip, timestamps|
      @requests[ip] = timestamps.select { |timestamp| timestamp > cutoff_time }
    end
    
    # Remove empty entries
    @requests.reject! { |ip, timestamps| timestamps.empty? }
  end
end