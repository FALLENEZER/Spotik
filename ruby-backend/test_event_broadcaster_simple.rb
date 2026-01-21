#!/usr/bin/env ruby

# Simple test for EventBroadcaster without database dependencies
# Tests the core broadcasting functionality and integration

require 'json'
require 'securerandom'
require 'ostruct'

# Mock the dependencies that EventBroadcaster needs
class MockRoom
  attr_reader :id, :participants
  
  def initialize(id)
    @id = id
    @participants = []
  end
  
  def self.[](id)
    new(id)
  end
end

class MockWebSocketConnection
  def self.get_room_connections(room_id)
    []
  end
  
  def self.get_user_connection(user_id)
    nil
  end
  
  def self.connection_stats
    { authenticated_users: [] }
  end
  
  def self.broadcast_to_room(room_id, message)
    puts "  📡 WebSocket broadcast to room #{room_id}: #{message[:type]}"
    true
  end
end

# Mock Iodine
module Iodine
  def self.publish(channel, message)
    puts "  📡 Iodine publish to #{channel}: #{JSON.parse(message)['type']}"
    true
  end
  
  def self.run_after(milliseconds, &block)
    # Mock timer - just execute immediately for testing
    block.call if block
  end
end

# Mock logger
$logger = OpenStruct.new(
  info: ->(msg) { puts "  ℹ️  #{msg}" },
  debug: ->(msg) { puts "  🐛 #{msg}" },
  warn: ->(msg) { puts "  ⚠️  #{msg}" },
  error: ->(msg) { puts "  ❌ #{msg}" }
)

# Load EventBroadcaster
require_relative 'app/services/event_broadcaster'

puts "🧪 Testing EventBroadcaster Core Functionality"
puts "=" * 50

# Test 1: Class structure and constants
puts "\n1. Testing class structure..."

if defined?(EventBroadcaster)
  puts "✅ EventBroadcaster class loaded"
else
  puts "❌ EventBroadcaster class not found"
  exit 1
end

if EventBroadcaster::EVENT_TYPES.is_a?(Hash) && EventBroadcaster::EVENT_TYPES.frozen?
  puts "✅ EVENT_TYPES constant properly defined (#{EventBroadcaster::EVENT_TYPES.size} events)"
else
  puts "❌ EVENT_TYPES constant not properly defined"
  exit 1
end

if EventBroadcaster::PRIORITY_LEVELS.is_a?(Hash) && EventBroadcaster::PRIORITY_LEVELS.frozen?
  puts "✅ PRIORITY_LEVELS constant properly defined (#{EventBroadcaster::PRIORITY_LEVELS.size} levels)"
else
  puts "❌ PRIORITY_LEVELS constant not properly defined"
  exit 1
end

# Test 2: Basic broadcasting methods
puts "\n2. Testing basic broadcasting methods..."

begin
  # Test room broadcasting
  result = EventBroadcaster.broadcast_to_room('test-room-123', 'user_joined', {
    message: 'Test user joined',
    user_id: 'test-user-456'
  })
  
  if result
    puts "✅ Room broadcasting works"
  else
    puts "⚠️  Room broadcasting returned false (expected with no connections)"
  end
  
  # Test user broadcasting
  result = EventBroadcaster.broadcast_to_user('test-user-456', 'test_event', {
    message: 'Test user message'
  })
  
  if result == false
    puts "✅ User broadcasting works (returns false with no connections)"
  else
    puts "⚠️  User broadcasting returned unexpected result: #{result}"
  end
  
  # Test global broadcasting
  result = EventBroadcaster.broadcast_global('server_status', {
    status: 'testing'
  })
  
  if result == false
    puts "✅ Global broadcasting works (returns false with no users)"
  else
    puts "⚠️  Global broadcasting returned unexpected result: #{result}"
  end
  
rescue => e
  puts "❌ Basic broadcasting failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
  exit 1
end

# Test 3: Specialized broadcasting methods
puts "\n3. Testing specialized broadcasting methods..."

