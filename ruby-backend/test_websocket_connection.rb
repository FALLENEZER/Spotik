#!/usr/bin/env ruby

# Test script for WebSocket connection functionality
# Tests WebSocket upgrade, authentication, and basic message handling

require 'bundler/setup'
require 'json'
require 'net/http'
require 'uri'

# Load the server components
require_relative 'config/settings'
require_relative 'config/database'
require_relative 'app/models'
require_relative 'app/services/auth_service'
require_relative 'app/websocket/connection'

puts "Testing WebSocket Connection Implementation"
puts "=" * 50

# Test 1: WebSocket Connection Class Initialization
puts "\n1. Testing WebSocket Connection Class Initialization"

begin
  # Mock environment for WebSocket connection
  mock_env = {
    'QUERY_STRING' => 'token=test_token_here',
    'HTTP_AUTHORIZATION' => nil,
    'REMOTE_ADDR' => '127.0.0.1'
  }
  
  connection = WebSocketConnection.new(mock_env)
  puts "✓ WebSocket connection class initialized successfully"
  puts "  - Connection ID: #{connection.instance_variable_get(:@connection_id)}"
  puts "  - Client IP: #{connection.send(:client_ip)}"
  
rescue => e
  puts "✗ Failed to initialize WebSocket connection: #{e.message}"
  puts "  #{e.backtrace.first}"
end

# Test 2: Token Extraction
puts "\n2. Testing Token Extraction"

test_cases = [
  {
    name: "Query parameter token",
    env: { 'QUERY_STRING' => 'token=abc123&other=value' },
    expected: 'abc123'
  },
  {
    name: "Authorization header",
    env: { 'HTTP_AUTHORIZATION' => 'Bearer xyz789' },
    expected: 'xyz789'
  },
  {
    name: "WebSocket protocol header",
    env: { 'HTTP_SEC_WEBSOCKET_PROTOCOL' => 'chat, token.def456' },
    expected: 'def456'
  },
  {
    name: "No token",
    env: {},
    expected: nil
  }
]

test_cases.each do |test_case|
  begin
    connection = WebSocketConnection.new(test_case[:env])
    extracted_token = connection.instance_variable_get(:@token)
    
    if extracted_token == test_case[:expected]
      puts "✓ #{test_case[:name]}: #{extracted_token || 'nil'}"
    else
      puts "✗ #{test_case[:name]}: expected #{test_case[:expected]}, got #{extracted_token}"
    end
    
  rescue => e
    puts "✗ #{test_case[:name]}: error - #{e.message}"
  end
end

# Test 3: Authentication Logic (without actual JWT)
puts "\n3. Testing Authentication Logic"

begin
  # Test with no token
  connection = WebSocketConnection.new({})
  auth_result = connection.send(:authenticate_connection)
  
  if auth_result == false
    puts "✓ Authentication correctly fails with no token"
  else
    puts "✗ Authentication should fail with no token"
  end
  
rescue => e
  puts "✗ Authentication test failed: #{e.message}"
end

# Test 4: Connection Management Class Methods
puts "\n4. Testing Connection Management"

begin
  # Test connection statistics
  stats = WebSocketConnection.connection_stats
  puts "✓ Connection statistics retrieved:"
  puts "  - Total connections: #{stats[:total_connections]}"
  puts "  - Room connections: #{stats[:room_connections]}"
  
  # Test room broadcasting (should not crash with no connections)
  WebSocketConnection.broadcast_to_room('test-room-id', {
    type: 'test_message',
    data: { message: 'Hello room!' }
  })
  puts "✓ Room broadcasting works with no connections"
  
  # Test user messaging (should return false with no connection)
  result = WebSocketConnection.send_to_user('test-user-id', {
    type: 'test_message',
    data: { message: 'Hello user!' }
  })
  
  if result == false
    puts "✓ User messaging correctly returns false for non-existent connection"
  else
    puts "✗ User messaging should return false for non-existent connection"
  end
  
rescue => e
  puts "✗ Connection management test failed: #{e.message}"
  puts "  #{e.backtrace.first}"
end

# Test 5: Message Handling Structure
puts "\n5. Testing Message Handling Structure"

begin
  connection = WebSocketConnection.new({ 'REMOTE_ADDR' => '127.0.0.1' })
  
  # Test message types that should be handled
  test_messages = [
    { type: 'ping', data: { client_time: Time.now.to_f } },
    { type: 'join_room', data: { room_id: 'test-room' } },
    { type: 'leave_room', data: {} },
    { type: 'get_room_state', data: {} },
    { type: 'unknown_type', data: {} }
  ]
  
  test_messages.each do |message|
    begin
      # This will fail because connection is not authenticated, but should not crash
      connection.send(:handle_message, message)
      puts "✓ Message type '#{message[:type]}' handled without crashing"
    rescue => e
      puts "✗ Message type '#{message[:type]}' caused error: #{e.message}"
    end
  end
  
rescue => e
  puts "✗ Message handling test failed: #{e.message}"
end

# Test 6: Error Handling
puts "\n6. Testing Error Handling"

begin
  connection = WebSocketConnection.new({ 'REMOTE_ADDR' => '127.0.0.1' })
  
  # Test error message creation
  connection.send(:send_error, 'test_error', 'This is a test error')
  puts "✓ Error message creation works"
  
  # Test cleanup
  connection.cleanup
  puts "✓ Connection cleanup works"
  
rescue => e
  puts "✗ Error handling test failed: #{e.message}"
end

# Test 7: Integration with Server
puts "\n7. Testing Server Integration"

begin
  # Check if server can load WebSocket connection
  require_relative 'server'
  puts "✓ Server loads WebSocket connection successfully"
  
  # Check if WebSocket endpoint exists in server
  server_source = File.read('server.rb')
  if server_source.include?('WebSocketConnection.new(env)')
    puts "✓ Server integrates WebSocket connection class"
  else
    puts "✗ Server does not integrate WebSocket connection class"
  end
  
rescue => e
  puts "✗ Server integration test failed: #{e.message}"
end

puts "\n" + "=" * 50
puts "WebSocket Connection Tests Complete"
puts "\nNext steps:"
puts "1. Start the server: ruby server.rb"
puts "2. Test WebSocket connection with a real client"
puts "3. Verify authentication with valid JWT tokens"
puts "4. Test room joining and real-time messaging"