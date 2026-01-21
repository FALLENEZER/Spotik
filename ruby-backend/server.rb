#!/usr/bin/env ruby

# Main server file for Spotik Ruby Backend
# Migration from Laravel to Ruby with native WebSocket support

require 'bundler/setup'
require 'iodine'
require 'sinatra/base'
require 'json'
require 'logger'

# Load configuration
require_relative 'config/settings'
require_relative 'config/database'
require_relative 'app/services/configuration_service'

# Load error handling and logging services
require_relative 'app/services/logging_service'
require_relative 'app/services/error_handler'
require_relative 'app/services/performance_monitor'
require_relative 'app/middleware/error_handling_middleware'

# Load performance optimization services
require_relative 'app/services/database_optimizer'
require_relative 'app/services/websocket_optimizer'
require_relative 'app/services/caching_service'
require_relative 'app/middleware/performance_middleware'

# Load models and controllers
require_relative 'app/models'
require_relative 'app/services/auth_service'
require_relative 'app/services/room_manager'
require_relative 'app/controllers/auth_controller'
require_relative 'app/controllers/room_controller'
require_relative 'app/controllers/track_controller'
require_relative 'app/controllers/playback_controller'
require_relative 'app/controllers/health_controller'
require_relative 'app/controllers/performance_controller'

# Load WebSocket components
require_relative 'app/websocket/connection'

# Setup logging
def setup_logging
  # Use the new LoggingService instead of basic Logger
  LoggingService.initialize_logging
  LoggingService.logger
end

# Initialize logger and services
$logger = setup_logging

# Track server startup time for uptime calculation
$server_start_time = Time.now

