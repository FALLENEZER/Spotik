#!/usr/bin/env ruby

# Simple Property-Based Test for Synchronized Playback Control
# **Feature: ruby-backend-migration, Property 8: Synchronized Playback Control**
# **Validates: Requirements 5.1, 5.2, 5.3, 5.4**

require 'securerandom'
require 'time'

# Mock classes for testing
class MockUser
  attr_accessor :id, :username, :email, :password_hash, :created_at, :updated_at
  
  def initialize(attributes = {})
    @id = attributes[:id] || SecureRandom.uuid
    @username = attributes[:username] || "user_#{SecureRandom.hex(4)}"
    @email = attributes[:email] || "#{@username}@example.com"
    @password_hash = attributes[:password_hash] || 'mock_hash'
    @created_at = attributes[:created_at] || Time.now
    @updated_at = attributes[:updated_at] || Time.now
  end
  
  def to_hash
    {
      id: @id,
      username: @username,
      email: @email,
      created_at: @created_at.iso8601,
      updated_at: @updated_at.iso8601
    }
  end
end

class MockTrack
  attr_accessor :id, :room_id, :uploader_id, :filename, :original_name, :duration_seconds, :file_size_bytes, :mime_type, :vote_score, :created_at, :updated_at
  
  def initialize(attributes = {})
    @id = attributes[:id] || SecureRandom.uuid
    @room_id = attributes[:room_id]
    @uploader_id = attributes[:uploader_id]
    @filename = attributes[:filename] || "track_#{SecureRandom.hex(4)}.mp3"
    @original_name = attributes[:original_name] || "Track #{SecureRandom.hex(4)}.mp3"
    @duration_seconds = attributes[:duration_seconds] || rand(60..300)
    @file_size_bytes = attributes[:file_size_bytes] || rand(1000000..10000000)
    @mime_type = attributes[:mime_type] || 'audio/mpeg'
    @vote_score = attributes[:vote_score] || 0
    @created_at = attributes[:created_at] || Time.now
    @updated_at = attributes[:updated_at] || Time.now
  end
  
  def to_hash
    {
      id: @id,
      room_id: @room_id,
      uploader_id: @uploader_id,
      filename: @filename,
      original_name: @original_name,
      duration_seconds: @duration_seconds,
      file_size_bytes: @file_size_bytes,
      mime_type: @mime_type,
      vote_score: @vote_score,
      created_at: @created_at.iso8601,
      updated_at: @updated_at.iso8601
    }
  end
end

class MockRoom
  attr_accessor :id, :name, :administrator_id, :current_track_id, :playback_started_at, :playback_paused_at, :is_playing, :created_at, :updated_at
  
  def initialize(attributes = {})
    @id = attributes[:id] || SecureRandom.uuid
    @name = attributes[:name] || "Room #{SecureRandom.hex(4)}"
    @administrator_id = attributes[:administrator_id]
    @current_track_id = attributes[:current_track_id]
    @playback_started_at = attributes[:playback_started_at]
    @playback_paused_at = attributes[:playback_paused_at]
    @is_playing = attributes[:is_playing] || false
    @created_at = attributes[:created_at] || Time.now
    @updated_at = attributes[:updated_at] || Time.now
    @tracks = attributes[:tracks] || []
    @participants = attributes[:participants] || []
  end
  
  def administered_by?(user)
    @administrator_id == user.id
  end
  
  def has_participant?(user)
    @participants.any? { |p| p.id == user.id } || administered_by?(user)
  end
  
  def current_track
    @tracks.find { |t| t.id == @current_track_id }
  end
  
  def next_track
    return nil if @tracks.empty?
    
    current_index = @tracks.find_index { |t| t.id == @current_track_id }
    return @tracks.first if current_index.nil?
    
    next_index = current_index + 1
    next_index < @tracks.length ? @tracks[next_index] : nil
  end
  
  def tracks
    @tracks
  end
  
  def add_track(track)
    @tracks << track
  end
  
  def add_participant(user)
    @participants << user unless @participants.any? { |p| p.id == user.id }
  end
  
  def administrator
    MockUser.new(id: @administrator_id, username: "admin_#{SecureRandom.hex(4)}")
  end
  
  def update(attributes)
    attributes.each do |key, value|
      instance_variable_set("@#{key}", value)
    end
    @updated_at = Time.now
  end
  
  def refresh
    self
  end
