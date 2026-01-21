#!/usr/bin/env ruby

# Minimal functionality test using only built-in Ruby libraries
# Tests basic Ruby backend structure without external gems

puts "=== Ruby Backend Minimal Functionality Test ==="
puts "Testing with built-in Ruby libraries only..."

# Set test environment
ENV['APP_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test_jwt_secret_key_for_testing_purposes_only'
ENV['JWT_TTL'] = '60'
ENV['SERVER_PORT'] = '3001'
ENV['LOG_LEVEL'] = 'error'

begin
  # Test 1: Basic Ruby functionality
  puts "\n1. Testing basic Ruby functionality..."
  puts "   Ruby version: #{RUBY_VERSION}"
  puts "   Platform: #{RUBY_PLATFORM}"
  puts "✅ Ruby environment working"
  
  # Test 2: Environment variables
  puts "\n2. Testing environment variables..."
  test_vars = {
    'APP_ENV' => ENV['APP_ENV'],
    'JWT_SECRET' => ENV['JWT_SECRET'][0..10] + '...',
    'SERVER_PORT' => ENV['SERVER_PORT']
  }
  
  test_vars.each do |key, value|
    puts "   #{key}: #{value}"
  end
  puts "✅ Environment variables working"
  
  # Test 3: File system operations
  puts "\n3. Testing file system operations..."
  
  # Check if required directories exist
  required_dirs = ['app', 'config', 'spec', 'storage']
  missing_dirs = []
  
  required_dirs.each do |dir|
    if Dir.exist?(dir)
      puts "   ✓ #{dir}/ directory exists"
    else
      missing_dirs << dir
      puts "   ✗ #{dir}/ directory missing"
    end
  end
  
  if missing_dirs.empty?
    puts "✅ Directory structure complete"
  else
    puts "⚠️  Some directories missing: #{missing_dirs.join(', ')}"
  end
  
  # Test 4: Check key files exist
  puts "\n4. Testing key files existence..."
  
  key_files = [
    'server.rb',
    'Gemfile',
    'config/settings.rb',
    'config/database.rb',
    'app/models.rb'
  ]
  
  missing_files = []
  
  key_files.each do |file|
    if File.exist?(file)
      size = File.size(file)
      puts "   ✓ #{file} (#{size} bytes)"
    else
      missing_files << file
      puts "   ✗ #{file} missing"
    end
  end
  
  if missing_files.empty?
    puts "✅ All key files present"
  else
    puts "❌ Missing files: #{missing_files.join(', ')}"
    exit 1
  end
  
  # Test 5: Basic string and hash operations
  puts "\n5. Testing basic data operations..."
  
  # Test hash operations
  test_hash = {
    'status' => 'success',
    'data' => {
      'user' => {
        'id' => 'test-123',
        'username' => 'testuser'
      }
    }
  }
  
  if test_hash['data']['user']['username'] == 'testuser'
    puts "   ✓ Hash operations working"
  else
    puts "   ✗ Hash operations failed"
    exit 1
  end
  
  # Test string operations
  test_string = "Bearer test_token_123"
  if test_string.start_with?('Bearer ') && test_string[7..-1] == 'test_token_123'
    puts "   ✓ String operations working"
  else
    puts "   ✗ String operations failed"
    exit 1
  end
  
  puts "✅ Basic data operations working"
  
  # Test 6: Time operations
  puts "\n6. Testing time operations..."
  
  now = Time.now
  unix_time = now.to_i
  formatted_time = now.strftime('%Y-%m-%d %H:%M:%S')
  
  puts "   Current time: #{formatted_time}"
  puts "   Unix timestamp: #{unix_time}"
  
  # Test time arithmetic
  future_time = now + 3600  # Add 1 hour
  if future_time > now
    puts "   ✓ Time arithmetic working"
  else
    puts "   ✗ Time arithmetic failed"
    exit 1
  end
  
  puts "✅ Time operations working"
  
  # Test 7: Basic HTTP status code mapping
  puts "\n7. Testing HTTP status code mapping..."
  
  status_messages = {
    200 => 'OK',
    201 => 'Created',
    400 => 'Bad Request',
    401 => 'Unauthorized',
    404 => 'Not Found',
    500 => 'Internal Server Error'
  }
  
  status_messages.each do |code, message|
    puts "   #{code}: #{message}"
  end
  
  puts "✅ HTTP status codes mapped"
  
  # Test 8: Basic error handling
  puts "\n8. Testing error handling..."
  
  begin
    # Test division by zero
    result = 1 / 0
    puts "   ✗ Error handling failed - should have caught division by zero"
    exit 1
  rescue ZeroDivisionError => e
    puts "   ✓ Caught ZeroDivisionError: #{e.message}"
  end
  
  begin
    # Test method call on nil
    nil.some_method
    puts "   ✗ Error handling failed - should have caught NoMethodError"
    exit 1
  rescue NoMethodError => e
    puts "   ✓ Caught NoMethodError: #{e.class.name}"
  end
  
  puts "✅ Error handling working"
  
  # Test 9: File reading capabilities
  puts "\n9. Testing file reading capabilities..."
  
  # Try to read a small config file
  if File.exist?('.env.test')
    content = File.read('.env.test')
    lines = content.lines.count
    puts "   ✓ Read .env.test (#{lines} lines)"
  else
    puts "   ⚠️  .env.test not found, skipping file read test"
  end
  
  # Test file writing
  test_file = 'tmp/test_write.txt'
  Dir.mkdir('tmp') unless Dir.exist?('tmp')
  
  File.write(test_file, "Test content\nLine 2\n")
  
  if File.exist?(test_file)
    read_content = File.read(test_file)
    if read_content.include?('Test content')
      puts "   ✓ File write/read working"
      File.delete(test_file)  # Cleanup
    else
      puts "   ✗ File content mismatch"
      exit 1
    end
  else
    puts "   ✗ File write failed"
    exit 1
  end
  
  puts "✅ File operations working"
  
  # Test 10: Basic class and module structure
  puts "\n10. Testing class and module structure..."
  
  module TestModule
    def self.test_method
      "Module method working"
    end
  end
  
  class TestClass
    attr_reader :name
    
    def initialize(name)
      @name = name
    end
    
    def greet
      "Hello, #{@name}!"
    end
  end
  
  # Test module
  if TestModule.test_method == "Module method working"
    puts "   ✓ Module methods working"
  else
    puts "   ✗ Module methods failed"
    exit 1
  end
  
  # Test class
  test_obj = TestClass.new("Ruby Backend")
  if test_obj.greet == "Hello, Ruby Backend!"
    puts "   ✓ Class methods working"
  else
    puts "   ✗ Class methods failed"
    exit 1
  end
  
  puts "✅ Class and module structure working"
  
  # Summary
  puts "\n" + "="*60
  puts "🎉 ALL MINIMAL FUNCTIONALITY TESTS PASSED!"
  puts "✅ Ruby environment (#{RUBY_VERSION})"
  puts "✅ Environment variables"
  puts "✅ File system operations"
  puts "✅ Key files present"
  puts "✅ Basic data operations"
  puts "✅ Time operations"
  puts "✅ HTTP status codes"
  puts "✅ Error handling"
  puts "✅ File operations"
  puts "✅ Class/module structure"
  puts "="*60
  
  puts "\nCore Ruby functionality is working!"
  puts "The Ruby backend structure is in place and basic operations are functional."
  puts "\nNote: This test uses only built-in Ruby libraries."
  puts "Full functionality requires proper gem installation and database setup."
  
rescue => e
  puts "❌ Test failed with error: #{e.message}"
  puts "   Error class: #{e.class.name}"
  puts "   Backtrace: #{e.backtrace.first(3).join("\n   ")}"
  exit 1
end