#!/usr/bin/env ruby

# Manual test script for authentication endpoints
# This script tests the authentication endpoints without requiring a database

require 'net/http'
require 'json'
require 'uri'

# Test configuration
BASE_URL = 'http://localhost:3000'
TEST_USER = {
  username: 'testuser',
  email: 'test@example.com',
  password: 'password123',
  password_confirmation: 'password123'
}

def make_request(method, path, data = nil, headers = {})
  uri = URI("#{BASE_URL}#{path}")
  http = Net::HTTP.new(uri.host, uri.port)
  
  case method.upcase
  when 'GET'
    request = Net::HTTP::Get.new(uri)
  when 'POST'
    request = Net::HTTP::Post.new(uri)
    if data
      request.body = data.to_json
      request['Content-Type'] = 'application/json'
    end
  end
  
  headers.each { |key, value| request[key] = value }
  
  begin
    response = http.request(request)
    {
      status: response.code.to_i,
      body: JSON.parse(response.body),
      headers: response.to_hash
    }
  rescue JSON::ParserError
    {
      status: response.code.to_i,
      body: response.body,
      headers: response.to_hash
    }
  rescue => e
    {
      error: e.message,
      status: 0
    }
  end
end

def test_endpoint(name, method, path, data = nil, headers = {}, expected_status = 200)
  puts "\n=== Testing #{name} ==="
  puts "#{method} #{path}"
  puts "Data: #{data.to_json}" if data
  
  result = make_request(method, path, data, headers)
  
  if result[:error]
    puts "❌ ERROR: #{result[:error]}"
    return false
  end
  
  puts "Status: #{result[:status]} (expected: #{expected_status})"
  puts "Response: #{JSON.pretty_generate(result[:body])}" if result[:body].is_a?(Hash)
  
  if result[:status] == expected_status
    puts "✅ PASSED"
    return result
  else
    puts "❌ FAILED - Expected status #{expected_status}, got #{result[:status]}"
    return false
  end
end

def run_tests
  puts "🚀 Starting Authentication Endpoints Test"
  puts "Base URL: #{BASE_URL}"
  
  # Test 1: API Info
  api_info = test_endpoint("API Info", "GET", "/api")
  return false unless api_info
  
  # Test 2: Register User
  register_result = test_endpoint("User Registration", "POST", "/api/auth/register", TEST_USER, {}, 201)
  return false unless register_result
  
  token = register_result[:body]['data']['token'] if register_result[:body]['data']
  puts "🔑 Token received: #{token[0..20]}..." if token
  
  # Test 3: Login User
  login_data = { email: TEST_USER[:email], password: TEST_USER[:password] }
  login_result = test_endpoint("User Login", "POST", "/api/auth/login", login_data)
  return false unless login_result
  
  login_token = login_result[:body]['data']['token'] if login_result[:body]['data']
  puts "🔑 Login token: #{login_token[0..20]}..." if login_token
  
  # Test 4: Get Current User
  auth_headers = { 'Authorization' => "Bearer #{login_token}" }
  me_result = test_endpoint("Get Current User", "GET", "/api/auth/me", nil, auth_headers)
  return false unless me_result
  
  # Test 5: Refresh Token
  refresh_result = test_endpoint("Refresh Token", "POST", "/api/auth/refresh", nil, auth_headers)
  return false unless refresh_result
  
  # Test 6: Logout
  logout_result = test_endpoint("Logout", "POST", "/api/auth/logout", nil, auth_headers)
  return false unless logout_result
  
  # Test 7: Invalid Token
  invalid_headers = { 'Authorization' => 'Bearer invalid.token.here' }
  test_endpoint("Invalid Token Test", "GET", "/api/auth/me", nil, invalid_headers, 401)
  
  # Test 8: Missing Token
  test_endpoint("Missing Token Test", "GET", "/api/auth/me", nil, {}, 401)
  
  puts "\n🎉 All authentication endpoint tests completed!"
  return true
end

if __FILE__ == $0
  puts "Authentication Endpoints Test Script"
  puts "===================================="
  puts
  puts "This script will test the authentication endpoints."
  puts "Make sure the Ruby server is running on #{BASE_URL}"
  puts
  print "Press Enter to continue or Ctrl+C to cancel..."
  gets
  
  success = run_tests
  
  if success
    puts "\n✅ All tests passed! Authentication endpoints are working correctly."
    exit 0
  else
    puts "\n❌ Some tests failed. Check the output above for details."
    exit 1
  end
end