#!/usr/bin/env ruby

# Multi-User Concurrent Integration Test
# **Feature: ruby-backend-migration, Task 17.1: Complete system integration and final testing**
# **Validates: Requirements 1.5, 15.1, 15.2, 15.3, 15.4, 15.5**

require 'bundler/setup'
require 'rspec'
require 'rack/test'
require 'json'
require 'securerandom'
require 'thread'
require 'timeout'
require 'net/http'
require 'uri'

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

# Mock WebSocketConnection for concurrent testing
class WebSocketConnection
  @@mock_connections = {}
  @@published_events = []
  @@connection_mutex = Mutex.new
  
  def self.send_to_user(user_id, message)
    @@connection_mutex.synchronize do
      @@published_events << {
        type: :user_message,
        user_id: user_id,
        message: message,
        timestamp: Time.now.to_f,
        thread_id: Thread.current.object_id
      }
    end
    true
  end
  
  def self.broadcast_to_room(room_id, message)
    @@connection_mutex.synchronize do
      @@published_events << {
        type: :room_broadcast,
        room_id: room_id,
        message: message,
        timestamp: Time.now.to_f,
        thread_id: Thread.current.object_id
      }
    end
    true
  end
  
  def self.get_published_events
    @@connection_mutex.synchronize { @@published_events.dup }
  end
  
  def self.clear_published_events
    @@connection_mutex.synchronize { @@published_events.clear }
  end
  
  def self.connection_stats
    @@connection_mutex.synchronize do
      {
        total_connections: @@mock_connections.length,
        authenticated_users: @@mock_connections.keys,
        rooms_with_connections: {},
        concurrent_threads: @@published_events.map { |e| e[:thread_id] }.uniq.length
      }
    end
  end
  
  def self.simulate_concurrent_connections(user_count)
    @@connection_mutex.synchronize do
      user_count.times do |i|
        user_id = "concurrent_user_#{i}_#{SecureRandom.hex(4)}"
        @@mock_connections[user_id] = {
          connected_at: Time.now.to_f,
          thread_id: Thread.current.object_id
        }
      end
    end
  end
end

# Load services and controllers
require_relative '../../app/services/auth_service'
require_relative '../../app/services/room_manager'
require_relative '../../app/controllers/auth_controller'
require_relative '../../app/controllers/room_controller'
require_relative '../../app/controllers/track_controller'
require_relative '../../app/controllers/playback_controller'

