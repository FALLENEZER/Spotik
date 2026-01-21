#!/usr/bin/env ruby

# Simple test script for track management endpoints
# Tests the basic functionality of track upload, voting, and streaming

require 'net/http'
require 'json'
require 'uri'
require 'tempfile'

# Configuration
BASE_URL = 'http://localhost:3001'
TEST_USER = {
  username: 'testuser_tracks',
  email: 'testuser_tracks@example.com',
  password: 'password123'
}

class TrackEndpointTester
  def initialize
    @base_uri = URI(BASE_URL)
    @token = nil
    @room_id = nil
    @track_id = nil
  end
  
  def run_tests
    puts "🧪 Testing Track Management Endpoints"
    puts "=" * 50
    
    begin
      test_server_health
      test_user_registration_and_login
      test_room_creation
      test_track_upload
      test_track_queue_retrieval
      test_track_voting
      test_track_unvoting
      test_track_streaming
      
      puts "\n✅ All track endpoint tests passed!"
      
    rescue => e
      puts "\n❌ Test failed: #{e.message}"
      puts e.backtrace.join("\n") if ENV['DEBUG']
      exit 1
    end
  end
  
  private
  
  def test_server_health
    puts "\n🔍 Testing server health..."
    
    response = make_request('GET', '/health')
    
    unless response.code == '200'
      raise "Server health check failed: #{response.code} - #{response.body}"
    end
    
    health_data = JSON.parse(response.body)
    unless health_data['status'] == 'healthy'
      raise "Server is not healthy: #{health_data['status']}"
    end
    
    puts "✅ Server is healthy"
  end
  
  def test_user_registration_and_login
    puts "\n🔍 Testing user registration and login..."
    
    # Register user
    register_data = {
      username: TEST_USER[:username],
      email: TEST_USER[:email],
      password: TEST_USER[:password],
      password_confirmation: TEST_USER[:password]
    }
    
    response = make_request('POST', '/api/auth/register', register_data)
    
    # User might already exist, that's okay
    unless ['200', '201', '422'].include?(response.code)
      raise "User registration failed: #{response.code} - #{response.body}"
    end
    
    # Login user
    login_data = {
      username: TEST_USER[:username],
      password: TEST_USER[:password]
    }
    
    response = make_request('POST', '/api/auth/login', login_data)
    
    unless response.code == '200'
      raise "User login failed: #{response.code} - #{response.body}"
    end
    
    login_result = JSON.parse(response.body)
    @token = login_result['token']
    
    unless @token
      raise "No token received from login"
    end
    
    puts "✅ User authentication successful"
  end
  
  def test_room_creation
    puts "\n🔍 Testing room creation..."
    
    room_data = {
      name: "Track Test Room #{Time.now.to_i}"
    }
    
    response = make_request('POST', '/api/rooms', room_data, @token)
    
    unless response.code == '201'
      raise "Room creation failed: #{response.code} - #{response.body}"
    end
    
    room_result = JSON.parse(response.body)
    @room_id = room_result['room']['id']
    
    unless @room_id
      raise "No room ID received from room creation"
    end
    
    puts "✅ Room created successfully: #{@room_id}"
  end
  
  def test_track_upload
    puts "\n🔍 Testing track upload..."
    
    # Create a fake audio file for testing
    temp_file = create_fake_audio_file
    
    begin
      # Prepare multipart form data
      boundary = "----WebKitFormBoundary#{rand(1000000)}"
      
      body = []
      body << "--#{boundary}"
      body << 'Content-Disposition: form-data; name="audio_file"; filename="test_track.mp3"'
      body << 'Content-Type: audio/mpeg'
      body << ''
      body << File.read(temp_file.path)
      body << "--#{boundary}--"
      
      post_body = body.join("\r\n")
      
      uri = URI("#{BASE_URL}/api/rooms/#{@room_id}/tracks")
      http = Net::HTTP.new(uri.host, uri.port)
      
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{@token}"
      request['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
      request.body = post_body
      
      response = http.request(request)
      
      unless response.code == '201'
        raise "Track upload failed: #{response.code} - #{response.body}"
      end
      
      upload_result = JSON.parse(response.body)
      @track_id = upload_result['track']['id']
      
      unless @track_id
        raise "No track ID received from track upload"
      end
      
      puts "✅ Track uploaded successfully: #{@track_id}"
      
    ensure
      temp_file.close
      temp_file.unlink
    end
  end
  
  def test_track_queue_retrieval
    puts "\n🔍 Testing track queue retrieval..."
    
    response = make_request('GET', "/api/rooms/#{@room_id}/tracks", nil, @token)
    
    unless response.code == '200'
      raise "Track queue retrieval failed: #{response.code} - #{response.body}"
    end
    
    queue_result = JSON.parse(response.body)
    tracks = queue_result['tracks']
    
    unless tracks.is_a?(Array) && tracks.length > 0
      raise "No tracks found in queue"
    end
    
    # Verify our uploaded track is in the queue
    our_track = tracks.find { |t| t['id'] == @track_id }
    unless our_track
      raise "Uploaded track not found in queue"
    end
    
    puts "✅ Track queue retrieved successfully (#{tracks.length} tracks)"
  end
  
  def test_track_voting
    puts "\n🔍 Testing track voting..."
    
    response = make_request('POST', "/api/tracks/#{@track_id}/vote", nil, @token)
    
    unless response.code == '200'
      raise "Track voting failed: #{response.code} - #{response.body}"
    end
    
    vote_result = JSON.parse(response.body)
    
    unless vote_result['user_has_voted'] == true
      raise "Vote was not recorded properly"
    end
    
    unless vote_result['vote_score'] > 0
      raise "Vote score was not updated"
    end
    
    puts "✅ Track voting successful (score: #{vote_result['vote_score']})"
  end
  
  def test_track_unvoting
    puts "\n🔍 Testing track unvoting..."
    
    response = make_request('DELETE', "/api/tracks/#{@track_id}/vote", nil, @token)
    
    unless response.code == '200'
      raise "Track unvoting failed: #{response.code} - #{response.body}"
    end
    
    unvote_result = JSON.parse(response.body)
    
    unless unvote_result['user_has_voted'] == false
      raise "Vote removal was not recorded properly"
    end
    
    puts "✅ Track unvoting successful (score: #{unvote_result['vote_score']})"
  end
  
  def test_track_streaming
    puts "\n🔍 Testing track streaming..."
    
    response = make_request('GET', "/api/tracks/#{@track_id}/stream", nil, @token)
    
    unless response.code == '200'
      raise "Track streaming failed: #{response.code} - #{response.body}"
    end
    
    # Check content type
    content_type = response['Content-Type']
    unless content_type && content_type.start_with?('audio/')
      raise "Invalid content type for audio stream: #{content_type}"
    end
    
    # Check that we got some content
    unless response.body && response.body.length > 0
      raise "No audio content received"
    end
    
    puts "✅ Track streaming successful (#{response.body.length} bytes)"
  end
  
  def create_fake_audio_file
    temp_file = Tempfile.new(['test_track', '.mp3'])
    
    # Create a minimal MP3-like file with proper header
    mp3_header = [0xFF, 0xFB, 0x90, 0x00].pack('C*')  # MP3 frame sync + basic header
    fake_audio_data = mp3_header + ('A' * 1000)  # Add some fake audio data
    
    temp_file.write(fake_audio_data)
    temp_file.rewind
    
    temp_file
  end
  
  def make_request(method, path, data = nil, token = nil)
    uri = URI("#{BASE_URL}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    
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
    
    if token
      request['Authorization'] = "Bearer #{token}"
    end
    
    if data
      request['Content-Type'] = 'application/json'
      request.body = data.to_json
    end
    
    http.request(request)
  end
end

# Run tests if this file is executed directly
if __FILE__ == $0
  tester = TrackEndpointTester.new
  tester.run_tests
end