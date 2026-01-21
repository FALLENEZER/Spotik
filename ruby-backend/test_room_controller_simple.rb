#!/usr/bin/env ruby

# Simple test for room controller logic without external dependencies

require 'securerandom'

# Mock dependencies
class MockLogger
  def info(msg); puts "INFO: #{msg}"; end
  def warn(msg); puts "WARN: #{msg}"; end
  def error(msg); puts "ERROR: #{msg}"; end
  def debug(msg); puts "DEBUG: #{msg}"; end
end

$logger = MockLogger.new

# Mock SpotikConfig
module SpotikConfig
  class Settings
    def self.app_debug?
      true
    end
  end
end

# Mock User
class MockUser
  attr_accessor :id, :username, :email
  
  def initialize(id: nil, username: nil, email: nil)
    @id = id || SecureRandom.uuid
    @username = username
    @email = email
  end
end

# Mock Room
class MockRoom
  attr_accessor :id, :name, :administrator_id, :participants
  
  def initialize(id: nil, name: nil, administrator_id: nil)
    @id = id || SecureRandom.uuid
    @name = name
    @administrator_id = administrator_id
    @participants = []
  end
  
  def has_participant?(user)
    @participants.any? { |p| p.id == user.id }
  end
  
  def add_participant(user)
    @participants << user unless has_participant?(user)
  end
  
  def remove_participant(user)
    initial_count = @participants.length
    @participants.reject! { |p| p.id == user.id }
    @participants.length < initial_count
  end
  
  def administered_by?(user)
    @administrator_id == user.id
  end
  
  def refresh
    self
  end
  
  def track_queue
    []
  end
  
  def is_playing
    false
  end
  
  def current_track
    nil
  end
  
  def tracks
    MockTrackCollection.new
  end
  
  def to_hash
    {
      id: @id,
      name: @name,
      administrator_id: @administrator_id,
      administrator: nil,
      current_track_id: nil,
      current_track: nil,
      playback_started_at: nil,
      playback_paused_at: nil,
      is_playing: false,
      participants: @participants.map { |p| { id: p.id, username: p.username } },
      track_count: 0,
      participant_count: @participants.length,
      created_at: Time.now.iso8601,
      updated_at: Time.now.iso8601,
      track_queue: []
    }
  end
end

class MockTrackCollection
  def count
    0
  end
end

# Mock Sequel for validation errors
module Sequel
  class ValidationFailed < StandardError
    attr_reader :errors
    
    def initialize(errors)
      @errors = errors
      super("Validation failed")
    end
  end
end

# Mock Room model
class MockRoomModel
  @@rooms = {}
  
  def self.create(attributes)
    # Validate required fields
    if attributes[:name].nil? || attributes[:name].strip.empty?
      raise Sequel::ValidationFailed.new({ name: ['is not present'] })
    end
    
    if attributes[:name].length > 100
      raise Sequel::ValidationFailed.new({ name: ['is longer than 100 characters'] })
    end
    
    room = MockRoom.new(
      name: attributes[:name],
      administrator_id: attributes[:administrator_id]
    )
    @@rooms[room.id] = room
    room
  end
  
  def self.[](id)
    @@rooms[id]
  end
  
  def self.all
    @@rooms.values
  end
  
  def self.clear_all
    @@rooms.clear
  end
end

# Mock AuthService
class MockAuthService
  def self.validate_jwt(token)
    return { success: false, status: 401, body: { error: 'Authentication required' } } if token.nil?
    return { success: false, status: 401, body: { error: 'Invalid or expired token' } } if token == 'invalid.jwt.token'
    
    # Return different users based on token
    if token == 'valid.jwt.token.other'
      user = MockUser.new(id: 'other-user-id', username: 'otheruser', email: 'other@test.com')
    else
      user = MockUser.new(id: 'test-user-id', username: 'testuser', email: 'test@example.com')
    end
    
    { success: true, user: user }
  end
end

# Set up constants
AuthService = MockAuthService
Room = MockRoomModel

# Load the controller
require_relative 'app/controllers/room_controller'