end

# Mock database models
class Room
  @@rooms = {}
  
  def self.[](id)
    @@rooms[id]
  end
  
  def self.create(attributes)
    room = MockRoom.new(attributes)
    @@rooms[room.id] = room
    room
  end
  
  def self.clear_all
    @@rooms.clear
  end
end

class Track
  @@tracks = {}
  
  def self.[](id)
    @@tracks[id]
  end
  
  def self.create(attributes)
    track = MockTrack.new(attributes)
    @@tracks[track.id] = track
    track
  end
  
  def self.clear_all
    @@tracks.clear
  end
end

class User
  @@users = {}
  
  def self.[](id)
    @@users[id]
  end
  
  def self.create(attributes)
    user = MockUser.new(attributes)
    @@users[user.id] = user
    user
  end
  
  def self.clear_all
    @@users.clear
  end
end

# Mock services
class AuthenticationError < StandardError; end

class AuthService
  def self.validate_jwt(token)
    user_id = token.split('_').last if token.start_with?('valid_token_')
    if user_id && User[user_id]
      { user: User[user_id] }
    else
      raise AuthenticationError.new('Invalid token')
    end
  end
end

class EventBroadcaster
  @@broadcast_log = []
  
  def self.broadcast_playback_activity(room_id, activity_type, user, data)
    @@broadcast_log << {
      room_id: room_id,
      activity_type: activity_type,
      user: user,
      data: data,
      timestamp: Time.now.to_f
    }
  end
  
  def self.last_broadcast
    @@broadcast_log.last
  end
  
  def self.clear_broadcast_log
    @@broadcast_log.clear
  end
  
  def self.broadcast_count
    @@broadcast_log.length
  end
end

# Mock logger
$logger = Object.new
def $logger.info(msg); end
def $logger.error(msg); end
def $logger.debug(msg); end
def $logger.warn(msg); end

# Load the PlaybackController
require_relative 'app/controllers/playback_controller'

puts "=== Property-Based Test: Synchronized Playback Control ==="
puts "Testing universal properties of playback control with timestamp synchronization"
puts "**Validates: Requirements 5.1, 5.2, 5.3, 5.4**"
puts

# Property test helper functions
def create_test_user(is_admin: false)
  User.create({
    username: "user_#{SecureRandom.hex(4)}",
    email: "user_#{SecureRandom.hex(4)}@example.com"
  })
end

def create_test_room(admin_user)
  room = Room.create({
    name: "Room #{SecureRandom.hex(4)}",
    administrator_id: admin_user.id
  })
  room.add_participant(admin_user)
  room
end

def create_test_track(room)
  track = Track.create({
    room_id: room.id,
    uploader_id: room.administrator_id,
    original_name: "Track #{SecureRandom.hex(4)}.mp3",
    duration_seconds: rand(60..300)
  })
  room.add_track(track)
  track
end

def generate_playback_action_sequence
  actions = []
  
  # Always start with a start action
  actions << { type: :start }
  
  # Add random sequence of other actions
  rand(2..6).times do
    actions << { type: [:pause, :resume, :skip].sample }
  end
  
  actions
end

def execute_playback_action(action, room, track, user)
  token = "valid_token_#{user.id}"
  
  case action[:type]
  when :start
    PlaybackController.start_track(room.id, track.id, token)
  when :pause
    PlaybackController.pause_track(room.id, token)
  when :resume
    PlaybackController.resume_track(room.id, token)
  when :skip
    PlaybackController.skip_track(room.id, token)
  when :stop
    PlaybackController.stop_playback(room.id, token)
  else
    { status: 400, body: { error: 'Unknown action' } }
  end
