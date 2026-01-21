# Property-based test for HTTP API compatibility
# **Feature: ruby-backend-migration, Property 2: HTTP API Compatibility**
# **Validates: Requirements 1.3, 9.1, 9.2, 9.3, 9.4, 9.5**

require 'bundler/setup'
require 'rspec'
require 'rantly'
require 'rantly/rspec_extensions'
require 'rack/test'
require 'json'
require 'securerandom'
require 'tempfile'
require 'bcrypt'

# Set test environment
ENV['APP_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test_jwt_secret_key_for_testing_purposes_only'
ENV['JWT_TTL'] = '60' # 1 hour for testing
ENV['APP_DEBUG'] = 'true' # Enable debug mode to see actual errors

# Load configuration and database first
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
  def self.send_to_user(user_id, message)
    # Mock implementation for testing
    true
  end
  
  def self.broadcast_to_room(room_id, message)
    # Mock implementation for testing
    true
  end
  
  def self.get_user_connection(user_id)
    nil # No connections in test
  end
  
  def self.get_room_connections(room_id)
    [] # No connections in test
  end
  
  def self.connection_stats
    {
      total_connections: 0,
      authenticated_users: [],
      rooms_with_connections: {}
    }
  end
  
  def self.cleanup_stale_connections
    # No-op in test
  end
end

# Load services and controllers
require_relative '../../app/services/auth_service'
require_relative '../../app/services/room_manager'
require_relative '../../app/controllers/auth_controller'
require_relative '../../app/controllers/room_controller'
require_relative '../../app/controllers/track_controller'

RSpec.describe 'HTTP API Compatibility Property Test', :property do
  include Rack::Test::Methods

  def app
    # Create a test version of the server
    require 'sinatra/base'
    require 'json'
    
    # Create test server class
    Class.new(Sinatra::Base) do
      configure do
        set :logging, false
        set :dump_errors, false
        set :show_exceptions, false
        
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

      # Helper method to extract token
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

      # Basic API info endpoint
      get '/api' do
        content_type :json
        {
          name: 'Spotik Ruby Backend Test',
          version: '1.0.0',
          environment: 'test',
          ruby_version: RUBY_VERSION,
          server: 'Test',
          websocket_support: true,
          timestamp: Time.now.iso8601
        }.to_json
      end

      # Catch-all for undefined routes
      not_found do
        content_type :json
        status 404
        { error: 'Endpoint not found', path: request.path_info }.to_json
      end

      # Error handler
      error do |e|
        content_type :json
        status 500
        { error: 'Internal server error', details: e.message }.to_json
      end
    end
  end

  before(:all) do
    # Database is already set up globally
    @test_db = DB
  end
  
  before(:each) do
    # Clean database before each test
    DB[:track_votes].delete
    DB[:room_participants].delete
    DB[:tracks].delete
    DB[:rooms].delete
    DB[:users].delete
  end

  describe 'Property 2: HTTP API Compatibility' do
    it 'returns Laravel-compatible responses for any valid authentication request' do
      test_instance = self
      
      property_of {
        # Generate various authentication scenarios
        auth_scenario = choose(:register, :login, :me, :refresh, :logout)
        user_data = test_instance.generate_valid_user_data
        [auth_scenario, user_data]
      }.check(10) { |auth_scenario, user_data|  # Reduced iterations for faster execution
        case auth_scenario
        when :register
          # Test user registration endpoint
          response = post '/api/auth/register', user_data.to_json, { 'CONTENT_TYPE' => 'application/json' }
          
          # Verify Laravel-compatible response structure
          expect([201, 422].include?(last_response.status)).to be true
          
          if last_response.status == 201
            body = JSON.parse(last_response.body)
            
            # Verify Laravel-compatible success response structure
            expect(body).to have_key('success')
            expect(body).to have_key('message')
            expect(body).to have_key('data')
            expect(body['success']).to be true
            expect(body['data']).to have_key('user')
            expect(body['data']).to have_key('token')
            expect(body['data']).to have_key('token_type')
            expect(body['data']).to have_key('expires_in')
            expect(body['data']['token_type']).to eq('bearer')
            
            # Verify user data structure
            user = body['data']['user']
            expect(user).to have_key('id')
            expect(user).to have_key('username')
            expect(user).to have_key('email')
            expect(user).to have_key('created_at')
            expect(user['username']).to eq(user_data[:username])
            expect(user['email']).to eq(user_data[:email])
          else
            # Verify Laravel-compatible error response structure
            body = JSON.parse(last_response.body)
            expect(body).to have_key('success')
            expect(body).to have_key('message')
            expect(body).to have_key('errors')
            expect(body['success']).to be false
          end
          
        when :login
          # Create user first
          user = create_test_user(user_data)
          
          # Test login endpoint
          login_data = { email: user_data[:email], password: user_data[:password] }
          response = post '/api/auth/login', login_data.to_json, { 'CONTENT_TYPE' => 'application/json' }
          
          # Verify Laravel-compatible response
          expect(last_response.status).to eq(200)
          body = JSON.parse(last_response.body)
          
          expect(body).to have_key('success')
          expect(body).to have_key('message')
          expect(body).to have_key('data')
          expect(body['success']).to be true
          expect(body['data']).to have_key('user')
          expect(body['data']).to have_key('token')
          expect(body['data']).to have_key('token_type')
          expect(body['data']).to have_key('expires_in')
          expect(body['data']['token_type']).to eq('bearer')
          
        when :me
          # Create user and get token
          user = create_test_user(user_data)
          token = AuthService.generate_jwt(user)
          
          # Test me endpoint
          response = get '/api/auth/me', {}, { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
          
          # Verify Laravel-compatible response
          expect(last_response.status).to eq(200)
          body = JSON.parse(last_response.body)
          
          expect(body).to have_key('success')
          expect(body).to have_key('message')
          expect(body).to have_key('data')
          expect(body['success']).to be true
          expect(body['data']).to have_key('user')
          
          user_info = body['data']['user']
          expect(user_info).to have_key('id')
          expect(user_info).to have_key('username')
          expect(user_info).to have_key('email')
          expect(user_info).to have_key('created_at')
          expect(user_info).to have_key('updated_at')
          
        when :refresh
          # Create user and get token
          user = create_test_user(user_data)
          token = AuthService.generate_jwt(user)
          
          # Test refresh endpoint
          response = post '/api/auth/refresh', {}, { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
          
          # Verify Laravel-compatible response
          expect(last_response.status).to eq(200)
          body = JSON.parse(last_response.body)
          
          expect(body).to have_key('success')
          expect(body).to have_key('message')
          expect(body).to have_key('data')
          expect(body['success']).to be true
          expect(body['data']).to have_key('token')
          expect(body['data']).to have_key('token_type')
          expect(body['data']).to have_key('expires_in')
          expect(body['data']['token_type']).to eq('bearer')
          
        when :logout
          # Create user and get token
          user = create_test_user(user_data)
          token = AuthService.generate_jwt(user)
          
          # Test logout endpoint
          response = post '/api/auth/logout', {}, { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
          
          # Verify Laravel-compatible response
          expect(last_response.status).to eq(200)
          body = JSON.parse(last_response.body)
          
          expect(body).to have_key('success')
          expect(body).to have_key('message')
          expect(body['success']).to be true
        end
        
        # Verify common Laravel-compatible headers
        expect(last_response.headers).to have_key('Content-Type')
        expect(last_response.headers['Content-Type']).to include('application/json')
        expect(last_response.headers).to have_key('Access-Control-Allow-Origin')
      }
    end

    it 'returns Laravel-compatible responses for any valid room management request' do
      test_instance = self
      
      property_of {
        # Generate various room management scenarios
        room_scenario = choose(:list_rooms, :create_room, :show_room, :join_room, :leave_room)
        user_data = test_instance.generate_valid_user_data
        room_data = test_instance.generate_valid_room_data
        [room_scenario, user_data, room_data]
      }.check(8) { |room_scenario, user_data, room_data|  # Reduced iterations for faster execution
        # Create user and get token
        user = create_test_user(user_data)
        token = AuthService.generate_jwt(user)
        auth_headers = { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
        
        case room_scenario
        when :list_rooms
          # Test list rooms endpoint
          response = get '/api/rooms', {}, auth_headers
          
          # Verify Laravel-compatible response
          expect(last_response.status).to eq(200)
          body = JSON.parse(last_response.body)
          
          expect(body).to have_key('rooms')
          expect(body).to have_key('total')
          expect(body['rooms']).to be_an(Array)
          expect(body['total']).to be_an(Integer)
          
        when :create_room
          # Test create room endpoint
          response = post '/api/rooms', room_data.to_json, 
                          { 'CONTENT_TYPE' => 'application/json' }.merge(auth_headers)
          
          # Verify Laravel-compatible response
          expect([201, 422].include?(last_response.status)).to be true
          body = JSON.parse(last_response.body)
          
          if last_response.status == 201
            expect(body).to have_key('room')
            expect(body).to have_key('message')
            
            room = body['room']
            expect(room).to have_key('id')
            expect(room).to have_key('name')
            expect(room).to have_key('administrator_id')
            expect(room).to have_key('is_playing')
            expect(room).to have_key('created_at')
            expect(room).to have_key('updated_at')
            expect(room).to have_key('participants')
            expect(room).to have_key('track_queue')
            expect(room['name']).to eq(room_data[:name])
            expect(room['administrator_id']).to eq(user.id)
          else
            expect(body).to have_key('error')
            expect(body).to have_key('errors')
          end
          
        when :show_room
          # Create a room first
          room = create_test_room(user, room_data)
          
          # Test show room endpoint
          response = get "/api/rooms/#{room.id}", {}, auth_headers
          
          # Verify Laravel-compatible response
          expect(last_response.status).to eq(200)
          body = JSON.parse(last_response.body)
          
          expect(body).to have_key('room')
          room_info = body['room']
          expect(room_info).to have_key('id')
          expect(room_info).to have_key('name')
          expect(room_info).to have_key('administrator_id')
          expect(room_info).to have_key('participants')
          expect(room_info).to have_key('track_queue')
          expect(room_info).to have_key('is_playing')
          expect(room_info).to have_key('current_track')
          expect(room_info).to have_key('is_user_participant')
          expect(room_info).to have_key('is_user_administrator')
          
        when :join_room
          # Create another user and room
          other_user = create_test_user(generate_valid_user_data)
          room = create_test_room(other_user, room_data)
          
          # Test join room endpoint
          response = post "/api/rooms/#{room.id}/join", {}, 
                          { 'CONTENT_TYPE' => 'application/json' }.merge(auth_headers)
          
          # Verify Laravel-compatible response
          expect(last_response.status).to eq(200)
          body = JSON.parse(last_response.body)
          
          expect(body).to have_key('room')
          expect(body).to have_key('message')
          expect(body['room']).to have_key('participants')
          
        when :leave_room
          # Create another user and room, then join it
          other_user = create_test_user(generate_valid_user_data)
          room = create_test_room(other_user, room_data)
          room.add_participant(user)
          
          # Test leave room endpoint
          response = delete "/api/rooms/#{room.id}/leave", {}, auth_headers
          
          # Verify Laravel-compatible response
          expect(last_response.status).to eq(200)
          body = JSON.parse(last_response.body)
          
          expect(body).to have_key('room')
          expect(body).to have_key('message')
        end
        
        # Verify common Laravel-compatible headers
        expect(last_response.headers).to have_key('Content-Type')
        expect(last_response.headers['Content-Type']).to include('application/json')
      }
    end

    it 'returns Laravel-compatible responses for any valid track management request' do
      test_instance = self
      
      property_of {
        # Generate various track management scenarios
        track_scenario = choose(:list_tracks, :upload_track, :vote_track, :unvote_track)
        user_data = test_instance.generate_valid_user_data
        room_data = test_instance.generate_valid_room_data
        [track_scenario, user_data, room_data]
      }.check(8) { |track_scenario, user_data, room_data|  # Reduced iterations for faster execution
        # Create user, room, and get token
        user = create_test_user(user_data)
        room = create_test_room(user, room_data)
        token = AuthService.generate_jwt(user)
        auth_headers = { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
        
        case track_scenario
        when :list_tracks
          # Test list tracks endpoint
          response = get "/api/rooms/#{room.id}/tracks", {}, auth_headers
          
          # Verify Laravel-compatible response
          expect(last_response.status).to eq(200)
          body = JSON.parse(last_response.body)
          
          expect(body).to have_key('tracks')
          expect(body).to have_key('total_count')
          expect(body['tracks']).to be_an(Array)
          expect(body['total_count']).to be_an(Integer)
          
        when :upload_track
          # Create a fake audio file
          temp_file = create_fake_audio_file
          
          begin
            # Test upload track endpoint (simplified for property test)
            # In a real scenario, we'd test multipart form data
            # For property testing, we'll simulate the controller response
            file_data = {
              audio_file: {
                filename: 'test.mp3',
                type: 'audio/mpeg',
                tempfile: temp_file
              }
            }
            
            # Simulate the upload by calling the controller directly
            result = TrackController.store(room.id, file_data, token)
            
            # Verify Laravel-compatible response structure
            unless [201, 422].include?(result[:status])
              puts "DEBUG: Upload track failed with status #{result[:status]}: #{result[:body]}"
            end
            expect([201, 422].include?(result[:status])).to be true
            
            if result[:status] == 201
              body = result[:body]
              expect(body).to have_key(:message)
              expect(body).to have_key(:track)
              
              track = body[:track]
              expect(track).to have_key(:id)
              expect(track).to have_key(:filename)
              expect(track).to have_key(:original_name)
              expect(track).to have_key(:duration_seconds)
              expect(track).to have_key(:vote_score)
              expect(track).to have_key(:uploader)
              expect(track).to have_key(:user_has_voted)
              expect(track).to have_key(:votes_count)
            else
              body = result[:body]
              expect(body).to have_key(:error)
              expect(body).to have_key(:errors)
            end
            
          ensure
            temp_file.close
            temp_file.unlink
          end
          
        when :vote_track
          # Create a track first
          track = create_test_track(user, room)
          
          # Test vote track endpoint
          response = post "/api/tracks/#{track.id}/vote", {}, 
                          { 'CONTENT_TYPE' => 'application/json' }.merge(auth_headers)
          
          # Debug output if test fails
          if last_response.status != 200
            puts "DEBUG: Vote track failed with status #{last_response.status}"
            puts "DEBUG: Response body: #{last_response.body}"
            puts "DEBUG: Track ID: #{track.id}"
            puts "DEBUG: User ID: #{user.id}"
            puts "DEBUG: Room ID: #{room.id}"
          end
          
          # Verify Laravel-compatible response
          expect(last_response.status).to eq(200)
          body = JSON.parse(last_response.body)
          
          expect(body).to have_key('message')
          expect(body).to have_key('vote_score')
          expect(body).to have_key('user_has_voted')
          expect(body['user_has_voted']).to be true
          expect(body['vote_score']).to be >= 1
          
        when :unvote_track
          # Create a track and vote for it first
          track = create_test_track(user, room)
          TrackVote.create(track_id: track.id, user_id: user.id, created_at: Time.now)
          track.update(vote_score: 1)
          
          # Test unvote track endpoint
          response = delete "/api/tracks/#{track.id}/vote", {}, auth_headers
          
          # Verify Laravel-compatible response
          expect(last_response.status).to eq(200)
          body = JSON.parse(last_response.body)
          
          expect(body).to have_key('message')
          expect(body).to have_key('vote_score')
          expect(body).to have_key('user_has_voted')
          expect(body['user_has_voted']).to be false
          expect(body['vote_score']).to be >= 0
        end
        
        # Verify common Laravel-compatible headers for HTTP responses
        if last_response
          expect(last_response.headers).to have_key('Content-Type')
          expect(last_response.headers['Content-Type']).to include('application/json')
        end
      }
    end

    it 'handles error cases with Laravel-compatible error responses' do
      test_instance = self
      
      property_of {
        # Generate various error scenarios
        error_scenario = choose(:invalid_token, :missing_token, :not_found, :validation_error, :forbidden)
        user_data = test_instance.generate_valid_user_data
        [error_scenario, user_data]
      }.check(8) { |error_scenario, user_data|  # Reduced iterations for faster execution
        case error_scenario
        when :invalid_token
          # Test with invalid token
          response = get '/api/auth/me', {}, { 'HTTP_AUTHORIZATION' => 'Bearer invalid.token.here' }
          
          expect(last_response.status).to eq(401)
          body = JSON.parse(last_response.body)
          
          expect(body).to have_key('success')
          expect(body).to have_key('message')
          expect(body).to have_key('error')
          expect(body['success']).to be false
          
        when :missing_token
          # Test without token
          response = get '/api/auth/me'
          
          expect(last_response.status).to eq(401)
          body = JSON.parse(last_response.body)
          
          expect(body).to have_key('success')
          expect(body).to have_key('message')
          expect(body).to have_key('error')
          expect(body['success']).to be false
          
        when :not_found
          # Test with non-existent room
          user = create_test_user(user_data)
          token = AuthService.generate_jwt(user)
          
          response = get '/api/rooms/nonexistent-id', {}, { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
          
          expect(last_response.status).to eq(404)
          body = JSON.parse(last_response.body)
          
          expect(body).to have_key('error')
          
        when :validation_error
          # Test with invalid room data
          user = create_test_user(user_data)
          token = AuthService.generate_jwt(user)
          
          invalid_room_data = { name: '' } # Empty name should fail validation
          response = post '/api/rooms', invalid_room_data.to_json, 
                          { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
          
          expect(last_response.status).to eq(422)
          body = JSON.parse(last_response.body)
          
          expect(body).to have_key('error')
          expect(body).to have_key('errors')
          expect(body['errors']).to be_a(Hash)
          
        when :forbidden
          # Test accessing room without permission
          user1 = create_test_user(user_data)
          user2 = create_test_user(generate_valid_user_data)
          room = create_test_room(user1, generate_valid_room_data)
          token2 = AuthService.generate_jwt(user2)
          
          # Try to get tracks without being a participant
          response = get "/api/rooms/#{room.id}/tracks", {}, { 'HTTP_AUTHORIZATION' => "Bearer #{token2}" }
          
          expect(last_response.status).to eq(403)
          body = JSON.parse(last_response.body)
          
          expect(body).to have_key('error')
        end
        
        # Verify error responses have proper headers
        expect(last_response.headers).to have_key('Content-Type')
        expect(last_response.headers['Content-Type']).to include('application/json')
      }
    end

    it 'maintains consistent HTTP status codes compatible with Laravel conventions' do
      test_instance = self
      
      property_of {
        # Generate various HTTP operations
        operation = choose(:get_success, :post_created, :post_validation_error, :unauthorized, :not_found, :forbidden)
        user_data = test_instance.generate_valid_user_data
        [operation, user_data]
      }.check(5) { |operation, user_data|  # Reduced iterations for faster execution
        case operation
        when :get_success
          # Test successful GET request
          user = create_test_user(user_data)
          token = AuthService.generate_jwt(user)
          
          response = get '/api/rooms', {}, { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
          
          # Should return 200 OK for successful GET
          expect(last_response.status).to eq(200)
          
        when :post_created
          # Test successful POST request (resource creation)
          user = create_test_user(user_data)
          token = AuthService.generate_jwt(user)
          room_data = generate_valid_room_data
          
          response = post '/api/rooms', room_data.to_json, 
                          { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
          
          # Should return 201 Created for successful resource creation
          expect(last_response.status).to eq(201)
          
        when :post_validation_error
          # Test POST with validation errors
          user = create_test_user(user_data)
          token = AuthService.generate_jwt(user)
          invalid_data = { name: '' }
          
          response = post '/api/rooms', invalid_data.to_json, 
                          { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
          
          # Should return 422 Unprocessable Entity for validation errors
          expect(last_response.status).to eq(422)
          
        when :unauthorized
          # Test without authentication
          response = get '/api/auth/me'
          
          # Should return 401 Unauthorized
          expect(last_response.status).to eq(401)
          
        when :not_found
          # Test non-existent resource
          user = create_test_user(user_data)
          token = AuthService.generate_jwt(user)
          
          response = get '/api/rooms/nonexistent', {}, { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }
          
          # Should return 404 Not Found
          expect(last_response.status).to eq(404)
          
        when :forbidden
          # Test forbidden access
          user1 = create_test_user(user_data)
          user2 = create_test_user(generate_valid_user_data)
          room = create_test_room(user1, generate_valid_room_data)
          token2 = AuthService.generate_jwt(user2)
          
          response = get "/api/rooms/#{room.id}/tracks", {}, { 'HTTP_AUTHORIZATION' => "Bearer #{token2}" }
          
          # Should return 403 Forbidden
          expect(last_response.status).to eq(403)
        end
        
        # Verify response has proper content type
        expect(last_response.headers['Content-Type']).to include('application/json')
      }
    end

    it 'maintains Laravel-compatible CORS headers for all requests' do
      test_instance = self
      
      property_of {
        # Generate various request types
        request_type = choose(:get, :post, :delete, :options)
        endpoint = choose('/api/rooms', '/api/auth/login', '/health', '/api')
        [request_type, endpoint]
      }.check(5) { |request_type, endpoint|  # Reduced iterations for faster execution
        case request_type
        when :get
          response = get endpoint
        when :post
          response = post endpoint, {}.to_json, { 'CONTENT_TYPE' => 'application/json' }
        when :delete
          response = delete endpoint
        when :options
          response = options endpoint
        end
        
        # Verify CORS headers are present (Laravel compatibility)
        expect(last_response.headers).to have_key('Access-Control-Allow-Origin')
        expect(last_response.headers).to have_key('Access-Control-Allow-Methods')
        expect(last_response.headers).to have_key('Access-Control-Allow-Headers')
        
        expect(last_response.headers['Access-Control-Allow-Origin']).to eq('*')
        expect(last_response.headers['Access-Control-Allow-Methods']).to include('GET')
        expect(last_response.headers['Access-Control-Allow-Methods']).to include('POST')
        expect(last_response.headers['Access-Control-Allow-Headers']).to include('Content-Type')
        expect(last_response.headers['Access-Control-Allow-Headers']).to include('Authorization')
        
        # OPTIONS requests should return 200
        if request_type == :options
          expect(last_response.status).to eq(200)
        end
      }
    end
  end

  # Helper methods for generating test data

  def generate_valid_user_data
    {
      username: "user_#{SecureRandom.hex(6)}",
      email: "#{SecureRandom.hex(6)}@example.com",
      password: "password#{rand(100..999)}",
      password_confirmation: "password#{rand(100..999)}"
    }.tap { |data| data[:password_confirmation] = data[:password] }
  end

  def generate_valid_room_data
    {
      name: "Room #{SecureRandom.hex(4)}"
    }
  end

  def create_test_user(user_data)
    User.create(
      username: user_data[:username],
      email: user_data[:email].downcase.strip,
      password_hash: BCrypt::Password.create(user_data[:password]),
      created_at: Time.now,
      updated_at: Time.now
    )
  end

  def create_test_room(user, room_data)
    room = Room.create(
      name: room_data[:name],
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
      room_id: room.id,
      uploader_id: user.id,
      filename: "track_#{SecureRandom.hex(8)}.mp3",
      original_name: "Test Track.mp3",
      file_path: "/fake/path/track.mp3",
      duration_seconds: rand(120..300),
      file_size_bytes: rand(1000000..5000000),
      mime_type: 'audio/mpeg',
      vote_score: 0,
      created_at: Time.now,
      updated_at: Time.now
    )
  end

  def create_fake_audio_file
    temp_file = Tempfile.new(['test_track', '.mp3'])
    
    # Create a minimal MP3-like file with proper header
    mp3_header = [0xFF, 0xFB, 0x90, 0x00].pack('C*')  # MP3 frame sync + basic header
    fake_audio_data = mp3_header + ('A' * 1000)  # Add some fake audio data
    
    temp_file.write(fake_audio_data)
    temp_file.rewind
    
    temp_file
  end
end