class SpotikServer < Sinatra::Base
  # Configure Sinatra
  configure do
    set :logging, SpotikConfig::Settings.app_debug?
    set :dump_errors, SpotikConfig::Settings.app_debug?
    set :show_exceptions, SpotikConfig::Settings.development?
    
    # Add error handling middleware
    use ErrorHandlingMiddleware
    use PerformanceMonitoringMiddleware if SpotikConfig::Settings.performance_monitoring_enabled?
    use DatabaseQueryMiddleware if SpotikConfig::Settings.performance_monitoring_enabled?
    use MemoryMonitoringMiddleware if SpotikConfig::Settings.performance_monitoring_enabled?
    use CompressionMiddleware, min_size: 1024, level: 6
    use SecurityHeadersMiddleware
    use RateLimitingMiddleware, max_requests: 1000, time_window: 3600 # 1000 requests per hour
    
    # CORS headers for frontend compatibility
    before do
      headers 'Access-Control-Allow-Origin' => '*'
      headers 'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS'
      headers 'Access-Control-Allow-Headers' => 'Content-Type, Authorization'
    end
    
    # Handle preflight requests
    options '*' do
      200
    end
  end

  # Enhanced health check endpoint with database validation
  get '/health' do
    content_type :json
    
    result = HealthController.comprehensive_health
    status result[:status]
    result[:body].to_json
  end

  # Basic health check endpoint (for load balancers)
  get '/health/basic' do
    content_type :json
    
    result = HealthController.basic_health
    status result[:status]
    result[:body].to_json
  end

  # Database-specific health check endpoint
  get '/health/database' do
    content_type :json
    
    result = HealthController.database_health
    status result[:status]
    result[:body].to_json
  end

  # Configuration-specific health check endpoint
  get '/health/configuration' do
    content_type :json
    
    result = HealthController.configuration_health
    status result[:status]
    result[:body].to_json
  end

  # Storage-specific health check endpoint
  get '/health/storage' do
    content_type :json
    
    result = HealthController.storage_health
    status result[:status]
    result[:body].to_json
  end

  # Performance monitoring health check endpoint
  get '/health/performance' do
    content_type :json
    
    result = HealthController.performance_health
    status result[:status]
    result[:body].to_json
  end

  # Kubernetes/Docker readiness probe
  get '/ready' do
    content_type :json
    
    result = HealthController.readiness_check
    status result[:status]
    result[:body].to_json
  end

  # Kubernetes/Docker liveness probe
  get '/live' do
    content_type :json
    
    result = HealthController.liveness_check
    status result[:status]
    result[:body].to_json
  end

  # Basic API info endpoint
  get '/api' do
    content_type :json
    {
      name: SpotikConfig::Settings.app_name,
      version: '1.0.0',
      environment: SpotikConfig::Settings.app_env,
      ruby_version: RUBY_VERSION,
      server: 'Iodine',
      websocket_support: true,
      timestamp: Time.now.iso8601
    }.to_json
  end

  # Configuration management endpoints
  get '/api/configuration/summary' do
    content_type :json
    
    token = extract_token_from_request
    
    begin
      # Authenticate user (required for configuration access)
      auth_data = AuthService.validate_jwt(token)
      current_user = auth_data[:user]
      
      status 200
      ConfigurationService.configuration_summary.to_json
      
    rescue AuthenticationError => e
      status 401
      { error: 'Authentication required for configuration access' }.to_json
    rescue => e
      LoggingService.log_error(:api, "Error getting configuration summary", {}, e)
      status 500
      { error: 'Failed to get configuration summary' }.to_json
    end
  end

  get '/api/configuration/environment' do
    content_type :json
    
    token = extract_token_from_request
    
    begin
      # Authenticate user (required for environment info)
      auth_data = AuthService.validate_jwt(token)
      current_user = auth_data[:user]
      
      status 200
      ConfigurationService.get_environment_info.to_json
      
    rescue AuthenticationError => e
      status 401
      { error: 'Authentication required for environment information' }.to_json
    rescue => e
      LoggingService.log_error(:api, "Error getting environment info", {}, e)
      status 500
      { error: 'Failed to get environment information' }.to_json
    end
  end

  get '/api/configuration/security' do
    content_type :json
    
    token = extract_token_from_request
    
    begin
      # Authenticate user (required for security configuration)
      auth_data = AuthService.validate_jwt(token)
      current_user = auth_data[:user]
      
      # Get security configuration (without sensitive values)
      security_config = ConfigurationService.get_security_configuration
      
      # Remove sensitive information
      security_config.delete(:jwt_secret) if security_config[:jwt_secret]
      
      status 200
      security_config.to_json
      
    rescue AuthenticationError => e
      status 401
      { error: 'Authentication required for security configuration' }.to_json
    rescue => e
      LoggingService.log_error(:api, "Error getting security configuration", {}, e)
      status 500
      { error: 'Failed to get security configuration' }.to_json
    end
  end

  get '/api/configuration/performance' do
    content_type :json
    
    token = extract_token_from_request
    
    begin
      # Authenticate user (optional for performance configuration)
      if token
        auth_data = AuthService.validate_jwt(token)
        current_user = auth_data[:user]
      end
      
      status 200
      ConfigurationService.get_performance_configuration.to_json
      
    rescue AuthenticationError => e
      # Return basic performance config for unauthenticated requests
      basic_config = {
        cache_enabled: ConfigurationService.get('cache.enabled'),
        websocket_ping_interval: ConfigurationService.get('websocket.ping_interval')
      }
      
      status 200
      basic_config.to_json
    rescue => e
      LoggingService.log_error(:api, "Error getting performance configuration", {}, e)
      status 500
      { error: 'Failed to get performance configuration' }.to_json
    end
  end

  post '/api/configuration/reload' do
    content_type :json
    
    token = extract_token_from_request
    
    begin
      # Authenticate user (required for configuration reload)
      auth_data = AuthService.validate_jwt(token)
      current_user = auth_data[:user]
      
      # Reload configuration
      ConfigurationService.reload_configuration
      
      LoggingService.log_info(:configuration, "Configuration reloaded by user", {
        user_id: current_user.id,
        username: current_user.username
      })
      
      status 200
      {
        success: true,
        message: 'Configuration reloaded successfully',
        timestamp: Time.now.iso8601
      }.to_json
      
    rescue AuthenticationError => e
      status 401
      { error: 'Authentication required for configuration reload' }.to_json
    rescue => e
      LoggingService.log_error(:api, "Error reloading configuration", {}, e)
      status 500
      { error: 'Failed to reload configuration' }.to_json
    end
  end

  put '/api/configuration/setting' do
    content_type :json
    
    begin
      begin
        params_hash = JSON.parse(request.body.read)
      rescue JSON::ParserError
        params_hash = params
      end
    
    token = extract_token_from_request
    
    begin
      # Authenticate user (required for configuration updates)
      auth_data = AuthService.validate_jwt(token)
      current_user = auth_data[:user]
      
      key_path = params_hash['key']
      value = params_hash['value']
      
      unless key_path && !key_path.empty?
        status 400
        return { error: 'Configuration key is required' }.to_json
      end
      
      # Update runtime setting
      result = ConfigurationService.update_runtime_setting(key_path, value)
      
      LoggingService.log_info(:configuration, "Runtime setting updated", {
        user_id: current_user.id,
        username: current_user.username,
        key: key_path,
        old_value: result[:old_value],
        new_value: result[:new_value]
      })
      
      status 200
      result.to_json
      
    rescue AuthenticationError => e
      status 401
      { error: 'Authentication required for configuration updates' }.to_json
    rescue ArgumentError => e
      status 400
      { error: e.message }.to_json
    rescue => e
      LoggingService.log_error(:api, "Error updating configuration setting", {
        key: params_hash['key'],
        value: params_hash['value']
      }, e)
      status 500
      { error: 'Failed to update configuration setting' }.to_json
    end
  end
    content_type :json
    
    token = extract_token_from_request
    
    begin
      # Authenticate user (optional for basic stats)
      if token
        auth_data = AuthService.validate_jwt(token)
        current_user = auth_data[:user]
        
        # Return detailed performance report for authenticated users
        status 200
        PerformanceMonitor.generate_performance_report.to_json
      else
        # Return basic performance stats for unauthenticated requests
        basic_stats = PerformanceMonitor.get_performance_statistics
        status 200
        {
          health_status: basic_stats[:health_status],
          uptime_hours: basic_stats[:uptime_hours],
          total_operations: basic_stats[:total_operations],
          operations_per_hour: basic_stats[:operations_per_hour],
          current_memory_mb: basic_stats[:current_memory_mb],
          current_connections: basic_stats[:current_connections]
        }.to_json
      end
      
    rescue AuthenticationError => e
      # Return basic stats if authentication fails
      basic_stats = PerformanceMonitor.get_performance_statistics
      status 200
      {
        health_status: basic_stats[:health_status],
        uptime_hours: basic_stats[:uptime_hours],
        operations_per_hour: basic_stats[:operations_per_hour]
      }.to_json
    rescue => e
      LoggingService.log_error(:api, "Error getting performance stats", {}, e)
      status 500
      { error: 'Failed to get performance statistics' }.to_json
    end
  end

  # Performance monitoring endpoints
  get '/api/performance/dashboard' do
    content_type :json
    
    token = extract_token_from_request
    result = PerformanceController.dashboard(token)
    status result[:status]
    result[:body].to_json
  end

  get '/api/performance/metrics' do
    content_type :json
    
    token = extract_token_from_request
    result = PerformanceController.metrics(token)
    status result[:status]
    result[:body].to_json
  end

  post '/api/performance/optimize' do
    content_type :json
    
    begin
      params_hash = JSON.parse(request.body.read)
    rescue JSON::ParserError
      params_hash = params
    end
    
    token = extract_token_from_request
    result = PerformanceController.optimize(params_hash, token)
    status result[:status]
    result[:body].to_json
  end

  get '/api/performance/health' do
    content_type :json
    
    token = extract_token_from_request
    result = PerformanceController.health_check(token)
    status result[:status]
    result[:body].to_json
  end

  get '/api/performance/benchmarks' do
    content_type :json
    
    token = extract_token_from_request
    result = PerformanceController.benchmarks(token)
    status result[:status]
    result[:body].to_json
  end

  post '/api/performance/cache/clear' do
    content_type :json
    
    begin
      params_hash = JSON.parse(request.body.read)
    rescue JSON::ParserError
      params_hash = params
    end
    
    token = extract_token_from_request
    result = PerformanceController.clear_cache(params_hash, token)
    status result[:status]
    result[:body].to_json
  end

  # Error statistics endpoint
  get '/api/monitoring/errors' do
    content_type :json
    
    token = extract_token_from_request
    
    begin
      # Authenticate user (required for error statistics)
      auth_data = AuthService.validate_jwt(token)
      current_user = auth_data[:user]
      
      status 200
      ErrorHandler.get_error_statistics.to_json
      
    rescue AuthenticationError => e
      status 401
      { error: 'Authentication required for error statistics' }.to_json
    rescue => e
      LoggingService.log_error(:api, "Error getting error statistics", {}, e)
      status 500
      { error: 'Failed to get error statistics' }.to_json
    end
  end

  # Logging statistics endpoint
  get '/api/monitoring/logging' do
    content_type :json
    
    token = extract_token_from_request
    
    begin
      # Authenticate user (required for logging statistics)
      auth_data = AuthService.validate_jwt(token)
      current_user = auth_data[:user]
      
      status 200
      LoggingService.get_statistics.to_json
      
    rescue AuthenticationError => e
      status 401
      { error: 'Authentication required for logging statistics' }.to_json
    rescue => e
      LoggingService.log_error(:api, "Error getting logging statistics", {}, e)
      status 500
      { error: 'Failed to get logging statistics' }.to_json
    end
  end

  # Authentication endpoints
  post '/api/auth/register' do
    content_type :json
    
    begin
      params_hash = JSON.parse(request.body.read)
    rescue JSON::ParserError
      params_hash = params
    end
    
    result = AuthController.register(params_hash)
    status result[:status]
    result[:body].to_json
  end

  post '/api/auth/login' do
    content_type :json
    
    begin
      params_hash = JSON.parse(request.body.read)
    rescue JSON::ParserError
      params_hash = params
    end
    
    result = AuthController.login(params_hash)
    status result[:status]
    result[:body].to_json
  end

  get '/api/auth/me' do
    content_type :json
    
    token = extract_token_from_request
    result = AuthController.me(token)
    status result[:status]
    result[:body].to_json
  end

  post '/api/auth/refresh' do
    content_type :json
    
    token = extract_token_from_request
    result = AuthController.refresh(token)
    status result[:status]
    result[:body].to_json
  end

  post '/api/auth/logout' do
    content_type :json
    
    token = extract_token_from_request
    result = AuthController.logout(token)
    status result[:status]
    result[:body].to_json
  end

  # Room management endpoints
  get '/api/rooms' do
    content_type :json
    
    token = extract_token_from_request
    result = RoomController.index(token)
    status result[:status]
    result[:body].to_json
  end

  post '/api/rooms' do
    content_type :json
    
    begin
      params_hash = JSON.parse(request.body.read)
    rescue JSON::ParserError
      params_hash = params
    end
    
    token = extract_token_from_request
    result = RoomController.create(params_hash, token)
    status result[:status]
    result[:body].to_json
  end

  get '/api/rooms/:id' do
    content_type :json
    
    token = extract_token_from_request
    result = RoomController.show(params[:id], token)
    status result[:status]
    result[:body].to_json
  end

  post '/api/rooms/:id/join' do
    content_type :json
    
    token = extract_token_from_request
    result = RoomController.join(params[:id], token)
    status result[:status]
    result[:body].to_json
  end

  delete '/api/rooms/:id/leave' do
    content_type :json
    
    token = extract_token_from_request
    result = RoomController.leave(params[:id], token)
    status result[:status]
    result[:body].to_json
  end

  # Track management endpoints
  get '/api/rooms/:id/tracks' do
    content_type :json
    
    token = extract_token_from_request
    result = TrackController.index(params[:id], token)
    status result[:status]
    result[:body].to_json
  end

  post '/api/rooms/:id/tracks' do
    content_type :json
    
    # Handle multipart form data for file upload
    file_data = {}
    if params[:audio_file] && params[:audio_file].is_a?(Hash)
      file_data[:audio_file] = params[:audio_file]
    end
    
    token = extract_token_from_request
    result = TrackController.store(params[:id], file_data, token)
    status result[:status]
    result[:body].to_json
  end

  # Track voting endpoints
  post '/api/tracks/:id/vote' do
    content_type :json
    
    token = extract_token_from_request
    result = TrackController.vote(params[:id], token)
    status result[:status]
    result[:body].to_json
  end

  delete '/api/tracks/:id/vote' do
    content_type :json
    
    token = extract_token_from_request
    result = TrackController.unvote(params[:id], token)
    status result[:status]
    result[:body].to_json
  end

  # Playback control endpoints
  post '/api/rooms/:id/playback/start' do
    content_type :json
    
    begin
      params_hash = JSON.parse(request.body.read)
    rescue JSON::ParserError
      params_hash = params
    end
    
    track_id = params_hash['track_id']
    token = extract_token_from_request
    result = PlaybackController.start_track(params[:id], track_id, token)
    status result[:status]
    result[:body].to_json
  end

  post '/api/rooms/:id/playback/pause' do
    content_type :json
    
    token = extract_token_from_request
    result = PlaybackController.pause_track(params[:id], token)
    status result[:status]
    result[:body].to_json
  end

  post '/api/rooms/:id/playback/resume' do
    content_type :json
    
    token = extract_token_from_request
    result = PlaybackController.resume_track(params[:id], token)
    status result[:status]
    result[:body].to_json
  end

  post '/api/rooms/:id/playback/skip' do
    content_type :json
    
    token = extract_token_from_request
    result = PlaybackController.skip_track(params[:id], token)
    status result[:status]
    result[:body].to_json
  end

  post '/api/rooms/:id/playback/stop' do
    content_type :json
    
    token = extract_token_from_request
    result = PlaybackController.stop_playback(params[:id], token)
    status result[:status]
    result[:body].to_json
  end

  get '/api/rooms/:id/playback/status' do
    content_type :json
    
    token = extract_token_from_request
    result = PlaybackController.get_playback_status(params[:id], token)
    status result[:status]
    result[:body].to_json
  end

  post '/api/rooms/:id/playback/seek' do
    content_type :json
    
    begin
      params_hash = JSON.parse(request.body.read)
    rescue JSON::ParserError
      params_hash = params
    end
    
    position = params_hash['position']
    token = extract_token_from_request
    result = PlaybackController.seek_to_position(params[:id], position, token)
    status result[:status]
    result[:body].to_json
  end

  # Track streaming endpoint with enhanced caching and range support
  get '/api/tracks/:id/stream' do
    token = extract_token_from_request
    range_header = request.env['HTTP_RANGE']
    if_none_match = request.env['HTTP_IF_NONE_MATCH']
    if_modified_since = request.env['HTTP_IF_MODIFIED_SINCE']
    
    result = TrackController.stream(params[:id], token, range_header)
    
    if result[:status] == 200
      # Handle file streaming with enhanced headers
      file_info = result[:file_info]
      track = result[:track]
      
      # Check for conditional requests (304 Not Modified)
      if file_info[:etag] && file_info[:last_modified]
        if FileService.not_modified?(if_none_match, if_modified_since, file_info[:etag], file_info[:last_modified])
          status 304
          return ''
        end
      end
      
      # Set headers from file service
      file_info[:headers].each { |key, value| response.headers[key] = value }
      
      # Handle range requests
      if file_info[:range_request]
        status file_info[:status] || 206
        
        # Stream partial content
        stream do |out|
          FileService.stream_file_content(
            file_info[:file_path], 
            file_info[:start_byte], 
            file_info[:content_length]
          ) do |chunk|
            out << chunk
          end
        end
      else
        # Stream full file
        status 200
        
        stream do |out|
          FileService.stream_file_content(file_info[:file_path]) do |chunk|
            out << chunk
          end
        end
      end
    else
      content_type :json
      status result[:status]
      result[:body].to_json
    end
  end
  
  # File metadata endpoint
  get '/api/tracks/:id/metadata' do
    content_type :json
    
    token = extract_token_from_request
    
    begin
      # Authenticate user
      auth_data = AuthService.validate_jwt(token)
      current_user = auth_data[:user]
      
      # Find track
      track = Track[params[:id]]
      unless track
        status 404
        return { error: 'Track not found' }.to_json
      end
      
      # Check if user has access to this track's room
      room = track.room
      unless room && room.has_participant?(current_user)
        status 403
        return { error: 'Access denied' }.to_json
      end
      
      # Get file metadata
      metadata = FileService.get_file_metadata(track.filename)
      
      if metadata[:success]
        status 200
        metadata.except(:success).to_json
      else
        status 404
        { error: metadata[:error] }.to_json
      end
      
    rescue AuthenticationError => e
      status 401
      { error: 'Authentication failed', message: e.message }.to_json
    rescue => e
      $logger&.error "Error getting track metadata: #{e.message}"
      status 500
      { error: 'Internal server error' }.to_json
    end
  end

  # Room manager status endpoint
  get '/api/rooms/manager/status' do
    content_type :json
    
    token = extract_token_from_request
    
    begin
      # Authenticate user (optional for basic status)
      if token
        auth_data = AuthService.validate_jwt(token)
        current_user = auth_data[:user]
        
        # Get detailed status for authenticated user
        status 200
        {
          room_manager: RoomManager.get_global_statistics,
          websocket_stats: WebSocketConnection.connection_stats,
          server_time: Time.now.to_f
        }.to_json
      else
        # Basic status for unauthenticated requests
        status 200
        {
          room_manager: RoomManager.get_global_statistics.except(:websocket_connections),
          server_time: Time.now.to_f
        }.to_json
      end
      
    rescue AuthenticationError => e
      # Return basic status if authentication fails
      status 200
      {
        room_manager: RoomManager.get_global_statistics.except(:websocket_connections),
        server_time: Time.now.to_f
      }.to_json
    rescue => e
      $logger&.error "Error getting room manager status: #{e.message}"
      status 500
      { error: 'Failed to get room manager status' }.to_json
    end
  end

  # Individual room statistics endpoint
  get '/api/rooms/:id/statistics' do
    content_type :json
    
    token = extract_token_from_request
    
    begin
      # Authenticate user
      auth_data = AuthService.validate_jwt(token)
      current_user = auth_data[:user]
      
      # Get room statistics
      room_stats = RoomManager.get_room_statistics(params[:id])
      
      if room_stats
        status 200
        room_stats.to_json
      else
        status 404
        { error: 'Room not found' }.to_json
      end
      
    rescue AuthenticationError => e
      status 401
      { error: 'Authentication failed', message: e.message }.to_json
    rescue => e
      $logger&.error "Error getting room statistics: #{e.message}"
      status 500
      { error: 'Failed to get room statistics' }.to_json
    end
  end

  # WebSocket status endpoint
  get '/api/websocket/status' do
    content_type :json
    
    token = extract_token_from_request
    
    begin
      # Authenticate user (optional for status endpoint)
      if token
        auth_data = AuthService.validate_jwt(token)
        current_user = auth_data[:user]
        
        # Get detailed status for authenticated user
        user_connection = WebSocketConnection.get_user_connection(current_user.id)
        
        status 200
        {
          websocket_enabled: true,
          user_connected: !user_connection.nil?,
          connection_stats: WebSocketConnection.connection_stats,
          user_room: user_connection&.room_id,
          server_time: Time.now.to_f
        }.to_json
      else
        # Basic status for unauthenticated requests
        status 200
        {
          websocket_enabled: true,
          connection_stats: WebSocketConnection.connection_stats.except(:authenticated_users),
          server_time: Time.now.to_f
        }.to_json
      end
      
    rescue AuthenticationError => e
      # Return basic status if authentication fails
      status 200
      {
        websocket_enabled: true,
        connection_stats: WebSocketConnection.connection_stats.except(:authenticated_users),
        server_time: Time.now.to_f
      }.to_json
    rescue => e
      $logger&.error "Error getting WebSocket status: #{e.message}"
      status 500
      { error: 'Failed to get WebSocket status' }.to_json
    end
  end

  # Broadcasting authentication endpoint (for WebSocket compatibility)
  post '/api/broadcasting/auth' do
    content_type :json
    
    begin
      # Extract token from Authorization header or request body
      token = extract_token_from_request
      
      unless token
        status 401
        return { 
          success: false,
          message: 'Authentication token required',
          error: 'No token provided'
        }.to_json
      end
      
      # Validate JWT token
      auth_data = AuthService.validate_jwt(token)
      user = auth_data[:user]
      
      # Generate WebSocket authentication response
      auth_response = {
        success: true,
        user: user.to_hash,
        websocket_url: "#{request.scheme == 'https' ? 'wss' : 'ws'}://#{request.host_with_port}/ws",
        server_time: Time.now.to_f,
        message: 'WebSocket authentication successful'
      }
      
      $logger.info "Broadcasting auth successful for user: #{user.username}"
      
      status 200
      auth_response.to_json
      
    rescue AuthenticationError => e
      $logger.warn "Broadcasting auth failed: #{e.message}"
      status 401
      {
        success: false,
        message: 'Authentication failed',
        error: e.message
      }.to_json
    rescue => e
      $logger.error "Broadcasting auth error: #{e.message}"
      status 500
      {
        success: false,
        message: 'Internal server error',
        error: SpotikConfig::Settings.app_debug? ? e.message : 'Authentication service unavailable'
      }.to_json
    end
  end

  # WebSocket upgrade endpoint
  get '/ws' do
    # Check if this is a WebSocket upgrade request
    if env['rack.upgrade?'] == :websocket
      $logger.info "WebSocket upgrade requested from #{request.ip}"
      
      # Create WebSocket connection with authentication
      connection = WebSocketConnection.new(env)
      
      env['rack.upgrade'] = connection
      [0, {}, []]
    else
      status 400
      content_type :json
      { error: 'WebSocket upgrade required' }.to_json
    end
  end

  # Catch-all for undefined routes
  not_found do
    content_type :json
    status 404
    { error: 'Endpoint not found', path: request.path_info }.to_json
  end

  # Error handler
  error do |e|
    # Use the new ErrorHandler instead of basic error handling
    error_response = ErrorHandler.handle_api_error(e, {
      method: request.request_method,
      path: request.path_info,
      ip_address: request.ip,
      user_agent: request.user_agent
    })
    
    content_type :json
    status error_response[:status]
    error_response[:body].to_json
  end

  private

  def extract_token_from_request
    # Check Authorization header first (Bearer token)
    auth_header = request.env['HTTP_AUTHORIZATION']
    if auth_header && auth_header.start_with?('Bearer ')
      return auth_header[7..-1] # Remove 'Bearer ' prefix
    end
    
    # Check for token in query parameters (fallback)
    params['token']
  end

  def get_uptime
    return 0 unless $server_start_time
    
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
end

