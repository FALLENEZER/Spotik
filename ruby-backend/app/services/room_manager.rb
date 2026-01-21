# Room Manager Service - Centralized room management with WebSocket broadcasting
# Implements comprehensive room state management and real-time event broadcasting

require 'json'
require 'securerandom'
require_relative 'event_broadcaster'

class RoomManager
  # Class-level room state cache for performance
  @@room_state_cache = {}
  @@cache_ttl = 5 # seconds
  
  class << self
    # Create a new room with the user as administrator
    def create_room(user, room_data)
      begin
        # Validate room data
        unless room_data['name'] && !room_data['name'].strip.empty?
          raise ArgumentError, 'Room name is required'
        end
        
        if room_data['name'].length > 100
          raise ArgumentError, 'Room name cannot exceed 100 characters'
        end
        
        # Create room
        room = Room.create(
          id: SecureRandom.uuid,
          name: room_data['name'].strip,
          administrator_id: user.id,
          is_playing: false,
          created_at: Time.now,
          updated_at: Time.now
        )
        
        # Add creator as first participant
        room.add_participant(user)
        
        # Reload to get fresh data
        room.refresh
        
        $logger&.info "Room created: #{room.id} (#{room.name}) by user #{user.username}"
        
        # Broadcast room creation event to all connected users (optional)
        broadcast_global_event('room_created', {
          room: room.to_hash,
          creator: user.to_hash
        })
        
        room
        
      rescue => e
        $logger&.error "Failed to create room: #{e.message}"
        raise
      end
    end
    
    # Join a room with comprehensive state management
    def join_room(user, room_id)
      begin
        room = Room[room_id]
        return { success: false, error: 'Room not found' } unless room
        
        # Check if user is already a participant
        if room.has_participant?(user)
          return { success: false, error: 'Already a participant in this room' }
        end
        
        # Add user as participant
        participant = room.add_participant(user)
        
        # Reload room to get fresh data
        room.refresh
        
        # Clear room state cache
        clear_room_cache(room_id)
        
        $logger&.info "User #{user.username} joined room #{room.name} (#{room_id})"
        
        # Broadcast user joined event to all room participants
        EventBroadcaster.broadcast_user_activity(room_id, :joined, user)
        
        # Send welcome message to the joining user
        WebSocketConnection.send_to_user(user.id, {
          type: 'room_joined_successfully',
          data: {
            room: room.to_hash,
            message: "Welcome to #{room.name}!",
            your_role: room.administered_by?(user) ? 'administrator' : 'participant'
          }
        })
        
        { success: true, room: room, participant: participant }
        
      rescue => e
        $logger&.error "Failed to join room #{room_id}: #{e.message}"
        $logger&.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
        { success: false, error: "Failed to join room: #{e.message}" }
      end
    end
    
    # Leave a room with cleanup and notifications
    def leave_room(user, room_id)
      begin
        room = Room[room_id]
        return { success: false, error: 'Room not found' } unless room
        
        # Check if user is a participant
        unless room.has_participant?(user)
          return { success: false, error: 'Not a participant in this room' }
        end
        
        # Check if user is the administrator
        if room.administered_by?(user)
          return { success: false, error: 'Administrator cannot leave their own room' }
        end
        
        # Remove user from participants
        removed = room.remove_participant(user)
        
        unless removed
          return { success: false, error: 'Failed to remove participant' }
        end
        
        # Reload room to get fresh data
        room.refresh
        
        # Clear room state cache
        clear_room_cache(room_id)
        
        $logger&.info "User #{user.username} left room #{room.name} (#{room_id})"
        
        # Disconnect user from WebSocket room if connected
        user_connection = WebSocketConnection.get_user_connection(user.id)
        if user_connection && user_connection.room_id == room_id
          user_connection.leave_current_room
        end
        
        # Broadcast user left event to remaining room participants
        EventBroadcaster.broadcast_user_activity(room_id, :left, user)
        
        # Send confirmation to the leaving user
        WebSocketConnection.send_to_user(user.id, {
          type: 'room_left_successfully',
          data: {
            room_id: room_id,
            room_name: room.name,
            message: "You have left #{room.name}"
          }
        })
        
        { success: true, room: room }
        
      rescue => e
        $logger&.error "Failed to leave room #{room_id}: #{e.message}"
        { success: false, error: 'Failed to leave room' }
      end
    end
    
    # Get comprehensive room state with caching
    def get_room_state(room_id, user = nil)
      begin
        # Check cache first
        cached_state = get_cached_room_state(room_id)
        if cached_state
          # Add user-specific data if user provided
          if user
            cached_state[:is_user_participant] = cached_state[:participants].any? { |p| p[:user_id] == user.id }
            cached_state[:is_user_administrator] = cached_state[:administrator_id] == user.id
          end
          return cached_state
        end
        
        room = Room[room_id]
        return nil unless room
        
        # Build comprehensive room state
        room_state = {
          id: room.id,
          name: room.name,
          administrator_id: room.administrator_id,
          administrator: room.administrator&.to_hash,
          current_track_id: room.current_track_id,
          current_track: room.current_track&.to_hash,
          is_playing: room.is_playing,
          playback_started_at: room.playback_started_at&.to_f,
          playback_paused_at: room.playback_paused_at&.to_f,
          current_playback_position: room.current_playback_position,
          participants: room.participants.map(&:to_hash),
          participant_count: room.participants.count,
          track_queue: room.track_queue.map(&:to_hash),
          track_count: room.tracks.count,
          created_at: room.created_at&.iso8601,
          updated_at: room.updated_at&.iso8601,
          server_time: Time.now.to_f
        }
        
        # Add user-specific data if user provided
        if user
          room_state[:is_user_participant] = room.has_participant?(user)
          room_state[:is_user_administrator] = room.administered_by?(user)
        end
        
        # Cache the state (without user-specific data)
        cache_room_state(room_id, room_state.except(:is_user_participant, :is_user_administrator))
        
        room_state
        
      rescue => e
        $logger&.error "Failed to get room state for #{room_id}: #{e.message}"
        nil
      end
    end
    
    # Broadcast message to all participants in a room
    # Delegates to EventBroadcaster for unified event handling
    def broadcast_to_room(room_id, event_type, data = {})
      EventBroadcaster.broadcast_to_room(room_id, event_type, data)
    end
    
    # Broadcast message to a specific user
    def send_to_user(user_id, event_type, data = {})
      begin
        message = {
          type: event_type,
          data: data.merge({
            timestamp: Time.now.to_f,
            server_time: Time.now.to_f
          })
        }
        
        success = WebSocketConnection.send_to_user(user_id, message)
        
        if success
          $logger&.debug "Sent #{event_type} to user #{user_id}"
        else
          $logger&.debug "User #{user_id} not connected via WebSocket"
        end
        
        success
        
      rescue => e
        $logger&.error "Failed to send message to user #{user_id}: #{e.message}"
        false
      end
    end
    
    # Handle user disconnection cleanup
    def handle_user_disconnect(user_id, room_id = nil)
      begin
        user = User[user_id]
        return unless user
        
        # If specific room provided, clean up that room
        if room_id
          cleanup_user_from_room(user, room_id)
        else
          # Clean up user from all rooms they're in
          cleanup_user_from_all_rooms(user)
        end
        
        $logger&.info "Cleaned up disconnected user #{user.username} (#{user_id})"
        
      rescue => e
        $logger&.error "Failed to handle user disconnect for #{user_id}: #{e.message}"
      end
    end
    
    # Get room statistics
    def get_room_statistics(room_id)
      begin
        room = Room[room_id]
        return nil unless room
        
        {
          room_id: room_id,
          name: room.name,
          participant_count: room.participants.count,
          track_count: room.tracks.count,
          is_playing: room.is_playing,
          current_track: room.current_track&.to_hash,
          websocket_connections: WebSocketConnection.get_room_connections(room_id).length,
          created_at: room.created_at&.iso8601,
          uptime: room.created_at ? Time.now - room.created_at : 0
        }
        
      rescue => e
        $logger&.error "Failed to get room statistics for #{room_id}: #{e.message}"
        nil
      end
    end
    
    # Get global room manager statistics
    def get_global_statistics
      begin
        {
          total_rooms: Room.count,
          active_rooms: Room.where(Sequel.~(current_track_id: nil)).count,
          total_participants: RoomParticipant.count,
          websocket_connections: WebSocketConnection.connection_stats,
          cache_stats: {
            cached_rooms: @@room_state_cache.keys.length,
            cache_ttl: @@cache_ttl
          },
          server_time: Time.now.to_f
        }
        
      rescue => e
        $logger&.error "Failed to get global statistics: #{e.message}"
        { error: e.message }
      end
    end
    
    # Periodic cleanup of stale room states and connections
    def cleanup_stale_data
      begin
        # Clean up expired cache entries
        cleanup_expired_cache
        
        # Clean up empty rooms (no participants)
        cleanup_empty_rooms
        
        # Clean up stale WebSocket connections
        WebSocketConnection.cleanup_stale_connections
        
        $logger&.debug "Completed periodic room manager cleanup"
        
      rescue => e
        $logger&.error "Failed to cleanup stale data: #{e.message}"
      end
    end
    
    private
    
    # Cache management
    def cache_room_state(room_id, state)
      @@room_state_cache[room_id] = {
        data: state,
        cached_at: Time.now
      }
    end
    
    def get_cached_room_state(room_id)
      cached = @@room_state_cache[room_id]
      return nil unless cached
      
      # Check if cache is still valid
      if Time.now - cached[:cached_at] < @@cache_ttl
        cached[:data]
      else
        @@room_state_cache.delete(room_id)
        nil
      end
    end
    
    def clear_room_cache(room_id)
      @@room_state_cache.delete(room_id)
    end
    
    def cleanup_expired_cache
      expired_keys = []
      
      @@room_state_cache.each do |room_id, cached|
        if Time.now - cached[:cached_at] >= @@cache_ttl
          expired_keys << room_id
        end
      end
      
      expired_keys.each { |key| @@room_state_cache.delete(key) }
      
      $logger&.debug "Cleaned up #{expired_keys.length} expired cache entries" if expired_keys.any?
    end
    
    # User cleanup helpers
    def cleanup_user_from_room(user, room_id)
      room = Room[room_id]
      return unless room && room.has_participant?(user)
      
      # Don't auto-remove administrators
      return if room.administered_by?(user)
      
      # Remove from room
      room.remove_participant(user)
      
      # Clear cache
      clear_room_cache(room_id)
      
      # Broadcast user left event
      EventBroadcaster.broadcast_user_activity(room_id, :websocket_disconnected, user)
    end
    
    def cleanup_user_from_all_rooms(user)
      # Find all rooms where user is a participant
      user_rooms = RoomParticipant.where(user_id: user.id).map(&:room)
      
      user_rooms.each do |room|
        next if room.administered_by?(user) # Don't auto-remove administrators
        
        cleanup_user_from_room(user, room.id)
      end
    end
    
    def cleanup_empty_rooms
      # Find rooms with no participants (excluding administrator-only rooms)
      empty_rooms = Room.left_join(:room_participants, room_id: :id)
                       .where(room_participants__id: nil)
                       .all
      
      empty_rooms.each do |room|
        # Only clean up rooms that have been empty for more than 1 hour
        if room.updated_at && Time.now - room.updated_at > 3600
          $logger&.info "Cleaning up empty room: #{room.name} (#{room.id})"
          
          # Broadcast room deletion event
          broadcast_global_event('room_deleted', {
            room_id: room.id,
            room_name: room.name,
            reason: 'empty_room_cleanup'
          })
          
          # Delete the room (cascades to tracks and participants)
          room.destroy
          
          # Clear cache
          clear_room_cache(room.id)
        end
      end
    end
    
    # Global event broadcasting (to all connected users)
    def broadcast_global_event(event_type, data = {})
      begin
        message = {
          type: event_type,
          data: data.merge({
            timestamp: Time.now.to_f,
            server_time: Time.now.to_f
          })
        }
        
        # Broadcast to all connected users
        WebSocketConnection.connection_stats[:authenticated_users].each do |user_id|
          WebSocketConnection.send_to_user(user_id, message)
        end
        
        $logger&.debug "Broadcasted global event: #{event_type}"
        
      rescue => e
        $logger&.error "Failed to broadcast global event #{event_type}: #{e.message}"
      end
    end
  end
end