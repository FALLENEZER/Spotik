# Playback Controller - Synchronized playback control with timestamp synchronization
# Implements comprehensive playback management for room administrators

require 'json'
require_relative '../services/auth_service'
require_relative '../services/room_manager'
require_relative '../services/event_broadcaster'

class PlaybackController
  class << self
    # POST /api/rooms/:id/playback/start - Start track playback
    def start_track(room_id, track_id, token)
      begin
        # Authenticate user
        auth_data = AuthService.validate_jwt(token)
        current_user = auth_data[:user]
        
        # Find room
        room = Room[room_id]
        unless room
          return {
            status: 404,
            body: { error: 'Room not found' }
          }
        end
        
        # Check if user is room administrator
        unless room.administered_by?(current_user)
          return {
            status: 403,
            body: { error: 'Only room administrators can control playback' }
          }
        end
        
        # Find track
        track = Track[track_id]
        unless track && track.room_id == room_id
          return {
            status: 404,
            body: { error: 'Track not found in this room' }
          }
        end
        
        # Start playback with precise timestamp
        start_time = Time.now
        room.update(
          current_track_id: track.id,
          playback_started_at: start_time,
          playback_paused_at: nil,
          is_playing: true,
          updated_at: start_time
        )
        
        $logger&.info "Playback started: track #{track.id} in room #{room.id} by #{current_user.username}"
        
        # Broadcast playback started event with accurate timestamps
        broadcast_playback_event(room, 'playback_started', current_user, {
          track: track.to_hash,
          started_at: start_time.to_f,
          server_time: Time.now.to_f,
          position: 0,
          administrator: current_user.to_hash,
          message: "#{current_user.username} started playing #{track.original_name}"
        })
        
        {
          status: 200,
          body: {
            message: 'Playback started successfully',
            track: track.to_hash,
            started_at: start_time.to_f,
            server_time: Time.now.to_f,
            is_playing: true
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
        $logger&.error "Error starting playback in room #{room_id}: #{e.message}"
        $logger&.error e.backtrace.join("\n") if SpotikConfig::Settings.app_debug?
        
        {
          status: 500,
          body: { 
            error: 'Failed to start playback',
            message: SpotikConfig::Settings.app_debug? ? e.message : 'Internal server error'
          }
        }
      end
    end
    
    # POST /api/rooms/:id/playback/pause - Pause track playback
    def pause_track(room_id, token)
      begin
        # Authenticate user
        auth_data = AuthService.validate_jwt(token)
        current_user = auth_data[:user]
        
        # Find room
        room = Room[room_id]
        unless room
          return {
            status: 404,
            body: { error: 'Room not found' }
          }
        end
        
        # Check if user is room administrator
        unless room.administered_by?(current_user)
          return {
            status: 403,
            body: { error: 'Only room administrators can control playback' }
          }
        end
        
        # Check if there's a current track
        unless room.current_track_id
          return {
            status: 400,
            body: { 
              error: 'No track is currently selected',
              message: 'Please start a track before attempting to pause'
            }
          }
        end
        
        # Check if playback is active
        unless room.is_playing
          return {
            status: 400,
            body: { 
              error: 'Playback is not currently active',
              message: 'Track is already paused or stopped'
            }
          }
        end
        
        # Calculate current position before pausing
        current_position = calculate_playback_position(room)
        pause_time = Time.now
        
        # Pause playback
        room.update(
          playback_paused_at: pause_time,
          is_playing: false,
          updated_at: pause_time
        )
        
        $logger&.info "Playback paused: room #{room.id} at position #{current_position}s by #{current_user.username}"
        
        # Broadcast playback paused event with accurate position
        broadcast_playback_event(room, 'playback_paused', current_user, {
          paused_at: pause_time.to_f,
          position: current_position,
          server_time: Time.now.to_f,
          administrator: current_user.to_hash,
          message: "#{current_user.username} paused playback"
        })
        
        {
          status: 200,
          body: {
            message: 'Playback paused successfully',
            paused_at: pause_time.to_f,
            position: current_position,
            server_time: Time.now.to_f,
            is_playing: false
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
        $logger&.error "Error pausing playback in room #{room_id}: #{e.message}"
        $logger&.error e.backtrace.join("\n") if SpotikConfig::Settings.app_debug?
        
        {
          status: 500,
          body: { 
            error: 'Failed to pause playback',
            message: SpotikConfig::Settings.app_debug? ? e.message : 'Internal server error'
          }
        }
      end
    end
    
    # POST /api/rooms/:id/playback/resume - Resume track playback
    def resume_track(room_id, token)
      begin
        # Authenticate user
        auth_data = AuthService.validate_jwt(token)
        current_user = auth_data[:user]
        
        # Find room
        room = Room[room_id]
        unless room
          return {
            status: 404,
            body: { error: 'Room not found' }
          }
        end
        
        # Check if user is room administrator
        unless room.administered_by?(current_user)
          return {
            status: 403,
            body: { error: 'Only room administrators can control playback' }
          }
        end
        
        # Check if there's a current track
        unless room.current_track_id
          return {
            status: 400,
            body: { 
              error: 'No track is currently selected',
              message: 'Please start a track before attempting to resume'
            }
          }
        end
        
        # Check if playback is paused
        if room.is_playing
          return {
            status: 400,
            body: { 
              error: 'Playback is not currently paused',
              message: 'Track is already playing'
            }
          }
        end
        
        unless room.playback_paused_at && room.playback_started_at
          return {
            status: 400,
            body: { 
              error: 'No paused playback to resume',
              message: 'Please start a track or pause an active track first'
            }
          }
        end
        
        # Calculate paused duration and adjust start time
        paused_duration = Time.now - room.playback_paused_at
        new_start_time = room.playback_started_at + paused_duration
        resume_time = Time.now
        
        # Resume playback with adjusted timestamp
        room.update(
          playback_started_at: new_start_time,
          playback_paused_at: nil,
          is_playing: true,
          updated_at: resume_time
        )
        
        # Calculate current position for broadcasting
        current_position = calculate_playback_position(room)
        
        $logger&.info "Playback resumed: room #{room.id} at position #{current_position}s by #{current_user.username}"
        
        # Broadcast playback resumed event with accurate position
        broadcast_playback_event(room, 'playback_resumed', current_user, {
          resumed_at: resume_time.to_f,
          position: current_position,
          server_time: Time.now.to_f,
          administrator: current_user.to_hash,
          message: "#{current_user.username} resumed playback"
        })
        
        {
          status: 200,
          body: {
            message: 'Playback resumed successfully',
            resumed_at: resume_time.to_f,
            position: current_position,
            server_time: Time.now.to_f,
            is_playing: true
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
        $logger&.error "Error resuming playback in room #{room_id}: #{e.message}"
        $logger&.error e.backtrace.join("\n") if SpotikConfig::Settings.app_debug?
        
        {
          status: 500,
          body: { 
            error: 'Failed to resume playback',
            message: SpotikConfig::Settings.app_debug? ? e.message : 'Internal server error'
          }
        }
      end
    end
    
    # POST /api/rooms/:id/playback/skip - Skip to next track
    def skip_track(room_id, token)
      begin
        # Authenticate user
        auth_data = AuthService.validate_jwt(token)
        current_user = auth_data[:user]
        
        # Find room
        room = Room[room_id]
        unless room
          return {
            status: 404,
            body: { error: 'Room not found' }
          }
        end
        
        # Check if user is room administrator
        unless room.administered_by?(current_user)
          return {
            status: 403,
            body: { error: 'Only room administrators can control playback' }
          }
        end
        
        # Get current track for logging
        current_track = room.current_track
        
        # Check if there's a current track to skip
        unless current_track
          return {
            status: 400,
            body: { 
              error: 'No track is currently playing',
              message: 'Please start a track before attempting to skip'
            }
          }
        end
        
        # Get next track in queue
        next_track = room.next_track
        
        if next_track
          # Start next track
          start_time = Time.now
          room.update(
            current_track_id: next_track.id,
            playback_started_at: start_time,
            playback_paused_at: nil,
            is_playing: true,
            updated_at: start_time
          )
          
          $logger&.info "Track skipped: from #{current_track&.id} to #{next_track.id} in room #{room.id} by #{current_user.username}"
          
          # Broadcast track skipped and new track started events
          broadcast_playback_event(room, 'track_skipped', current_user, {
            previous_track: current_track&.to_hash,
            new_track: next_track.to_hash,
            started_at: start_time.to_f,
            position: 0,
            server_time: Time.now.to_f,
            administrator: current_user.to_hash,
            message: "#{current_user.username} skipped to #{next_track.original_name}"
          })
          
          {
            status: 200,
            body: {
              message: 'Track skipped successfully',
              previous_track: current_track&.to_hash,
              new_track: next_track.to_hash,
              started_at: start_time.to_f,
              server_time: Time.now.to_f,
              is_playing: true
            }
          }
        else
          # No next track, stop playback
          stop_time = Time.now
          room.update(
            current_track_id: nil,
            playback_started_at: nil,
            playback_paused_at: nil,
            is_playing: false,
            updated_at: stop_time
          )
          
          $logger&.info "Playback stopped: no more tracks in queue for room #{room.id} by #{current_user.username}"
          
          # Broadcast playback stopped event
          broadcast_playback_event(room, 'playback_stopped', current_user, {
            stopped_at: stop_time.to_f,
            reason: 'no_more_tracks',
            server_time: Time.now.to_f,
            administrator: current_user.to_hash,
            message: "#{current_user.username} skipped track - no more tracks in queue"
          })
          
          {
            status: 200,
            body: {
              message: 'No more tracks in queue - playback stopped',
              previous_track: current_track&.to_hash,
              stopped_at: stop_time.to_f,
              server_time: Time.now.to_f,
              is_playing: false
            }
          }
        end
        
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
        $logger&.error "Error skipping track in room #{room_id}: #{e.message}"
        $logger&.error e.backtrace.join("\n") if SpotikConfig::Settings.app_debug?
        
        {
          status: 500,
          body: { 
            error: 'Failed to skip track',
            message: SpotikConfig::Settings.app_debug? ? e.message : 'Internal server error'
          }
        }
      end
    end
    
    # POST /api/rooms/:id/playback/stop - Stop playback
    def stop_playback(room_id, token)
      begin
        # Authenticate user
        auth_data = AuthService.validate_jwt(token)
        current_user = auth_data[:user]
        
        # Find room
        room = Room[room_id]
        unless room
          return {
            status: 404,
            body: { error: 'Room not found' }
          }
        end
        
        # Check if user is room administrator
        unless room.administered_by?(current_user)
          return {
            status: 403,
            body: { error: 'Only room administrators can control playback' }
          }
        end
        
        # Get current track for logging
        current_track = room.current_track
        
        # Stop playback
        stop_time = Time.now
        room.update(
          current_track_id: nil,
          playback_started_at: nil,
          playback_paused_at: nil,
          is_playing: false,
          updated_at: stop_time
        )
        
        $logger&.info "Playback stopped: room #{room.id} by #{current_user.username}"
        
        # Broadcast playback stopped event
        broadcast_playback_event(room, 'playback_stopped', current_user, {
          stopped_at: stop_time.to_f,
          previous_track: current_track&.to_hash,
          reason: 'administrator_stop',
          server_time: Time.now.to_f,
          administrator: current_user.to_hash,
          message: "#{current_user.username} stopped playback"
        })
        
        {
          status: 200,
          body: {
            message: 'Playback stopped successfully',
            stopped_at: stop_time.to_f,
            server_time: Time.now.to_f,
            is_playing: false
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
        $logger&.error "Error stopping playback in room #{room_id}: #{e.message}"
        $logger&.error e.backtrace.join("\n") if SpotikConfig::Settings.app_debug?
        
        {
          status: 500,
          body: { 
            error: 'Failed to stop playback',
            message: SpotikConfig::Settings.app_debug? ? e.message : 'Internal server error'
          }
        }
      end
    end
    
    # GET /api/rooms/:id/playback/status - Get current playback status
    def get_playback_status(room_id, token)
      begin
        # Authenticate user
        auth_data = AuthService.validate_jwt(token)
        current_user = auth_data[:user]
        
        # Find room
        room = Room[room_id]
        unless room
          return {
            status: 404,
            body: { error: 'Room not found' }
          }
        end
        
        # Check if user is participant of the room
        unless room.has_participant?(current_user)
          return {
            status: 403,
            body: { error: 'You must be a participant of this room to view playback status' }
          }
        end
        
        # Calculate current playback position
        current_position = calculate_playback_position(room)
        
        # Build comprehensive playback status
        playback_status = {
          room_id: room.id,
          is_playing: room.is_playing,
          current_track: room.current_track&.to_hash,
          playback_started_at: room.playback_started_at&.to_f,
          playback_paused_at: room.playback_paused_at&.to_f,
          current_position: current_position,
          server_time: Time.now.to_f,
          next_track: room.next_track&.to_hash,
          queue_length: room.tracks.count,
          administrator: room.administrator&.to_hash
        }
        
        {
          status: 200,
          body: {
            playback_status: playback_status
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
        $logger&.error "Error getting playback status for room #{room_id}: #{e.message}"
        $logger&.error e.backtrace.join("\n") if SpotikConfig::Settings.app_debug?
        
        {
          status: 500,
          body: { 
            error: 'Failed to get playback status',
            message: SpotikConfig::Settings.app_debug? ? e.message : 'Internal server error'
          }
        }
      end
    end
    
    # POST /api/rooms/:id/playback/seek - Seek to specific position (admin only)
    def seek_to_position(room_id, position, token)
      begin
        # Authenticate user
        auth_data = AuthService.validate_jwt(token)
        current_user = auth_data[:user]
        
        # Find room
        room = Room[room_id]
        unless room
          return {
            status: 404,
            body: { error: 'Room not found' }
          }
        end
        
        # Check if user is room administrator
        unless room.administered_by?(current_user)
          return {
            status: 403,
            body: { error: 'Only room administrators can seek playback' }
          }
        end
        
        # Validate position
        position = position.to_f
        if position < 0
          return {
            status: 400,
            body: { error: 'Position cannot be negative' }
          }
        end
        
        # Check if there's a current track
        unless room.current_track
          return {
            status: 400,
            body: { error: 'No track is currently playing' }
          }
        end
        
        # Validate position doesn't exceed track duration
        if room.current_track.duration_seconds && position > room.current_track.duration_seconds
          return {
            status: 400,
            body: { error: 'Position exceeds track duration' }
          }
        end
        
        # Calculate new start time based on seek position
        seek_time = Time.now
        new_start_time = seek_time - position
        
        # Update playback timestamps
        room.update(
          playback_started_at: new_start_time,
          playback_paused_at: room.is_playing ? nil : seek_time,
          updated_at: seek_time
        )
        
        $logger&.info "Playback seeked: room #{room.id} to position #{position}s by #{current_user.username}"
        
        # Broadcast seek event
        broadcast_playback_event(room, 'playback_seeked', current_user, {
          seeked_at: seek_time.to_f,
          position: position,
          server_time: Time.now.to_f,
          administrator: current_user.to_hash,
          message: "#{current_user.username} seeked to #{position.round(1)}s"
        })
        
        {
          status: 200,
          body: {
            message: 'Playback seeked successfully',
            seeked_at: seek_time.to_f,
            position: position,
            server_time: Time.now.to_f,
            is_playing: room.is_playing
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
        $logger&.error "Error seeking playback in room #{room_id}: #{e.message}"
        $logger&.error e.backtrace.join("\n") if SpotikConfig::Settings.app_debug?
        
        {
          status: 500,
          body: { 
            error: 'Failed to seek playback',
            message: SpotikConfig::Settings.app_debug? ? e.message : 'Internal server error'
          }
        }
      end
    end
    
    private
    
    # Calculate accurate playback position using server timestamps
    def calculate_playback_position(room)
      return 0 unless room.playback_started_at
      
      if room.is_playing
        # Currently playing - calculate elapsed time since start
        (Time.now - room.playback_started_at).to_f
      elsif room.playback_paused_at
        # Currently paused - calculate time until pause
        (room.playback_paused_at - room.playback_started_at).to_f
      else
        # Not playing and no pause time - return 0
        0
      end
    end
    
    # Broadcast playback event to all room participants using EventBroadcaster
    def broadcast_playback_event(room, event_type, current_user, additional_data = {})
      # Map event types to EventBroadcaster activity types
      activity_type = case event_type
      when 'playback_started'
        :started
      when 'playback_paused'
        :paused
      when 'playback_resumed'
        :resumed
      when 'playback_stopped'
        :stopped
      when 'playback_seeked'
        :seeked
      when 'track_skipped'
        :skipped
      else
        :started # fallback
      end
      
      EventBroadcaster.broadcast_playback_activity(room.id, activity_type, current_user, additional_data)
    end
  end
end