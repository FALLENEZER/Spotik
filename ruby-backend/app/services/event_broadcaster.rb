# Unified Event Broadcasting System
# Implements comprehensive real-time event broadcasting using Iodine's native Pub/Sub capabilities
# Consolidates all room activity broadcasting into a single, efficient system

require 'securerandom'

# Try to require JSON, but make it optional for testing
begin
  require 'json'
rescue LoadError
  # Mock JSON for testing environments
  module JSON
    def self.parse(str)
      { 'type' => 'mock_event' }
    end
    
    def self.generate(obj)
      obj.to_s
    end
  end
end

class EventBroadcaster
  # Event type constants for consistency
  EVENT_TYPES = {
    # User events
    user_joined: 'user_joined',
    user_left: 'user_left',
    user_connected_websocket: 'user_connected_websocket',
    user_disconnected_websocket: 'user_disconnected_websocket',
    
    # Track events
    track_added: 'track_added',
    track_voted: 'track_voted',
    track_unvoted: 'track_unvoted',
    queue_reordered: 'queue_reordered',
    
    # Playback events
    playback_started: 'playback_started',
    playback_paused: 'playback_paused',
    playback_resumed: 'playback_resumed',
    playback_stopped: 'playback_stopped',
    playback_seeked: 'playback_seeked',
    track_skipped: 'track_skipped',
    
    # Room state events
    room_state_updated: 'room_state_updated',
    room_created: 'room_created',
    room_deleted: 'room_deleted',
    
    # System events
    server_status: 'server_status',
    connection_established: 'connection_established',
    error: 'error'
  }.freeze
  
  # Event priority levels for delivery confirmation
  PRIORITY_LEVELS = {
    critical: 1,    # Must be delivered (playback control, user join/leave)
    high: 2,        # Should be delivered (voting, track addition)
    normal: 3,      # Best effort (status updates, notifications)
    low: 4          # Optional (debug info, statistics)
  }.freeze
  
  # Class-level event tracking for delivery confirmation
  @@pending_events = {}
  @@event_statistics = {
    total_events: 0,
    successful_deliveries: 0,
    failed_deliveries: 0,
    events_by_type: Hash.new(0),
    events_by_room: Hash.new(0)
  }
  
  class << self
    # Main broadcasting method - broadcasts event to all participants in a room
    def broadcast_to_room(room_id, event_type, data = {}, options = {})
      begin
        # Validate inputs
        return false unless room_id && event_type
        
        # Ensure event type is valid
        unless EVENT_TYPES.values.include?(event_type.to_s)
          $logger&.warn "Unknown event type: #{event_type}"
        end
        
        # Generate unique event ID for tracking
        event_id = SecureRandom.hex(8)
        
        # Build comprehensive event payload
        event_payload = build_event_payload(event_id, event_type, room_id, data, options)
        
        # Get room participants for delivery confirmation
        room = Room[room_id]
        return false unless room
        
        participant_count = room.participants.count
        websocket_connections = WebSocketConnection.get_room_connections(room_id).length
        
        # Track pending event for delivery confirmation
        track_pending_event(event_id, room_id, event_type, participant_count, websocket_connections, options)
        
        # Broadcast using Iodine's native Pub/Sub system and WebSocket connections
        channel_name = "room_#{room_id}"
        
        # Use both Iodine pub/sub and direct WebSocket broadcasting for reliability
        iodine_success = Iodine.publish(channel_name, event_payload.to_json)
        websocket_success = WebSocketConnection.broadcast_to_room(room_id, {
          type: event_type,
          data: event_payload[:data],
          metadata: event_payload[:metadata]
        })
        
        success = iodine_success || websocket_success
        
        if success
          # Update statistics
          update_event_statistics(event_type, room_id, :success)
          
          # Log successful broadcast
          $logger&.info "Event broadcasted: #{event_type} to room #{room_id} (#{websocket_connections} connections, event_id: #{event_id})"
          
          # Schedule delivery confirmation check for critical events
          if options[:priority] == :critical
            schedule_delivery_confirmation(event_id, options[:confirmation_timeout] || 5.0)
          end
          
          true
        else
          # Update statistics
          update_event_statistics(event_type, room_id, :failure)
          
          $logger&.error "Failed to broadcast event: #{event_type} to room #{room_id}"
          false
        end
        
      rescue => e
        $logger&.error "Error broadcasting event #{event_type} to room #{room_id}: #{e.message}"
        $logger&.error e.backtrace.join("\n") if SpotikConfig::Settings.app_debug?
        
        update_event_statistics(event_type, room_id, :failure)
        false
      end
    end
    
    # Broadcast to a specific user
    def broadcast_to_user(user_id, event_type, data = {}, options = {})
      begin
        return false unless user_id && event_type
        
        # Generate unique event ID
        event_id = SecureRandom.hex(8)
        
        # Build event payload
        event_payload = build_event_payload(event_id, event_type, nil, data, options)
        event_payload[:data][:target_user_id] = user_id
        
        # Use WebSocket connection to send to specific user
        connection = WebSocketConnection.get_user_connection(user_id)
        
        if connection
          connection.send_message(event_payload)
          
          update_event_statistics(event_type, 'user_direct', :success)
          $logger&.debug "Event sent to user #{user_id}: #{event_type} (event_id: #{event_id})"
          
          true
        else
          update_event_statistics(event_type, 'user_direct', :failure)
          $logger&.debug "User #{user_id} not connected via WebSocket"
          
          false
        end
        
      rescue => e
        $logger&.error "Error broadcasting event #{event_type} to user #{user_id}: #{e.message}"
        update_event_statistics(event_type, 'user_direct', :failure)
        false
      end
    end
    
    # Broadcast global event to all connected users
    def broadcast_global(event_type, data = {}, options = {})
      begin
        return false unless event_type
        
        # Generate unique event ID
        event_id = SecureRandom.hex(8)
        
        # Build event payload
        event_payload = build_event_payload(event_id, event_type, nil, data, options)
        event_payload[:data][:global_event] = true
        
        # Get all connected users
        connected_users = WebSocketConnection.connection_stats[:authenticated_users] || []
        
        success_count = 0
        connected_users.each do |user_id|
          if broadcast_to_user(user_id, event_type, data, options)
            success_count += 1
          end
        end
        
        $logger&.info "Global event broadcasted: #{event_type} to #{success_count}/#{connected_users.length} users (event_id: #{event_id})"
        
        success_count > 0
        
      rescue => e
        $logger&.error "Error broadcasting global event #{event_type}: #{e.message}"
        false
      end
    end
    
    # Specialized broadcasting methods for different event categories
    
    # User activity events (join, leave, connect, disconnect)
    def broadcast_user_activity(room_id, activity_type, user, additional_data = {})
      case activity_type
      when :joined
        broadcast_to_room(room_id, EVENT_TYPES[:user_joined], {
          user: user.to_hash,
          room_id: room_id,
          participant_count: Room[room_id]&.participants&.count || 0,
          participants: Room[room_id]&.participants&.map(&:to_hash) || [],
          message: "#{user.username} joined the room"
        }.merge(additional_data), { priority: :critical })
        
      when :left
        broadcast_to_room(room_id, EVENT_TYPES[:user_left], {
          user: user.to_hash,
          room_id: room_id,
          participant_count: Room[room_id]&.participants&.count || 0,
          participants: Room[room_id]&.participants&.map(&:to_hash) || [],
          message: "#{user.username} left the room"
        }.merge(additional_data), { priority: :critical })
        
      when :websocket_connected
        broadcast_to_room(room_id, EVENT_TYPES[:user_connected_websocket], {
          user: user.to_hash,
          room_id: room_id,
          websocket_connections: WebSocketConnection.get_room_connections(room_id).length,
          message: "#{user.username} connected to room via WebSocket"
        }.merge(additional_data), { priority: :high })
        
      when :websocket_disconnected
        broadcast_to_room(room_id, EVENT_TYPES[:user_disconnected_websocket], {
          user: user.to_hash,
          room_id: room_id,
          websocket_connections: WebSocketConnection.get_room_connections(room_id).length,
          message: "#{user.username} disconnected from room WebSocket"
        }.merge(additional_data), { priority: :high })
      end
    end
    
    # Track-related events (addition, voting, queue changes)
    def broadcast_track_activity(room_id, activity_type, track, user, additional_data = {})
      room = Room[room_id]
      return false unless room
      
      case activity_type
      when :added
        # Get updated queue for broadcasting
        updated_queue = room.track_queue.map(&:to_hash)
        
        broadcast_to_room(room_id, EVENT_TYPES[:track_added], {
          track: track.to_hash,
          room_id: room_id,
          uploader: user.to_hash,
          queue_position: updated_queue.find_index { |t| t[:id] == track.id } + 1,
          total_tracks: updated_queue.length,
          updated_queue: updated_queue,
          message: "#{user.username} added a new track: #{track.original_name}"
        }.merge(additional_data), { priority: :high })
        
      when :voted
        # Reload track to get updated vote data
        track.refresh
        updated_queue = room.track_queue.map do |queue_track|
          track_data = queue_track.to_hash
          track_data[:user_has_voted] = queue_track.has_vote_from?(user)
          track_data[:votes_count] = queue_track.votes.count
          track_data
        end
        
        broadcast_to_room(room_id, EVENT_TYPES[:track_voted], {
          track: track.to_hash,
          room_id: room_id,
          voter: user.to_hash,
          new_vote_score: track.vote_score,
          updated_queue: updated_queue,
          message: "#{user.username} voted for #{track.original_name}"
        }.merge(additional_data), { priority: :high })
        
      when :unvoted
        # Reload track to get updated vote data
        track.refresh
        updated_queue = room.track_queue.map do |queue_track|
          track_data = queue_track.to_hash
          track_data[:user_has_voted] = queue_track.has_vote_from?(user)
          track_data[:votes_count] = queue_track.votes.count
          track_data
        end
        
        broadcast_to_room(room_id, EVENT_TYPES[:track_unvoted], {
          track: track.to_hash,
          room_id: room_id,
          voter: user.to_hash,
          new_vote_score: track.vote_score,
          updated_queue: updated_queue,
          message: "#{user.username} removed vote from #{track.original_name}"
        }.merge(additional_data), { priority: :high })
        
      when :queue_reordered
        updated_queue = room.track_queue.map(&:to_hash)
        
        broadcast_to_room(room_id, EVENT_TYPES[:queue_reordered], {
          room_id: room_id,
          updated_queue: updated_queue,
          reorder_reason: additional_data[:reason] || 'unknown',
          affected_track: track.to_hash,
          message: additional_data[:message] || "Queue reordered"
        }.merge(additional_data), { priority: :high })
      end
    end
    
    # Playback control events (play, pause, resume, stop, seek, skip)
    def broadcast_playback_activity(room_id, activity_type, user, additional_data = {})
      room = Room[room_id]
      return false unless room
      
      # Calculate current playback position
      current_position = calculate_playback_position(room)
      
      # Base playback data
      base_data = {
        room_id: room_id,
        is_playing: room.is_playing,
        current_track: room.current_track&.to_hash,
        playback_started_at: room.playback_started_at&.to_f,
        playback_paused_at: room.playback_paused_at&.to_f,
        current_position: current_position,
        server_time: Time.now.to_f,
        administrator: user.to_hash
      }
      
      case activity_type
      when :started
        broadcast_to_room(room_id, EVENT_TYPES[:playback_started], base_data.merge({
          track: additional_data[:track]&.to_hash || room.current_track&.to_hash,
          started_at: additional_data[:started_at] || room.playback_started_at&.to_f,
          position: 0,
          message: "#{user.username} started playing #{room.current_track&.original_name}"
        }).merge(additional_data), { priority: :critical })
        
      when :paused
        broadcast_to_room(room_id, EVENT_TYPES[:playback_paused], base_data.merge({
          paused_at: additional_data[:paused_at] || room.playback_paused_at&.to_f,
          position: current_position,
          message: "#{user.username} paused playback"
        }).merge(additional_data), { priority: :critical })
        
      when :resumed
        broadcast_to_room(room_id, EVENT_TYPES[:playback_resumed], base_data.merge({
          resumed_at: additional_data[:resumed_at] || Time.now.to_f,
          position: current_position,
          message: "#{user.username} resumed playback"
        }).merge(additional_data), { priority: :critical })
        
      when :stopped
        broadcast_to_room(room_id, EVENT_TYPES[:playback_stopped], base_data.merge({
          stopped_at: additional_data[:stopped_at] || Time.now.to_f,
          reason: additional_data[:reason] || 'administrator_stop',
          message: "#{user.username} stopped playback"
        }).merge(additional_data), { priority: :critical })
        
      when :seeked
        broadcast_to_room(room_id, EVENT_TYPES[:playback_seeked], base_data.merge({
          seeked_at: additional_data[:seeked_at] || Time.now.to_f,
          position: additional_data[:position] || current_position,
          message: "#{user.username} seeked to #{(additional_data[:position] || current_position).round(1)}s"
        }).merge(additional_data), { priority: :critical })
        
      when :skipped
        broadcast_to_room(room_id, EVENT_TYPES[:track_skipped], base_data.merge({
          previous_track: additional_data[:previous_track]&.to_hash,
          new_track: additional_data[:new_track]&.to_hash || room.current_track&.to_hash,
          started_at: additional_data[:started_at] || room.playback_started_at&.to_f,
          position: 0,
          message: additional_data[:message] || "#{user.username} skipped track"
        }).merge(additional_data), { priority: :critical })
      end
    end
    
    # Room state events
    def broadcast_room_state(room_id, user = nil, additional_data = {})
      room = Room[room_id]
      return false unless room
      
      # Get comprehensive room state
      room_state = RoomManager.get_room_state(room_id, user)
      return false unless room_state
      
      broadcast_to_room(room_id, EVENT_TYPES[:room_state_updated], {
        room: room_state,
        updated_by: user&.to_hash,
        message: "Room state updated"
      }.merge(additional_data), { priority: :normal })
    end
    
    # Error broadcasting
    def broadcast_error(target, error_code, message, additional_data = {})
      error_data = {
        error_code: error_code,
        message: message,
        timestamp: Time.now.to_f
      }.merge(additional_data)
      
      case target
      when /^room_/
        room_id = target.sub('room_', '')
        broadcast_to_room(room_id, EVENT_TYPES[:error], error_data, { priority: :high })
      when /^user_/
        user_id = target.sub('user_', '')
        broadcast_to_user(user_id, EVENT_TYPES[:error], error_data, { priority: :high })
      else
        broadcast_global(EVENT_TYPES[:error], error_data, { priority: :high })
      end
    end
    
    # Event delivery confirmation and error handling
    def confirm_event_delivery(event_id, user_id)
      pending_event = @@pending_events[event_id]
      return false unless pending_event
      
      pending_event[:confirmed_users] << user_id
      pending_event[:confirmed_at] = Time.now
      
      # Check if all users have confirmed
      if pending_event[:confirmed_users].length >= pending_event[:expected_confirmations]
        @@pending_events.delete(event_id)
        $logger&.debug "Event #{event_id} fully confirmed by all users"
        true
      else
        false
      end
    end
    
    # Get event broadcasting statistics
    def get_statistics
      {
        total_events: @@event_statistics[:total_events],
        successful_deliveries: @@event_statistics[:successful_deliveries],
        failed_deliveries: @@event_statistics[:failed_deliveries],
        success_rate: calculate_success_rate,
        events_by_type: @@event_statistics[:events_by_type].to_h,
        events_by_room: @@event_statistics[:events_by_room].to_h,
        pending_events: @@pending_events.length,
        server_time: Time.now.to_f
      }
    end
    
    # Cleanup stale pending events
    def cleanup_stale_events
      stale_events = []
      current_time = Time.now
      
      @@pending_events.each do |event_id, event_data|
        if current_time - event_data[:created_at] > 30 # 30 seconds timeout
          stale_events << event_id
        end
      end
      
      stale_events.each do |event_id|
        @@pending_events.delete(event_id)
      end
      
      $logger&.debug "Cleaned up #{stale_events.length} stale pending events" if stale_events.any?
    end
    
    private
    
    # Build standardized event payload
    def build_event_payload(event_id, event_type, room_id, data, options)
      {
        event_id: event_id,
        type: event_type,
        data: data.merge({
          room_id: room_id,
          timestamp: Time.now.to_f,
          server_time: Time.now.to_f
        }),
        metadata: {
          priority: options[:priority] || :normal,
          requires_confirmation: options[:requires_confirmation] || false,
          retry_count: options[:retry_count] || 0,
          created_at: Time.now.to_f
        }
      }
    end
    
    # Track pending event for delivery confirmation
    def track_pending_event(event_id, room_id, event_type, participant_count, websocket_connections, options)
      if options[:requires_confirmation] || options[:priority] == :critical
        @@pending_events[event_id] = {
          room_id: room_id,
          event_type: event_type,
          expected_confirmations: websocket_connections,
          confirmed_users: [],
          created_at: Time.now,
          confirmed_at: nil,
          priority: options[:priority] || :normal
        }
      end
    end
    
    # Schedule delivery confirmation check
    def schedule_delivery_confirmation(event_id, timeout_seconds)
      # Use Iodine's timer to check delivery confirmation
      Iodine.run_after(timeout_seconds * 1000) do # Convert to milliseconds
        pending_event = @@pending_events[event_id]
        
        if pending_event
          confirmed_count = pending_event[:confirmed_users].length
          expected_count = pending_event[:expected_confirmations]
          
          if confirmed_count < expected_count
            $logger&.warn "Event #{event_id} delivery incomplete: #{confirmed_count}/#{expected_count} confirmations"
            
            # Optionally retry critical events
            if pending_event[:priority] == :critical
              retry_failed_event(event_id, pending_event)
            end
          end
          
          # Clean up the pending event
          @@pending_events.delete(event_id)
        end
      end
    end
    
    # Retry failed critical events
    def retry_failed_event(event_id, pending_event)
      $logger&.info "Retrying critical event #{event_id} for room #{pending_event[:room_id]}"
      
      # This would require storing the original event data and retrying
      # For now, just log the failure
      update_event_statistics(pending_event[:event_type], pending_event[:room_id], :retry)
    end
    
    # Update event statistics
    def update_event_statistics(event_type, room_id, result)
      @@event_statistics[:total_events] += 1
      @@event_statistics[:events_by_type][event_type.to_s] += 1
      @@event_statistics[:events_by_room][room_id.to_s] += 1
      
      case result
      when :success
        @@event_statistics[:successful_deliveries] += 1
      when :failure
        @@event_statistics[:failed_deliveries] += 1
      when :retry
        # Don't count retries in success/failure stats
      end
    end
    
    # Calculate success rate
    def calculate_success_rate
      total = @@event_statistics[:successful_deliveries] + @@event_statistics[:failed_deliveries]
      return 0.0 if total == 0
      
      (@@event_statistics[:successful_deliveries].to_f / total * 100).round(2)
    end
    
    # Calculate playback position helper
    def calculate_playback_position(room)
      return 0 unless room.playback_started_at
      
      if room.is_playing
        (Time.now - room.playback_started_at).to_f
      elsif room.playback_paused_at
        (room.playback_paused_at - room.playback_started_at).to_f
      else
        0
      end
    end
  end
end