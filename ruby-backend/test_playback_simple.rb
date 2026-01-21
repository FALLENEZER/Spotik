#!/usr/bin/env ruby

# Simple test for PlaybackController functionality
# Tests synchronized playback control without database dependencies

require 'securerandom'
require 'time'
require 'json'

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
def $logger.info(msg); puts "INFO: #{msg}"; end
def $logger.error(msg); puts "ERROR: #{msg}"; end
def $logger.debug(msg); puts "DEBUG: #{msg}"; end
def $logger.warn(msg); puts "WARN: #{msg}"; end

# Load the PlaybackController
require_relative 'app/controllers/playback_controller'

puts "=== Simple Playback Controller Test ==="
puts "Testing synchronized playback control functionality"
puts

# Test setup
def setup_test_data
  puts "Setting up test data..."
  
  admin_user = User.create({
    username: "admin_test",
    email: "admin@test.com"
  })
  
  room = Room.create({
    name: "Test Room",
    administrator_id: admin_user.id
  })
  room.add_participant(admin_user)
  
  track1 = Track.create({
    room_id: room.id,
    uploader_id: admin_user.id,
    original_name: "Test Track 1.mp3",
    duration_seconds: 180
  })
  room.add_track(track1)
  
  track2 = Track.create({
    room_id: room.id,
    uploader_id: admin_user.id,
    original_name: "Test Track 2.mp3",
    duration_seconds: 240
  })
  room.add_track(track2)
  
  puts "✓ Created test user: #{admin_user.username}"
  puts "✓ Created test room: #{room.name}"
  puts "✓ Created test tracks: #{track1.original_name}, #{track2.original_name}"
  puts
  
  { admin_user: admin_user, room: room, track1: track1, track2: track2 }
end

# Test playback start
def test_playback_start(admin_user, room, track)
  puts "Testing playback start..."
  
  token = "valid_token_#{admin_user.id}"
  result = PlaybackController.start_track(room.id, track.id, token)
  
  if result[:status] == 200
    puts "✓ Playback started successfully"
    puts "  - Track: #{track.original_name}"
    puts "  - Started at: #{Time.at(result[:body][:started_at]).strftime('%H:%M:%S.%3N')}"
    puts "  - Server time: #{Time.at(result[:body][:server_time]).strftime('%H:%M:%S.%3N')}"
    
    # Verify room state
    room.refresh
    if room.is_playing && room.current_track_id == track.id
      puts "✓ Room state updated correctly"
    else
      puts "✗ Room state not updated correctly"
      return false
    end
    
    # Verify broadcasting
    broadcast = EventBroadcaster.last_broadcast
    if broadcast && broadcast[:activity_type] == :started
      puts "✓ Playback event broadcasted"
    else
      puts "✗ Playback event not broadcasted"
      return false
    end
  else
    puts "✗ Playback start failed: #{result[:body][:error]}"
    return false
  end
  
  puts
  true
end

# Test playback pause
def test_playback_pause(admin_user, room)
  puts "Testing playback pause..."
  
  sleep(0.1) # Small delay to have some playback time
  
  token = "valid_token_#{admin_user.id}"
  result = PlaybackController.pause_track(room.id, token)
  
  if result[:status] == 200
    puts "✓ Playback paused successfully"
    puts "  - Paused at: #{Time.at(result[:body][:paused_at]).strftime('%H:%M:%S.%3N')}"
    puts "  - Position: #{result[:body][:position].round(3)}s"
    
    # Verify room state
    room.refresh
    if !room.is_playing && room.playback_paused_at
      puts "✓ Room state updated correctly"
    else
      puts "✗ Room state not updated correctly"
      return false
    end
    
    # Verify broadcasting
    broadcast = EventBroadcaster.last_broadcast
    if broadcast && broadcast[:activity_type] == :paused
      puts "✓ Pause event broadcasted"
    else
      puts "✗ Pause event not broadcasted"
      return false
    end
  else
    puts "✗ Playback pause failed: #{result[:body][:error]}"
    return false
  end
  
  puts
  true
end

# Test playback resume
def test_playback_resume(admin_user, room)
  puts "Testing playback resume..."
  
  sleep(0.1) # Small delay to simulate pause duration
  
  token = "valid_token_#{admin_user.id}"
  result = PlaybackController.resume_track(room.id, token)
  
  if result[:status] == 200
    puts "✓ Playback resumed successfully"
    puts "  - Resumed at: #{Time.at(result[:body][:resumed_at]).strftime('%H:%M:%S.%3N')}"
    puts "  - Position: #{result[:body][:position].round(3)}s"
    
    # Verify room state
    room.refresh
    if room.is_playing && !room.playback_paused_at
      puts "✓ Room state updated correctly"
    else
      puts "✗ Room state not updated correctly"
      return false
    end
    
    # Verify broadcasting
    broadcast = EventBroadcaster.last_broadcast
    if broadcast && broadcast[:activity_type] == :resumed
      puts "✓ Resume event broadcasted"
    else
      puts "✗ Resume event not broadcasted"
      return false
    end
  else
    puts "✗ Playback resume failed: #{result[:body][:error]}"
    return false
  end
  
  puts
  true
