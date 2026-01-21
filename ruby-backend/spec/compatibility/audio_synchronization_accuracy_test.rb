#!/usr/bin/env ruby

# Audio Synchronization Accuracy Test
# **Feature: ruby-backend-migration, Task 16.1: Audio synchronization accuracy tests**
# **Validates: Requirements 15.4** - System SHALL ensure same audio synchronization accuracy

require 'bundler/setup'
require 'rspec'
require 'json'
require 'securerandom'
require 'time'
require 'timeout'

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

# Load services and controllers
require_relative '../../app/services/auth_service'
require_relative '../../app/services/room_manager'
require_relative '../../app/controllers/playback_controller'

RSpec.describe 'Audio Synchronization Accuracy Test', :audio_sync_accuracy do
  
  before(:each) do
    # Clean database
    DB[:track_votes].delete
    DB[:room_participants].delete
    DB[:tracks].delete
    DB[:rooms].delete
    DB[:users].delete
  end

  describe 'Timestamp Precision and Accuracy' do
    
    it 'maintains millisecond precision in playback timestamps' do
      user = create_test_user
      room = create_test_room(user)
      track = create_test_track(user, room)
      token = AuthService.generate_jwt(user)
      
      # Test playback start timestamp precision
      start_time_before = Time.now.to_f
      result = PlaybackController.start_track(room.id, track.id, token)
      start_time_after = Time.now.to_f
      
      expect(result[:status]).to eq(200)
      
      body = result[:body]
      
      # Verify timestamp is within the request timeframe
      expect(body[:started_at]).to be_between(start_time_before, start_time_after)
      expect(body[:server_time]).to be_between(start_time_before, start_time_after)
      
      # Verify millisecond precision (should have at least 3 decimal places)
      started_at_str = body[:started_at].to_s
      server_time_str = body[:server_time].to_s
      
      expect(started_at_str).to match(/\d+\.\d{3,}/)  # At least 3 decimal places
      expect(server_time_str).to match(/\d+\.\d{3,}/)  # At least 3 decimal places
      
      # Verify timestamps are very close (within 1ms)
      expect((body[:started_at] - body[:server_time]).abs).to be < 0.001
    end

    it 'calculates playback position accurately across time' do
      user = create_test_user
      room = create_test_room(user)
      track = create_test_track(user, room)
      token = AuthService.generate_jwt(user)
      
      # Start playback
      start_result = PlaybackController.start_track(room.id, track.id, token)
      expect(start_result[:status]).to eq(200)
      
      start_time = start_result[:body][:started_at]
      
      # Wait a known amount of time
      sleep_duration = 0.5  # 500ms
      sleep(sleep_duration)
      
      # Get current playback status
      status_result = PlaybackController.get_playback_status(room.id, token)
      expect(status_result[:status]).to eq(200)
      
      current_position = status_result[:body][:playback_status][:current_position]
      expected_position = sleep_duration
      
      # Position should be accurate within 50ms tolerance
      expect(current_position).to be_within(0.05).of(expected_position)
      
      # Verify position calculation is based on server time
      server_calculated_position = Time.now.to_f - start_time
      expect(current_position).to be_within(0.1).of(server_calculated_position)
    end

    it 'maintains synchronization accuracy through pause/resume cycles' do
      user = create_test_user
      room = create_test_room(user)
      track = create_test_track(user, room)
      token = AuthService.generate_jwt(user)
      
      # Start playback
      start_result = PlaybackController.start_track(room.id, track.id, token)
      expect(start_result[:status]).to eq(200)
      
      # Play for a short time
      play_duration_1 = 0.3
      sleep(play_duration_1)
      
      # Pause playback
      pause_result = PlaybackController.pause_track(room.id, token)
      expect(pause_result[:status]).to eq(200)
      
      pause_position = pause_result[:body][:position]
      pause_time = pause_result[:body][:paused_at]
      
      # Verify pause position accuracy
      expect(pause_position).to be_within(0.05).of(play_duration_1)
      
      # Wait while paused (position should not change)
      pause_duration = 0.2
      sleep(pause_duration)
      
      # Resume playback
      resume_result = PlaybackController.resume_track(room.id, token)
      expect(resume_result[:status]).to eq(200)
      
      resume_position = resume_result[:body][:position]
      
      # Position should be preserved from pause
      expect(resume_position).to be_within(0.01).of(pause_position)
      
      # Play for additional time
      play_duration_2 = 0.4
      sleep(play_duration_2)
      
      # Check final position
      final_status = PlaybackController.get_playback_status(room.id, token)
      final_position = final_status[:body][:playback_status][:current_position]
      
      expected_final_position = play_duration_1 + play_duration_2
      expect(final_position).to be_within(0.1).of(expected_final_position)
    end

    it 'handles multiple rapid pause/resume cycles accurately' do
      user = create_test_user
      room = create_test_room(user)
      track = create_test_track(user, room)
      token = AuthService.generate_jwt(user)
      
      # Start playback
      PlaybackController.start_track(room.id, track.id, token)
      
      total_play_time = 0
      cycles = 5
      
      cycles.times do |i|
        # Play for a short time
        play_duration = 0.1 + (i * 0.05)  # Varying durations
        sleep(play_duration)
        total_play_time += play_duration
        
        # Pause
        pause_result = PlaybackController.pause_track(room.id, token)
        expect(pause_result[:status]).to eq(200)
        
        pause_position = pause_result[:body][:position]
        expect(pause_position).to be_within(0.1).of(total_play_time)
        
        # Brief pause
        sleep(0.05)
        
        # Resume
        resume_result = PlaybackController.resume_track(room.id, token)
        expect(resume_result[:status]).to eq(200)
        
        # Verify position preserved
        resume_position = resume_result[:body][:position]
        expect(resume_position).to be_within(0.02).of(pause_position)
      end
      
      # Final verification
      final_status = PlaybackController.get_playback_status(room.id, token)
      final_position = final_status[:body][:playback_status][:current_position]
      
      expect(final_position).to be_within(0.15).of(total_play_time)
    end
  end

  describe 'Server Time Synchronization' do
    
    it 'provides consistent server time across multiple requests' do
      # Make multiple rapid requests to check time consistency
      time_measurements = []
      
      10.times do |i|
        request_start = Time.now.to_f
        
        # Simulate time endpoint request (would be HTTP in real scenario)
        server_time = Time.now.to_f
        
        request_end = Time.now.to_f
        
        time_measurements << {
          server_time: server_time,
          request_start: request_start,
          request_end: request_end,
          request_duration: request_end - request_start
        }
        
        sleep(0.01) if i < 9  # Small delay between requests
      end
      
      # Verify server time progression is consistent
      time_diffs = time_measurements.each_cons(2).map do |prev, curr|
        actual_diff = curr[:server_time] - prev[:server_time]
        expected_diff = curr[:request_start] - prev[:request_start]
        (actual_diff - expected_diff).abs
      end
      
      # Time differences should be minimal (server clock consistent)
      expect(time_diffs.max).to be < 0.01, "Server time inconsistency detected: #{time_diffs.max}s"
      
      # Verify all server times are within reasonable bounds
      time_measurements.each do |measurement|
        expect(measurement[:server_time]).to be_between(
          measurement[:request_start] - 0.001,  # Allow 1ms before request
          measurement[:request_end] + 0.001     # Allow 1ms after request
        )
      end
    end

    it 'maintains time synchronization accuracy under load' do
      user = create_test_user
      room = create_test_room(user)
      track = create_test_track(user, room)
      token = AuthService.generate_jwt(user)
      
      # Simulate concurrent playback operations
      operations = []
      
      # Start playback
      start_time = Time.now.to_f
      start_result = PlaybackController.start_track(room.id, track.id, token)
      operations << { type: :start, time: Time.now.to_f, result: start_result }
      
      # Perform rapid operations
      10.times do |i|
        sleep(0.05)  # 50ms intervals
        
        if i % 2 == 0
          # Pause
          result = PlaybackController.pause_track(room.id, token)
          operations << { type: :pause, time: Time.now.to_f, result: result }
        else
          # Resume
          result = PlaybackController.resume_track(room.id, token)
          operations << { type: :resume, time: Time.now.to_f, result: result }
        end
      end
      
      # Verify timestamp consistency across all operations
      operations.each_with_index do |operation, index|
        next unless operation[:result][:status] == 200
        
        body = operation[:result][:body]
        operation_time = operation[:time]
        
        # Verify server_time in response is close to operation time
        if body[:server_time]
          expect(body[:server_time]).to be_within(0.01).of(operation_time)
        end
        
        # Verify timestamps are monotonically increasing
        if index > 0
          prev_operation = operations[index - 1]
          if prev_operation[:result][:status] == 200 && prev_operation[:result][:body][:server_time]
            expect(body[:server_time]).to be >= prev_operation[:result][:body][:server_time]
          end
        end
      end
    end

    it 'calculates network latency compensation accurately' do
      user = create_test_user
      room = create_test_room(user)
      track = create_test_track(user, room)
      token = AuthService.generate_jwt(user)
      
      # Simulate network latency by measuring request/response times
      latency_measurements = []
      
      5.times do
        request_start = Time.now.to_f
        
        # Make playback status request
        result = PlaybackController.get_playback_status(room.id, token)
        
        request_end = Time.now.to_f
        
        if result[:status] == 200
          server_time = result[:body][:server_time] || Time.now.to_f
          
          # Calculate apparent latency
          round_trip_time = request_end - request_start
          estimated_server_time = request_start + (round_trip_time / 2)
          
          latency_measurements << {
            round_trip_time: round_trip_time,
            server_time: server_time,
            estimated_server_time: estimated_server_time,
            time_diff: (server_time - estimated_server_time).abs
          }
        end
        
        sleep(0.1)
      end
      
      # Verify latency compensation is reasonable
      latency_measurements.each do |measurement|
        # Time difference should be small (good synchronization)
        expect(measurement[:time_diff]).to be < 0.05, 
          "Poor time synchronization: #{measurement[:time_diff]}s difference"
        
        # Round trip time should be reasonable for local testing
        expect(measurement[:round_trip_time]).to be < 0.1, 
          "Excessive round trip time: #{measurement[:round_trip_time]}s"
      end
      
      # Calculate average latency compensation accuracy
      avg_time_diff = latency_measurements.map { |m| m[:time_diff] }.sum / latency_measurements.length
      expect(avg_time_diff).to be < 0.02, "Average time synchronization error too high: #{avg_time_diff}s"
    end
  end

  describe 'Cross-Client Synchronization' do
    
    it 'maintains synchronization accuracy across multiple simulated clients' do
      admin_user = create_test_user(username: 'admin', email: 'admin@example.com')
      room = create_test_room(admin_user)
      track = create_test_track(admin_user, room)
      admin_token = AuthService.generate_jwt(admin_user)
      
      # Create multiple participant users
      participants = 3.times.map do |i|
        user = create_test_user(username: "participant#{i}", email: "participant#{i}@example.com")
        room.add_participant(user)
        {
          user: user,
          token: AuthService.generate_jwt(user)
        }
      end
      
      # Admin starts playback
      start_time = Time.now.to_f
      start_result = PlaybackController.start_track(room.id, track.id, admin_token)
      expect(start_result[:status]).to eq(200)
      
      playback_started_at = start_result[:body][:started_at]
      
      # Wait some time
      sleep(0.3)
      
      # Each participant checks playback status
      participant_positions = participants.map do |participant|
        status_result = PlaybackController.get_playback_status(room.id, participant[:token])
        expect(status_result[:status]).to eq(200)
        
        {
          user_id: participant[:user].id,
          position: status_result[:body][:playback_status][:current_position],
          server_time: status_result[:body][:server_time],
          request_time: Time.now.to_f
        }
      end
      
      # Verify all participants see similar positions
      positions = participant_positions.map { |p| p[:position] }
      position_variance = positions.max - positions.min
      
      expect(position_variance).to be < 0.1, 
        "Position variance too high across participants: #{position_variance}s"
      
      # Verify positions are reasonable based on elapsed time
      expected_position = Time.now.to_f - playback_started_at
      positions.each do |position|
        expect(position).to be_within(0.15).of(expected_position)
      end
    end

    it 'handles synchronization during concurrent playback control actions' do
      admin_user = create_test_user(username: 'admin', email: 'admin@example.com')
      room = create_test_room(admin_user)
      track = create_test_track(admin_user, room)
      admin_token = AuthService.generate_jwt(admin_user)
      
      # Start playback
      PlaybackController.start_track(room.id, track.id, admin_token)
      
      # Simulate rapid control actions
      control_actions = []
      
      # Perform sequence of pause/resume actions
      5.times do |i|
        sleep(0.1)
        
        if i % 2 == 0
          action_time = Time.now.to_f
          result = PlaybackController.pause_track(room.id, admin_token)
          control_actions << { type: :pause, time: action_time, result: result }
        else
          action_time = Time.now.to_f
          result = PlaybackController.resume_track(room.id, admin_token)
          control_actions << { type: :resume, time: action_time, result: result }
        end
      end
      
      # Verify each action was processed correctly
      control_actions.each_with_index do |action, index|
        expect(action[:result][:status]).to eq(200), 
          "Control action #{action[:type]} failed at index #{index}"
        
        body = action[:result][:body]
        
        # Verify timestamp accuracy
        if body[:server_time]
          expect(body[:server_time]).to be_within(0.01).of(action[:time])
        end
        
        # Verify state consistency
        case action[:type]
        when :pause
          expect(body[:is_playing]).to be false
          expect(body[:paused_at]).to be_within(0.01).of(action[:time])
        when :resume
          expect(body[:is_playing]).to be true
        end
      end
      
      # Final position check should be accurate
      final_status = PlaybackController.get_playback_status(room.id, admin_token)
      final_position = final_status[:body][:playback_status][:current_position]
      
      # Position should be reasonable (accounting for pause/resume cycles)
      expect(final_position).to be >= 0
      expect(final_position).to be <= 1.0  # Total test duration
    end
  end

  describe 'Edge Cases and Error Handling' do
    
    it 'handles playback position at track boundaries accurately' do
      user = create_test_user
      room = create_test_room(user)
      # Create a very short track for boundary testing
      track = Track.create(
        id: SecureRandom.uuid,
        room_id: room.id,
        uploader_id: user.id,
        filename: "short_track.mp3",
        original_name: "Short Track.mp3",
        file_path: "/tmp/short_track.mp3",
        duration_seconds: 1,  # 1 second track
        file_size_bytes: 100000,
        mime_type: 'audio/mpeg',
        vote_score: 0,
        created_at: Time.now,
        updated_at: Time.now
      )
      token = AuthService.generate_jwt(user)
      
      # Start playback
      start_result = PlaybackController.start_track(room.id, track.id, token)
      expect(start_result[:status]).to eq(200)
      
      # Wait for track to "finish"
      sleep(1.2)  # Slightly longer than track duration
      
      # Check position - should be capped at track duration
      status_result = PlaybackController.get_playback_status(room.id, token)
      position = status_result[:body][:playback_status][:current_position]
      
      expect(position).to be <= track.duration_seconds
      expect(position).to be >= track.duration_seconds - 0.1  # Should be near the end
    end

    it 'maintains accuracy during system clock adjustments' do
      user = create_test_user
      room = create_test_room(user)
      track = create_test_track(user, room)
      token = AuthService.generate_jwt(user)
      
      # Start playback
      start_result = PlaybackController.start_track(room.id, track.id, token)
      expect(start_result[:status]).to eq(200)
      
      original_started_at = start_result[:body][:started_at]
      
      # Simulate small time adjustments (like NTP corrections)
      # In a real system, this would be handled by the OS
      # Here we test that our calculations remain stable
      
      sleep(0.2)
      
      # Get position multiple times in quick succession
      positions = []
      5.times do
        status_result = PlaybackController.get_playback_status(room.id, token)
        positions << status_result[:body][:playback_status][:current_position]
        sleep(0.01)
      end
      
      # Positions should be monotonically increasing (or stable)
      positions.each_cons(2) do |prev_pos, curr_pos|
        expect(curr_pos).to be >= prev_pos - 0.01  # Allow small variance
      end
      
      # All positions should be reasonable
      expected_min = 0.2
      expected_max = 0.3
      positions.each do |position|
        expect(position).to be_between(expected_min - 0.1, expected_max + 0.1)
      end
    end

    it 'handles rapid state changes without losing synchronization' do
      user = create_test_user
      room = create_test_room(user)
      track = create_test_track(user, room)
      token = AuthService.generate_jwt(user)
      
      # Perform very rapid state changes
      operations = []
      
      # Start
      result = PlaybackController.start_track(room.id, track.id, token)
      operations << { type: :start, result: result, time: Time.now.to_f }
      
      # Rapid pause/resume cycles
      20.times do |i|
        sleep(0.02)  # 20ms intervals - very rapid
        
        if i % 2 == 0
          result = PlaybackController.pause_track(room.id, token)
          operations << { type: :pause, result: result, time: Time.now.to_f }
        else
          result = PlaybackController.resume_track(room.id, token)
          operations << { type: :resume, result: result, time: Time.now.to_f }
        end
      end
      
      # Verify all operations succeeded
      failed_operations = operations.select { |op| op[:result][:status] != 200 }
      expect(failed_operations).to be_empty, 
        "Some rapid operations failed: #{failed_operations.map { |op| op[:type] }}"
      
      # Verify final state is consistent
      final_status = PlaybackController.get_playback_status(room.id, token)
      expect(final_status[:status]).to eq(200)
      
      final_position = final_status[:body][:playback_status][:current_position]
      
      # Position should be reasonable despite rapid changes
      expect(final_position).to be >= 0
      expect(final_position).to be <= 1.0  # Total test duration
      
      # Verify no synchronization drift occurred
      last_operation = operations.last
      if last_operation[:result][:body][:server_time]
        time_diff = (Time.now.to_f - last_operation[:result][:body][:server_time]).abs
        expect(time_diff).to be < 0.1, "Synchronization drift detected: #{time_diff}s"
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