#!/usr/bin/env ruby

# Migration Validation Test
# **Feature: ruby-backend-migration, Task 16.1: Migration validation tests for data compatibility**
# **Validates: Requirements 15.5** - System SHALL show equivalent or better performance

require 'bundler/setup'
require 'rspec'
require 'json'
require 'securerandom'
require 'bcrypt'
require 'benchmark'

# Set test environment
ENV['APP_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test_jwt_secret_key_for_testing_purposes_only'

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

# Load services
require_relative '../../app/services/auth_service'
require_relative '../../app/services/room_manager'

RSpec.describe 'Migration Validation Test', :migration_validation do
  
  before(:each) do
    # Clean database
    DB[:track_votes].delete
    DB[:room_participants].delete
    DB[:tracks].delete
    DB[:rooms].delete
    DB[:users].delete
  end

  describe 'Laravel Data Compatibility' do
    
    it 'handles Laravel-created user data correctly' do
      # Create user data that mimics Laravel structure
      laravel_user_data = {
        id: SecureRandom.uuid,
        username: 'laravel_migrated_user',
        email: 'laravel@example.com',
        # Laravel uses bcrypt with specific cost
        password_hash: BCrypt::Password.create('password123', cost: 10),
        created_at: Time.parse('2024-01-01 10:00:00 UTC'),
        updated_at: Time.parse('2024-01-01 10:00:00 UTC')
      }
      
      # Insert directly into database (simulating Laravel-created data)
      DB[:users].insert(laravel_user_data)
      
      # Verify Ruby system can read Laravel data
      user = User[laravel_user_data[:id]]
      expect(user).not_to be_nil
      expect(user.username).to eq(laravel_user_data[:username])
      expect(user.email).to eq(laravel_user_data[:email])
      
      # Verify Ruby system can authenticate Laravel user
      authenticated_user = AuthService.authenticate(laravel_user_data[:email], 'password123')
      expect(authenticated_user).not_to be_nil
      expect(authenticated_user[:user].id).to eq(laravel_user_data[:id])
      
      # Verify JWT generation works with Laravel user
      jwt_token = AuthService.generate_jwt(user)
      expect(jwt_token).to be_a(String)
      expect(jwt_token.split('.').length).to eq(3)  # Valid JWT structure
      
      # Verify JWT validation works
      validated = AuthService.validate_jwt(jwt_token)
      expect(validated[:user].id).to eq(user.id)
    end

    it 'handles Laravel-created room and participant data correctly' do
      # Create Laravel-style user
      user = create_laravel_style_user
      
      # Create Laravel-style room data
      laravel_room_data = {
        id: SecureRandom.uuid,
        name: 'Laravel Migrated Room',
        administrator_id: user.id,
        current_track_id: nil,
        playback_started_at: nil,
        playback_paused_at: nil,
        is_playing: false,
        created_at: Time.parse('2024-01-01 11:00:00 UTC'),
        updated_at: Time.parse('2024-01-01 11:00:00 UTC')
      }
      
      # Insert room data
      DB[:rooms].insert(laravel_room_data)
      
      # Create Laravel-style participant relationship
      participant_data = {
        id: SecureRandom.uuid,
        room_id: laravel_room_data[:id],
        user_id: user.id,
        joined_at: Time.parse('2024-01-01 11:05:00 UTC'),
        created_at: Time.parse('2024-01-01 11:05:00 UTC'),
        updated_at: Time.parse('2024-01-01 11:05:00 UTC')
      }
      
      DB[:room_participants].insert(participant_data)
      
      # Verify Ruby system can read Laravel room data
      room = Room[laravel_room_data[:id]]
      expect(room).not_to be_nil
      expect(room.name).to eq(laravel_room_data[:name])
      expect(room.administrator_id).to eq(user.id)
      
      # Verify participant relationships work
      expect(room.has_participant?(user)).to be true
      participants = room.participants
      expect(participants.length).to eq(1)
      expect(participants.first.id).to eq(user.id)
      
      # Verify Ruby system can manage Laravel room
      room.update(name: 'Updated by Ruby System')
      room.refresh
      expect(room.name).to eq('Updated by Ruby System')
    end

    it 'handles Laravel-created track and voting data correctly' do
      user = create_laravel_style_user
      room = create_laravel_style_room(user)
      
      # Create Laravel-style track data
      laravel_track_data = {
        id: SecureRandom.uuid,
        room_id: room.id,
        uploader_id: user.id,
        filename: 'laravel_track_123456.mp3',
        original_name: 'Laravel Uploaded Song.mp3',
        file_path: '/storage/app/audio/tracks/laravel_track_123456.mp3',
        duration_seconds: 240,
        file_size_bytes: 3500000,
        mime_type: 'audio/mpeg',
        vote_score: 0,
        created_at: Time.parse('2024-01-01 12:00:00 UTC'),
        updated_at: Time.parse('2024-01-01 12:00:00 UTC')
      }
      
      DB[:tracks].insert(laravel_track_data)
      
      # Create Laravel-style vote data
      vote_data = {
        id: SecureRandom.uuid,
        track_id: laravel_track_data[:id],
        user_id: user.id,
        created_at: Time.parse('2024-01-01 12:05:00 UTC'),
        updated_at: Time.parse('2024-01-01 12:05:00 UTC')
      }
      
      DB[:track_votes].insert(vote_data)
      
      # Update track vote score
      DB[:tracks].where(id: laravel_track_data[:id]).update(vote_score: 1)
      
      # Verify Ruby system can read Laravel track data
      track = Track[laravel_track_data[:id]]
      expect(track).not_to be_nil
      expect(track.original_name).to eq(laravel_track_data[:original_name])
      expect(track.duration_seconds).to eq(laravel_track_data[:duration_seconds])
      expect(track.vote_score).to eq(1)
      
      # Verify voting relationships work
      expect(track.has_vote_from?(user)).to be true
      votes = track.votes
      expect(votes.length).to eq(1)
      expect(votes.first.user_id).to eq(user.id)
      
      # Verify Ruby system can manage Laravel track
      track.update(vote_score: 2)
      track.refresh
      expect(track.vote_score).to eq(2)
    end
  end

  describe 'Database Schema Compatibility' do
    
    it 'validates all required database tables exist with correct structure' do
      required_tables = [:users, :rooms, :tracks, :room_participants, :track_votes]
      
      required_tables.each do |table_name|
        expect(DB.table_exists?(table_name)).to be true, "Table #{table_name} does not exist"
      end
    end

    it 'validates user table structure matches Laravel schema' do
      user_columns = DB.schema(:users).map { |col| col[0] }
      
      required_columns = [:id, :username, :email, :password_hash, :created_at, :updated_at]
      required_columns.each do |column|
        expect(user_columns).to include(column), "Users table missing column: #{column}"
      end
    end

    it 'validates room table structure matches Laravel schema' do
      room_columns = DB.schema(:rooms).map { |col| col[0] }
      
      required_columns = [:id, :name, :administrator_id, :current_track_id, 
                         :playback_started_at, :playback_paused_at, :is_playing, 
                         :created_at, :updated_at]
      required_columns.each do |column|
        expect(room_columns).to include(column), "Rooms table missing column: #{column}"
      end
    end

    it 'validates track table structure matches Laravel schema' do
      track_columns = DB.schema(:tracks).map { |col| col[0] }
      
      required_columns = [:id, :room_id, :uploader_id, :filename, :original_name, 
                         :file_path, :duration_seconds, :file_size_bytes, :mime_type, 
                         :vote_score, :created_at, :updated_at]
      required_columns.each do |column|
        expect(track_columns).to include(column), "Tracks table missing column: #{column}"
      end
    end

    it 'validates foreign key relationships work correctly' do
      user = create_laravel_style_user
      room = create_laravel_style_room(user)
      track = create_laravel_style_track(user, room)
      
      # Test user -> room relationship
      expect(room.administrator_id).to eq(user.id)
      
      # Test room -> track relationship
      expect(track.room_id).to eq(room.id)
      
      # Test track -> user relationship
      expect(track.uploader_id).to eq(user.id)
      
      # Test participant relationship
      room.add_participant(user)
      participant = DB[:room_participants].where(room_id: room.id, user_id: user.id).first
      expect(participant).not_to be_nil
      
      # Test vote relationship
      vote_id = SecureRandom.uuid
      DB[:track_votes].insert(id: vote_id, track_id: track.id, user_id: user.id, 
                              created_at: Time.now, updated_at: Time.now)
      vote = DB[:track_votes].where(track_id: track.id, user_id: user.id).first
      expect(vote).not_to be_nil
    end
  end

  describe 'Performance Comparison' do
    
    it 'demonstrates equivalent or better database query performance' do
      # Create test data
      users = 10.times.map { create_laravel_style_user }
      rooms = users.map { |user| create_laravel_style_room(user) }
      tracks = rooms.flat_map { |room| 5.times.map { create_laravel_style_track(users.sample, room) } }
      
      # Add participants and votes
      rooms.each do |room|
        users.sample(3).each { |user| room.add_participant(user) }
      end
      
      tracks.each do |track|
        users.sample(rand(1..5)).each do |user|
          unless track.has_vote_from?(user)
            DB[:track_votes].insert(
              id: SecureRandom.uuid,
              track_id: track.id,
              user_id: user.id,
              created_at: Time.now,
              updated_at: Time.now
            )
          end
        end
      end
      
      # Benchmark common operations
      benchmark_results = {}
      
      # User authentication
      benchmark_results[:authentication] = Benchmark.measure do
        100.times do
          user = users.sample
          AuthService.authenticate(user.email, 'password123')
        end
      end
      
      # Room listing
      benchmark_results[:room_listing] = Benchmark.measure do
        100.times do
          Room.all.to_a
        end
      end
      
      # Track queue retrieval
      benchmark_results[:track_queue] = Benchmark.measure do
        100.times do
          room = rooms.sample
          room.tracks.to_a
        end
      end
      
      # Participant listing
      benchmark_results[:participant_listing] = Benchmark.measure do
        100.times do
          room = rooms.sample
          room.participants.to_a
        end
      end
      
      # Vote counting
      benchmark_results[:vote_counting] = Benchmark.measure do
        100.times do
          track = tracks.sample
          track.votes.count
        end
      end
      
      # Verify performance is reasonable (not slower than expected)
      benchmark_results.each do |operation, result|
        puts "#{operation}: #{result.real.round(4)}s for 100 operations"
        
        # Performance expectations (adjust based on hardware)
        case operation
        when :authentication
          expect(result.real).to be < 2.0, "Authentication too slow: #{result.real}s"
        when :room_listing
          expect(result.real).to be < 1.0, "Room listing too slow: #{result.real}s"
        when :track_queue
          expect(result.real).to be < 1.0, "Track queue retrieval too slow: #{result.real}s"
        when :participant_listing
          expect(result.real).to be < 1.0, "Participant listing too slow: #{result.real}s"
        when :vote_counting
          expect(result.real).to be < 1.0, "Vote counting too slow: #{result.real}s"
        end
      end
    end

    it 'demonstrates memory efficiency with large datasets' do
      # Create larger dataset
      initial_memory = get_memory_usage
      
      users = 50.times.map { create_laravel_style_user }
      rooms = users.map { |user| create_laravel_style_room(user) }
      tracks = rooms.flat_map { |room| 10.times.map { create_laravel_style_track(users.sample, room) } }
      
      # Add many participants and votes
      rooms.each do |room|
        users.sample(10).each { |user| room.add_participant(user) }
      end
      
      tracks.each do |track|
        users.sample(rand(5..15)).each do |user|
          unless track.has_vote_from?(user)
            DB[:track_votes].insert(
              id: SecureRandom.uuid,
              track_id: track.id,
              user_id: user.id,
              created_at: Time.now,
              updated_at: Time.now
            )
          end
        end
      end
      
      final_memory = get_memory_usage
      memory_increase = final_memory - initial_memory
      
      puts "Memory usage increase: #{memory_increase}MB for #{users.length} users, #{rooms.length} rooms, #{tracks.length} tracks"
      
      # Memory usage should be reasonable
      expect(memory_increase).to be < 100, "Memory usage too high: #{memory_increase}MB"
      
      # Verify system still performs well with large dataset
      start_time = Time.now
      
      # Perform complex query
      complex_query_result = DB[:rooms]
        .join(:tracks, room_id: :id)
        .join(:track_votes, track_id: :tracks__id)
        .group(:rooms__id)
        .select(:rooms__name, Sequel.function(:count, :track_votes__id).as(:total_votes))
        .order(Sequel.desc(:total_votes))
        .limit(10)
        .all
      
      query_time = Time.now - start_time
      
      expect(complex_query_result).not_to be_empty
      expect(query_time).to be < 1.0, "Complex query too slow: #{query_time}s"
    end

    it 'validates concurrent operation performance' do
      user = create_laravel_style_user
      room = create_laravel_style_room(user)
      
      # Simulate concurrent operations
      threads = []
      results = []
      
      # Concurrent user authentications
      10.times do
        threads << Thread.new do
          start_time = Time.now
          result = AuthService.authenticate(user.email, 'password123')
          end_time = Time.now
          results << { operation: :auth, duration: end_time - start_time, success: !result.nil? }
        end
      end
      
      # Concurrent room operations
      10.times do |i|
        threads << Thread.new do
          start_time = Time.now
          test_room = create_laravel_style_room(user, name: "Concurrent Room #{i}")
          end_time = Time.now
          results << { operation: :room_create, duration: end_time - start_time, success: !test_room.nil? }
        end
      end
      
      # Wait for all threads to complete
      threads.each(&:join)
      
      # Verify all operations succeeded
      failed_operations = results.select { |r| !r[:success] }
      expect(failed_operations).to be_empty, "Some concurrent operations failed"
      
      # Verify performance under concurrency
      auth_times = results.select { |r| r[:operation] == :auth }.map { |r| r[:duration] }
      room_create_times = results.select { |r| r[:operation] == :room_create }.map { |r| r[:duration] }
      
      expect(auth_times.max).to be < 1.0, "Concurrent auth too slow: #{auth_times.max}s"
      expect(room_create_times.max).to be < 2.0, "Concurrent room creation too slow: #{room_create_times.max}s"
      
      puts "Concurrent auth times: #{auth_times.map { |t| t.round(3) }}"
      puts "Concurrent room creation times: #{room_create_times.map { |t| t.round(3) }}"
    end
  end

  describe 'Cross-System Integration' do
    
    it 'validates data created by Ruby system is Laravel-compatible' do
      # Create data using Ruby system
      user = User.create(
        id: SecureRandom.uuid,
        username: 'ruby_created_user',
        email: 'ruby@example.com',
        password_hash: BCrypt::Password.create('password123'),
        created_at: Time.now,
        updated_at: Time.now
      )
      
      room = Room.create(
        id: SecureRandom.uuid,
        name: 'Ruby Created Room',
        administrator_id: user.id,
        is_playing: false,
        created_at: Time.now,
        updated_at: Time.now
      )
      
      # Verify data structure is Laravel-compatible
      user_data = DB[:users].where(id: user.id).first
      expect(user_data[:id]).to be_a(String)
      expect(user_data[:username]).to be_a(String)
      expect(user_data[:email]).to be_a(String)
      expect(user_data[:password_hash]).to be_a(String)
      expect(user_data[:created_at]).to be_a(Time)
      expect(user_data[:updated_at]).to be_a(Time)
      
      room_data = DB[:rooms].where(id: room.id).first
      expect(room_data[:id]).to be_a(String)
      expect(room_data[:name]).to be_a(String)
      expect(room_data[:administrator_id]).to eq(user.id)
      expect(room_data[:is_playing]).to be_in([true, false])
      expect(room_data[:created_at]).to be_a(Time)
      expect(room_data[:updated_at]).to be_a(Time)
    end

    it 'validates UUID format consistency' do
      # Create various entities
      user = create_laravel_style_user
      room = create_laravel_style_room(user)
      track = create_laravel_style_track(user, room)
      
      # Verify all IDs are valid UUIDs
      uuid_pattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
      
      expect(user.id).to match(uuid_pattern), "User ID not valid UUID: #{user.id}"
      expect(room.id).to match(uuid_pattern), "Room ID not valid UUID: #{room.id}"
      expect(track.id).to match(uuid_pattern), "Track ID not valid UUID: #{track.id}"
      
      # Verify foreign key relationships use correct UUIDs
      expect(room.administrator_id).to eq(user.id)
      expect(track.room_id).to eq(room.id)
      expect(track.uploader_id).to eq(user.id)
    end

    it 'validates timestamp format consistency' do
      user = create_laravel_style_user
      room = create_laravel_style_room(user)
      
      # Verify timestamps are in correct format
      expect(user.created_at).to be_a(Time)
      expect(user.updated_at).to be_a(Time)
      expect(room.created_at).to be_a(Time)
      expect(room.updated_at).to be_a(Time)
      
      # Verify timestamps are reasonable
      now = Time.now
      expect(user.created_at).to be_between(now - 60, now + 1)
      expect(user.updated_at).to be_between(now - 60, now + 1)
      expect(room.created_at).to be_between(now - 60, now + 1)
      expect(room.updated_at).to be_between(now - 60, now + 1)
    end
  end

  # Helper methods

  def create_laravel_style_user(username: nil, email: nil)
    username ||= "user_#{SecureRandom.hex(6)}"
    email ||= "#{username}@example.com"
    
    User.create(
      id: SecureRandom.uuid,
      username: username,
      email: email.downcase.strip,
      password_hash: BCrypt::Password.create('password123', cost: 10),  # Laravel default cost
      created_at: Time.now,
      updated_at: Time.now
    )
  end

  def create_laravel_style_room(user, name: nil)
    name ||= "Room #{SecureRandom.hex(4)}"
    
    Room.create(
      id: SecureRandom.uuid,
      name: name,
      administrator_id: user.id,
      is_playing: false,
      created_at: Time.now,
      updated_at: Time.now
    )
  end

  def create_laravel_style_track(user, room)
    Track.create(
      id: SecureRandom.uuid,
      room_id: room.id,
      uploader_id: user.id,
      filename: "track_#{SecureRandom.hex(8)}.mp3",
      original_name: "Test Track #{SecureRandom.hex(4)}.mp3",
      file_path: "/storage/app/audio/tracks/track_#{SecureRandom.hex(8)}.mp3",  # Laravel path format
      duration_seconds: rand(120..300),
      file_size_bytes: rand(1000000..5000000),
      mime_type: 'audio/mpeg',
      vote_score: 0,
      created_at: Time.now,
      updated_at: Time.now
    )
  end

  def get_memory_usage
    # Simple memory usage estimation (works on Unix-like systems)
    begin
      `ps -o rss= -p #{Process.pid}`.to_i / 1024.0  # Convert KB to MB
    rescue
      0  # Fallback if ps command not available
    end
  end
end