end

# Property Test 1: Synchronized Playback State
def test_synchronized_playback_state
  puts "Property Test 1: Synchronized Playback State"
  puts "For any playback control action by a room administrator, the system should update room state and broadcast with accurate timestamps"
  
  passed_tests = 0
  total_tests = 20
  
  total_tests.times do |iteration|
    # Clear state for each iteration
    Room.clear_all
    Track.clear_all
    User.clear_all
    EventBroadcaster.clear_broadcast_log
    
    # Generate test data
    admin_user = create_test_user(is_admin: true)
    room = create_test_room(admin_user)
    tracks = [create_test_track(room), create_test_track(room)]
    action_sequence = generate_playback_action_sequence
    
    test_passed = true
    
    # Execute the sequence of playback actions
    action_sequence.each_with_index do |action, index|
      
      case action[:type]
      when :start
        track = tracks.sample
        result = execute_playback_action(action, room, track, admin_user)
        
        # Verify playback started correctly (Requirement 5.1)
        if result[:status] != 200
          puts "  ✗ Start track failed on iteration #{iteration}, action #{index}"
          test_passed = false
          break
        end
        
        unless result[:body][:is_playing] && result[:body][:track][:id] == track.id
          puts "  ✗ Playback state incorrect on iteration #{iteration}, action #{index}"
          test_passed = false
          break
        end
        
        # Verify timestamp synchronization
        unless (result[:body][:started_at] - Time.now.to_f).abs < 0.1
          puts "  ✗ Timestamp synchronization failed on iteration #{iteration}, action #{index}"
          test_passed = false
          break
        end
        
        # Verify broadcasting
        broadcast = EventBroadcaster.last_broadcast
        unless broadcast && broadcast[:activity_type] == :started
          puts "  ✗ Broadcasting failed on iteration #{iteration}, action #{index}"
          test_passed = false
          break
        end
        
        # Verify room state updated
        room_state = Room[room.id]
        unless room_state.is_playing && room_state.current_track_id == track.id
          puts "  ✗ Room state not updated on iteration #{iteration}, action #{index}"
          test_passed = false
          break
        end
        
      when :pause
        room_state = Room[room.id]
        next unless room_state && room_state.is_playing
        
        result = execute_playback_action(action, room, nil, admin_user)
        
        # Verify playback paused correctly (Requirement 5.2)
        if result[:status] != 200
          puts "  ✗ Pause track failed on iteration #{iteration}, action #{index}"
          test_passed = false
          break
        end
        
        unless !result[:body][:is_playing]
          puts "  ✗ Pause state incorrect on iteration #{iteration}, action #{index}"
          test_passed = false
          break
        end
        
        # Verify position calculation
        unless result[:body][:position] >= 0
          puts "  ✗ Position calculation failed on iteration #{iteration}, action #{index}"
          test_passed = false
          break
        end
        
        # Verify broadcasting
        broadcast = EventBroadcaster.last_broadcast
        unless broadcast && broadcast[:activity_type] == :paused
          puts "  ✗ Pause broadcasting failed on iteration #{iteration}, action #{index}"
          test_passed = false
          break
        end
        
      when :resume
        room_state = Room[room.id]
        next unless room_state && !room_state.is_playing && room_state.playback_paused_at
        
        result = execute_playback_action(action, room, nil, admin_user)
        
        # Verify playback resumed correctly (Requirement 5.3)
        if result[:status] != 200
          puts "  ✗ Resume track failed on iteration #{iteration}, action #{index}"
          test_passed = false
          break
        end
        
        unless result[:body][:is_playing]
          puts "  ✗ Resume state incorrect on iteration #{iteration}, action #{index}"
          test_passed = false
          break
        end
        
        # Verify broadcasting
        broadcast = EventBroadcaster.last_broadcast
        unless broadcast && broadcast[:activity_type] == :resumed
          puts "  ✗ Resume broadcasting failed on iteration #{iteration}, action #{index}"
          test_passed = false
          break
        end
        
      when :skip
        result = execute_playback_action(action, room, nil, admin_user)
        
        # Verify skip behavior
        if result[:status] != 200
          puts "  ✗ Skip track failed on iteration #{iteration}, action #{index}"
          test_passed = false
          break
        end
        
        # Verify broadcasting - could be either skipped or stopped
        broadcast = EventBroadcaster.last_broadcast
        unless broadcast && [:skipped, :stopped].include?(broadcast[:activity_type])
          puts "  ✗ Skip broadcasting failed on iteration #{iteration}, action #{index}"
          test_passed = false
          break
        end
        
      end
      
      # Verify server-side timestamp calculation (Requirement 5.4)
      if result && result[:status] == 200 && result[:body][:server_time]
        server_time = result[:body][:server_time]
        unless (server_time - Time.now.to_f).abs < 0.1
          puts "  ✗ Server timestamp failed on iteration #{iteration}, action #{index}"
          test_passed = false
          break
        end
        
        # Verify real-time broadcasting occurred
        unless EventBroadcaster.broadcast_count > 0
          puts "  ✗ No broadcasting occurred on iteration #{iteration}, action #{index}"
          test_passed = false
          break
        end
      end
      
      # Small delay to ensure timestamp differences
      sleep(0.01)
    end
    
    passed_tests += 1 if test_passed
  end
  
  puts "  Results: #{passed_tests}/#{total_tests} iterations passed"
  puts "  Success rate: #{((passed_tests.to_f / total_tests) * 100).round(1)}%"
  puts
  
  passed_tests == total_tests
