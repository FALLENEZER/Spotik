# Room Controller - Handles room management endpoints
# Compatible with Laravel API format
# Uses RoomManager service for comprehensive room management

require 'json'
require_relative '../services/auth_service'
require_relative '../services/room_manager'

class RoomController
  # GET /api/rooms - List all rooms
  def self.index(token = nil)
    begin
      # Authenticate user (optional for listing public rooms)
      current_user = nil
      if token
        auth_data = AuthService.validate_jwt(token)
        current_user = auth_data[:user] if auth_data
      end
      
      # Get all rooms with their basic information
      rooms = Room.all.map do |room|
        room_data = room.to_hash
        
        # Include additional computed fields for compatibility
        room_data[:participant_count] = room.participants.count
        room_data[:track_count] = room.tracks.count
        room_data[:is_user_participant] = current_user ? room.has_participant?(current_user) : false
        room_data[:is_user_administrator] = current_user ? room.administered_by?(current_user) : false
        
        room_data
      end
      
      {
        status: 200,
        body: {
          rooms: rooms,
          total: rooms.length
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
      $logger&.error "Error listing rooms: #{e.message}"
      $logger&.error e.backtrace.join("\n") if SpotikConfig::Settings.app_debug?
      
      {
        status: 500,
        body: { error: 'Failed to retrieve rooms' }
      }
    end
  end
  
  # POST /api/rooms - Create new room
  def self.create(params, token)
    begin
      # Authenticate user
      auth_data = AuthService.validate_jwt(token)
      current_user = auth_data[:user]
      
      # Validate required parameters
      unless params['name'] && !params['name'].strip.empty?
        return {
          status: 422,
          body: {
            error: 'Validation failed',
            errors: {
              name: ['The name field is required.']
            }
          }
        }
      end
      
      # Validate name length (max 100 characters, compatible with Laravel)
      if params['name'].length > 100
        return {
          status: 422,
          body: {
            error: 'Validation failed',
            errors: {
              name: ['The name may not be greater than 100 characters.']
            }
          }
        }
      end
      
      # Create room using RoomManager
      room = RoomManager.create_room(current_user, params)
      
      {
        status: 201,
        body: {
          room: room.to_hash,
          message: 'Room created successfully'
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
    rescue ArgumentError => e
      {
        status: 422,
        body: {
          error: 'Validation failed',
          message: e.message
        }
      }
    rescue Sequel::ValidationFailed => e
      $logger&.warn "Room creation validation failed: #{e.message}"
      
      {
        status: 422,
        body: {
          error: 'Validation failed',
          errors: format_validation_errors(e.errors)
        }
      }
      
    rescue => e
      $logger&.error "Error creating room: #{e.message}"
      $logger&.error e.backtrace.join("\n") if SpotikConfig::Settings.app_debug?
      
      {
        status: 500,
        body: { error: 'Failed to create room' }
      }
    end
  end
  
  # GET /api/rooms/:id - Get room details
  def self.show(room_id, token = nil)
    begin
      # Find room
      room = Room[room_id]
      unless room
        return {
          status: 404,
          body: { error: 'Room not found' }
        }
      end
      
      # Authenticate user (optional for viewing room details)
      current_user = nil
      if token
        auth_data = AuthService.validate_jwt(token)
        current_user = auth_data[:user] if auth_data
      end
      
      # Get comprehensive room state from RoomManager
      room_data = RoomManager.get_room_state(room_id, current_user)
      
      unless room_data
        return {
          status: 404,
          body: { error: 'Room not found' }
        }
      end
      
      {
        status: 200,
        body: { room: room_data }
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
      $logger&.error "Error retrieving room #{room_id}: #{e.message}"
      $logger&.error e.backtrace.join("\n") if SpotikConfig::Settings.app_debug?
      
      {
        status: 500,
        body: { error: 'Failed to retrieve room' }
      }
    end
  end
  
  # POST /api/rooms/:id/join - Join room
  def self.join(room_id, token)
    begin
      # Authenticate user
      auth_data = AuthService.validate_jwt(token)
      current_user = auth_data[:user]
      
      # Use RoomManager to join room
      result = RoomManager.join_room(current_user, room_id)
      
      if result[:success]
        {
          status: 200,
          body: {
            room: result[:room].to_hash,
            message: 'Successfully joined room'
          }
        }
      else
        case result[:error]
        when 'Room not found'
          {
            status: 404,
            body: { error: result[:error] }
          }
        when 'Already a participant in this room'
          {
            status: 409,
            body: { 
              error: 'Already a participant',
              message: result[:error]
            }
          }
        else
          {
            status: 500,
            body: { error: result[:error] }
          }
        end
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
      $logger&.error "Error joining room #{room_id}: #{e.message}"
      $logger&.error e.backtrace.join("\n") if SpotikConfig::Settings.app_debug?
      
      {
        status: 500,
        body: { error: 'Failed to join room' }
      }
    end
  end
  
  # DELETE /api/rooms/:id/leave - Leave room
  def self.leave(room_id, token)
    begin
      # Authenticate user
      auth_data = AuthService.validate_jwt(token)
      current_user = auth_data[:user]
      
      # Use RoomManager to leave room
      result = RoomManager.leave_room(current_user, room_id)
      
      if result[:success]
        {
          status: 200,
          body: {
            room: result[:room].to_hash,
            message: 'Successfully left room'
          }
        }
      else
        case result[:error]
        when 'Room not found'
          {
            status: 404,
            body: { error: result[:error] }
          }
        when 'Not a participant in this room'
          {
            status: 409,
            body: { 
              error: 'Not a participant',
              message: result[:error]
            }
          }
        when 'Administrator cannot leave their own room'
          {
            status: 403,
            body: { 
              error: 'Administrator cannot leave',
              message: result[:error]
            }
          }
        else
          {
            status: 500,
            body: { error: result[:error] }
          }
        end
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
      $logger&.error "Error leaving room #{room_id}: #{e.message}"
      $logger&.error e.backtrace.join("\n") if SpotikConfig::Settings.app_debug?
      
      {
        status: 500,
        body: { error: 'Failed to leave room' }
      }
    end
  end
  
  private
  
  # Format Sequel validation errors to Laravel-compatible format
  def self.format_validation_errors(errors)
    formatted = {}
    
    errors.each do |field, messages|
      formatted[field] = Array(messages).map do |message|
        # Convert Sequel error messages to Laravel-style messages
        case message
        when /is not present/
          "The #{field} field is required."
        when /is longer than 100 characters/
          "The #{field} may not be greater than 100 characters."
        else
          message
        end
      end
    end
    
    formatted
  end
end