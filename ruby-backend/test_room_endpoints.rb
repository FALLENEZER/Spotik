#!/usr/bin/env ruby

# Test script for room management endpoints
# This script tests the basic functionality of room endpoints

require 'bundler/setup'
require 'net/http'
require 'json'
require 'uri'

# Configuration
SERVER_HOST = 'localhost'
SERVER_PORT = 3000
BASE_URL = "http://#{SERVER_HOST}:#{SERVER_PORT}"

class RoomEndpointTester
  def initialize
    @base_url = BASE_URL
    @auth_token = nil
  end
  
  def run_tests
    puts "🧪 Testing Room Management Endpoints"
    puts "=" * 50
    
    # Test server health first
    unless test_server_health
      puts "❌ Server is not healthy, aborting tests"
      return false
    end
    
    # Test authentication first (needed for room operations)
    unless test_authentication
      puts "❌ Authentication failed, aborting room tests"
      return false
    end
    
    # Test room endpoints
    test_list_rooms
    test_create_room
    test_get_room_details
    test_join_room
    test_leave_room
    
    puts "\n✅ All room endpoint tests completed"
    true
  end
  
  private
  
  def test_server_health
    puts "\n🔍 Testing server health..."
    
    response = make_request('GET', '/health')
    
    if response && response.code == '200'
      health_data = JSON.parse(response.body)
      puts "✅ Server is healthy (status: #{health_data['status']})"
      return true
    else
      puts "❌ Server health check failed"
      return false
    end
  rescue => e
    puts "❌ Server health check error: #{e.message}"
    false
  end
  
  def test_authentication
    puts "\n🔐 Testing authentication..."
    
    # Try to register a test user
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
      return true
    else
      puts "❌ Authentication failed: #{response&.body}"
      return false
    end
  rescue => e
    puts "❌ Authentication error: #{e.message}"
    false
  end
  
  def test_list_rooms
    puts "\n📋 Testing GET /api/rooms..."
    
    response = make_request('GET', '/api/rooms', nil, @auth_token)
    
    if response && response.code == '200'
      rooms_data = JSON.parse(response.body)
      puts "✅ Rooms listed successfully (#{rooms_data['total']} rooms)"
      puts "   Response includes: #{rooms_data.keys.join(', ')}"
    else
      puts "❌ Failed to list rooms: #{response&.body}"
    end
  rescue => e
    puts "❌ List rooms error: #{e.message}"
  end
  
  def test_create_room
    puts "\n🏠 Testing POST /api/rooms..."
    
    room_data = {
      name: "Test Room #{Time.now.to_i}"
    }
    
    response = make_request('POST', '/api/rooms', room_data, @auth_token)
    
    if response && response.code == '201'
      created_room = JSON.parse(response.body)
      @test_room_id = created_room['room']['id']
      puts "✅ Room created successfully (ID: #{@test_room_id})"
      puts "   Room name: #{created_room['room']['name']}"
      puts "   Administrator: #{created_room['room']['administrator_id']}"
    else
      puts "❌ Failed to create room: #{response&.body}"
    end
  rescue => e
    puts "❌ Create room error: #{e.message}"
  end
  
  def test_get_room_details
    return unless @test_room_id
    
    puts "\n🔍 Testing GET /api/rooms/:id..."
    
    response = make_request('GET', "/api/rooms/#{@test_room_id}", nil, @auth_token)
    
    if response && response.code == '200'
      room_data = JSON.parse(response.body)
      puts "✅ Room details retrieved successfully"
      puts "   Room ID: #{room_data['room']['id']}"
      puts "   Participants: #{room_data['room']['participant_count']}"
      puts "   Tracks: #{room_data['room']['track_count']}"
    else
      puts "❌ Failed to get room details: #{response&.body}"
    end
  rescue => e
    puts "❌ Get room details error: #{e.message}"
  end
  
  def test_join_room
    return unless @test_room_id
    
    puts "\n🚪 Testing POST /api/rooms/:id/join..."
    
    # Since we're already the creator, this should return a conflict
    response = make_request('POST', "/api/rooms/#{@test_room_id}/join", {}, @auth_token)
    
    if response && response.code == '409'
      puts "✅ Join room correctly detected existing participation"
    elsif response && response.code == '200'
      puts "✅ Successfully joined room"
    else
      puts "❌ Unexpected join room response: #{response&.body}"
    end
  rescue => e
    puts "❌ Join room error: #{e.message}"
  end
  
  def test_leave_room
    return unless @test_room_id
    
    puts "\n🚪 Testing DELETE /api/rooms/:id/leave..."
    
    # Since we're the administrator, this should be forbidden
    response = make_request('DELETE', "/api/rooms/#{@test_room_id}/leave", nil, @auth_token)
    
    if response && response.code == '403'
      puts "✅ Leave room correctly prevented administrator from leaving"
    else
      puts "❌ Unexpected leave room response: #{response&.body}"
    end
  rescue => e
    puts "❌ Leave room error: #{e.message}"
  end
  
  def make_request(method, path, data = nil, token = nil)
    uri = URI("#{@base_url}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 10
    
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
  tester = RoomEndpointTester.new
  success = tester.run_tests
  exit(success ? 0 : 1)
end