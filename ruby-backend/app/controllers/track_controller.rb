# Track Controller - Handles track management endpoints
# Compatible with Laravel API format

require 'json'
require_relative '../services/auth_service'
require_relative '../services/file_service'
require_relative '../services/event_broadcaster'

class TrackController
  # GET /api/rooms/:id/tracks - Get room track queue
  def self.index(room_id, token = nil)
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
          body: { error: 'You must be a participant of this room to view tracks' }
        }
      end
      
      # Get track queue ordered by vote score (desc) then created_at (asc)
      tracks = room.track_queue.map do |track|
        track_data = track.to_hash
        
        # Add user-specific information
        track_data[:user_has_voted] = track.has_vote_from?(current_user)
        track_data[:votes_count] = track.votes.count
        track_data[:queue_position] = room.track_queue.to_a.find_index(track) + 1
        
        # Add voting details for transparency
        track_data[:voters] = track.voters.map(&:username) if SpotikConfig::Settings.app_debug?
        
        track_data
      end
      
      {
        status: 200,
        body: {
          tracks: tracks,
          total_count: tracks.length
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
      $logger&.error "Error retrieving tracks for room #{room_id}: #{e.message}"
      $logger&.error e.backtrace.join("\n") if SpotikConfig::Settings.app_debug?
      
      {
        status: 500,
        body: { 
          error: 'Failed to retrieve tracks',
          message: SpotikConfig::Settings.app_debug? ? e.message : 'Internal server error'
        }
      }
    end
  end
  
  # POST /api/rooms/:id/tracks - Upload new track
  def self.store(room_id, file_data, token)
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
          body: { error: 'You must be a participant of this room to upload tracks' }
        }
      end
      
      # Validate file data
      unless file_data && file_data[:audio_file]
        return {
          status: 422,
          body: {
            error: 'Validation failed',
            errors: {
              audio_file: ['The audio file field is required.']
            }
          }
        }
      end
      
      # Save uploaded file
      file_result = FileService.save_uploaded_file(file_data[:audio_file], current_user.id, room.id)
      
      unless file_result[:success]
        return {
          status: 422,
          body: {
            error: 'Validation failed',
            errors: {
              audio_file: file_result[:errors]
            }
          }
        }
      end
      
      file_info = file_result[:file_info]
      
      # Create track record
      track = Track.create(
        room_id: room.id,
        uploader_id: current_user.id,
        filename: file_info[:filename],
        original_name: file_info[:original_name],
        file_path: file_info[:file_path],
        duration_seconds: file_info[:duration_seconds],
        file_size_bytes: file_info[:file_size_bytes],
        mime_type: file_info[:mime_type],
        vote_score: 0,
        created_at: Time.now,
        updated_at: Time.now
      )
      
      # Reload to get fresh data with associations
      track.refresh
      
      $logger&.info "Track uploaded: #{track.id} by user #{current_user.id} to room #{room.id}"
      
      # Auto-start playback if no track is currently playing and this is the first track in queue
      auto_started_playback = false
      if !room.is_playing && !room.current_track_id
        begin
          room.update(
            current_track_id: track.id,
            playback_started_at: Time.now,
            playback_paused_at: nil,
            is_playing: true
          )
          
          auto_started_playback = true
          $logger&.info "Auto-started playback for new track: #{track.id} in room #{room.id}"
          
        rescue => e
          $logger&.warn "Failed to auto-start playback: #{e.message}"
        end
      end
      
      # Broadcast track_added event via WebSocket to all room participants
      begin
        # Get updated room state for broadcasting
        room.refresh
        updated_queue = room.track_queue.map(&:to_hash)
        
        EventBroadcaster.broadcast_track_activity(room.id, :added, track, current_user)
        
        # If playback auto-started, broadcast that event too
        if auto_started_playback
          EventBroadcaster.broadcast_playback_activity(room.id, :started, current_user, {
            track: track,
            started_at: room.playback_started_at.to_f,
            auto_started: true,
            message: "Playback started automatically with #{track.original_name}"
          })
        end
        
        $logger&.info "Broadcasted track_added event for track #{track.id} in room #{room.id}"
        
      rescue => e
        $logger&.error "Failed to broadcast track_added event: #{e.message}"
      end
      
      # Prepare response data (Laravel format compatibility)
      track_data = track.to_hash
      track_data[:user_has_voted] = false
      track_data[:votes_count] = 0
      
      {
        status: 201,
        body: {
          message: 'Track uploaded successfully',
          track: track_data
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
    rescue Sequel::ValidationFailed => e
      $logger&.warn "Track creation validation failed: #{e.message}"
      
      {
        status: 422,
        body: {
          error: 'Validation failed',
          errors: format_validation_errors(e.errors)
        }
      }
      
    rescue => e
      $logger&.error "Error uploading track to room #{room_id}: #{e.message}"
      $logger&.error e.backtrace.join("\n") if SpotikConfig::Settings.app_debug?
      
      # Clean up file if track creation failed
      if file_result && file_result[:success] && file_result[:file_info]
        FileService.delete_file(file_result[:file_info][:filename])
      end
      
      {
        status: 500,
        body: { 
          error: 'Failed to upload track',
          message: SpotikConfig::Settings.app_debug? ? e.message : 'Internal server error'
        }
      }
    end
  end
  
  # POST /api/tracks/:id/vote - Vote for track
  def self.vote(track_id, token)
    begin
      # Authenticate user
      auth_data = AuthService.validate_jwt(token)
      current_user = auth_data[:user]
      
      # Find track
      track = Track[track_id]
      unless track
        return {
          status: 404,
          body: { error: 'Track not found' }
        }
      end
      
      # Get room
      room = track.room
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
          body: { error: 'You must be a participant of this room to vote' }
        }
      end
      
      # Add vote (will not duplicate if already exists)
      was_new_vote = false
      existing_vote = track.votes_dataset.where(user_id: current_user.id).first
      
      if existing_vote
        # Vote already exists
        message = 'Vote already exists'
      else
        # Create new vote
        TrackVote.create(
          track_id: track.id,
          user_id: current_user.id,
          created_at: Time.now
        )
        was_new_vote = true
        message = 'Vote added successfully'
        
        # Update track vote score
        track.update(vote_score: track.votes.count)
      end
      
      # Reload track to get fresh vote data
      track.refresh
      
      $logger&.info "User #{current_user.id} voted for track #{track.id} (new: #{was_new_vote})"
      
      # Broadcast track_voted event and queue reordering via WebSocket
      if was_new_vote
        begin
          # Get updated room and queue state
          room.refresh
          updated_queue = room.track_queue.map do |queue_track|
            track_data = queue_track.to_hash
            track_data[:user_has_voted] = queue_track.has_vote_from?(current_user)
            track_data[:votes_count] = queue_track.votes.count
            track_data
          end
          
          # Broadcast vote event to all room participants
          EventBroadcaster.broadcast_track_activity(room.id, :voted, track, current_user)
          
          # Check if queue order changed and broadcast queue_reordered event
          # Compare current queue order with what it would be without this vote
          old_track_score = track.vote_score - 1
          queue_changed = check_queue_order_changed(room, track.id, old_track_score, track.vote_score)
          
          if queue_changed
            EventBroadcaster.broadcast_track_activity(room.id, :queue_reordered, track, current_user, {
              reason: 'vote_added',
              message: "Queue reordered due to vote for #{track.original_name}"
            })
          end
          
          $logger&.info "Broadcasted track_voted event for track #{track.id} by user #{current_user.id}"
          
        rescue => e
          $logger&.error "Failed to broadcast track_voted event: #{e.message}"
        end
      end
      
      {
        status: 200,
        body: {
          message: message,
          vote_score: track.vote_score,
          user_has_voted: true
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
      $logger&.error "Error voting for track #{track_id}: #{e.message}"
      $logger&.error e.backtrace.join("\n") if SpotikConfig::Settings.app_debug?
      
      {
        status: 500,
        body: { 
          error: 'Failed to vote for track',
          message: SpotikConfig::Settings.app_debug? ? e.message : 'Internal server error'
        }
      }
    end
  end
  
  # DELETE /api/tracks/:id/vote - Remove vote
  def self.unvote(track_id, token)
    begin
      # Authenticate user
      auth_data = AuthService.validate_jwt(token)
      current_user = auth_data[:user]
      
      # Find track
      track = Track[track_id]
      unless track
        return {
          status: 404,
          body: { error: 'Track not found' }
        }
      end
      
      # Get room
      room = track.room
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
          body: { error: 'You must be a participant of this room to remove votes' }
        }
      end
      
      # Remove vote
      vote_removed = false
      existing_vote = track.votes_dataset.where(user_id: current_user.id).first
      
      if existing_vote
        existing_vote.destroy
        vote_removed = true
        message = 'Vote removed successfully'
        
        # Update track vote score
        track.update(vote_score: [track.votes.count, 0].max)
      else
        message = 'No vote to remove'
      end
      
      # Reload track to get fresh vote data
      track.refresh
      
      $logger&.info "User #{current_user.id} removed vote for track #{track.id} (removed: #{vote_removed})"
      
      # Broadcast track_unvoted event and queue reordering via WebSocket
      if vote_removed
        begin
          # Get updated room and queue state
          room.refresh
          updated_queue = room.track_queue.map do |queue_track|
            track_data = queue_track.to_hash
            track_data[:user_has_voted] = queue_track.has_vote_from?(current_user)
            track_data[:votes_count] = queue_track.votes.count
            track_data
          end
          
          # Broadcast unvote event to all room participants
          EventBroadcaster.broadcast_track_activity(room.id, :unvoted, track, current_user)
          
          # Check if queue order changed and broadcast queue_reordered event
          # Compare current queue order with what it would be with the previous vote
          old_track_score = track.vote_score + 1
          queue_changed = check_queue_order_changed(room, track.id, old_track_score, track.vote_score)
          
          if queue_changed
            EventBroadcaster.broadcast_track_activity(room.id, :queue_reordered, track, current_user, {
              reason: 'vote_removed',
              message: "Queue reordered due to vote removal from #{track.original_name}"
            })
          end
          
          $logger&.info "Broadcasted track_unvoted event for track #{track.id} by user #{current_user.id}"
          
        rescue => e
          $logger&.error "Failed to broadcast track_unvoted event: #{e.message}"
        end
      end
      
      {
        status: 200,
        body: {
          message: message,
          vote_score: track.vote_score,
          user_has_voted: false
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
      $logger&.error "Error removing vote for track #{track_id}: #{e.message}"
      $logger&.error e.backtrace.join("\n") if SpotikConfig::Settings.app_debug?
      
      {
        status: 500,
        body: { 
          error: 'Failed to remove vote',
          message: SpotikConfig::Settings.app_debug? ? e.message : 'Internal server error'
        }
      }
    end
  end
  
  # GET /api/tracks/:id/stream - Stream track audio file
  def self.stream(track_id, token, range_header = nil)
    begin
      # Authenticate user
      auth_data = AuthService.validate_jwt(token)
      current_user = auth_data[:user]
      
      # Find track
      track = Track[track_id]
      unless track
        return {
          status: 404,
          body: { error: 'Track not found' }
        }
      end
      
      # Get room
      room = track.room
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
          body: { error: 'You must be a participant of this room to stream tracks' }
        }
      end
      
      # Get file info with enhanced caching and range support
      file_result = FileService.serve_file(track.filename, range_header)
      unless file_result[:success]
        return {
          status: 404,
          body: { error: file_result[:error] || 'Audio file not found' }
        }
      end
      
      # Return file streaming info with enhanced metadata
      {
        status: file_result[:status] || 200,
        file_info: file_result,
        track: track
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
      $logger&.error "Error streaming track #{track_id}: #{e.message}"
      $logger&.error e.backtrace.join("\n") if SpotikConfig::Settings.app_debug?
      
      {
        status: 500,
        body: { 
          error: 'Failed to stream audio file',
          message: SpotikConfig::Settings.app_debug? ? e.message : 'Internal server error'
        }
      }
    end
  end
  
  private
  
  # Check if queue order changed due to vote score change
  def self.check_queue_order_changed(room, track_id, old_score, new_score)
    return false if old_score == new_score
    
    # Get all tracks in the room with their current scores
    all_tracks = room.tracks.map do |t|
      score = t.id == track_id ? old_score : t.vote_score
      { id: t.id, vote_score: score, created_at: t.created_at }
    end
    
    # Sort by old ordering (vote_score desc, created_at asc)
    old_order = all_tracks.sort do |a, b|
      if a[:vote_score] == b[:vote_score]
        a[:created_at] <=> b[:created_at]
      else
        b[:vote_score] <=> a[:vote_score]
      end
    end
    
    # Update the affected track's score and sort by new ordering
    all_tracks.find { |t| t[:id] == track_id }[:vote_score] = new_score
    new_order = all_tracks.sort do |a, b|
      if a[:vote_score] == b[:vote_score]
        a[:created_at] <=> b[:created_at]
      else
        b[:vote_score] <=> a[:vote_score]
      end
    end
    
    # Check if the order changed
    old_order.map { |t| t[:id] } != new_order.map { |t| t[:id] }
  end
  
  # Format Sequel validation errors to Laravel-compatible format
  def self.format_validation_errors(errors)
    formatted = {}
    
    errors.each do |field, messages|
      formatted[field] = Array(messages).map do |message|
        # Convert Sequel error messages to Laravel-style messages
        case message
        when /is not present/
          "The #{field} field is required."
        when /is longer than \d+ characters/
          "The #{field} field is too long."
        else
          message
        end
      end
    end
    
    formatted
  end
end