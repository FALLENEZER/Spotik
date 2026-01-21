#!/usr/bin/env ruby

# Integration test for room management endpoints
# This test starts the server and makes real HTTP requests

require 'bundler/setup'
require 'net/http'
require 'json'
require 'uri'
require 'timeout'

# Configuration
SERVER_HOST = 'localhost'
SERVER_PORT = 3001  # Use different port to avoid conflicts
BASE_URL = "http://#{SERVER_HOST}:#{SERVER_PORT}"

class RoomIntegrationTest
  def initialize
    @base_url = BASE_URL
    @auth_token = nil
    @server_pid = nil
  end
  
  def run_tests
    puts "🧪 Room Management Integration Test"
    puts "=" * 50
    
    # Start server
    unless start_server
      puts "❌ Failed to start server"
      return false
    end
    
    begin
      # Wait for server to be ready
      unless wait_for_server
        puts "❌ Server did not start properly"
        return false
      end
      
      # Run tests
      test_authentication
      test_room_endpoints
      
      puts "\n✅ Integration tests completed successfully"
      true
    ensure
      stop_server
    end
  end
  
  private
  
  def start_server
    puts "🚀 Starting Ruby server on port #{SERVER_PORT}..."
    
    # Set environment variables for test
    ENV['APP_ENV'] = 'test'
    ENV['SERVER_PORT'] = SERVER_PORT.to_s
    ENV['SERVER_HOST'] = SERVER_HOST
    
    # Start server in background
    @server_pid = spawn(
      'ruby', 'server.rb',
      chdir: Dir.pwd,
      out: '/dev/null',
      err: '/dev/null'
    )
    
    # Give server time to start
    sleep 2
    
    # Check if process is still running
    begin
      Process.getpgid(@server_pid)
      puts "✅ Server started with PID #{@server_pid}"
      true
    rescue Errno::ESRCH
      puts "❌ Server process died"
      false
    end
  end
  
  def stop_server
    if @server_pid
      puts "🛑 Stopping server..."
      begin
        Process.kill('TERM', @server_pid)
        Process.wait(@server_pid)
        puts "✅ Server stopped"
      rescue => e
        puts "⚠️  Error stopping server: #{e.message}"
      end
    end
  end
  
  def wait_for_server(timeout = 10)
    puts "⏳ Waiting for server to be ready..."
    
    Timeout.timeout(timeout) do
      loop do
        begin
          response = make_request('GET', '/health')
          if response && response.code == '200'
            puts "✅ Server is ready"
            return true
          end
        rescue => e
          # Server not ready yet, continue waiting
        end
        sleep 0.5
      end
    end
  rescue Timeout::Error
    puts "❌ Server did not become ready within #{timeout} seconds"
    false
  end
  
  def test_authentication
    puts "\n🔐 Testing authentication..."
    
    # Register a test user
    register_data = {
      username: "testuser_#{Time.now.to_i}",
      email: "test_#{Time.now.to_i}@example.com",
      password: "testpassword123",
      password_confirmation: "testpassword123"
    }
    
    response = make_request('POST', '/api/auth/register', register_data)
    
    if response && response.code == '201'
      auth_data = JSON.parse(response.body)
      @auth_token = auth_data['token']
      puts "✅ User registered and authenticated"
    else
      puts "❌ Authentication failed: #{response&.body}"
    end
  end
  
  def test_room_endpoints
    return unless @auth_token
    
    puts "\n🏠 Testing room endpoints..."
    
    # Test listing rooms
    puts "  📋 Testing GET /api/rooms..."
    response = make_request('GET', '/api/rooms', nil, @auth_token)
    if response && response.code == '200'
      puts "  ✅ Rooms listed successfully"
    else
      puts "  ❌ Failed to list rooms: #{response&.code} #{response&.body}"
    end
    
    # Test creating room
    puts "  🏗️  Testing POST /api/rooms..."
    room_data = { name: "Test Room #{Time.now.to_i}" }
    response = make_request('POST', '/api/rooms', room_data, @auth_token)
    
    if response && response.code == '201'
      created_room = JSON.parse(response.body)
      @test_room_id = created_room['room']['id']
      puts "  ✅ Room created successfully (ID: #{@test_room_id})"
      
      # Test getting room details
      puts "  🔍 Testing GET /api/rooms/:id..."
      response = make_request('GET', "/api/rooms/#{@test_room_id}", nil, @auth_token)
      if response && response.code == '200'
        puts "  ✅ Room details retrieved successfully"
      else
        puts "  ❌ Failed to get room details: #{response&.code} #{response&.body}"
      end
      
      # Test joining room (should conflict since we're already the creator)
      puts "  🚪 Testing POST /api/rooms/:id/join..."
      response = make_request('POST', "/api/rooms/#{@test_room_id}/join", {}, @auth_token)
      if response && response.code == '409'
        puts "  ✅ Join room correctly detected existing participation"
      else
        puts "  ❌ Unexpected join room response: #{response&.code} #{response&.body}"
      end
      
      # Test leaving room (should be forbidden since we're the administrator)
      puts "  🚪 Testing DELETE /api/rooms/:id/leave..."
      response = make_request('DELETE', "/api/rooms/#{@test_room_id}/leave", nil, @auth_token)
      if response && response.code == '403'
        puts "  ✅ Leave room correctly prevented administrator from leaving"
      else
        puts "  ❌ Unexpected leave room response: #{response&.code} #{response&.body}"
      end
      
    else
      puts "  ❌ Failed to create room: #{response&.code} #{response&.body}"
    end
  end
  
  def make_request(method, path, data = nil, token = nil)
    uri = URI("#{@base_url}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 5
    
    case method.upcase
    when 'GET'
      request = Net::HTTP::Get.new(uri)
    when 'POST'
      request = Net::HTTP::Post.new(uri)
    when 'DELETE'
      request = Net::HTTP::Delete.new(uri)
    else
      raise "Unsupported HTTP method: #{method}"
    end
    
    # Set headers
    request['Content-Type'] = 'application/json'
    request['Authorization'] = "Bearer #{token}" if token
    
    # Set body for POST requests
    if data && (method.upcase == 'POST')
      request.body = data.to_json
    end
    
    http.request(request)
  rescue => e
    puts "Request error: #{e.message}"
    nil
  end
end

# Run tests if script is executed directly
if __FILE__ == $0
  tester = RoomIntegrationTest.new
  success = tester.run_tests
  exit(success ? 0 : 1)
end