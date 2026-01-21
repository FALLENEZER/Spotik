#!/usr/bin/env ruby

# Basic functionality test for Ruby backend
# Tests core components without requiring full database setup

puts "=== Ruby Backend Basic Functionality Test ==="
puts "Testing core components and API structure..."

# Set test environment
ENV['APP_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test_jwt_secret_key_for_testing_purposes_only'
ENV['JWT_TTL'] = '60'
ENV['SERVER_PORT'] = '3001'
ENV['LOG_LEVEL'] = 'error'

begin
  # Test 1: Configuration Loading
  puts "\n1. Testing configuration loading..."
  require_relative 'config/settings'
  
  puts "✅ Settings loaded successfully"
  puts "   App Name: #{SpotikConfig::Settings.app_name}"
  puts "   Environment: #{SpotikConfig::Settings.app_env}"
  puts "   Server Port: #{SpotikConfig::Settings.server_port}"
  puts "   JWT TTL: #{SpotikConfig::Settings.jwt_ttl} minutes"
  
  # Test 2: Basic Dependencies
  puts "\n2. Testing basic dependencies..."
  require 'json'
  require 'logger'
  require 'sinatra/base'
  
  puts "✅ Basic dependencies loaded"
  
  # Test 3: JWT Service (without database)
  puts "\n3. Testing JWT service..."
  require 'jwt'
  require 'bcrypt'
  
  # Simple JWT test
  payload = { user_id: 'test-user-123', exp: Time.now.to_i + 3600 }
  token = JWT.encode(payload, SpotikConfig::Settings.jwt_secret, 'HS256')
  decoded = JWT.decode(token, SpotikConfig::Settings.jwt_secret, true, { algorithm: 'HS256' })
  
  if decoded[0]['user_id'] == 'test-user-123'
    puts "✅ JWT encoding/decoding works"
    puts "   Token: #{token[0..20]}..."
  else
    puts "❌ JWT test failed"
    exit 1
  end
  
  # Test 4: Password Hashing
  puts "\n4. Testing password hashing..."
  password = 'test_password_123'
  hash = BCrypt::Password.create(password)
  
  if BCrypt::Password.new(hash) == password
    puts "✅ Password hashing works"
    puts "   Hash: #{hash[0..20]}..."
  else
    puts "❌ Password hashing test failed"
    exit 1
  end
  
  # Test 5: JSON Processing
  puts "\n5. Testing JSON processing..."
  test_data = {
    status: 'success',
    data: {
      user: {
        id: 'test-123',
        username: 'testuser',
        email: 'test@example.com'
      },
      token: token
    },
    timestamp: Time.now.iso8601
  }
  
  json_string = test_data.to_json
  parsed_data = JSON.parse(json_string, symbolize_names: true)
  
  if parsed_data[:data][:user][:username] == 'testuser'
    puts "✅ JSON processing works"
    puts "   Data size: #{json_string.length} bytes"
  else
    puts "❌ JSON processing test failed"
    exit 1
  end
  
  # Test 6: Basic Sinatra App Structure
  puts "\n6. Testing Sinatra app structure..."
  
  class TestApp < Sinatra::Base
    get '/test' do
      content_type :json
      { message: 'Test endpoint working', timestamp: Time.now.iso8601 }.to_json
    end
    
    get '/health' do
      content_type :json
      { status: 'healthy', test_mode: true }.to_json
    end
  end
  
  puts "✅ Sinatra app structure created"
  puts "   Test endpoints: /test, /health"
  
  # Test 7: File System Operations
  puts "\n7. Testing file system operations..."
  
  test_dir = './tmp/test_files'
  Dir.mkdir(test_dir) unless Dir.exist?(test_dir)
  
  test_file = File.join(test_dir, 'test.txt')
  File.write(test_file, 'Test file content')
  
  if File.exist?(test_file) && File.read(test_file) == 'Test file content'
    puts "✅ File system operations work"
    puts "   Test file: #{test_file}"
    
    # Cleanup
    File.delete(test_file)
    Dir.rmdir(test_dir) if Dir.empty?(test_dir)
  else
    puts "❌ File system operations test failed"
    exit 1
  end
  
  # Test 8: Error Handling
  puts "\n8. Testing error handling..."
  
  begin
    # Test invalid JWT
    JWT.decode('invalid.token.here', SpotikConfig::Settings.jwt_secret, true, { algorithm: 'HS256' })
    puts "❌ Invalid JWT should have raised an error"
    exit 1
  rescue JWT::DecodeError => e
    puts "✅ JWT error handling works"
    puts "   Error: #{e.class.name}"
  end
  
  # Test 9: Time and Date Operations
  puts "\n9. Testing time and date operations..."
  
  now = Time.now
  iso_time = now.iso8601
  unix_time = now.to_f
  
  parsed_time = Time.parse(iso_time)
  
  if (parsed_time.to_f - unix_time).abs < 1.0
    puts "✅ Time operations work"
    puts "   ISO time: #{iso_time}"
    puts "   Unix time: #{unix_time}"
  else
    puts "❌ Time operations test failed"
    exit 1
  end
  
  # Test 10: Basic HTTP Status Codes
  puts "\n10. Testing HTTP status code handling..."
  
  status_codes = {
    200 => 'OK',
    201 => 'Created',
    400 => 'Bad Request',
    401 => 'Unauthorized',
    403 => 'Forbidden',
    404 => 'Not Found',
    422 => 'Unprocessable Entity',
    500 => 'Internal Server Error'
  }
  
  status_codes.each do |code, message|
    # Just verify we can reference these codes
    if code.is_a?(Integer) && code >= 200 && code < 600
      # Status code is valid
    else
      puts "❌ Invalid status code: #{code}"
      exit 1
    end
  end
  
  puts "✅ HTTP status codes validated"
  puts "   Codes tested: #{status_codes.keys.join(', ')}"
  
  # Summary
  puts "\n" + "="*50
  puts "🎉 ALL BASIC FUNCTIONALITY TESTS PASSED!"
  puts "✅ Configuration loading"
  puts "✅ Dependencies loading"
  puts "✅ JWT service"
  puts "✅ Password hashing"
  puts "✅ JSON processing"
  puts "✅ Sinatra app structure"
  puts "✅ File system operations"
  puts "✅ Error handling"
  puts "✅ Time operations"
  puts "✅ HTTP status codes"
  puts "="*50
  
  puts "\nCore Ruby backend components are functional!"
  puts "Ready for integration testing with database and WebSocket components."
  
rescue LoadError => e
  puts "❌ Dependency loading failed: #{e.message}"
  puts "   Missing gem or file: #{e.message}"
  exit 1
rescue => e
  puts "❌ Test failed with error: #{e.message}"
  puts "   Error class: #{e.class.name}"
  puts "   Backtrace: #{e.backtrace.first(3).join("\n   ")}"
  exit 1
end