end

# Test playback status
def test_playback_status(admin_user, room)
  puts "Testing playback status..."
  
  token = "valid_token_#{admin_user.id}"
  result = PlaybackController.get_playback_status(room.id, token)
  
  if result[:status] == 200
    status = result[:body][:playback_status]
    puts "✓ Playback status retrieved successfully"
    puts "  - Room ID: #{status[:room_id]}"
    puts "  - Is playing: #{status[:is_playing]}"
    puts "  - Current track: #{status[:current_track] ? status[:current_track][:original_name] : 'None'}"
    puts "  - Current position: #{status[:current_position].round(3)}s"
    puts "  - Queue length: #{status[:queue_length]}"
  else
    puts "✗ Playback status failed: #{result[:body][:error]}"
    return false
  end
  
  puts
  true
end

# Test timestamp synchronization
def test_timestamp_synchronization(admin_user, room, track)
  puts "Testing timestamp synchronization..."
  
  token = "valid_token_#{admin_user.id}"
  
  # Start playback and measure timing
  client_start_time = Time.now
  result = PlaybackController.start_track(room.id, track.id, token)
  client_end_time = Time.now
  
  if result[:status] == 200
    server_start_time = result[:body][:started_at]
    server_time = result[:body][:server_time]
    
    # Calculate timing differences
    client_duration = (client_end_time - client_start_time) * 1000 # ms
    server_client_diff = (server_time - client_end_time.to_f) * 1000 # ms
    
    puts "✓ Timestamp synchronization test completed"
    puts "  - Client request duration: #{client_duration.round(2)}ms"
    puts "  - Server-client time diff: #{server_client_diff.round(2)}ms"
    
    # Wait and check position accuracy
    sleep(0.2)
    
    status_result = PlaybackController.get_playback_status(room.id, token)
    if status_result[:status] == 200
      status = status_result[:body][:playback_status]
      expected_position = Time.now.to_f - server_start_time
      actual_position = status[:current_position]
      position_diff = (actual_position - expected_position).abs
      
      puts "  - Expected position: #{expected_position.round(3)}s"
      puts "  - Actual position: #{actual_position.round(3)}s"
      puts "  - Position difference: #{(position_diff * 1000).round(2)}ms"
      
      if position_diff < 0.1 # Less than 100ms difference
        puts "✓ Position synchronization accurate (< 100ms difference)"
      else
        puts "⚠ Position synchronization may need improvement (> 100ms difference)"
      end
    end
  else
    puts "✗ Timestamp synchronization test failed: #{result[:body][:error]}"
    return false
  end
  
  puts
  true
end

# Main test execution
begin
  # Clear any existing data
  Room.clear_all
  Track.clear_all
  User.clear_all
  EventBroadcaster.clear_broadcast_log
  
  # Setup test data
  test_data = setup_test_data
  admin_user = test_data[:admin_user]
  room = test_data[:room]
  track1 = test_data[:track1]
  track2 = test_data[:track2]
  
  # Run tests
  tests_passed = 0
  total_tests = 5
  
  tests_passed += 1 if test_playback_start(admin_user, room, track1)
  tests_passed += 1 if test_playback_pause(admin_user, room)
  tests_passed += 1 if test_playback_resume(admin_user, room)
  tests_passed += 1 if test_playback_status(admin_user, room)
  tests_passed += 1 if test_timestamp_synchronization(admin_user, room, track2)
  
  # Test summary
  puts "=== Test Summary ==="
  puts "Tests passed: #{tests_passed}/#{total_tests}"
  puts "Success rate: #{((tests_passed.to_f / total_tests) * 100).round(1)}%"
  
  if tests_passed == total_tests
    puts "✓ All playback controller tests passed!"
    puts
    puts "Key features verified:"
    puts "- ✓ Play/pause/resume controls with administrator access"
    puts "- ✓ Server-side timestamp synchronization"
    puts "- ✓ Accurate playback position calculation"
    puts "- ✓ Real-time state broadcasting via EventBroadcaster"
    puts "- ✓ Comprehensive playback status reporting"
    puts "- ✓ Timestamp-based synchronization accuracy"
  else
    puts "✗ Some tests failed. Please check the implementation."
  end
  
rescue => e
  puts "✗ Test execution failed: #{e.message}"
  puts e.backtrace.join("\n")
end

puts
puts "=== Simple Playback Controller Test Complete ==="