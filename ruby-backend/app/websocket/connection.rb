# WebSocket connection handler with JWT authentication
# Implements native WebSocket support for Spotik Ruby Backend

require 'json'
require 'uri'
require_relative '../controllers/playback_controller'
require_relative '../services/event_broadcaster'

class WebSocketConnection
  # Class-level connection tracking
  @@connections = {}
  @@room_connections = {}
  
  attr_reader :user, :user_id, :client, :room_id, :authenticated
  
  def initialize(env)
    @env = env
    @client = nil
    @user = nil
    @user_id = nil
    @room_id = nil
    @authenticated = false
    @connection_id = SecureRandom.hex(16)
    @connected_at = Time.now
    
    # Extract token from query parameters or headers
    @token = extract_token_from_env(env)
    
    $logger&.info "WebSocket connection initialized: #{@connection_id} from #{client_ip}"
  end
  
  # Called when WebSocket connection is established
  def on_open(client)
    @client = client
    
    LoggingService.log_websocket_event('connection_opened', nil, nil, {
      connection_id: @connection_id,
      ip_address: client_ip
    })
    
    # Authenticate the connection
    ErrorHandler.with_error_recovery('websocket_authentication', {
      connection_id: @connection_id,
      ip_address: client_ip
    }) do
      if authenticate_connection
        @authenticated = true
        @@connections[@user_id] = self
        
        # Register connection with optimizer
        WebSocketOptimizer.register_connection(@connection_id, @user_id, @room_id)
        
        LoggingService.log_auth_event('websocket_authentication', @user.username, true, {
          connection_id: @connection_id,
          ip_address: client_ip,
          user_id: @user_id
        })
        
        # Send welcome message
        send_message({
          type: 'connection_established',
          data: {
            connection_id: @connection_id,
            user: @user.to_hash,
            server_time: Time.now.to_f,
            message: 'WebSocket connection authenticated successfully'
          }
        })
        
        # Send current server status
        send_server_status
        
      else
        LoggingService.log_auth_event('websocket_authentication', @token ? 'token_provided' : 'no_token', false, {
          connection_id: @connection_id,
          ip_address: client_ip
        })
        
        # Send authentication error and close connection
        send_message({
          type: 'authentication_error',
          data: {
            error: 'Authentication failed',
            message: 'Invalid or missing JWT token'
          }
        })
        
        # Close connection after a brief delay to ensure message is sent
        client.close
      end
    end
  end
  
  # Called when a message is received from the client
  def on_message(client, data)
    unless @authenticated
      LoggingService.log_security_event('unauthenticated_websocket_message', 'Received message from unauthenticated connection', {
        connection_id: @connection_id,
        ip_address: client_ip,
        data_length: data.length
      })
      return
    end
    
    # Update connection activity for optimization
    WebSocketOptimizer.update_connection_activity(@connection_id, :message_received, data.bytesize)
    
    PerformanceMonitor.measure_operation(:websocket_message, 'message_processing', {
      user_id: @user_id,
      connection_id: @connection_id
    }) do
      begin
        message = JSON.parse(data)
        LoggingService.log_websocket_event('message_received', @user_id, @room_id, {
          message_type: message['type'],
          connection_id: @connection_id
        })
        
        handle_message(message)
        
      rescue JSON::ParserError => e
        error_response = ErrorHandler.handle_websocket_error(e, {
          user_id: @user_id,
          connection_id: @connection_id,
          context_type: 'websocket',
          data_received: data[0..100] # First 100 chars for debugging
        })
        
        send_message(error_response)
        
      rescue => e
        error_response = ErrorHandler.handle_websocket_error(e, {
          user_id: @user_id,
          connection_id: @connection_id,
          room_id: @room_id,
          context_type: 'websocket'
        })
        
        send_message(error_response)
      end
    end
  end
  
  # Called when WebSocket connection is closed
  def on_close(client)
    LoggingService.log_websocket_event('connection_closed', @user_id, @room_id, {
      connection_id: @connection_id,
      authenticated: @authenticated,
      duration_seconds: @connected_at ? (Time.now - @connected_at).round(2) : 0
    })
    
    if @authenticated && @user_id
      # Unregister connection from optimizer
      WebSocketOptimizer.unregister_connection(@connection_id)
      
      # Remove from global connections
      @@connections.delete(@user_id)
      
      # Handle room cleanup via RoomManager - clean up from ALL rooms, not just current WebSocket room
      ErrorHandler.with_error_recovery('websocket_cleanup', {
        user_id: @user_id,
        connection_id: @connection_id
      }) do
        RoomManager.handle_user_disconnect(@user_id)
      end
      
      # Leave current room if connected
      leave_current_room if @room_id
      
      LoggingService.log_websocket_event('connection_cleanup_completed', @user_id, nil, {
        connection_id: @connection_id,
        username: @user&.username
      })
    end
  end
  
  # Called when an error occurs
  def on_error(client, error)
    error_context = {
      connection_id: @connection_id,
      user_id: @user_id,
      room_id: @room_id,
      authenticated: @authenticated,
      ip_address: client_ip
    }
    
    error_response = ErrorHandler.handle_websocket_error(error, error_context)
    
    # Try to send error message to client if connection is still active
    if @client && @authenticated
      begin
        send_message(error_response)
      rescue
        # If we can't send the error message, just log it
        LoggingService.log_error(:websocket, "Failed to send error message to client", error_context, error)
      end
    end
  end
  
  # Class methods for connection management
  class << self
    # Get connection for a specific user
    def get_user_connection(user_id)
      @@connections[user_id]
    end
    
    # Get all connections in a room
    def get_room_connections(room_id)
      @@room_connections[room_id] || []
    end
    
    # Broadcast message to all connections in a room
    def broadcast_to_room(room_id, message)
      connections = get_room_connections(room_id)
      
      if connections.any?
        $logger&.debug "Broadcasting to room #{room_id}: #{message[:type]} (#{connections.length} connections)"
        
        connections.each do |connection|
          begin
            connection.send_message(message)
          rescue => e
            $logger&.error "Failed to broadcast to user #{connection.user_id}: #{e.message}"
          end
        end
      else
        $logger&.debug "No connections found for room #{room_id}"
      end
    end
    
    # Broadcast message to a specific user
    def send_to_user(user_id, message)
      connection = get_user_connection(user_id)
      
      if connection
        connection.send_message(message)
        true
      else
        $logger&.debug "No WebSocket connection found for user #{user_id}"
        false
      end
    end
    
    # Get connection statistics
    def connection_stats
      {
        total_connections: @@connections.length,
        room_connections: @@room_connections.transform_values(&:length),
        authenticated_users: @@connections.keys
      }
    end
    
    # Clean up stale connections (called periodically)
    def cleanup_stale_connections
      stale_connections = []
      
      @@connections.each do |user_id, connection|
        if connection.stale?
          stale_connections << user_id
        end
      end
      
      stale_connections.each do |user_id|
        connection = @@connections[user_id]
        connection&.cleanup
        @@connections.delete(user_id)
      end
      
      $logger&.info "Cleaned up #{stale_connections.length} stale WebSocket connections" if stale_connections.any?
    end
  end
  
  # Send message to this connection
  def send_message(message)
    return unless @client && @authenticated
    
    begin
      # Add timestamp to all messages
      message[:timestamp] = Time.now.to_f unless message[:timestamp]
      
      message_json = message.to_json
      @client.write(message_json)
      
      # Update connection activity for optimization
      WebSocketOptimizer.update_connection_activity(@connection_id, :message_sent, message_json.bytesize)
      
    rescue => e
      $logger&.error "Failed to send WebSocket message to #{@user&.username}: #{e.message}"
    end
  end
  
  # Join a room
  def join_room(room_id)
    return false unless @authenticated
    
    begin
      room = Room[room_id]
      return false unless room
      
      # Check if user has access to this room (must be a participant)
      unless room.has_participant?(@user)
        send_error('access_denied', 'You are not a participant of this room')
        return false
      end
      
      # Leave current room if connected to one
      leave_current_room if @room_id
      
      # Join new room
      @room_id = room_id
      @@room_connections[room_id] ||= []
      @@room_connections[room_id] << self
      
      $logger&.info "User #{@user.username} joined WebSocket room: #{room_id}"
      
      # Get comprehensive room state from RoomManager
      room_state = RoomManager.get_room_state(room_id, @user)
      
      # Send room state to the user
      send_message({
        type: 'room_joined',
        data: {
          room: room_state,
          message: "Joined room: #{room.name}",
          websocket_connected: true
        }
      })
      
      # Notify other room participants via EventBroadcaster
      EventBroadcaster.broadcast_user_activity(room_id, :websocket_connected, @user)
      
      true
      
    rescue => e
      $logger&.error "Error joining WebSocket room #{room_id} for user #{@user.username}: #{e.message}"
      send_error('room_join_error', 'Failed to join room')
      false
    end
  end
  
  # Leave current room
  def leave_current_room
    return unless @room_id
    
    room_id = @room_id
    @room_id = nil
    
    # Remove from room connections
    if @@room_connections[room_id]
      @@room_connections[room_id].delete(self)
      @@room_connections.delete(room_id) if @@room_connections[room_id].empty?
    end
    
    $logger&.info "User #{@user&.username} left WebSocket room: #{room_id}"
    
    # Notify other room participants via EventBroadcaster
    if @authenticated && @user
      EventBroadcaster.broadcast_user_activity(room_id, :websocket_disconnected, @user)
    end
  end
  
  # Check if connection is stale
  def stale?
    # Consider connection stale if it's been inactive for more than 5 minutes
    Time.now - @connected_at > 300
  end
  
  # Cleanup connection resources
  def cleanup
    leave_current_room if @room_id
    @client = nil
    @authenticated = false
  end
  
  private
  
  # Extract JWT token from environment (query params or headers)
  def extract_token_from_env(env)
    # Check query parameters first
    query_string = env['QUERY_STRING']
    if query_string && !query_string.empty?
      params = URI.decode_www_form(query_string).to_h
      return params['token'] if params['token']
    end
    
    # Check Authorization header
    auth_header = env['HTTP_AUTHORIZATION']
    if auth_header && auth_header.start_with?('Bearer ')
      return auth_header[7..-1] # Remove 'Bearer ' prefix
    end
    
    # Check Sec-WebSocket-Protocol header (some clients send token here)
    protocol_header = env['HTTP_SEC_WEBSOCKET_PROTOCOL']
    if protocol_header && protocol_header.include?('token.')
      # Extract token from protocol header (format: "token.JWT_TOKEN_HERE")
      parts = protocol_header.split('token.')
      return parts[1] if parts.length > 1
    end
    
    nil
  end
  
  # Authenticate the WebSocket connection using JWT
  def authenticate_connection
    return false unless @token
    
    begin
      auth_data = AuthService.validate_jwt(@token)
      @user = auth_data[:user]
      @user_id = @user.id
      
      $logger&.debug "WebSocket authentication successful for user: #{@user.username}"
      true
      
    rescue AuthenticationError => e
      $logger&.warn "WebSocket authentication failed: #{e.message}"
      false
    rescue => e
      $logger&.error "WebSocket authentication error: #{e.message}"
      false
    end
  end
  
  # Handle incoming WebSocket messages
  def handle_message(message)
    message_type = message['type']
    data = message['data'] || {}
    
    case message_type
    when 'ping'
      handle_ping(data)
    when 'join_room'
      handle_join_room(data)
    when 'leave_room'
      handle_leave_room(data)
    when 'get_room_state'
      handle_get_room_state(data)
    when 'playback_control'
      handle_playback_control(data)
    when 'vote_track'
      handle_vote_track(data)
    when 'get_track_queue'
      handle_get_track_queue(data)
    else
      $logger&.warn "Unknown WebSocket message type from #{@user.username}: #{message_type}"
      send_error('unknown_message_type', "Unknown message type: #{message_type}")
    end
  end
  
  # Handle ping message (for keepalive)
  def handle_ping(data)
    send_message({
      type: 'pong',
      data: {
        server_time: Time.now.to_f,
        client_time: data['client_time']
      }
    })
  end
  
  # Handle room join request
  def handle_join_room(data)
    room_id = data['room_id']
    
    unless room_id
      send_error('missing_room_id', 'Room ID is required')
      return
    end
    
    join_room(room_id)
  end
  
  # Handle room leave request
  def handle_leave_room(data)
    leave_current_room
    
    send_message({
      type: 'room_left',
      data: {
        message: 'Left room successfully'
      }
    })
  end
  
  # Handle room state request
  def handle_get_room_state(data)
    unless @room_id
      send_error('not_in_room', 'You are not connected to any room')
      return
    end
    
    begin
      # Get comprehensive room state from RoomManager
      room_state = RoomManager.get_room_state(@room_id, @user)
      
      if room_state
        send_message({
          type: 'room_state',
          data: {
            room: room_state,
            websocket_connected: true,
            connection_id: @connection_id
          }
        })
      else
        send_error('room_not_found', 'Room not found')
      end
      
    rescue => e
      $logger&.error "Error getting room state for #{@user.username}: #{e.message}"
      send_error('room_state_error', 'Failed to get room state')
    end
  end
  
  # Handle playback control (admin only)
  def handle_playback_control(data)
    unless @room_id
      send_error('not_in_room', 'You are not connected to any room')
      return
    end
    
    begin
      room = Room[@room_id]
      
      unless room && room.administered_by?(@user)
        send_error('access_denied', 'Only room administrators can control playback')
        return
      end
      
      action = data['action']
      token = AuthService.generate_jwt(@user_id)
      
      case action
      when 'play', 'start'
        track_id = data['track_id']
        if track_id
          result = PlaybackController.start_track(@room_id, track_id, token)
          if result[:status] == 200
            send_message({
              type: 'playback_control_success',
              data: {
                action: 'start',
                result: result[:body]
              }
            })
          else
            send_error('playback_control_failed', result[:body][:error] || 'Failed to start playback')
          end
        else
          send_error('missing_track_id', 'Track ID is required for play action')
        end
        
      when 'pause'
        result = PlaybackController.pause_track(@room_id, token)
        if result[:status] == 200
          send_message({
            type: 'playback_control_success',
            data: {
              action: 'pause',
              result: result[:body]
            }
          })
        else
          send_error('playback_control_failed', result[:body][:error] || 'Failed to pause playback')
        end
        
      when 'resume'
        result = PlaybackController.resume_track(@room_id, token)
        if result[:status] == 200
          send_message({
            type: 'playback_control_success',
            data: {
              action: 'resume',
              result: result[:body]
            }
          })
        else
          send_error('playback_control_failed', result[:body][:error] || 'Failed to resume playback')
        end
        
      when 'stop'
        result = PlaybackController.stop_playback(@room_id, token)
        if result[:status] == 200
          send_message({
            type: 'playback_control_success',
            data: {
              action: 'stop',
              result: result[:body]
            }
          })
        else
          send_error('playback_control_failed', result[:body][:error] || 'Failed to stop playback')
        end
        
      when 'skip'
        result = PlaybackController.skip_track(@room_id, token)
        if result[:status] == 200
          send_message({
            type: 'playback_control_success',
            data: {
              action: 'skip',
              result: result[:body]
            }
          })
        else
          send_error('playback_control_failed', result[:body][:error] || 'Failed to skip track')
        end
        
      when 'seek'
        position = data['position']
        if position
          result = PlaybackController.seek_to_position(@room_id, position, token)
          if result[:status] == 200
            send_message({
              type: 'playback_control_success',
              data: {
                action: 'seek',
                result: result[:body]
              }
            })
          else
            send_error('playback_control_failed', result[:body][:error] || 'Failed to seek playback')
          end
        else
          send_error('missing_position', 'Position is required for seek action')
        end
        
      else
        send_error('invalid_action', "Invalid playback action: #{action}")
      end
      
    rescue => e
      $logger&.error "Error handling playback control for #{@user.username}: #{e.message}"
      send_error('playback_control_error', 'Failed to control playback')
    end
  end
  
  # Handle track queue request
  def handle_get_track_queue(data)
    unless @room_id
      send_error('not_in_room', 'You are not connected to any room')
      return
    end
    
    begin
      # Use the track controller to get the queue with user-specific data
      token = AuthService.generate_jwt(@user_id)
      result = TrackController.index(@room_id, token)
      
      if result[:status] == 200
        send_message({
          type: 'track_queue',
          data: {
            room_id: @room_id,
            tracks: result[:body][:tracks],
            total_count: result[:body][:total_count],
            server_time: Time.now.to_f
          }
        })
      else
        send_error('queue_error', result[:body][:error] || 'Failed to get track queue')
      end
      
    rescue => e
      $logger&.error "Error getting track queue for #{@user.username}: #{e.message}"
      send_error('queue_error', 'Failed to get track queue')
    end
  end
  
  # Handle track voting
  def handle_vote_track(data)
    unless @room_id
      send_error('not_in_room', 'You are not connected to any room')
      return
    end
    
    track_id = data['track_id']
    vote_type = data['vote_type'] # 'up' or 'remove'
    
    unless track_id
      send_error('missing_track_id', 'Track ID is required')
      return
    end
    
    begin
      # Use the track controller methods to ensure consistency with HTTP API
      # and proper real-time broadcasting
      token = AuthService.generate_jwt(@user_id)
      
      case vote_type
      when 'up'
        result = TrackController.vote(track_id, token)
        
        if result[:status] == 200
          send_message({
            type: 'vote_success',
            data: {
              track_id: track_id,
              vote_type: 'added',
              vote_score: result[:body][:vote_score],
              user_has_voted: result[:body][:user_has_voted],
              message: result[:body][:message]
            }
          })
        else
          send_error('vote_failed', result[:body][:error] || 'Failed to add vote')
        end
        
      when 'remove'
        result = TrackController.unvote(track_id, token)
        
        if result[:status] == 200
          send_message({
            type: 'vote_success',
            data: {
              track_id: track_id,
              vote_type: 'removed',
              vote_score: result[:body][:vote_score],
              user_has_voted: result[:body][:user_has_voted],
              message: result[:body][:message]
            }
          })
        else
          send_error('vote_failed', result[:body][:error] || 'Failed to remove vote')
        end
        
      else
        send_error('invalid_vote_type', "Invalid vote type: #{vote_type}")
      end
      
    rescue => e
      $logger&.error "Error handling track vote for #{@user.username}: #{e.message}"
      send_error('vote_error', 'Failed to process vote')
    end
  end
  
  # Broadcast playback event to all room participants
  def broadcast_playback_event(event_type, room, track = nil)
    event_data = {
      type: event_type,
      data: {
        room_id: room.id,
        is_playing: room.is_playing,
        playback_started_at: room.playback_started_at&.to_f,
        playback_paused_at: room.playback_paused_at&.to_f,
        current_position: room.current_playback_position,
        server_time: Time.now.to_f
      }
    }
    
    if track
      event_data[:data][:track] = track.to_hash
    end
    
    WebSocketConnection.broadcast_to_room(room.id, event_data)
  end
  
  # Broadcast vote event to all room participants
  def broadcast_vote_event(event_type, track)
    # Reload track to get updated vote score
    track.reload
    
    WebSocketConnection.broadcast_to_room(@room_id, {
      type: event_type,
      data: {
        track: track.to_hash,
        room_id: @room_id,
        voter: @user.to_hash
      }
    })
  end
  
  # Send error message to client
  def send_error(error_code, message)
    send_message({
      type: 'error',
      data: {
        error_code: error_code,
        message: message
      }
    })
  end
  
  # Send current server status
  def send_server_status
    send_message({
      type: 'server_status',
      data: {
        server_time: Time.now.to_f,
        connection_stats: WebSocketConnection.connection_stats
      }
    })
  end
  
  # Get client IP address
  def client_ip
    @env['HTTP_X_FORWARDED_FOR'] || @env['HTTP_X_REAL_IP'] || @env['REMOTE_ADDR'] || 'unknown'
  end
end