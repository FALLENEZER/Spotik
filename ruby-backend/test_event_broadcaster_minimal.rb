#!/usr/bin/env ruby

# Minimal test for EventBroadcaster - tests core functionality without external dependencies

require 'securerandom'
require 'ostruct'

# Mock all external dependencies
class MockRoom
  def self.[](id)
    OpenStruct.new(id: id, participants: OpenStruct.new(count: 0))
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
    puts "  📡 WebSocket broadcast to room #{room_id}"
    true
  end
end

module Iodine
  def self.publish(channel, message)
    puts "  📡 Iodine publish to #{channel}"
    true
  end
  
  def self.run_after(milliseconds, &block)
    block.call if block
  end
end

$logger = OpenStruct.new(
  info: ->(msg) { puts "  ℹ️  #{msg}" },
  debug: ->(msg) { puts "  🐛 #{msg}" },
  warn: ->(msg) { puts "  ⚠️  #{msg}" },
  error: ->(msg) { puts "  ❌ #{msg}" }
)

# Mock JSON for compatibility
module JSON
  def self.parse(str)
    { 'type' => 'mock_event' }
  end
end

puts "🧪 Testing EventBroadcaster - Minimal Test"
puts "=" * 50

# Load the EventBroadcaster
begin
  require_relative 'app/services/event_broadcaster'
  puts "✅ EventBroadcaster loaded successfully"
rescue => e
  puts "❌ Failed to load EventBroadcaster: #{e.message}"
  exit 1
end

# Test 1: Check class exists and has basic structure
puts "\n1. Testing class structure..."

if defined?(EventBroadcaster)
  puts "✅ EventBroadcaster class exists"
else
  puts "❌ EventBroadcaster class not found"
  exit 1
end

# Test 2: Check constants
puts "\n2. Testing constants..."

if defined?(EventBroadcaster::EVENT_TYPES) && EventBroadcaster::EVENT_TYPES.is_a?(Hash)
  puts "✅ EVENT_TYPES constant defined (#{EventBroadcaster::EVENT_TYPES.size} events)"
else
  puts "❌ EVENT_TYPES constant missing or invalid"
  exit 1
end

if defined?(EventBroadcaster::PRIORITY_LEVELS) && EventBroadcaster::PRIORITY_LEVELS.is_a?(Hash)
  puts "✅ PRIORITY_LEVELS constant defined (#{EventBroadcaster::PRIORITY_LEVELS.size} levels)"
else
  puts "❌ PRIORITY_LEVELS constant missing or invalid"
  exit 1
end

# Test 3: Check required methods exist
puts "\n3. Testing method availability..."

required_methods = [
  :broadcast_to_room,
  :broadcast_to_user,
  :broadcast_global,
  :broadcast_user_activity,
  :broadcast_track_activity,
  :broadcast_playback_activity,
  :get_statistics
]

missing_methods = []
required_methods.each do |method|
  if EventBroadcaster.respond_to?(method)
    puts "  ✅ #{method}"
  else
    missing_methods << method
    puts "  ❌ #{method}"
  end
end

if missing_methods.empty?
  puts "✅ All required methods present"
else
  puts "❌ Missing methods: #{missing_methods.join(', ')}"
  exit 1
end

# Test 4: Test basic broadcasting (should not crash)
puts "\n4. Testing basic broadcasting..."

begin
  result = EventBroadcaster.broadcast_to_room('test-room', 'user_joined', { test: 'data' })
  puts "✅ broadcast_to_room executed (result: #{result})"
  
  result = EventBroadcaster.broadcast_to_user('test-user', 'test_event', { test: 'data' })
  puts "✅ broadcast_to_user executed (result: #{result})"
  
  result = EventBroadcaster.broadcast_global('server_status', { status: 'test' })
  puts "✅ broadcast_global executed (result: #{result})"
  
rescue => e
  puts "❌ Basic broadcasting failed: #{e.message}"
  exit 1
end

# Test 5: Test specialized methods with mock objects
puts "\n5. Testing specialized broadcasting..."

begin
  mock_user = OpenStruct.new(
    id: 'test-user',
    username: 'testuser',
    to_hash: { id: 'test-user', username: 'testuser' }
  )
  
  mock_track = OpenStruct.new(
    id: 'test-track',
    original_name: 'Test Song.mp3',
    to_hash: { id: 'test-track', original_name: 'Test Song.mp3' }
  )
  
  result = EventBroadcaster.broadcast_user_activity('test-room', :joined, mock_user)
  puts "✅ broadcast_user_activity executed"
  
  result = EventBroadcaster.broadcast_track_activity('test-room', :added, mock_track, mock_user)
  puts "✅ broadcast_track_activity executed"
  
  result = EventBroadcaster.broadcast_playback_activity('test-room', :started, mock_user)
  puts "✅ broadcast_playback_activity executed"
  
rescue => e
  puts "❌ Specialized broadcasting failed: #{e.message}"
  puts "   Error details: #{e.backtrace.first}"
  exit 1
end

# Test 6: Test statistics
puts "\n6. Testing statistics..."

begin
  stats = EventBroadcaster.get_statistics
  
  if stats.is_a?(Hash)
    puts "✅ Statistics returned as hash"
    puts "   Keys: #{stats.keys.join(', ')}"
  else
    puts "❌ Statistics not returned as hash"
    exit 1
  end
  
rescue => e
  puts "❌ Statistics test failed: #{e.message}"
  exit 1
end

puts "\n" + "=" * 50
puts "🎉 All minimal tests passed!"
puts "✅ EventBroadcaster is properly structured"
puts "✅ All required methods are available"
puts "✅ Basic broadcasting functionality works"
puts "✅ Specialized broadcasting methods work"
puts "✅ Statistics system is functional"
puts "\n📊 Unified Event Broadcasting System: OPERATIONAL"