end

# Property Test 2: Playback Position Calculation Accuracy
def test_playback_position_accuracy
  puts "Property Test 2: Playback Position Calculation Accuracy"
  puts "For any playback state, the calculated position should accurately reflect elapsed time based on server timestamps"
  
  passed_tests = 0
  total_tests = 15
  scenarios = [:playing_continuously, :paused_and_resumed, :multiple_pause_resume_cycles]
  
  total_tests.times do |iteration|
    # Clear state for each iteration
    Room.clear_all
    Track.clear_all
    User.clear_all
    EventBroadcaster.clear_broadcast_log
    
    admin_user = create_test_user(is_admin: true)
    room = create_test_room(admin_user)
    track = create_test_track(room)
    
    # Choose random scenario
    scenario = scenarios.sample
    test_passed = true
    
    case scenario
    when :playing_continuously
      # Start playback and check position after random delay
      start_result = execute_playback_action({ type: :start }, room, track, admin_user)
      if start_result[:status] != 200
        puts "  ✗ Start failed on iteration #{iteration} (scenario: #{scenario})"
        next
      end
      
      delay = rand(0.1..1.0)
      sleep(delay)
      
      status_result = PlaybackController.get_playback_status(room.id, "valid_token_#{admin_user.id}")
      if status_result[:status] != 200
        puts "  ✗ Status failed on iteration #{iteration} (scenario: #{scenario})"
        next
      end
      
      expected_position = delay
      actual_position = status_result[:body][:playback_status][:current_position]
      
      unless (actual_position - expected_position).abs < 0.2
        puts "  ✗ Position calculation failed on iteration #{iteration} (scenario: #{scenario})"
        puts "    Expected: #{expected_position.round(3)}s, Actual: #{actual_position.round(3)}s"
        test_passed = false
      end
      
    when :paused_and_resumed
      # Start, pause, wait, resume, check position
      start_result = execute_playback_action({ type: :start }, room, track, admin_user)
      if start_result[:status] != 200
        puts "  ✗ Start failed on iteration #{iteration} (scenario: #{scenario})"
        next
      end
      
      play_duration = rand(0.1..0.5)
      sleep(play_duration)
      
      pause_result = execute_playback_action({ type: :pause }, room, nil, admin_user)
      if pause_result[:status] != 200
        puts "  ✗ Pause failed on iteration #{iteration} (scenario: #{scenario})"
        next
      end
      
      pause_duration = rand(0.1..0.5)
      sleep(pause_duration)
      
      resume_result = execute_playback_action({ type: :resume }, room, nil, admin_user)
      if resume_result[:status] != 200
        puts "  ✗ Resume failed on iteration #{iteration} (scenario: #{scenario})"
        next
      end
      
      additional_play_duration = rand(0.1..0.5)
      sleep(additional_play_duration)
      
      status_result = PlaybackController.get_playback_status(room.id, "valid_token_#{admin_user.id}")
      if status_result[:status] != 200
        puts "  ✗ Status failed on iteration #{iteration} (scenario: #{scenario})"
        next
      end
      
      expected_position = play_duration + additional_play_duration
      actual_position = status_result[:body][:playback_status][:current_position]
      
      unless (actual_position - expected_position).abs < 0.3
        puts "  ✗ Position calculation failed on iteration #{iteration} (scenario: #{scenario})"
        puts "    Expected: #{expected_position.round(3)}s, Actual: #{actual_position.round(3)}s"
        test_passed = false
      end
      
    when :multiple_pause_resume_cycles
      # Multiple pause/resume cycles
      start_result = execute_playback_action({ type: :start }, room, track, admin_user)
      if start_result[:status] != 200
        puts "  ✗ Start failed on iteration #{iteration} (scenario: #{scenario})"
        next
      end
      
      total_play_time = 0
      cycles = rand(2..3)
      
      cycles.times do
        play_duration = rand(0.1..0.3)
        sleep(play_duration)
        total_play_time += play_duration
        
        pause_result = execute_playback_action({ type: :pause }, room, nil, admin_user)
        if pause_result[:status] != 200
          test_passed = false
          break
        end
        
        pause_duration = rand(0.1..0.2)
        sleep(pause_duration)
        
        resume_result = execute_playback_action({ type: :resume }, room, nil, admin_user)
        if resume_result[:status] != 200
          test_passed = false
          break
        end
      end
      
      next unless test_passed
      
      final_play_duration = rand(0.1..0.3)
      sleep(final_play_duration)
      total_play_time += final_play_duration
      
      status_result = PlaybackController.get_playback_status(room.id, "valid_token_#{admin_user.id}")
      if status_result[:status] != 200
        puts "  ✗ Status failed on iteration #{iteration} (scenario: #{scenario})"
        next
      end
      
      actual_position = status_result[:body][:playback_status][:current_position]
      
      unless (actual_position - total_play_time).abs < 0.4
        puts "  ✗ Position calculation failed on iteration #{iteration} (scenario: #{scenario})"
        puts "    Expected: #{total_play_time.round(3)}s, Actual: #{actual_position.round(3)}s"
        test_passed = false
      end
    end
    
    passed_tests += 1 if test_passed
  end
  
  puts "  Results: #{passed_tests}/#{total_tests} iterations passed"
  puts "  Success rate: #{((passed_tests.to_f / total_tests) * 100).round(1)}%"
  puts
  
  passed_tests == total_tests
