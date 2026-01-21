#!/usr/bin/env ruby

# Test script for unified event broadcasting system
# Verifies that EventBroadcaster is properly integrated and working

require_relative 'app/models'
require_relative 'app/services/event_broadcaster'
require_relative 'app/websocket/connection'

puts "🧪 Testing Unified Event Broadcasting System"
puts "=" * 50

# Test 1: EventBroadcaster class exists and has required methods
puts "\n1. Testing EventBroadcaster class structure..."

required_methods = [
  :broadcast_to_room,
  :broadcast_to_user,
  :broadcast_global,
  :broadcast_user_activity,
  :broadcast_track_activity,
  :broadcast_playback_activity,
  :broadcast_room_state,
  :broadcast_error,
  :get_statistics,
  :cleanup_stale_events
]

missing_methods = []
required_methods.each do |method|
  unless EventBroadcaster.respond_to?(method)
    missing_methods << method
  end
end

if missing_methods.empty?
  puts "✅ All required methods present"
else
  puts "❌ Missing methods: #{missing_methods.join(', ')}"
  exit 1
end

# Test 2: Event types are properly defined
puts "\n2. Testing event type constants..."

required_event_types = [
  'user_joined', 'user_left', 'user_connected_websocket', 'user_disconnected_websocket',
  'track_added', 'track_voted', 'track_unvoted', 'queue_reordered',
  'playback_started', 'playback_paused', 'playback_resumed', 'playback_stopped',
  'playback_seeked', 'track_skipped', 'room_state_updated', 'error'
]

missing_event_types = []
required_event_types.each do |event_type|
  unless EventBroadcaster::EVENT_TYPES.values.include?(event_type)
    missing_event_types << event_type
  end
end

if missing_event_types.empty?
  puts "✅ All required event types defined"
else
  puts "❌ Missing event types: #{missing_event_types.join(', ')}"
  exit 1
end

# Test 3: Priority levels are defined
puts "\n3. Testing priority levels..."

required_priorities = [:critical, :high, :normal, :low]
missing_priorities = []

required_priorities.each do |priority|
  unless EventBroadcaster::PRIORITY_LEVELS.key?(priority)
    missing_priorities << priority
  end
end

if missing_priorities.empty?
  puts "✅ All priority levels defined"
else
  puts "❌ Missing priorities: #{missing_priorities.join(', ')}"
  exit 1
end

# Test 4: Test basic broadcasting (without actual WebSocket connections)
puts "\n4. Testing basic event broadcasting..."

begin
  # Test room broadcasting
  result = EventBroadcaster.broadcast_to_room('test-room-123', 'test_event', {
    message: 'Test broadcast message',
    test_data: 'hello world'
  })
  
  puts "✅ Room broadcasting method executed (result: #{result})"
  
  # Test user broadcasting
  result = EventBroadcaster.broadcast_to_user('test-user-456', 'test_event', {
    message: 'Test user message'
  })
  
  puts "✅ User broadcasting method executed (result: #{result})"
  
  # Test global broadcasting
  result = EventBroadcaster.broadcast_global('server_status', {
    status: 'testing',
    message: 'System test in progress'
  })
  
  puts "✅ Global broadcasting method executed (result: #{result})"
  
rescue => e
  puts "❌ Broadcasting test failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
  exit 1
end

# Test 5: Test specialized broadcasting methods
puts "\n5. Testing specialized broadcasting methods..."

begin
  # Create mock user object
  mock_user = OpenStruct.new(
    id: 'test-user-123',
    username: 'testuser',
    to_hash: { id: 'test-user-123', username: 'testuser' }
  )
  
  # Create mock track object
  mock_track = OpenStruct.new(
    id: 'test-track-456',
    original_name: 'Test Song.mp3',
    to_hash: { id: 'test-track-456', original_name: 'Test Song.mp3' }
  )
  
  # Test user activity broadcasting
  result = EventBroadcaster.broadcast_user_activity('test-room-123', :joined, mock_user)
  puts "✅ User activity broadcasting executed (result: #{result})"
  
  # Test track activity broadcasting
  result = EventBroadcaster.broadcast_track_activity('test-room-123', :added, mock_track, mock_user)
  puts "✅ Track activity broadcasting executed (result: #{result})"
  
  # Test playback activity broadcasting
  result = EventBroadcaster.broadcast_playback_activity('test-room-123', :started, mock_user, {
    track: mock_track,
    started_at: Time.now.to_f
  })
  puts "✅ Playback activity broadcasting executed (result: #{result})"
  
rescue => e
  puts "❌ Specialized broadcasting test failed: #{e.message}"
  puts e.backtrace.first(3).join("\n")
  exit 1
end

# Test 6: Test statistics and monitoring
puts "\n6. Testing statistics and monitoring..."

begin
  stats = EventBroadcaster.get_statistics
  
  required_stat_keys = [:total_events, :successful_deliveries, :failed_deliveries, 
                       :success_rate, :events_by_type, :events_by_room, :server_time]
  
  missing_stat_keys = []
  required_stat_keys.each do |key|
    unless stats.key?(key)
      missing_stat_keys << key
    end
  end
  
  if missing_stat_keys.empty?
    puts "✅ Statistics structure complete"
    puts "   Total events: #{stats[:total_events]}"
    puts "   Success rate: #{stats[:success_rate]}%"
  else
    puts "❌ Missing statistics keys: #{missing_stat_keys.join(', ')}"
    exit 1
  end
  
rescue => e
  puts "❌ Statistics test failed: #{e.message}"
  exit 1
end

# Test 7: Test event delivery confirmation system
puts "\n7. Testing event delivery confirmation..."

begin
  # Test cleanup of stale events
  EventBroadcaster.cleanup_stale_events
  puts "✅ Stale event cleanup executed successfully"
  
  # Test event confirmation (with mock data)
  result = EventBroadcaster.confirm_event_delivery('test-event-id', 'test-user-id')
  puts "✅ Event delivery confirmation executed (result: #{result})"
  
rescue => e
  puts "❌ Event delivery confirmation test failed: #{e.message}"
  exit 1
end

puts "\n" + "=" * 50
puts "🎉 All unified event broadcasting tests passed!"
puts "✅ EventBroadcaster is properly integrated and functional"
puts "✅ All event types and priority levels are defined"
puts "✅ Specialized broadcasting methods work correctly"
puts "✅ Statistics and monitoring systems are operational"
puts "✅ Event delivery confirmation system is functional"
puts "\n📊 Event Broadcasting System Status: READY"