# Server startup
def start_server
  # Initialize configuration system first
  begin
    LoggingService.log_system_event('configuration_init', "Initializing configuration system")
    ConfigurationService.initialize_configuration
    LoggingService.log_system_event('configuration_loaded', "Configuration system initialized successfully")
  rescue SpotikConfig::ConfigurationError => e
    puts "FATAL: Configuration validation failed:"
    e.validation_errors.each { |error| puts "  ERROR: #{error}" }
    e.validation_warnings.each { |warning| puts "  WARNING: #{warning}" }
    exit 1
  rescue => e
    puts "FATAL: Configuration system initialization failed: #{e.message}"
    exit 1
  end
  
  LoggingService.log_system_event('server_startup', "Starting #{SpotikConfig::Settings.app_name} Ruby Backend", {
    environment: SpotikConfig::Settings.app_env,
    ruby_version: RUBY_VERSION,
    performance_monitoring: SpotikConfig::Settings.performance_monitoring_enabled?,
    configuration_files: ConfigurationService.configuration_health[:config_files_loaded]&.length || 0,
    environment_variables: ConfigurationService.configuration_health[:environment_variables_loaded]&.length || 0
  })
  
  # Initialize performance optimizations
  begin
    LoggingService.log_system_event('performance_init', "Initializing performance optimizations")
    
    # Initialize database optimizations
    DatabaseOptimizer.initialize_optimizations
    
    # Initialize WebSocket optimizations
    WebSocketOptimizer.initialize_optimizations
    
    # Initialize caching service
    CachingService.initialize_caching
    
    # Warm up caches if in production
    if SpotikConfig::Settings.production?
      CachingService.warm_up_cache
    end
    
    LoggingService.log_system_event('performance_ready', "Performance optimizations initialized successfully")
    
  rescue => e
    LoggingService.log_error(:system, "Failed to initialize performance optimizations", {}, e)
    # Continue startup even if optimizations fail
  end
  
  # Test database connection and validate schema (skip in test environment)
  unless SpotikConfig::Settings.test?
    begin
      # Establish database connection
      db_connection = SpotikConfig::Database.connection
      LoggingService.log_info(:database, "Database connection established")
      
      # Validate schema compatibility with Laravel database
      LoggingService.log_info(:system, "Validating database schema compatibility...")
      schema_validation = SpotikConfig::Database.validate_schema_compatibility
      
      case schema_validation[:status]
      when 'valid'
        LoggingService.log_info(:database, "✓ Database schema validation passed")
      when 'warning'
        LoggingService.log_warn(:database, "⚠ Database schema validation completed with warnings")
        schema_validation[:warnings].each { |warning| LoggingService.log_warn(:database, "  - #{warning}") }
        LoggingService.log_warn(:system, "Server will start but some features may not work optimally")
      when 'invalid'
        LoggingService.log_error(:database, "✗ Database schema validation failed")
        schema_validation[:errors].each { |error| LoggingService.log_error(:database, "  - #{error}") }
        LoggingService.log_fatal(:system, "Server cannot start with invalid schema")
        exit 1
      when 'error'
        LoggingService.log_error(:database, "✗ Database schema validation error")
        schema_validation[:errors].each { |error| LoggingService.log_error(:database, "  - #{error}") }
        LoggingService.log_fatal(:system, "Server cannot start due to schema validation error")
        exit 1
      end
      
      # Log schema validation summary
      tables_count = schema_validation[:tables].keys.length
      errors_count = schema_validation[:errors].length
      warnings_count = schema_validation[:warnings].length
      
      LoggingService.log_info(:database, "Schema validation summary", {
        tables_validated: tables_count,
        errors: errors_count,
        warnings: warnings_count
      })
      
    rescue SpotikConfig::DatabaseConnectionError => e
      LoggingService.log_fatal(:database, "Database connection failed", {
        error_message: e.message,
        original_error: e.original_error&.message
      }, e)
      exit 1
    rescue => e
      LoggingService.log_fatal(:database, "Database initialization failed", {}, e)
      exit 1
    end
  else
    LoggingService.log_info(:system, "Skipping database validation in test environment")
  end
  
  # Configure Iodine
  Iodine.threads = SpotikConfig::Settings.server_threads
  Iodine.workers = SpotikConfig::Settings.server_workers
  
  # Setup periodic cleanup tasks
  Iodine.run_every(300_000) do # Run every 5 minutes (300,000 milliseconds)
    ErrorHandler.with_error_recovery('periodic_cleanup') do
      WebSocketConnection.cleanup_stale_connections
      RoomManager.cleanup_stale_data
      LoggingService.rotate_logs if SpotikConfig::Settings.production?
    end
  end
  
  # Setup periodic performance monitoring
  if SpotikConfig::Settings.performance_monitoring_enabled?
    Iodine.run_every(60_000) do # Run every minute
      ErrorHandler.with_error_recovery('performance_monitoring') do
        # Performance monitoring is handled by PerformanceMonitor background thread
        # This just ensures the monitoring is still active
        LoggingService.log_debug(:performance, "Periodic performance check", {
          health_status: PerformanceMonitor.get_performance_health,
          memory_mb: PerformanceMonitor.send(:get_memory_usage),
          connections: PerformanceMonitor.send(:get_connection_count)
        })
      end
    end
  end
  
  # Start the server
  LoggingService.log_system_event('server_starting', "Starting server", {
    host: SpotikConfig::Settings.server_host,
    port: SpotikConfig::Settings.server_port,
    threads: SpotikConfig::Settings.server_threads,
    workers: SpotikConfig::Settings.server_workers
  })
  
  Iodine.listen(
    service: :http,
    handler: SpotikServer,
    port: SpotikConfig::Settings.server_port,
    address: SpotikConfig::Settings.server_host,
    public: './public'  # Static file serving
  )
  
  # Graceful shutdown handling
  trap('INT') do
    LoggingService.log_system_event('server_shutdown', "Shutting down server (SIGINT)")
    cleanup_and_shutdown
  end
  
  trap('TERM') do
    LoggingService.log_system_event('server_shutdown', "Terminating server (SIGTERM)")
    cleanup_and_shutdown
  end
  
  LoggingService.log_system_event('server_started', "Server started successfully", {
    health_check_url: "http://#{SpotikConfig::Settings.server_host}:#{SpotikConfig::Settings.server_port}/health",
    database_health_url: "http://#{SpotikConfig::Settings.server_host}:#{SpotikConfig::Settings.server_port}/health/database",
    performance_monitoring: SpotikConfig::Settings.performance_monitoring_enabled?
  })
  
  Iodine.start
end

# Cleanup and shutdown helper
def cleanup_and_shutdown
  begin
    # Close database connections
    SpotikConfig::Database.close_connection if defined?(SpotikConfig::Database)
    
    # Log final statistics
    if defined?(ErrorHandler)
      error_stats = ErrorHandler.get_error_statistics
      LoggingService.log_info(:system, "Final error statistics", error_stats)
    end
    
    if defined?(PerformanceMonitor) && SpotikConfig::Settings.performance_monitoring_enabled?
      perf_stats = PerformanceMonitor.get_performance_statistics
      LoggingService.log_info(:system, "Final performance statistics", perf_stats)
    end
    
    LoggingService.log_system_event('server_stopped', "Server shutdown completed")
    
  rescue => e
    # Even if cleanup fails, we should still stop
    puts "Error during shutdown: #{e.message}"
  ensure
    Iodine.stop
  end
end

# Start the server if this file is run directly
if __FILE__ == $0
  start_server
end