end

# Property Test 3: Administrator-Only Control Access
def test_administrator_only_access
  puts "Property Test 3: Administrator-Only Control Access"
  puts "For any playback control action, only room administrators should be able to execute the action successfully"
  
  passed_tests = 0
  total_tests = 15
  actions = [:start, :pause, :resume, :skip, :stop]
  
  total_tests.times do |iteration|
    # Clear state for each iteration
    Room.clear_all
    Track.clear_all
    User.clear_all
    EventBroadcaster.clear_broadcast_log
    
    admin_user = create_test_user(is_admin: true)
    regular_user = create_test_user(is_admin: false)
    room = create_test_room(admin_user)
    track = create_test_track(room)
    action = { type: actions.sample }
    
    test_passed = true
    
    # Setup room state for different actions
    case action[:type]
    when :pause, :resume, :skip
      # Start playback first so we can test pause/resume/skip
      start_result = execute_playback_action({ type: :start }, room, track, admin_user)
      if start_result[:status] != 200
        puts "  ✗ Setup failed on iteration #{iteration} (action: #{action[:type]})"
        next
      end
      
      if action[:type] == :resume
        pause_result = execute_playback_action({ type: :pause }, room, nil, admin_user)
        if pause_result[:status] != 200
          puts "  ✗ Setup pause failed on iteration #{iteration} (action: #{action[:type]})"
          next
        end
      end
    end
    
    # Regular user should be denied access
    user_result = execute_playback_action(action, room, track, regular_user)
    unless user_result[:status] == 403
      puts "  ✗ Regular user should be denied access on iteration #{iteration} (action: #{action[:type]})"
      puts "    Got status: #{user_result[:status]}"
      test_passed = false
    end
    
    unless user_result[:body][:error] && user_result[:body][:error].include?('administrator')
      puts "  ✗ Error message should mention administrator on iteration #{iteration} (action: #{action[:type]})"
      test_passed = false
    end
    
    # Admin should be able to control playback (reset state first if needed)
    if action[:type] == :pause
      # Ensure we're playing
      execute_playback_action({ type: :start }, room, track, admin_user)
    elsif action[:type] == :resume
      # Ensure we're paused
      execute_playback_action({ type: :start }, room, track, admin_user)
      execute_playback_action({ type: :pause }, room, nil, admin_user)
    end
    
    admin_result = execute_playback_action(action, room, track, admin_user)
    unless admin_result[:status] == 200
      puts "  ✗ Admin should be able to control playback on iteration #{iteration} (action: #{action[:type]})"
      puts "    Got status: #{admin_result[:status]}, error: #{admin_result[:body][:error]}"
      test_passed = false
    end
    
    passed_tests += 1 if test_passed
  end
  
  puts "  Results: #{passed_tests}/#{total_tests} iterations passed"
  puts "  Success rate: #{((passed_tests.to_f / total_tests) * 100).round(1)}%"
  puts
  
  passed_tests == total_tests