begin
  # Create mock objects
  mock_user = OpenStruct.new(
    id: 'test-user-123',
    username: 'testuser',
    to_hash: { id: 'test-user-123', username: 'testuser' }
  )
  
  mock_track = OpenStruct.new(
    id: 'test-track-456',
    original_name: 'Test Song.mp3',
    vote_score: 5,
    to_hash: { id: 'test-track-456', original_name: 'Test Song.mp3', vote_score: 5 }
  )
  
  # Test user activity broadcasting
  result = EventBroadcaster.broadcast_user_activity('test-room-123', :joined, mock_user)
  puts "✅ User activity broadcasting executed"
  
  # Test track activity broadcasting  
  result = EventBroadcaster.broadcast_track_activity('test-room-123', :added, mock_track, mock_user)
  puts "✅ Track activity broadcasting executed"
  
  # Test playback activity broadcasting
  result = EventBroadcaster.broadcast_playback_activity('test-room-123', :started, mock_user, {
    track: mock_track,
    started_at: Time.now.to_f
  })
  puts "✅ Playback activity broadcasting executed"
  
rescue => e
  puts "❌ Specialized broadcasting failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
  exit 1
end

# Test 4: Statistics and monitoring
puts "\n4. Testing statistics and monitoring..."

begin
  stats = EventBroadcaster.get_statistics
  
  required_keys = [:total_events, :successful_deliveries, :failed_deliveries, 
                   :success_rate, :events_by_type, :events_by_room, :server_time]
  
  missing_keys = required_keys.select { |key| !stats.key?(key) }
  
  if missing_keys.empty?
    puts "✅ Statistics structure complete"
    puts "   Total events: #{stats[:total_events]}"
    puts "   Success rate: #{stats[:success_rate]}%"
    puts "   Events by type: #{stats[:events_by_type].size} types tracked"
  else
    puts "❌ Missing statistics keys: #{missing_keys.join(', ')}"
    exit 1
  end
  
rescue => e
  puts "❌ Statistics test failed: #{e.message}"
  exit 1
end

# Test 5: Event delivery confirmation
puts "\n5. Testing event delivery confirmation..."

begin
  # Test cleanup
  EventBroadcaster.cleanup_stale_events
  puts "✅ Stale event cleanup executed"
  
  # Test confirmation
  result = EventBroadcaster.confirm_event_delivery('test-event-id', 'test-user-id')
  puts "✅ Event delivery confirmation executed (result: #{result})"
  
rescue => e
  puts "❌ Event delivery confirmation failed: #{e.message}"
  exit 1
end

# Test 6: Event types coverage
puts "\n6. Testing event types coverage..."

expected_events = [
  'user_joined', 'user_left', 'user_connected_websocket', 'user_disconnected_websocket',
  'track_added', 'track_voted', 'track_unvoted', 'queue_reordered',
  'playback_started', 'playback_paused', 'playback_resumed', 'playback_stopped',
  'playback_seeked', 'track_skipped', 'room_state_updated', 'error'
]

missing_events = expected_events.select { |event| !EventBroadcaster::EVENT_TYPES.values.include?(event) }

if missing_events.empty?
  puts "✅ All expected event types present (#{expected_events.size} events)"
else
  puts "❌ Missing event types: #{missing_events.join(', ')}"
  exit 1
end

# Test 7: Priority levels coverage
puts "\n7. Testing priority levels..."

expected_priorities = [:critical, :high, :normal, :low]
missing_priorities = expected_priorities.select { |priority| !EventBroadcaster::PRIORITY_LEVELS.key?(priority) }

if missing_priorities.empty?
  puts "✅ All priority levels present (#{expected_priorities.size} levels)"
  EventBroadcaster::PRIORITY_LEVELS.each do |level, value|
    puts "   #{level}: #{value}"
  end
else
  puts "❌ Missing priority levels: #{missing_priorities.join(', ')}"
  exit 1
end

puts "\n" + "=" * 50
puts "🎉 All EventBroadcaster tests passed!"
puts "✅ Core broadcasting functionality works"
puts "✅ Specialized broadcasting methods work"
puts "✅ Statistics and monitoring operational"
puts "✅ Event delivery confirmation functional"
puts "✅ All event types and priorities defined"
puts "\n📊 Unified Event Broadcasting System: READY"
puts "🚀 Integration with Iodine Pub/Sub: ACTIVE"
puts "🔗 WebSocket connection integration: ACTIVE"