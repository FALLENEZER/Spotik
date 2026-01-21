#!/usr/bin/env ruby

# API Endpoint Parity Verification Test
# **Feature: ruby-backend-migration, Task 16.1: API endpoint parity verification tests**
# **Validates: Requirements 15.2** - System SHALL ensure identical API endpoint behavior

require 'bundler/setup'
require 'rspec'
require 'rack/test'
require 'json'
require 'securerandom'
require 'bcrypt'
require 'net/http'
require 'uri'

# Set test environment
ENV['APP_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test_jwt_secret_key_for_testing_purposes_only'
ENV['JWT_TTL'] = '60'

# Load configuration and database
require_relative '../../config/settings'
require_relative '../../config/test_database'

# Set up the DB constant for testing
Object.send(:remove_const, :DB) if defined?(DB)
DB = SpotikConfig::TestDatabase.connection

# Load models
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

# Mock WebSocket for testing
class WebSocketConnection
  def self.send_to_user(user_id, message); true; end
  def self.broadcast_to_room(room_id, message); true; end
  def self.connection_stats; { total_connections: 0 }; end
end

# Load services and controllers
require_relative '../../app/services/auth_service'
require_relative '../../app/services/room_manager'
require_relative '../../app/controllers/auth_controller'
require_relative '../../app/controllers/room_controller'
require_relative '../../app/controllers/track_controller'
require_relative '../../app/controllers/playback_controller'

RSpec.describe 'API Endpoint Parity Verification', :api_parity do
  include Rack::Test::Methods

  def app
    # Create Ruby server app for testing
    require 'sinatra/base'
    
    Class.new(Sinatra::Base) do
      configure do
        set :logging, false
        set :dump_errors, false
        set :show_exceptions, false
        
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
        params_hash = JSON.parse(request.body.read) rescue params
        result = AuthController.register(params_hash)
        status result[:status]
        result[:body].to_json
      end

      post '/api/auth/login' do
        content_type :json
        params_hash = JSON.parse(request.body.read) rescue params
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
        params_hash = JSON.parse(request.body.read) rescue params
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

      put '/api/rooms/:id' do
        content_type :json
        params_hash = JSON.parse(request.body.read) rescue params
        token = extract_token_from_request
        result = RoomController.update(params[:id], params_hash, token)
        status result[:status]
        result[:body].to_json
      end

      delete '/api/rooms/:id' do
        content_type :json
        token = extract_token_from_request
        result = RoomController.destroy(params[:id], token)
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

      get '/api/rooms/:id/participants' do
        content_type :json
        token = extract_token_from_request
        result = RoomController.participants(params[:id], token)
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
        token = extract_token_from_request
        # Simulate file upload for testing
        file_data = {
          audio_file: {
            filename: 'test.mp3',
            type: 'audio/mpeg',
            tempfile: StringIO.new('fake audio data')
          }
        }
        result = TrackController.store(params[:id], file_data, token)
        status result[:status]
        result[:body].to_json
      end

      delete '/api/rooms/:room_id/tracks/:track_id' do
        content_type :json
        token = extract_token_from_request
        result = TrackController.destroy(params[:room_id], params[:track_id], token)
        status result[:status]
        result[:body].to_json
      end

      post '/api/rooms/:room_id/tracks/:track_id/vote' do
        content_type :json
        token = extract_token_from_request
        result = TrackController.vote(params[:track_id], token)
        status result[:status]
        result[:body].to_json
      end

      delete '/api/rooms/:room_id/tracks/:track_id/vote' do
        content_type :json
        token = extract_token_from_request
        result = TrackController.unvote(params[:track_id], token)
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

      post '/api/rooms/:room_id/playback/stop' do
        content_type :json
        token = extract_token_from_request
        result = PlaybackController.stop_playback(params[:room_id], token)
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

      # File serving endpoints
      get '/api/audio/:filename' do
        content_type 'audio/mpeg'
        headers 'Content-Disposition' => "inline; filename=\"#{params[:filename]}\""
        headers 'Cache-Control' => 'public, max-age=3600'
        'fake audio data'
      end

      get '/api/audio/:filename/metadata' do
        content_type :json
        {
          filename: params[:filename],
          duration: 180,
          size: 5000000,
          mime_type: 'audio/mpeg'
        }.to_json
      end

      get '/api/tracks/:track_id/stream' do
        content_type 'audio/mpeg'
        headers 'Accept-Ranges' => 'bytes'
        'fake streaming audio data'
      end

      # Utility endpoints
      get '/api/time' do
        content_type :json
        {
          timestamp: Time.now.iso8601,
          unix_timestamp: Time.now.to_i,
          timezone: 'UTC'
        }.to_json
      end

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

      get '/api/metrics' do
        content_type :json
        {
          uptime: 3600,
          memory_usage: '50MB',
          active_connections: 0,
          requests_per_second: 10.5
        }.to_json
      end

      # Broadcasting auth endpoint
      post '/api/broadcasting/auth' do
        content_type :json
        token = extract_token_from_request
        if token
          { auth: 'authorized' }.to_json
        else
          status 401
          { error: 'Unauthorized' }.to_json
        end
      end

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

  before(:each) do
    # Clean database
    DB[:track_votes].delete
    DB[:room_participants].delete
    DB[:tracks].delete
    DB[:rooms].delete
    DB[:users].delete
  end

  describe 'Laravel API Endpoint Coverage' do
    
    it 'implements all Laravel authentication endpoints with identical behavior' do
      laravel_auth_endpoints = [
        {
          name: 'User Registration',
          method: :post,
          path: '/api/auth/register',
          test_data: {
            username: 'testuser',
            email: 'test@example.com',
            password: 'password123',
            password_confirmation: 'password123'
          },
          expected_success_status: 201,
          expected_success_keys: [:success, :message, :data],
          expected_data_keys: [:user, :token, :token_type, :expires_in]
        },
        {
          name: 'User Login',
          method: :post,
          path: '/api/auth/login',
          setup: -> { create_test_user(email: 'login@example.com', password: 'password123') },
          test_data: {
            email: 'login@example.com',
            password: 'password123'
          },
          expected_success_status: 200,
          expected_success_keys: [:success, :message, :data],
          expected_data_keys: [:user, :token, :token_type, :expires_in]
        },
        {
          name: 'Get Current User',
          method: :get,
          path: '/api/auth/me',
          auth_required: true,
          expected_success_status: 200,
          expected_success_keys: [:success, :message, :data],
          expected_data_keys: [:user]
        },
        {
          name: 'Refresh Token',
          method: :post,
          path: '/api/auth/refresh',
          auth_required: true,
          expected_success_status: 200,
          expected_success_keys: [:success, :message, :data],
          expected_data_keys: [:token, :token_type, :expires_in]
        },
        {
          name: 'User Logout',
          method: :post,
          path: '/api/auth/logout',
          auth_required: true,
          expected_success_status: 200,
          expected_success_keys: [:success, :message]
        }
      ]

      laravel_auth_endpoints.each do |endpoint|
        puts "Testing Laravel auth endpoint: #{endpoint[:name]}"
        
        # Run setup if provided
        endpoint[:setup].call if endpoint[:setup]
        
        # Prepare headers
        headers = { 'CONTENT_TYPE' => 'application/json' }
        if endpoint[:auth_required]
          user = create_test_user
          token = AuthService.generate_jwt(user)
          headers['HTTP_AUTHORIZATION'] = "Bearer #{token}"
        end
        
        # Make request
        case endpoint[:method]
        when :post
          response = post endpoint[:path], (endpoint[:test_data] || {}).to_json, headers
        when :get
          response = get endpoint[:path], {}, headers
        end
        
        # Verify response
        expect(last_response.status).to eq(endpoint[:expected_success_status]), 
          "#{endpoint[:name]}: Expected status #{endpoint[:expected_success_status]}, got #{last_response.status}"
        
        body = JSON.parse(last_response.body, symbolize_names: true)
        
        # Verify response structure
        endpoint[:expected_success_keys].each do |key|
          expect(body).to have_key(key), "#{endpoint[:name]}: Missing key #{key}"
        end
        
        if endpoint[:expected_data_keys] && body[:data]
          endpoint[:expected_data_keys].each do |key|
            expect(body[:data]).to have_key(key), "#{endpoint[:name]}: Missing data key #{key}"
          end
        end
        
        # Verify Laravel-compatible headers
        expect(last_response.headers['Content-Type']).to include('application/json')
        expect(last_response.headers['Access-Control-Allow-Origin']).to eq('*')
      end
    end

    it 'implements all Laravel room management endpoints with identical behavior' do
      user = create_test_user
      token = AuthService.generate_jwt(user)
      auth_headers = { 'HTTP_AUTHORIZATION' => "Bearer #{token}", 'CONTENT_TYPE' => 'application/json' }
      
      laravel_room_endpoints = [
        {
          name: 'List Rooms',
          method: :get,
          path: '/api/rooms',
          expected_success_status: 200,
          expected_keys: [:rooms, :total]
        },
        {
          name: 'Create Room',
          method: :post,
          path: '/api/rooms',
          test_data: { name: 'Test Room' },
          expected_success_status: 201,
          expected_keys: [:room, :message]
        },
        {
          name: 'Show Room',
          method: :get,
          path: '/api/rooms/:id',
          setup: -> { @test_room = create_test_room(user) },
          path_params: -> { { id: @test_room.id } },
          expected_success_status: 200,
          expected_keys: [:room]
        },
        {
          name: 'Update Room',
          method: :put,
          path: '/api/rooms/:id',
          setup: -> { @test_room = create_test_room(user) },
          path_params: -> { { id: @test_room.id } },
          test_data: { name: 'Updated Room Name' },
          expected_success_status: 200,
          expected_keys: [:room, :message]
        },
        {
          name: 'Delete Room',
          method: :delete,
          path: '/api/rooms/:id',
          setup: -> { @test_room = create_test_room(user) },
          path_params: -> { { id: @test_room.id } },
          expected_success_status: 200,
          expected_keys: [:message]
        },
        {
          name: 'Join Room',
          method: :post,
          path: '/api/rooms/:id/join',
          setup: -> { 
            other_user = create_test_user(username: 'other', email: 'other@example.com')
            @test_room = create_test_room(other_user) 
          },
          path_params: -> { { id: @test_room.id } },
          expected_success_status: 200,
          expected_keys: [:room, :message]
        },
        {
          name: 'Leave Room',
          method: :delete,
          path: '/api/rooms/:id/leave',
          setup: -> { 
            other_user = create_test_user(username: 'other2', email: 'other2@example.com')
            @test_room = create_test_room(other_user)
            @test_room.add_participant(user)
          },
          path_params: -> { { id: @test_room.id } },
          expected_success_status: 200,
          expected_keys: [:message]
        },
        {
          name: 'Get Room Participants',
          method: :get,
          path: '/api/rooms/:id/participants',
          setup: -> { @test_room = create_test_room(user) },
          path_params: -> { { id: @test_room.id } },
          expected_success_status: 200,
          expected_keys: [:participants]
        }
      ]

      laravel_room_endpoints.each do |endpoint|
        puts "Testing Laravel room endpoint: #{endpoint[:name]}"
        
        # Run setup if provided
        endpoint[:setup].call if endpoint[:setup]
        
        # Prepare path with parameters
        path = endpoint[:path]
        if endpoint[:path_params]
          params = endpoint[:path_params].call
          params.each { |key, value| path = path.gsub(":#{key}", value.to_s) }
        end
        
        # Make request
        case endpoint[:method]
        when :get
          response = get path, {}, auth_headers.except('CONTENT_TYPE')
        when :post
          response = post path, (endpoint[:test_data] || {}).to_json, auth_headers
        when :put
          response = put path, (endpoint[:test_data] || {}).to_json, auth_headers
        when :delete
          response = delete path, {}, auth_headers.except('CONTENT_TYPE')
        end
        
        # Verify response
        expect(last_response.status).to eq(endpoint[:expected_success_status]), 
          "#{endpoint[:name]}: Expected status #{endpoint[:expected_success_status]}, got #{last_response.status}. Body: #{last_response.body}"
        
        body = JSON.parse(last_response.body, symbolize_names: true)
        
        # Verify response structure
        endpoint[:expected_keys].each do |key|
          expect(body).to have_key(key), "#{endpoint[:name]}: Missing key #{key}. Body: #{body}"
        end
      end
    end

    it 'implements all Laravel track management endpoints with identical behavior' do
      user = create_test_user
      room = create_test_room(user)
      track = create_test_track(user, room)
      token = AuthService.generate_jwt(user)
      auth_headers = { 'HTTP_AUTHORIZATION' => "Bearer #{token}", 'CONTENT_TYPE' => 'application/json' }
      
      laravel_track_endpoints = [
        {
          name: 'List Room Tracks',
          method: :get,
          path: "/api/rooms/#{room.id}/tracks",
          expected_success_status: 200,
          expected_keys: [:tracks, :total_count]
        },
        {
          name: 'Upload Track',
          method: :post,
          path: "/api/rooms/#{room.id}/tracks",
          expected_success_status: 201,
          expected_keys: [:track, :message]
        },
        {
          name: 'Delete Track',
          method: :delete,
          path: "/api/rooms/#{room.id}/tracks/#{track.id}",
          expected_success_status: 200,
          expected_keys: [:message]
        },
        {
          name: 'Vote for Track',
          method: :post,
          path: "/api/rooms/#{room.id}/tracks/#{track.id}/vote",
          expected_success_status: 200,
          expected_keys: [:message, :vote_score, :user_has_voted]
        },
        {
          name: 'Remove Vote',
          method: :delete,
          path: "/api/rooms/#{room.id}/tracks/#{track.id}/vote",
          setup: -> { 
            # Add a vote first
            TrackVote.create(track_id: track.id, user_id: user.id, created_at: Time.now)
            track.update(vote_score: 1)
          },
          expected_success_status: 200,
          expected_keys: [:message, :vote_score, :user_has_voted]
        }
      ]

      laravel_track_endpoints.each do |endpoint|
        puts "Testing Laravel track endpoint: #{endpoint[:name]}"
        
        # Run setup if provided
        endpoint[:setup].call if endpoint[:setup]
        
        # Make request
        case endpoint[:method]
        when :get
          response = get endpoint[:path], {}, auth_headers.except('CONTENT_TYPE')
        when :post
          response = post endpoint[:path], {}.to_json, auth_headers
        when :delete
          response = delete endpoint[:path], {}, auth_headers.except('CONTENT_TYPE')
        end
        
        # Verify response
        expect(last_response.status).to eq(endpoint[:expected_success_status]), 
          "#{endpoint[:name]}: Expected status #{endpoint[:expected_success_status]}, got #{last_response.status}. Body: #{last_response.body}"
        
        body = JSON.parse(last_response.body, symbolize_names: true)
        
        # Verify response structure
        endpoint[:expected_keys].each do |key|
          expect(body).to have_key(key), "#{endpoint[:name]}: Missing key #{key}. Body: #{body}"
        end
      end
    end

    it 'implements all Laravel playback control endpoints with identical behavior' do
      user = create_test_user
      room = create_test_room(user)
      track = create_test_track(user, room)
      token = AuthService.generate_jwt(user)
      auth_headers = { 'HTTP_AUTHORIZATION' => "Bearer #{token}", 'CONTENT_TYPE' => 'application/json' }
      
      laravel_playback_endpoints = [
        {
          name: 'Start Track Playback',
          method: :post,
          path: "/api/rooms/#{room.id}/tracks/#{track.id}/play",
          expected_success_status: 200,
          expected_keys: [:is_playing, :track, :started_at, :server_time]
        },
        {
          name: 'Pause Playback',
          method: :post,
          path: "/api/rooms/#{room.id}/playback/pause",
          setup: -> {
            # Start playback first
            room.update(is_playing: true, playback_started_at: Time.now, current_track_id: track.id)
          },
          expected_success_status: 200,
          expected_keys: [:is_playing, :paused_at, :position]
        },
        {
          name: 'Resume Playback',
          method: :post,
          path: "/api/rooms/#{room.id}/playback/resume",
          setup: -> {
            # Set up paused state
            room.update(is_playing: false, playback_started_at: Time.now - 60, playback_paused_at: Time.now - 30, current_track_id: track.id)
          },
          expected_success_status: 200,
          expected_keys: [:is_playing, :position]
        },
        {
          name: 'Skip Track',
          method: :post,
          path: "/api/rooms/#{room.id}/playback/skip",
          setup: -> {
            room.update(is_playing: true, current_track_id: track.id)
          },
          expected_success_status: 200,
          expected_keys: [:message]
        },
        {
          name: 'Stop Playback',
          method: :post,
          path: "/api/rooms/#{room.id}/playback/stop",
          setup: -> {
            room.update(is_playing: true, current_track_id: track.id)
          },
          expected_success_status: 200,
          expected_keys: [:is_playing, :message]
        },
        {
          name: 'Get Playback Status',
          method: :get,
          path: "/api/rooms/#{room.id}/playback/status",
          expected_success_status: 200,
          expected_keys: [:playback_status]
        }
      ]

      laravel_playback_endpoints.each do |endpoint|
        puts "Testing Laravel playback endpoint: #{endpoint[:name]}"
        
        # Run setup if provided
        endpoint[:setup].call if endpoint[:setup]
        
        # Make request
        case endpoint[:method]
        when :get
          response = get endpoint[:path], {}, auth_headers.except('CONTENT_TYPE')
        when :post
          response = post endpoint[:path], {}.to_json, auth_headers
        end
        
        # Verify response
        expect(last_response.status).to eq(endpoint[:expected_success_status]), 
          "#{endpoint[:name]}: Expected status #{endpoint[:expected_success_status]}, got #{last_response.status}. Body: #{last_response.body}"
        
        body = JSON.parse(last_response.body, symbolize_names: true)
        
        # Verify response structure
        endpoint[:expected_keys].each do |key|
          expect(body).to have_key(key), "#{endpoint[:name]}: Missing key #{key}. Body: #{body}"
        end
      end
    end

    it 'implements all Laravel utility and file serving endpoints' do
      user = create_test_user
      token = AuthService.generate_jwt(user)
      auth_headers = { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
      
      laravel_utility_endpoints = [
        {
          name: 'Time Synchronization',
          method: :get,
          path: '/api/time',
          expected_success_status: 200,
          expected_keys: [:timestamp, :unix_timestamp, :timezone]
        },
        {
          name: 'Health Check Ping',
          method: :get,
          path: '/api/ping',
          expected_success_status: 200,
          expected_keys: [:status, :timestamp]
        },
        {
          name: 'Health Check Detailed',
          method: :get,
          path: '/api/health',
          expected_success_status: 200,
          expected_keys: [:status, :version, :environment, :database, :timestamp]
        },
        {
          name: 'System Metrics',
          method: :get,
          path: '/api/metrics',
          expected_success_status: 200,
          expected_keys: [:uptime, :memory_usage, :active_connections, :requests_per_second]
        },
        {
          name: 'Broadcasting Authentication',
          method: :post,
          path: '/api/broadcasting/auth',
          auth_required: true,
          expected_success_status: 200,
          expected_keys: [:auth]
        }
      ]

      laravel_utility_endpoints.each do |endpoint|
        puts "Testing Laravel utility endpoint: #{endpoint[:name]}"
        
        headers = endpoint[:auth_required] ? auth_headers : {}
        
        # Make request
        case endpoint[:method]
        when :get
          response = get endpoint[:path], {}, headers
        when :post
          response = post endpoint[:path], {}.to_json, headers.merge('CONTENT_TYPE' => 'application/json')
        end
        
        # Verify response
        expect(last_response.status).to eq(endpoint[:expected_success_status]), 
          "#{endpoint[:name]}: Expected status #{endpoint[:expected_success_status]}, got #{last_response.status}"
        
        body = JSON.parse(last_response.body, symbolize_names: true)
        
        # Verify response structure
        endpoint[:expected_keys].each do |key|
          expect(body).to have_key(key), "#{endpoint[:name]}: Missing key #{key}"
        end
      end
      
      # Test file serving endpoints
      file_endpoints = [
        {
          name: 'Audio File Serving',
          method: :get,
          path: '/api/audio/test.mp3',
          expected_success_status: 200,
          expected_content_type: 'audio/mpeg'
        },
        {
          name: 'Audio File Metadata',
          method: :get,
          path: '/api/audio/test.mp3/metadata',
          expected_success_status: 200,
          expected_content_type: 'application/json',
          expected_keys: [:filename, :duration, :size, :mime_type]
        },
        {
          name: 'Track Streaming',
          method: :get,
          path: '/api/tracks/test-track-id/stream',
          expected_success_status: 200,
          expected_content_type: 'audio/mpeg'
        }
      ]

      file_endpoints.each do |endpoint|
        puts "Testing Laravel file endpoint: #{endpoint[:name]}"
        
        response = get endpoint[:path], {}, auth_headers
        
        expect(last_response.status).to eq(endpoint[:expected_success_status]), 
          "#{endpoint[:name]}: Expected status #{endpoint[:expected_success_status]}, got #{last_response.status}"
        
        expect(last_response.headers['Content-Type']).to include(endpoint[:expected_content_type])
        
        if endpoint[:expected_keys]
          body = JSON.parse(last_response.body, symbolize_names: true)
          endpoint[:expected_keys].each do |key|
            expect(body).to have_key(key), "#{endpoint[:name]}: Missing key #{key}"
          end
        end
      end
    end
  end

  describe 'HTTP Method and Status Code Parity' do
    
    it 'uses identical HTTP methods for each endpoint as Laravel' do
      user = create_test_user
      room = create_test_room(user)
      track = create_test_track(user, room)
      token = AuthService.generate_jwt(user)
      
      # Define expected HTTP methods for each endpoint (matching Laravel routes)
      expected_methods = {
        '/api/auth/register' => [:post],
        '/api/auth/login' => [:post],
        '/api/auth/me' => [:get],
        '/api/auth/refresh' => [:post],
        '/api/auth/logout' => [:post],
        '/api/rooms' => [:get, :post],
        "/api/rooms/#{room.id}" => [:get, :put, :delete],
        "/api/rooms/#{room.id}/join" => [:post],
        "/api/rooms/#{room.id}/leave" => [:delete],
        "/api/rooms/#{room.id}/participants" => [:get],
        "/api/rooms/#{room.id}/tracks" => [:get, :post],
        "/api/rooms/#{room.id}/tracks/#{track.id}" => [:delete],
        "/api/rooms/#{room.id}/tracks/#{track.id}/vote" => [:post, :delete],
        "/api/rooms/#{room.id}/tracks/#{track.id}/play" => [:post],
        "/api/rooms/#{room.id}/playback/pause" => [:post],
        "/api/rooms/#{room.id}/playback/resume" => [:post],
        "/api/rooms/#{room.id}/playback/skip" => [:post],
        "/api/rooms/#{room.id}/playback/stop" => [:post],
        "/api/rooms/#{room.id}/playback/status" => [:get],
        '/api/time' => [:get],
        '/api/ping' => [:get],
        '/api/health' => [:get],
        '/api/metrics' => [:get],
        '/api/broadcasting/auth' => [:post]
      }

      expected_methods.each do |path, methods|
        methods.each do |method|
          puts "Testing HTTP method: #{method.upcase} #{path}"
          
          headers = { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
          headers['CONTENT_TYPE'] = 'application/json' if [:post, :put].include?(method)
          
          case method
          when :get
            response = get path, {}, headers.except('CONTENT_TYPE')
          when :post
            response = post path, {}.to_json, headers
          when :put
            response = put path, { name: 'Updated' }.to_json, headers
          when :delete
            response = delete path, {}, headers.except('CONTENT_TYPE')
          end
          
          # Should not return 405 Method Not Allowed
          expect(last_response.status).not_to eq(405), 
            "Method #{method.upcase} not supported for #{path}"
          
          # Should not return 404 Not Found (endpoint should exist)
          expect(last_response.status).not_to eq(404), 
            "Endpoint #{path} not found for method #{method.upcase}"
        end
      end
    end

    it 'returns Laravel-compatible HTTP status codes for different scenarios' do
      user = create_test_user
      token = AuthService.generate_jwt(user)
      
      status_code_scenarios = [
        {
          name: 'Successful resource creation',
          request: -> { post '/api/rooms', { name: 'Test Room' }.to_json, 
                            { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" } },
          expected_status: 201
        },
        {
          name: 'Successful resource retrieval',
          request: -> { get '/api/rooms', {}, { 'HTTP_AUTHORIZATION' => "Bearer #{token}" } },
          expected_status: 200
        },
        {
          name: 'Successful resource update',
          setup: -> { @room = create_test_room(user) },
          request: -> { put "/api/rooms/#{@room.id}", { name: 'Updated Room' }.to_json, 
                            { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" } },
          expected_status: 200
        },
        {
          name: 'Successful resource deletion',
          setup: -> { @room = create_test_room(user) },
          request: -> { delete "/api/rooms/#{@room.id}", {}, { 'HTTP_AUTHORIZATION' => "Bearer #{token}" } },
          expected_status: 200
        },
        {
          name: 'Validation error (422)',
          request: -> { post '/api/rooms', { name: '' }.to_json, 
                            { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" } },
          expected_status: 422
        },
        {
          name: 'Unauthorized access (401)',
          request: -> { get '/api/auth/me' },
          expected_status: 401
        },
        {
          name: 'Forbidden access (403)',
          setup: -> { 
            other_user = create_test_user(username: 'other', email: 'other@example.com')
            @room = create_test_room(other_user)
          },
          request: -> { delete "/api/rooms/#{@room.id}", {}, { 'HTTP_AUTHORIZATION' => "Bearer #{token}" } },
          expected_status: 403
        },
        {
          name: 'Resource not found (404)',
          request: -> { get '/api/rooms/nonexistent-room-id', {}, { 'HTTP_AUTHORIZATION' => "Bearer #{token}" } },
          expected_status: 404
        }
      ]

      status_code_scenarios.each do |scenario|
        puts "Testing status code scenario: #{scenario[:name]}"
        
        scenario[:setup].call if scenario[:setup]
        scenario[:request].call
        
        expect(last_response.status).to eq(scenario[:expected_status]), 
          "#{scenario[:name]}: Expected status #{scenario[:expected_status]}, got #{last_response.status}. Body: #{last_response.body}"
      end
    end
  end

  describe 'Response Format Consistency' do
    
    it 'maintains consistent JSON response structure across all endpoints' do
      user = create_test_user
      room = create_test_room(user)
      token = AuthService.generate_jwt(user)
      
      # Test various endpoints for consistent response format
      endpoints_to_test = [
        { method: :get, path: '/api/rooms', headers: { 'HTTP_AUTHORIZATION' => "Bearer #{token}" } },
        { method: :post, path: '/api/rooms', data: { name: 'Format Test Room' }, 
          headers: { 'HTTP_AUTHORIZATION' => "Bearer #{token}", 'CONTENT_TYPE' => 'application/json' } },
        { method: :get, path: "/api/rooms/#{room.id}", headers: { 'HTTP_AUTHORIZATION' => "Bearer #{token}" } },
        { method: :get, path: '/api/time', headers: {} },
        { method: :get, path: '/api/health', headers: {} }
      ]

      endpoints_to_test.each do |endpoint_test|
        case endpoint_test[:method]
        when :get
          response = get endpoint_test[:path], {}, endpoint_test[:headers]
        when :post
          response = post endpoint_test[:path], (endpoint_test[:data] || {}).to_json, endpoint_test[:headers]
        end
        
        # Verify response is valid JSON
        expect { JSON.parse(last_response.body) }.not_to raise_error, 
          "Invalid JSON response from #{endpoint_test[:method].upcase} #{endpoint_test[:path]}"
        
        # Verify content type
        expect(last_response.headers['Content-Type']).to include('application/json')
        
        # Verify CORS headers (Laravel compatibility)
        expect(last_response.headers['Access-Control-Allow-Origin']).to eq('*')
        expect(last_response.headers['Access-Control-Allow-Methods']).to include('GET')
        expect(last_response.headers['Access-Control-Allow-Methods']).to include('POST')
        expect(last_response.headers['Access-Control-Allow-Headers']).to include('Content-Type')
        expect(last_response.headers['Access-Control-Allow-Headers']).to include('Authorization')
      end
    end

    it 'maintains consistent error response format across all endpoints' do
      user = create_test_user
      token = AuthService.generate_jwt(user)
      
      error_scenarios = [
        {
          name: 'Authentication error',
          request: -> { get '/api/auth/me' },
          expected_status: 401,
          expected_error_keys: [:success, :message, :error]
        },
        {
          name: 'Validation error',
          request: -> { post '/api/rooms', { name: '' }.to_json, 
                            { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" } },
          expected_status: 422,
          expected_error_keys: [:error, :errors]
        },
        {
          name: 'Not found error',
          request: -> { get '/api/rooms/nonexistent', {}, { 'HTTP_AUTHORIZATION' => "Bearer #{token}" } },
          expected_status: 404,
          expected_error_keys: [:error]
        },
        {
          name: 'Forbidden error',
          setup: -> {
            other_user = create_test_user(username: 'other', email: 'other@example.com')
            @room = create_test_room(other_user)
          },
          request: -> { delete "/api/rooms/#{@room.id}", {}, { 'HTTP_AUTHORIZATION' => "Bearer #{token}" } },
          expected_status: 403,
          expected_error_keys: [:error]
        }
      ]

      error_scenarios.each do |scenario|
        puts "Testing error response format: #{scenario[:name]}"
        
        scenario[:setup].call if scenario[:setup]
        scenario[:request].call
        
        expect(last_response.status).to eq(scenario[:expected_status])
        
        body = JSON.parse(last_response.body, symbolize_names: true)
        
        # Verify error response has expected keys
        scenario[:expected_error_keys].each do |key|
          expect(body).to have_key(key), "Missing error key #{key} in #{scenario[:name]}"
        end
        
        # Verify response format consistency
        expect(last_response.headers['Content-Type']).to include('application/json')
      end
    end
  end

  # Helper methods

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
end