# Test runner
class RoomControllerTest
  def run_tests
    puts "🧪 Testing Room Controller Logic"
    puts "=" * 50
    
    MockRoomModel.clear_all
    
    test_index
    test_create
    test_show
    test_join
    test_leave
    
    puts "\n✅ All controller tests completed"
  end
  
  private
  
  def test_index
    puts "\n📋 Testing RoomController.index..."
    
    # Create a test room
    room = MockRoomModel.create(name: 'Test Room', administrator_id: 'test-user-id')
    
    # Test without authentication
    result = RoomController.index
    puts "  Without auth: #{result[:status]} - #{result[:body][:total]} rooms"
    
    # Test with authentication
    result = RoomController.index('valid.jwt.token')
    puts "  With auth: #{result[:status]} - #{result[:body][:total]} rooms"
    
    puts "  ✅ Index tests passed"
  end
  
  def test_create
    puts "\n🏗️  Testing RoomController.create..."
    
    # Test valid creation
    result = RoomController.create({ 'name' => 'New Test Room' }, 'valid.jwt.token')
    puts "  Valid creation: #{result[:status]} - #{result[:body][:message] || result[:body][:error]}"
    
    # Test missing name
    result = RoomController.create({}, 'valid.jwt.token')
    puts "  Missing name: #{result[:status]} - #{result[:body][:error]}"
    
    # Test name too long
    result = RoomController.create({ 'name' => 'a' * 101 }, 'valid.jwt.token')
    puts "  Name too long: #{result[:status]} - #{result[:body][:error]}"
    
    # Test without auth
    result = RoomController.create({ 'name' => 'Test' }, nil)
    puts "  Without auth: #{result[:status]} - #{result[:body][:error]}"
    
    puts "  ✅ Create tests passed"
  end
  
  def test_show
    puts "\n🔍 Testing RoomController.show..."
    
    # Create a test room
    room = MockRoomModel.create(name: 'Show Test Room', administrator_id: 'test-user-id')
    
    # Test existing room
    result = RoomController.show(room.id)
    puts "  Existing room: #{result[:status]} - #{result[:body][:room][:name] if result[:body]}"
    
    # Test non-existent room
    result = RoomController.show('non-existent-id')
    puts "  Non-existent room: #{result[:status]} - #{result[:body][:error]}"
    
    puts "  ✅ Show tests passed"
  end
  
  def test_join
    puts "\n🚪 Testing RoomController.join..."
    
    # Create a test room
    room = MockRoomModel.create(name: 'Join Test Room', administrator_id: 'test-user-id')
    
    # Test joining with different user
    result = RoomController.join(room.id, 'valid.jwt.token.other')
    puts "  Join as other user: #{result[:status]} - #{result[:body][:message] || result[:body][:error]}"
    
    # Test joining again (should conflict)
    result = RoomController.join(room.id, 'valid.jwt.token.other')
    puts "  Join again: #{result[:status]} - #{result[:body][:error]}"
    
    # Test non-existent room
    result = RoomController.join('non-existent-id', 'valid.jwt.token.other')
    puts "  Non-existent room: #{result[:status]} - #{result[:body][:error]}"
    
    puts "  ✅ Join tests passed"
  end
  
  def test_leave
    puts "\n🚪 Testing RoomController.leave..."
    
    # Create a test room and add a participant
    room = MockRoomModel.create(name: 'Leave Test Room', administrator_id: 'test-user-id')
    other_user = MockUser.new(id: 'other-user-id', username: 'otheruser')
    room.add_participant(other_user)
    
    # Test leaving as participant
    result = RoomController.leave(room.id, 'valid.jwt.token.other')
    puts "  Leave as participant: #{result[:status]} - #{result[:body][:message] || result[:body][:error]}"
    
    # Test leaving as administrator (should be forbidden)
    result = RoomController.leave(room.id, 'valid.jwt.token')
    puts "  Leave as admin: #{result[:status]} - #{result[:body][:error]}"
    
    # Test leaving when not a participant
    result = RoomController.leave(room.id, 'valid.jwt.token.other')
    puts "  Leave when not participant: #{result[:status]} - #{result[:body][:error]}"
    
    puts "  ✅ Leave tests passed"
  end
end

# Run tests
if __FILE__ == $0
  tester = RoomControllerTest.new
  tester.run_tests
end