RSpec.describe 'Multi-User Concurrent Integration Tests', :integration do
  include Rack::Test::Methods

  def app
    # Create a test version of the Ruby server with thread safety
    require 'sinatra/base'
    require 'json'
    
    Class.new(Sinatra::Base) do
      configure do
        set :logging, false
        set :dump_errors, false
        set :show_exceptions, false
        set :threaded, true  # Enable thread safety
        
        # CORS headers
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
      post '/api/tracks/:id/vote' do
        content_type :json
        token = extract_token_from_request
        result = TrackController.vote(params[:id], token)
        status result[:status]
        result[:body].to_json
      end

      # Playback control endpoints
      post '/api/rooms/:room_id/playback/start' do
        content_type :json
        begin
          params_hash = JSON.parse(request.body.read)
        rescue JSON::ParserError
          params_hash = params
        end
        track_id = params_hash['track_id']
        token = extract_token_from_request
        result = PlaybackController.start_track(params[:room_id], track_id, token)
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

      # Health and monitoring endpoints
      get '/api/health' do
        content_type :json
        {
          status: 'healthy',
          timestamp: Time.now.iso8601,
          concurrent_connections: WebSocketConnection.connection_stats[:total_connections],
          active_threads: Thread.list.length
        }.to_json
      end

      get '/api/metrics' do
        content_type :json
        {
          websocket_stats: WebSocketConnection.connection_stats,
          system_stats: {
            active_threads: Thread.list.length,
            memory_usage: `ps -o rss= -p #{Process.pid}`.to_i * 1024, # bytes
            uptime: Time.now.to_f - $server_start_time.to_f
          }
        }.to_json
      end

      error do |e|
        content_type :json
        status 500
        { error: 'Internal server error', details: e.message, thread_id: Thread.current.object_id }.to_json
      end
    end
  end

  before(:all) do
    @test_db = DB
    $server_start_time = Time.now
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

  describe 'Concurrent User Registration and Authentication' do
    it 'handles multiple simultaneous user registrations without conflicts' do
      user_count = 10
      registration_threads = []
      registration_results = []
      results_mutex = Mutex.new
      
      # Create concurrent registration threads
      user_count.times do |i|
        registration_threads << Thread.new do
          user_data = {
            username: "concurrent_user_#{i}_#{SecureRandom.hex(4)}",
            email: "concurrent#{i}_#{SecureRandom.hex(4)}@example.com",
            password: 'password123',
            password_confirmation: 'password123'
          }
          
          response = post '/api/auth/register', user_data.to_json, 
                          { 'CONTENT_TYPE' => 'application/json' }
          
          results_mutex.synchronize do
            registration_results << {
              thread_id: Thread.current.object_id,
              status: last_response.status,
              body: JSON.parse(last_response.body, symbolize_names: true),
              user_data: user_data
            }
          end
        end
      end
      
      # Wait for all registrations to complete
      registration_threads.each(&:join)
      
      # Verify all registrations succeeded
      expect(registration_results.length).to eq(user_count)
      
      successful_registrations = registration_results.select { |r| r[:status] == 201 }
      expect(successful_registrations.length).to eq(user_count)
      
      # Verify no duplicate usernames or emails were created
      usernames = registration_results.map { |r| r[:user_data][:username] }
      emails = registration_results.map { |r| r[:user_data][:email] }
      
      expect(usernames.uniq.length).to eq(user_count)
      expect(emails.uniq.length).to eq(user_count)
      
      # Verify database consistency
      expect(User.count).to eq(user_count)
      
      puts "✅ Successfully handled #{user_count} concurrent user registrations"
    end

    it 'handles concurrent login attempts for the same user safely' do
      # Create a test user
      user_data = {
        username: 'concurrent_login_user',
        email: 'concurrent_login@example.com',
        password: 'password123',
        password_confirmation: 'password123'
      }
      
      post '/api/auth/register', user_data.to_json, { 'CONTENT_TYPE' => 'application/json' }
      expect(last_response.status).to eq(201)
      
      # Attempt concurrent logins
      login_count = 5
      login_threads = []
      login_results = []
      results_mutex = Mutex.new
      
      login_count.times do |i|
        login_threads << Thread.new do
          login_data = {
            email: user_data[:email],
            password: user_data[:password]
          }
          
          response = post '/api/auth/login', login_data.to_json,
                          { 'CONTENT_TYPE' => 'application/json' }
          
          results_mutex.synchronize do
            login_results << {
              thread_id: Thread.current.object_id,
              status: last_response.status,
              body: JSON.parse(last_response.body, symbolize_names: true)
            }
          end
        end
      end
      
      # Wait for all logins to complete
      login_threads.each(&:join)
      
      # Verify all logins succeeded
      expect(login_results.length).to eq(login_count)
      
      successful_logins = login_results.select { |r| r[:status] == 200 }
      expect(successful_logins.length).to eq(login_count)
      
      # Verify all tokens are valid and different (each login gets a new token)
      tokens = successful_logins.map { |r| r[:body][:data][:token] }
      expect(tokens.uniq.length).to eq(login_count)
      
      puts "✅ Successfully handled #{login_count} concurrent login attempts"
    end
  end

  describe 'Concurrent Room Operations' do
    it 'handles multiple users creating rooms simultaneously' do
      # Create test users first
      user_count = 8
      users = []
      
      user_count.times do |i|
        user_data = {
          username: "room_creator_#{i}_#{SecureRandom.hex(4)}",
          email: "creator#{i}_#{SecureRandom.hex(4)}@example.com",
          password: 'password123',
          password_confirmation: 'password123'
        }
        
        post '/api/auth/register', user_data.to_json, { 'CONTENT_TYPE' => 'application/json' }
        expect(last_response.status).to eq(201)
        
        body = JSON.parse(last_response.body, symbolize_names: true)
        users << {
          id: body[:data][:user][:id],
          token: body[:data][:token],
          username: user_data[:username]
        }
      end
      
      # Create rooms concurrently
      room_creation_threads = []
      room_results = []
      results_mutex = Mutex.new
      
      users.each_with_index do |user, i|
        room_creation_threads << Thread.new do
          room_data = {
            name: "Concurrent Room #{i} - #{SecureRandom.hex(4)}"
          }
          
          response = post '/api/rooms', room_data.to_json,
                          { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{user[:token]}" }
          
          results_mutex.synchronize do
            room_results << {
              thread_id: Thread.current.object_id,
              user_id: user[:id],
              status: last_response.status,
              body: last_response.status == 201 ? JSON.parse(last_response.body, symbolize_names: true) : nil,
              room_name: room_data[:name]
            }
          end
        end
      end
      
      # Wait for all room creations to complete
      room_creation_threads.each(&:join)
      
      # Verify all room creations succeeded
      expect(room_results.length).to eq(user_count)
      
      successful_creations = room_results.select { |r| r[:status] == 201 }
      expect(successful_creations.length).to eq(user_count)
      
      # Verify database consistency
      expect(Room.count).to eq(user_count)
      
      # Verify each user is administrator of their room
      successful_creations.each do |result|
        room_data = result[:body][:room]
        expect(room_data[:administrator_id]).to eq(result[:user_id])
      end
      
      puts "✅ Successfully handled #{user_count} concurrent room creations"
    end

    it 'handles multiple users joining the same room concurrently' do
      # Create room administrator
      admin_data = {
        username: 'room_admin',
        email: 'admin@example.com',
        password: 'password123',
        password_confirmation: 'password123'
      }
      
      post '/api/auth/register', admin_data.to_json, { 'CONTENT_TYPE' => 'application/json' }
      expect(last_response.status).to eq(201)
      
      admin_body = JSON.parse(last_response.body, symbolize_names: true)
      admin_token = admin_body[:data][:token]
      
      # Create a room
      room_data = { name: 'Concurrent Join Test Room' }
      post '/api/rooms', room_data.to_json,
           { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{admin_token}" }
      expect(last_response.status).to eq(201)
      
      room_body = JSON.parse(last_response.body, symbolize_names: true)
      room_id = room_body[:room][:id]
      
      # Create multiple users to join the room
      join_user_count = 12
      join_users = []
      
      join_user_count.times do |i|
        user_data = {
          username: "join_user_#{i}_#{SecureRandom.hex(4)}",
          email: "join#{i}_#{SecureRandom.hex(4)}@example.com",
          password: 'password123',
          password_confirmation: 'password123'
        }
        
        post '/api/auth/register', user_data.to_json, { 'CONTENT_TYPE' => 'application/json' }
        expect(last_response.status).to eq(201)
        
        body = JSON.parse(last_response.body, symbolize_names: true)
        join_users << {
          id: body[:data][:user][:id],
          token: body[:data][:token],
          username: user_data[:username]
        }
      end
      
      # Join room concurrently
      join_threads = []
      join_results = []
      results_mutex = Mutex.new
      
      join_users.each do |user|
        join_threads << Thread.new do
          response = post "/api/rooms/#{room_id}/join", {},
                          { 'HTTP_AUTHORIZATION' => "Bearer #{user[:token]}" }
          
          results_mutex.synchronize do
            join_results << {
              thread_id: Thread.current.object_id,
              user_id: user[:id],
              status: last_response.status,
              body: last_response.status == 200 ? JSON.parse(last_response.body, symbolize_names: true) : nil
            }
          end
        end
      end
      
      # Wait for all joins to complete
      join_threads.each(&:join)
      
      # Verify all joins succeeded
      expect(join_results.length).to eq(join_user_count)
      
      successful_joins = join_results.select { |r| r[:status] == 200 }
      expect(successful_joins.length).to eq(join_user_count)
      
      # Verify WebSocket events were broadcast for all joins
      events = WebSocketConnection.get_published_events
      join_events = events.select { |e| e[:type] == :room_broadcast }
      expect(join_events.length).to be >= join_user_count
      
      # Verify database consistency - room should have all participants
      room = Room[room_id]
      expect(room.participants.count).to eq(join_user_count + 1) # +1 for admin
      
      puts "✅ Successfully handled #{join_user_count} concurrent room joins"
    end
  end

  describe 'Concurrent Voting and Playback Operations' do
    it 'handles concurrent voting on multiple tracks without race conditions' do
      # Setup: Create users, room, and tracks
      user_count = 15
      track_count = 5
      
      # Create admin user and room
      admin_data = {
        username: 'voting_admin',
        email: 'voting_admin@example.com',
        password: 'password123',
        password_confirmation: 'password123'
      }
      
      post '/api/auth/register', admin_data.to_json, { 'CONTENT_TYPE' => 'application/json' }
      admin_body = JSON.parse(last_response.body, symbolize_names: true)
      admin_token = admin_body[:data][:token]
      admin_id = admin_body[:data][:user][:id]
      
      # Create room
      room_data = { name: 'Concurrent Voting Test Room' }
      post '/api/rooms', room_data.to_json,
           { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{admin_token}" }
      room_body = JSON.parse(last_response.body, symbolize_names: true)
      room_id = room_body[:room][:id]
      
      # Create voting users
      voting_users = []
      user_count.times do |i|
        user_data = {
          username: "voter_#{i}_#{SecureRandom.hex(4)}",
          email: "voter#{i}_#{SecureRandom.hex(4)}@example.com",
          password: 'password123',
          password_confirmation: 'password123'
        }
        
        post '/api/auth/register', user_data.to_json, { 'CONTENT_TYPE' => 'application/json' }
        body = JSON.parse(last_response.body, symbolize_names: true)
        voting_users << {
          id: body[:data][:user][:id],
          token: body[:data][:token]
        }
        
        # Join room
        post "/api/rooms/#{room_id}/join", {}, { 'HTTP_AUTHORIZATION' => "Bearer #{body[:data][:token]}" }
      end
      
      # Create tracks
      tracks = []
      track_count.times do |i|
        track = Track.create(
          id: SecureRandom.uuid,
          room_id: room_id,
          uploader_id: admin_id,
          filename: "concurrent_vote_track_#{i}.mp3",
          original_name: "Concurrent Vote Track #{i}",
          file_path: "/tmp/concurrent_vote_track_#{i}.mp3",
          duration_seconds: rand(120..300),
          file_size_bytes: rand(1_000_000..5_000_000),
          mime_type: 'audio/mpeg',
          vote_score: 0,
          created_at: Time.now,
          updated_at: Time.now
        )
        tracks << track
      end
      
      # Clear events before voting
      WebSocketConnection.clear_published_events
      
      # Perform concurrent voting
      voting_threads = []
      voting_results = []
      results_mutex = Mutex.new
      
      # Each user votes for random tracks
      voting_users.each do |user|
        voting_threads << Thread.new do
          # Vote for 2-3 random tracks
          votes_to_cast = rand(2..3)
          selected_tracks = tracks.sample(votes_to_cast)
          
          selected_tracks.each do |track|
            response = post "/api/tracks/#{track.id}/vote", {},
                            { 'HTTP_AUTHORIZATION' => "Bearer #{user[:token]}" }
            
            results_mutex.synchronize do
              voting_results << {
                thread_id: Thread.current.object_id,
                user_id: user[:id],
                track_id: track.id,
                status: last_response.status,
                timestamp: Time.now.to_f
              }
            end
            
            # Small random delay to simulate real user behavior
            sleep(rand(0.01..0.05))
          end
        end
      end
      
      # Wait for all voting to complete
      voting_threads.each(&:join)
      
      # Verify voting results
      successful_votes = voting_results.select { |r| r[:status] == 200 }
      expect(successful_votes.length).to be > 0
      
      # Verify vote counts in database are consistent
      tracks.each do |track|
        track.refresh
        expected_votes = voting_results.count { |r| r[:track_id] == track.id && r[:status] == 200 }
        actual_votes = track.votes.count
        
        expect(actual_votes).to eq(expected_votes), 
          "Track #{track.id} vote count mismatch: expected #{expected_votes}, got #{actual_votes}"
      end
      
      # Verify WebSocket events were broadcast for votes
      events = WebSocketConnection.get_published_events
      vote_events = events.select { |e| e[:type] == :room_broadcast }
      expect(vote_events.length).to be >= successful_votes.length
      
      puts "✅ Successfully handled #{successful_votes.length} concurrent votes across #{track_count} tracks"
    end

    it 'handles concurrent playback control operations safely' do
      # Setup: Create admin user, room, and track
      admin_data = {
        username: 'playback_admin',
        email: 'playback_admin@example.com',
        password: 'password123',
        password_confirmation: 'password123'
      }
      
      post '/api/auth/register', admin_data.to_json, { 'CONTENT_TYPE' => 'application/json' }
      admin_body = JSON.parse(last_response.body, symbolize_names: true)
      admin_token = admin_body[:data][:token]
      admin_id = admin_body[:data][:user][:id]
      
      # Create room
      room_data = { name: 'Concurrent Playback Test Room' }
      post '/api/rooms', room_data.to_json,
           { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{admin_token}" }
      room_body = JSON.parse(last_response.body, symbolize_names: true)
      room_id = room_body[:room][:id]
      
      # Create track
      track = Track.create(
        id: SecureRandom.uuid,
        room_id: room_id,
        uploader_id: admin_id,
        filename: "concurrent_playback_track.mp3",
        original_name: "Concurrent Playback Track",
        file_path: "/tmp/concurrent_playback_track.mp3",
        duration_seconds: 180,
        file_size_bytes: 3_000_000,
        mime_type: 'audio/mpeg',
        vote_score: 0,
        created_at: Time.now,
        updated_at: Time.now
      )
      
      # Clear events before playback testing
      WebSocketConnection.clear_published_events
      
      # Test concurrent playback operations
      playback_operations = [
        { action: 'start', data: { track_id: track.id } },
        { action: 'pause', data: {} },
        { action: 'resume', data: {} },
        { action: 'pause', data: {} },
        { action: 'resume', data: {} }
      ]
      
      playback_threads = []
      playback_results = []
      results_mutex = Mutex.new
      
      playback_operations.each_with_index do |operation, i|
        playback_threads << Thread.new do
          # Small delay to ensure operations happen in sequence but test concurrency handling
          sleep(i * 0.1)
          
          endpoint = case operation[:action]
                    when 'start'
                      "/api/rooms/#{room_id}/playback/start"
                    when 'pause'
                      "/api/rooms/#{room_id}/playback/pause"
                    when 'resume'
                      "/api/rooms/#{room_id}/playback/resume"
                    end
          
          response = post endpoint, operation[:data].to_json,
                          { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{admin_token}" }
          
          results_mutex.synchronize do
            playback_results << {
              thread_id: Thread.current.object_id,
              action: operation[:action],
              status: last_response.status,
              body: last_response.status == 200 ? JSON.parse(last_response.body, symbolize_names: true) : nil,
              timestamp: Time.now.to_f
            }
          end
        end
      end
      
      # Wait for all playback operations to complete
      playback_threads.each(&:join)
      
      # Verify all operations succeeded
      expect(playback_results.length).to eq(playback_operations.length)
      
      successful_operations = playback_results.select { |r| r[:status] == 200 }
      expect(successful_operations.length).to eq(playback_operations.length)
      
      # Verify operations happened in correct sequence
      sorted_results = playback_results.sort_by { |r| r[:timestamp] }
      expected_sequence = playback_operations.map { |op| op[:action] }
      actual_sequence = sorted_results.map { |r| r[:action] }
      
      expect(actual_sequence).to eq(expected_sequence)
      
      # Verify WebSocket events were broadcast for all operations
      events = WebSocketConnection.get_published_events
      playback_events = events.select { |e| e[:type] == :room_broadcast }
      expect(playback_events.length).to be >= successful_operations.length
      
      puts "✅ Successfully handled #{successful_operations.length} concurrent playback operations"
    end
  end

  describe 'System Load and Performance Under Concurrent Operations' do
    it 'maintains system stability under high concurrent load' do
      # This test simulates a realistic high-load scenario
      concurrent_users = 20
      operations_per_user = 5
      total_operations = concurrent_users * operations_per_user
      
      puts "🔄 Starting high-load test with #{concurrent_users} users, #{operations_per_user} operations each"
      
      # Create users concurrently
      user_creation_start = Time.now
      user_threads = []
      created_users = []
      users_mutex = Mutex.new
      
      concurrent_users.times do |i|
        user_threads << Thread.new do
          user_data = {
            username: "load_user_#{i}_#{SecureRandom.hex(6)}",
            email: "load#{i}_#{SecureRandom.hex(6)}@example.com",
            password: 'password123',
            password_confirmation: 'password123'
          }
          
          response = post '/api/auth/register', user_data.to_json, { 'CONTENT_TYPE' => 'application/json' }
          
          if last_response.status == 201
            body = JSON.parse(last_response.body, symbolize_names: true)
            users_mutex.synchronize do
              created_users << {
                id: body[:data][:user][:id],
                token: body[:data][:token],
                username: user_data[:username]
              }
            end
          end
        end
      end
      
      user_threads.each(&:join)
      user_creation_time = Time.now - user_creation_start
      
      expect(created_users.length).to eq(concurrent_users)
      puts "✅ Created #{concurrent_users} users in #{user_creation_time.round(2)}s"
      
      # Create a shared room for all users
      admin_user = created_users.first
      room_data = { name: 'High Load Test Room' }
      post '/api/rooms', room_data.to_json,
           { 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{admin_user[:token]}" }
      room_body = JSON.parse(last_response.body, symbolize_names: true)
      room_id = room_body[:room][:id]
      
      # All users join the room concurrently
      join_start = Time.now
      join_threads = []
      
      created_users[1..-1].each do |user| # Skip admin who's already in the room
        join_threads << Thread.new do
          post "/api/rooms/#{room_id}/join", {}, { 'HTTP_AUTHORIZATION' => "Bearer #{user[:token]}" }
        end
      end
      
      join_threads.each(&:join)
      join_time = Time.now - join_start
      puts "✅ #{concurrent_users - 1} users joined room in #{join_time.round(2)}s"
      
      # Create tracks for voting
      track_count = 8
      tracks = []
      track_count.times do |i|
        track = Track.create(
          id: SecureRandom.uuid,
          room_id: room_id,
          uploader_id: admin_user[:id],
          filename: "load_test_track_#{i}.mp3",
          original_name: "Load Test Track #{i}",
          file_path: "/tmp/load_test_track_#{i}.mp3",
          duration_seconds: rand(120..300),
          file_size_bytes: rand(1_000_000..5_000_000),
          mime_type: 'audio/mpeg',
          vote_score: 0,
          created_at: Time.now,
          updated_at: Time.now
        )
        tracks << track
      end
      
      # Clear events before load test
      WebSocketConnection.clear_published_events
      
      # Perform mixed operations concurrently
      load_test_start = Time.now
      operation_threads = []
      operation_results = []
      results_mutex = Mutex.new
      
      created_users.each do |user|
        operation_threads << Thread.new do
          operations_per_user.times do |op_i|
            # Mix of different operations
            operation_type = [:vote, :room_list, :auth_check].sample
            
            case operation_type
            when :vote
              track = tracks.sample
              response = post "/api/tracks/#{track.id}/vote", {},
                              { 'HTTP_AUTHORIZATION' => "Bearer #{user[:token]}" }
            when :room_list
              response = get '/api/rooms', {}, { 'HTTP_AUTHORIZATION' => "Bearer #{user[:token]}" }
            when :auth_check
              response = get '/api/auth/me', {}, { 'HTTP_AUTHORIZATION' => "Bearer #{user[:token]}" }
            end
            
            results_mutex.synchronize do
              operation_results << {
                thread_id: Thread.current.object_id,
                user_id: user[:id],
                operation: operation_type,
                status: last_response.status,
                timestamp: Time.now.to_f
              }
            end
            
            # Small random delay to simulate real user behavior
            sleep(rand(0.01..0.1))
          end
        end
      end
      
      # Wait for all operations to complete
      operation_threads.each(&:join)
      load_test_time = Time.now - load_test_start
      
      # Analyze results
      expect(operation_results.length).to eq(total_operations)
      
      successful_operations = operation_results.select { |r| r[:status] == 200 }
      success_rate = (successful_operations.length.to_f / total_operations * 100).round(2)
      
      operations_per_second = (total_operations / load_test_time).round(2)
      
      # Verify system performance
      expect(success_rate).to be >= 95.0, "Success rate too low: #{success_rate}%"
      expect(operations_per_second).to be >= 10.0, "Operations per second too low: #{operations_per_second}"
      
      # Check system health after load test
      get '/api/health'
      expect(last_response.status).to eq(200)
      health_data = JSON.parse(last_response.body, symbolize_names: true)
      expect(health_data[:status]).to eq('healthy')
      
      # Verify WebSocket events were handled properly
      events = WebSocketConnection.get_published_events
      expect(events.length).to be > 0
      
      puts "✅ Load test completed successfully:"
      puts "   - Total operations: #{total_operations}"
      puts "   - Success rate: #{success_rate}%"
      puts "   - Operations per second: #{operations_per_second}"
      puts "   - Total time: #{load_test_time.round(2)}s"
      puts "   - WebSocket events: #{events.length}"
      puts "   - Active threads during test: #{operation_results.map { |r| r[:thread_id] }.uniq.length}"
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

  def create_test_room(name: nil, administrator_id: nil)
    name ||= "Room #{SecureRandom.hex(4)}"
    administrator_id ||= create_test_user.id
    
    Room.create(
      id: SecureRandom.uuid,
      name: name,
      administrator_id: administrator_id,
      is_playing: false,
      created_at: Time.now,
      updated_at: Time.now
    )
  end
end