end

# Main test execution
begin
  puts "Running Property-Based Tests for Synchronized Playback Control..."
  puts
  
  # Run all property tests
  test1_passed = test_synchronized_playback_state
  test2_passed = test_playback_position_accuracy
  test3_passed = test_administrator_only_access
  
  # Summary
  total_properties = 3
  passed_properties = [test1_passed, test2_passed, test3_passed].count(true)
  
  puts "=== Property Test Summary ==="
  puts "Properties passed: #{passed_properties}/#{total_properties}"
  puts "Success rate: #{((passed_properties.to_f / total_properties) * 100).round(1)}%"
  puts
  
  if passed_properties == total_properties
    puts "✓ All synchronized playback control properties verified!"
    puts
    puts "Validated Requirements:"
    puts "- ✓ 5.1: Playback start with timestamp broadcasting"
    puts "- ✓ 5.2: Playback pause with position calculation"
    puts "- ✓ 5.3: Playback resume with timestamp adjustment"
    puts "- ✓ 5.4: Server-side timestamp synchronization"
    puts
    puts "Key Properties Verified:"
    puts "- ✓ Synchronized playback state across all control actions"
    puts "- ✓ Accurate playback position calculation using server timestamps"
    puts "- ✓ Administrator-only access control for playback operations"
    puts "- ✓ Real-time event broadcasting for all room participants"
    puts "- ✓ Timestamp-based synchronization with sub-second accuracy"
  else
    puts "✗ Some property tests failed. Please check the implementation."
    puts
    puts "Failed Properties:"
    puts "- Property 1 (Synchronized Playback State): #{test1_passed ? 'PASSED' : 'FAILED'}"
    puts "- Property 2 (Position Calculation Accuracy): #{test2_passed ? 'PASSED' : 'FAILED'}"
    puts "- Property 3 (Administrator-Only Access): #{test3_passed ? 'PASSED' : 'FAILED'}"
  end
  
rescue => e
  puts "✗ Property test execution failed: #{e.message}"
  puts e.backtrace.join("\n")
end

puts
puts "=== Property-Based Test Complete ==="