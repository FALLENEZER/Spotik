#!/usr/bin/env ruby

# Comprehensive Compatibility Test Suite
# **Feature: ruby-backend-migration, Task 16.1: Create comprehensive compatibility test suite**
# **Validates: Requirements 15.1, 15.2, 15.3, 15.4, 15.5**

require 'bundler/setup'
require 'rspec'
require 'rantly'
require 'rantly/rspec_extensions'
require 'rack/test'
require 'json'
require 'securerandom'
require 'tempfile'
require 'bcrypt'
require 'net/http'
require 'uri'
require 'timeout'

# Set test environment
ENV['APP_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test_jwt_secret_key_for_testing_purposes_only'
ENV['JWT_TTL'] = '60'
ENV['APP_DEBUG'] = 'true'

# Load configuration and database
require_relative '../../config/settings'
require_relative '../../config/test_database'

# Set up the DB constant for testing
Object.send(:remove_const, :DB) if defined?(DB)
DB = SpotikConfig::TestDatabase.connection

# Load models with test database
require_relative '../../app/models/user'
require_relative '../../app/models/room'
require_relative '../../app/models/track'
require_relative '../../app/models/room_participant'
require_relative '../../app/models/track_vote'

# Override the database connection for models
[User, Room, Track, RoomParticipant, TrackVote].each do |model|
  model.dataset = DB[model.table_name]
end

# Finalize associations
Sequel::Model.finalize_associations

# Mock WebSocketConnection for testing
class WebSocketConnection
  @@mock_connections = {}
  @@published_events = []
  
  def self.send_to_user(user_id, message)
    @@published_events << {
      type: :user_message,
      user_id: user_id,
      message: message,
      timestamp: Time.now.to_f
    }
    true
  end
  
  def self.broadcast_to_room(room_id, message)
    @@published_events << {
      type: :room_broadcast,
      room_id: room_id,
      message: message,
      timestamp: Time.now.to_f
    }
    true
  end
  
  def self.get_published_events
    @@published_events
  end
  
  def self.clear_published_events
    @@published_events.clear
  end
  
  def self.connection_stats
    {
      total_connections: @@mock_connections.length,
      authenticated_users: @@mock_connections.keys,
      rooms_with_connections: {}
    }
  end
end

# Load services and controllers
require_relative '../../app/services/auth_service'
require_relative '../../app/services/room_manager'
require_relative '../../app/controllers/auth_controller'
require_relative '../../app/controllers/room_controller'
require_relative '../../app/controllers/track_controller'
require_relative '../../app/controllers/playback_controller'

RSpec.describe 'Comprehensive Compatibility Test Suite', :compatibility do
  include Rack::Test::Methods

  def app
    # Create a test version of the Ruby server
    require 'sinatra/base'
    require 'json'
    
    Class.new(Sinatra::Base) do
      configure do
        set :logging, false
        set :dump_errors, false
        set :show_exceptions, false
        
        # CORS headers for Laravel compatibility
        before do
          headers 'Access-Control-Allow-Origin' => '*'
          headers 'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS'
          headers 'Access-Control-Allow-Headers' => 'Content-Type, Authorization'
        end
        
        options '*' do
          200
        end
      end

      def extract_token_from_request
        auth_header = request.env['HTTP_AUTHORIZATION']
        if auth_header && auth_header.start_with?('Bearer ')
          return auth_header[7..-1]
        end
        params['token']
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
      post '/api/rooms/:room_id/tracks/:track_id/play' do
        content_type :json
        token = extract_token_from_request
        result = PlaybackController.start_track(params[:room_id], params[:track_id], token)
        status result[:status]
        result[:body].to_json
      end

      post '/api/rooms/:room_id/playback/pause' do
        content_type :json
        token = extract_token_from_request
        result = PlaybackController.pause_track(params[:room_id], token)
        status result[:status]
        result[:body].to_json
      end

      post '/api/rooms/:room_id/playback/resume' do
        content_type :json
        token = extract_token_from_request
        result = PlaybackController.resume_track(params[:room_id], token)
        status result[:status]
        result[:body].to_json
      end

      post '/api/rooms/:room_id/playback/skip' do
        content_type :json
        token = extract_token_from_request
        result = PlaybackController.skip_track(params[:room_id], token)
        status result[:status]
        result[:body].to_json
      end

      get '/api/rooms/:room_id/playback/status' do
        content_type :json
        token = extract_token_from_request
        result = PlaybackController.get_playback_status(params[:room_id], token)
        status result[:status]
        result[:body].to_json
      end

      # Time synchronization endpoint (Laravel compatibility)
      get '/api/time' do
        content_type :json
        {
          timestamp: Time.now.iso8601,
          unix_timestamp: Time.now.to_i,
          timezone: 'UTC'
        }.to_json
      end

      # Health check endpoints
      get '/api/ping' do
        content_type :json
        { status: 'ok', timestamp: Time.now.iso8601 }.to_json
      end

      get '/api/health' do
        content_type :json
        {
          status: 'healthy',
          version: '1.0.0',
          environment: 'test',
          database: 'connected',
          timestamp: Time.now.iso8601
        }.to_json
      end

      # Catch-all for undefined routes
      not_found do
        content_type :json
        status 404
        { error: 'Endpoint not found', path: request.path_info }.to_json
      end

      error do |e|
        content_type :json
        status 500
        { error: 'Internal server error', details: e.message }.to_json
      end
    end
  end

  before(:all) do
    @test_db = DB
  end
  
  before(:each) do
    # Clean database before each test
    DB[:track_votes].delete
    DB[:room_participants].delete
    DB[:tracks].delete
    DB[:rooms].delete
    DB[:users].delete
    
    # Clear WebSocket events
    WebSocketConnection.clear_published_events
  end

  describe 'Ruby System vs Legacy_System Behavior Comparison' do
    # **Validates: Requirements 15.1** - System SHALL pass all existing tests Legacy_System
    
    it 'produces identical authentication responses to Laravel system' do
      test_scenarios = [
        {
          name: 'User registration with valid data',
          endpoint: '/api/auth/register',
          method: :post,
          data: {
            username: 'testuser123',
            email: 'test@example.com',
            password: 'password123',
            password_confirmation: 'password123'
          },
          expected_status: 201,
          expected_structure: {
            success: true,
            message: String,
            data: {
              user: { id: String, username: String, email: String, created_at: String },
              token: String,
              token_type: 'bearer',
              expires_in: Integer
            }
          }
        },
        {
          name: 'User login with valid credentials',
          endpoint: '/api/auth/login',
          method: :post,
          setup: -> { create_test_user(username: 'loginuser', email: 'login@example.com', password: 'password123') },
          data: {
            email: 'login@example.com',
            password: 'password123'
          },
          expected_status: 200,
          expected_structure: {
            success: true,
            message: String,
            data: {
              user: { id: String, username: String, email: String, created_at: String },
              token: String,
              token_type: 'bearer',
              expires_in: Integer
            }
          }
        },
        {
          name: 'User login with invalid credentials',
          endpoint: '/api/auth/login',
          method: :post,
          data: {
            email: 'nonexistent@example.com',
            password: 'wrongpassword'
          },
          expected_status: 401,
          expected_structure: {
            success: false,
            message: String,
            error: String
          }
        }
      ]

      test_scenarios.each do |scenario|
        puts "Testing: #{scenario[:name]}"
        
        # Run setup if provided
        scenario[:setup].call if scenario[:setup]
        
        # Make request
        case scenario[:method]
        when :post
          response = post scenario[:endpoint], scenario[:data].to_json, { 'CONTENT_TYPE' => 'application/json' }
        when :get
          response = get scenario[:endpoint]
        end
        
        # Verify status matches Laravel expectations
        expect(last_response.status).to eq(scenario[:expected_status]), 
          "Status mismatch for #{scenario[:name]}: expected #{scenario[:expected_status]}, got #{last_response.status}"
        
        # Verify response structure matches Laravel format
        body = JSON.parse(last_response.body, symbolize_names: true)
        verify_response_structure(body, scenario[:expected_structure], scenario[:name])
        
        # Verify Laravel-compatible headers
        expect(last_response.headers['Content-Type']).to include('application/json')
        expect(last_response.headers['Access-Control-Allow-Origin']).to eq('*')
      end
    end

    it 'produces identical room management responses to Laravel system' do
      # Create test user for room operations
      user = create_test_user(username: 'roomuser', email: 'room@example.com', password: 'password123')
      token = AuthService.generate_jwt(user)
      auth_headers = { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

      room_scenarios = [
        {
          name: 'List all rooms',
          endpoint: '/api/rooms',
          method: :get,
          expected_status: 200,
          expected_structure: {
            rooms: Array,
            total: Integer
          }
        },
        {
          name: 'Create new room',
          endpoint: '/api/rooms',
          method: :post,
          data: { name: 'Test Room' },
          expected_status: 201,
          expected_structure: {
            room: {
              id: String,
              name: String,
              administrator_id: String,
              is_playing: false,
              created_at: String,
              updated_at: String,
              participants: Array,
              track_queue: Array
            },
            message: String
          }
        },
        {
          name: 'Create room with invalid data',
          endpoint: '/api/rooms',
          method: :post,
          data: { name: '' },
          expected_status: 422,
          expected_structure: {
            error: String,
            errors: Hash
          }
        }
      ]

      room_scenarios.each do |scenario|
        puts "Testing: #{scenario[:name]}"
        
        case scenario[:method]
        when :post
          response = post scenario[:endpoint], (scenario[:data] || {}).to_json, 
                          { 'CONTENT_TYPE' => 'application/json' }.merge(auth_headers)
        when :get
          response = get scenario[:endpoint], {}, auth_headers
        end
        
        expect(last_response.status).to eq(scenario[:expected_status])
        
        body = JSON.parse(last_response.body, symbolize_names: true)
        verify_response_structure(body, scenario[:expected_structure], scenario[:name])
      end
    end

    it 'maintains identical error response formats to Laravel system' do
      error_scenarios = [
        {
          name: 'Unauthorized access without token',
          endpoint: '/api/auth/me',
          method: :get,
          expected_status: 401,
          expected_structure: {
            success: false,
            message: String,
            error: String
          }
        },
        {
          name: 'Invalid token format',
          endpoint: '/api/auth/me',
          method: :get,
          headers: { 'HTTP_AUTHORIZATION' => 'Bearer invalid.token.format' },
          expected_status: 401,
          expected_structure: {
            success: false,
            message: String,
            error: String
          }
        },
        {
          name: 'Resource not found',
          endpoint: '/api/rooms/nonexistent-room-id',
          method: :get,
          headers: { 'HTTP_AUTHORIZATION' => "Bearer #{create_valid_token}" },
          expected_status: 404,
          expected_structure: {
            error: String
          }
        }
      ]

      error_scenarios.each do |scenario|
        puts "Testing error case: #{scenario[:name]}"
        
        case scenario[:method]
        when :get
          response = get scenario[:endpoint], {}, scenario[:headers] || {}
        end
        
        expect(last_response.status).to eq(scenario[:expected_status])
        
        body = JSON.parse(last_response.body, symbolize_names: true)
        verify_response_structure(body, scenario[:expected_structure], scenario[:name])
      end
    end
  end

  describe 'WebSocket Event Format Validation' do
    # **Validates: Requirements 15.3** - System SHALL support same WebSocket events and formats
    
    it 'generates WebSocket events in Laravel-compatible format' do
      # Create test data
      user = create_test_user(username: 'wsuser', email: 'ws@example.com', password: 'password123')
      room = create_test_room(user, name: 'WebSocket Test Room')
      
      # Test user activity events
      room.add_participant(user)
      
      # Verify user joined event format
      events = WebSocketConnection.get_published_events
      user_joined_event = events.find { |e| e[:type] == :room_broadcast }
      
      expect(user_joined_event).not_to be_nil
      expect(user_joined_event[:room_id]).to eq(room.id)
      expect(user_joined_event[:message]).to have_key(:type)
      expect(user_joined_event[:message]).to have_key(:data)
      expect(user_joined_event[:message]).to have_key(:timestamp)
      
      # Verify event data structure matches Laravel format
      message_data = user_joined_event[:message][:data]
      expect(message_data).to have_key(:room_id)
      expect(message_data).to have_key(:user)
      expect(message_data[:user]).to have_key(:id)
      expect(message_data[:user]).to have_key(:username)
    end

    it 'validates track-related WebSocket event formats' do
      user = create_test_user(username: 'trackuser', email: 'track@example.com', password: 'password123')
      room = create_test_room(user, name: 'Track Test Room')
      track = create_test_track(user, room)
      
      WebSocketConnection.clear_published_events
      
      # Simulate track addition event
      require_relative '../../app/services/event_broadcaster'
      EventBroadcaster.broadcast_track_activity(room.id, :added, track, user)
      
      events = WebSocketConnection.get_published_events
      track_event = events.find { |e| e[:type] == :room_broadcast }
      
      expect(track_event).not_to be_nil
      
      # Verify Laravel-compatible track event structure
      message_data = track_event[:message][:data]
      expect(message_data).to have_key(:track)
      expect(message_data).to have_key(:uploader)
      expect(message_data).to have_key(:room_id)
      
      track_data = message_data[:track]
      expect(track_data).to have_key(:id)
      expect(track_data).to have_key(:filename)
      expect(track_data).to have_key(:original_name)
      expect(track_data).to have_key(:duration_seconds)
      expect(track_data).to have_key(:vote_score)
    end

    it 'validates playback control WebSocket event formats' do
      user = create_test_user(username: 'playbackuser', email: 'playback@example.com', password: 'password123')
      room = create_test_room(user, name: 'Playback Test Room')
      track = create_test_track(user, room)
      
      WebSocketConnection.clear_published_events
      
      # Simulate playback start event
      require_relative '../../app/services/event_broadcaster'
      EventBroadcaster.broadcast_playback_activity(room.id, :started, user, {
        track: track,
        started_at: Time.now.to_f
      })
      
      events = WebSocketConnection.get_published_events
      playback_event = events.find { |e| e[:type] == :room_broadcast }
      
      expect(playback_event).not_to be_nil
      
      # Verify Laravel-compatible playback event structure
      message_data = playback_event[:message][:data]
      expect(message_data).to have_key(:room_id)
      expect(message_data).to have_key(:is_playing)
      expect(message_data).to have_key(:administrator)
      expect(message_data).to have_key(:server_time)
      
      # Verify timestamp precision for synchronization
      expect(message_data[:server_time]).to be_within(0.1).of(Time.now.to_f)
    end
  end

  describe 'API Endpoint Parity Verification' do
    # **Validates: Requirements 15.2** - System SHALL ensure identical API endpoint behavior
    
    it 'verifies all Laravel API endpoints are implemented with identical behavior' do
      # Define Laravel API endpoints that must be supported
      laravel_endpoints = [
        # Authentication endpoints
        { path: '/api/auth/register', method: :post, auth_required: false },
        { path: '/api/auth/login', method: :post, auth_required: false },
        { path: '/api/auth/me', method: :get, auth_required: true },
        { path: '/api/auth/refresh', method: :post, auth_required: true },
        { path: '/api/auth/logout', method: :post, auth_required: true },
        
        # Room management endpoints
        { path: '/api/rooms', method: :get, auth_required: true },
        { path: '/api/rooms', method: :post, auth_required: true },
        { path: '/api/rooms/:id', method: :get, auth_required: true },
        { path: '/api/rooms/:id/join', method: :post, auth_required: true },
        { path: '/api/rooms/:id/leave', method: :delete, auth_required: true },
        
        # Track management endpoints
        { path: '/api/rooms/:id/tracks', method: :get, auth_required: true },
        { path: '/api/tracks/:id/vote', method: :post, auth_required: true },
        { path: '/api/tracks/:id/vote', method: :delete, auth_required: true },
        
        # Playback control endpoints
        { path: '/api/rooms/:room_id/tracks/:track_id/play', method: :post, auth_required: true },
        { path: '/api/rooms/:room_id/playback/pause', method: :post, auth_required: true },
        { path: '/api/rooms/:room_id/playback/resume', method: :post, auth_required: true },
        { path: '/api/rooms/:room_id/playback/skip', method: :post, auth_required: true },
        { path: '/api/rooms/:room_id/playback/status', method: :get, auth_required: true },
        
        # Utility endpoints
        { path: '/api/time', method: :get, auth_required: false },
        { path: '/api/ping', method: :get, auth_required: false },
        { path: '/api/health', method: :get, auth_required: false }
      ]

      # Create test user and token for authenticated endpoints
      user = create_test_user(username: 'apiuser', email: 'api@example.com', password: 'password123')
      token = AuthService.generate_jwt(user)
      room = create_test_room(user, name: 'API Test Room')
      track = create_test_track(user, room)

      laravel_endpoints.each do |endpoint_spec|
        puts "Verifying endpoint: #{endpoint_spec[:method].upcase} #{endpoint_spec[:path]}"
        
        # Prepare path with actual IDs
        path = endpoint_spec[:path]
          .gsub(':id', room.id)
          .gsub(':room_id', room.id)
          .gsub(':track_id', track.id)
        
        # Prepare headers
        headers = {}
        if endpoint_spec[:auth_required]
          headers['HTTP_AUTHORIZATION'] = "Bearer #{token}"
        end
        
        # Make request
        case endpoint_spec[:method]
        when :get
          response = get path, {}, headers
        when :post
          response = post path, {}.to_json, { 'CONTENT_TYPE' => 'application/json' }.merge(headers)
        when :delete
          response = delete path, {}, headers
        end
        
        # Verify endpoint exists (not 404)
        expect(last_response.status).not_to eq(404), 
          "Endpoint #{endpoint_spec[:method].upcase} #{endpoint_spec[:path]} not implemented"
        
        # Verify proper authentication handling
        if endpoint_spec[:auth_required]
          # Test without auth should return 401
          case endpoint_spec[:method]
          when :get
            unauth_response = get path
          when :post
            unauth_response = post path, {}.to_json, { 'CONTENT_TYPE' => 'application/json' }
          when :delete
            unauth_response = delete path
          end
          
          expect(last_response.status).to eq(401), 
            "Endpoint #{endpoint_spec[:path]} should require authentication"
        end
        
        # Verify response format is JSON
        expect(last_response.headers['Content-Type']).to include('application/json')
      end
    end

    it 'verifies HTTP status codes match Laravel conventions' do
      user = create_test_user(username: 'statususer', email: 'status@example.com', password: 'password123')
      token = AuthService.generate_jwt(user)
      
      status_code_tests = [
        {
          name: 'Successful resource creation',
          request: -> { post '/api/rooms', { name: 'Status Test Room' }.to_json, 
                            { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" } },
          expected_status: 201
        },
        {
          name: 'Successful resource retrieval',
          request: -> { get '/api/rooms', {}, { 'HTTP_AUTHORIZATION' => "Bearer #{token}" } },
          expected_status: 200
        },
        {
          name: 'Validation error',
          request: -> { post '/api/rooms', { name: '' }.to_json, 
                            { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" } },
          expected_status: 422
        },
        {
          name: 'Unauthorized access',
          request: -> { get '/api/auth/me' },
          expected_status: 401
        },
        {
          name: 'Resource not found',
          request: -> { get '/api/rooms/nonexistent', {}, { 'HTTP_AUTHORIZATION' => "Bearer #{token}" } },
          expected_status: 404
        }
      ]

      status_code_tests.each do |test|
        puts "Testing status code: #{test[:name]}"
        test[:request].call
        expect(last_response.status).to eq(test[:expected_status]), 
          "Status code mismatch for #{test[:name]}: expected #{test[:expected_status]}, got #{last_response.status}"
      end
    end
  end

  describe 'Audio Synchronization Accuracy Tests' do
    # **Validates: Requirements 15.4** - System SHALL ensure same audio synchronization accuracy
    
    it 'maintains timestamp precision for synchronized playback' do
      user = create_test_user(username: 'syncuser', email: 'sync@example.com', password: 'password123')
      room = create_test_room(user, name: 'Sync Test Room')
      track = create_test_track(user, room)
      token = AuthService.generate_jwt(user)
      
      # Test playback start timing precision
      start_time = Time.now.to_f
      response = post "/api/rooms/#{room.id}/tracks/#{track.id}/play", {}.to_json,
                      { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
      end_time = Time.now.to_f
      
      expect(last_response.status).to eq(200)
      
      body = JSON.parse(last_response.body, symbolize_names: true)
      
      # Verify timestamp precision (should be within request timeframe)
      expect(body[:started_at]).to be_between(start_time, end_time)
      expect(body[:server_time]).to be_between(start_time, end_time)
      
      # Verify timestamp precision to milliseconds (Laravel compatibility)
      expect(body[:started_at]).to be_within(0.001).of(body[:server_time])
    end

    it 'calculates playback position accurately across pause/resume cycles' do
      user = create_test_user(username: 'positionuser', email: 'position@example.com', password: 'password123')
      room = create_test_room(user, name: 'Position Test Room')
      track = create_test_track(user, room)
      token = AuthService.generate_jwt(user)
      
      # Start playback
      post "/api/rooms/#{room.id}/tracks/#{track.id}/play", {}.to_json,
           { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
      
      expect(last_response.status).to eq(200)
      start_response = JSON.parse(last_response.body, symbolize_names: true)
      
      # Wait a short time
      sleep(0.5)
      
      # Pause playback
      post "/api/rooms/#{room.id}/playback/pause", {}.to_json,
           { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
      
      expect(last_response.status).to eq(200)
      pause_response = JSON.parse(last_response.body, symbolize_names: true)
      
      # Verify position calculation accuracy
      expected_position = pause_response[:paused_at] - start_response[:started_at]
      actual_position = pause_response[:position]
      
      expect(actual_position).to be_within(0.1).of(expected_position)
      
      # Wait while paused (position should not change)
      sleep(0.3)
      
      # Resume playback
      post "/api/rooms/#{room.id}/playback/resume", {}.to_json,
           { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
      
      expect(last_response.status).to eq(200)
      resume_response = JSON.parse(last_response.body, symbolize_names: true)
      
      # Position should be preserved from pause
      expect(resume_response[:position]).to be_within(0.05).of(actual_position)
    end

    it 'provides consistent server time synchronization endpoint' do
      # Test time endpoint multiple times to verify consistency
      time_responses = []
      
      5.times do |i|
        request_start = Time.now.to_f
        get '/api/time'
        request_end = Time.now.to_f
        
        expect(last_response.status).to eq(200)
        
        body = JSON.parse(last_response.body, symbolize_names: true)
        
        # Verify response structure matches Laravel format
        expect(body).to have_key(:timestamp)
        expect(body).to have_key(:unix_timestamp)
        expect(body).to have_key(:timezone)
        
        # Verify timestamp is within request timeframe
        server_time = Time.parse(body[:timestamp]).to_f
        expect(server_time).to be_between(request_start, request_end)
        
        # Verify unix timestamp matches ISO timestamp
        expect(body[:unix_timestamp]).to be_within(1).of(server_time.to_i)
        
        time_responses << {
          server_time: server_time,
          request_time: (request_start + request_end) / 2,
          latency: request_end - request_start
        }
        
        sleep(0.1) if i < 4 # Small delay between requests
      end
      
      # Verify time synchronization consistency
      time_drifts = time_responses.each_cons(2).map do |prev, curr|
        expected_diff = curr[:request_time] - prev[:request_time]
        actual_diff = curr[:server_time] - prev[:server_time]
        (actual_diff - expected_diff).abs
      end
      
      # Time drift should be minimal (server clock should be consistent)
      expect(time_drifts.max).to be < 0.1, "Server time drift too high: #{time_drifts.max}s"
    end
  end

  describe 'Migration Validation Tests' do
    # **Validates: Requirements 15.5** - System SHALL show equivalent or better performance
    
    it 'validates data compatibility with existing Laravel database schema' do
      # Test that Ruby system can work with Laravel-created data structures
      
      # Create user with Laravel-compatible password hash
      laravel_password_hash = BCrypt::Password.create('testpassword')
      user = User.create(
        id: SecureRandom.uuid,
        username: 'laraveluser',
        email: 'laravel@example.com',
        password_hash: laravel_password_hash,
        created_at: Time.now,
        updated_at: Time.now
      )
      
      # Verify Ruby system can authenticate Laravel-created user
      login_response = post '/api/auth/login', {
        email: 'laravel@example.com',
        password: 'testpassword'
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }
      
      expect(last_response.status).to eq(200)
      
      body = JSON.parse(last_response.body, symbolize_names: true)
      expect(body[:success]).to be true
      expect(body[:data][:user][:id]).to eq(user.id)
    end

    it 'validates WebSocket event delivery performance' do
      user = create_test_user(username: 'perfuser', email: 'perf@example.com', password: 'password123')
      room = create_test_room(user, name: 'Performance Test Room')
      
      WebSocketConnection.clear_published_events
      
      # Measure event broadcasting performance
      start_time = Time.now.to_f
      
      # Simulate multiple rapid events
      10.times do |i|
        room.add_participant(create_test_user(username: "user#{i}", email: "user#{i}@example.com", password: 'password123'))
      end
      
      end_time = Time.now.to_f
      
      events = WebSocketConnection.get_published_events
      
      # Verify all events were published
      expect(events.length).to be >= 10
      
      # Verify event delivery timing (should be fast)
      total_time = end_time - start_time
      expect(total_time).to be < 1.0, "Event broadcasting too slow: #{total_time}s for 10 events"
      
      # Verify event timestamps are in correct order
      event_times = events.map { |e| e[:timestamp] }
      expect(event_times).to eq(event_times.sort), "Events not delivered in chronological order"
    end

    it 'validates cross-system integration compatibility' do
      # Test that Ruby system responses can be consumed by Laravel-compatible clients
      
      user = create_test_user(username: 'integrationuser', email: 'integration@example.com', password: 'password123')
      token = AuthService.generate_jwt(user)
      
      # Test room creation response format
      room_response = post '/api/rooms', { name: 'Integration Test Room' }.to_json,
                           { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
      
      expect(last_response.status).to eq(201)
      
      room_body = JSON.parse(last_response.body, symbolize_names: true)
      
      # Verify response can be processed by Laravel-compatible client
      expect(room_body[:room]).to have_key(:id)
      expect(room_body[:room]).to have_key(:name)
      expect(room_body[:room]).to have_key(:administrator_id)
      expect(room_body[:room]).to have_key(:participants)
      expect(room_body[:room]).to have_key(:track_queue)
      
      # Verify date formats are Laravel-compatible (ISO 8601)
      expect(room_body[:room][:created_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      expect(room_body[:room][:updated_at]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      
      # Test that created room can be retrieved with same format
      room_id = room_body[:room][:id]
      get_response = get "/api/rooms/#{room_id}", {}, { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
      
      expect(last_response.status).to eq(200)
      
      get_body = JSON.parse(last_response.body, symbolize_names: true)
      
      # Verify consistency between create and get responses
      expect(get_body[:room][:id]).to eq(room_body[:room][:id])
      expect(get_body[:room][:name]).to eq(room_body[:room][:name])
      expect(get_body[:room][:administrator_id]).to eq(room_body[:room][:administrator_id])
    end
  end

  # Helper methods for test data generation and verification

  def create_test_user(username: nil, email: nil, password: 'password123')
    username ||= "user_#{SecureRandom.hex(6)}"
    email ||= "#{username}@example.com"
    
    User.create(
      id: SecureRandom.uuid,
      username: username,
      email: email.downcase.strip,
      password_hash: BCrypt::Password.create(password),
      created_at: Time.now,
      updated_at: Time.now
    )
  end

  def create_test_room(user, name: nil)
    name ||= "Room #{SecureRandom.hex(4)}"
    
    room = Room.create(
      id: SecureRandom.uuid,
      name: name,
      administrator_id: user.id,
      is_playing: false,
      created_at: Time.now,
      updated_at: Time.now
    )
    
    # Add creator as participant
    room.add_participant(user)
    room
  end

  def create_test_track(user, room)
    Track.create(
      id: SecureRandom.uuid,
      room_id: room.id,
      uploader_id: user.id,
      filename: "track_#{SecureRandom.hex(8)}.mp3",
      original_name: "Test Track #{SecureRandom.hex(4)}.mp3",
      file_path: "/tmp/test_track.mp3",
      duration_seconds: rand(120..300),
      file_size_bytes: rand(1000000..5000000),
      mime_type: 'audio/mpeg',
      vote_score: 0,
      created_at: Time.now,
      updated_at: Time.now
    )
  end

  def create_valid_token
    user = create_test_user
    AuthService.generate_jwt(user)
  end

  def verify_response_structure(actual, expected, test_name)
    case expected
    when Hash
      expect(actual).to be_a(Hash), "Expected Hash for #{test_name}, got #{actual.class}"
      expected.each do |key, expected_value|
        expect(actual).to have_key(key), "Missing key #{key} in #{test_name}"
        verify_response_structure(actual[key], expected_value, "#{test_name}.#{key}")
      end
    when Array
      expect(actual).to be_a(Array), "Expected Array for #{test_name}, got #{actual.class}"
    when Class
      expect(actual).to be_a(expected), "Expected #{expected} for #{test_name}, got #{actual.class}"
    else
      expect(actual).to eq(expected), "Expected #{expected} for #{test_name}, got #{actual}"
    end
  end
end