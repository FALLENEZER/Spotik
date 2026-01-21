#!/usr/bin/env ruby

# Simple test for authentication service functionality
# Tests the core authentication logic without database dependencies

puts "Testing Authentication Service..."

# Set test environment
ENV['APP_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test_jwt_secret_key_for_testing_purposes_only'
ENV['JWT_TTL'] = '60' # 1 hour for testing

begin
  # Load configuration
  require_relative 'config/settings'
  
  # Load test database configuration
  require_relative 'config/test_database'
  
  # Override the DB constant for testing
  Object.send(:remove_const, :DB) if defined?(DB)
  DB = SpotikConfig::TestDatabase.connection
  
  # Load models and services with test database
  require_relative 'app/models/user'
  require_relative 'app/services/auth_service'
  require_relative 'app/controllers/auth_controller'
  
  # Finalize associations
  Sequel::Model.finalize_associations
  
  puts "✅ All dependencies loaded successfully"
  
  # Clean database
  DB[:users].delete
  puts "✅ Database cleaned"
  
  # Test 1: User Registration
  puts "\n=== Test 1: User Registration ==="
  
  user_data = {
    'username' => 'testuser',
    'email' => 'test@example.com',
    'password' => 'password123',
    'password_confirmation' => 'password123'
  }
  
  register_result = AuthController.register(user_data)
  
  if register_result[:status] == 201
    puts "✅ User registration successful"
    puts "   Status: #{register_result[:status]}"
    puts "   User ID: #{register_result[:body][:data][:user][:id]}"
    puts "   Token: #{register_result[:body][:data][:token][0..20]}..."
    registration_token = register_result[:body][:data][:token]
  else
    puts "❌ User registration failed"
    puts "   Status: #{register_result[:status]}"
    puts "   Body: #{register_result[:body]}"
    exit 1
  end
  
  # Test 2: User Login
  puts "\n=== Test 2: User Login ==="
  
  login_data = {
    'email' => 'test@example.com',
    'password' => 'password123'
  }
  
  login_result = AuthController.login(login_data)
  
  if login_result[:status] == 200
    puts "✅ User login successful"
    puts "   Status: #{login_result[:status]}"
    puts "   User ID: #{login_result[:body][:data][:user][:id]}"
    puts "   Token: #{login_result[:body][:data][:token][0..20]}..."
    login_token = login_result[:body][:data][:token]
  else
    puts "❌ User login failed"
    puts "   Status: #{login_result[:status]}"
    puts "   Body: #{login_result[:body]}"
    exit 1
  end
  
  # Test 3: Get Current User
  puts "\n=== Test 3: Get Current User ==="
  
  me_result = AuthController.me(login_token)
  
  if me_result[:status] == 200
    puts "✅ Get current user successful"
    puts "   Status: #{me_result[:status]}"
    puts "   Username: #{me_result[:body][:data][:user][:username]}"
    puts "   Email: #{me_result[:body][:data][:user][:email]}"
  else
    puts "❌ Get current user failed"
    puts "   Status: #{me_result[:status]}"
    puts "   Body: #{me_result[:body]}"
    exit 1
  end
  
  # Test 4: Token Validation
  puts "\n=== Test 4: Token Validation ==="
  
  begin
    auth_data = AuthService.validate_jwt(login_token)
    puts "✅ Token validation successful"
    puts "   User ID: #{auth_data[:user].id}"
    puts "   Username: #{auth_data[:user].username}"
    puts "   Email: #{auth_data[:user].email}"
  rescue => e
    puts "❌ Token validation failed: #{e.message}"
    exit 1
  end
  
  # Test 5: Invalid Token Handling
  puts "\n=== Test 5: Invalid Token Handling ==="
  
  begin
    AuthService.validate_jwt('invalid.token.here')
    puts "❌ Invalid token should have been rejected"
    exit 1
  rescue AuthenticationError => e
    puts "✅ Invalid token properly rejected"
    puts "   Error code: #{e.code}"
    puts "   Error message: #{e.message}"
  end
  
  # Test 6: Token Refresh
  puts "\n=== Test 6: Token Refresh ==="
  
  refresh_result = AuthController.refresh(login_token)
  
  if refresh_result[:status] == 200
    puts "✅ Token refresh successful"
    puts "   Status: #{refresh_result[:status]}"
    puts "   New token: #{refresh_result[:body][:data][:token][0..20]}..."
    refreshed_token = refresh_result[:body][:data][:token]
    
    # Verify new token works
    auth_data = AuthService.validate_jwt(refreshed_token)
    puts "✅ Refreshed token is valid"
    puts "   User ID: #{auth_data[:user].id}"
  else
    puts "❌ Token refresh failed"
    puts "   Status: #{refresh_result[:status]}"
    puts "   Body: #{refresh_result[:body]}"
    exit 1
  end
  
  # Test 7: Logout
  puts "\n=== Test 7: Logout ==="
  
  logout_result = AuthController.logout(login_token)
  
  if logout_result[:status] == 200
    puts "✅ Logout successful"
    puts "   Status: #{logout_result[:status]}"
    puts "   Message: #{logout_result[:body][:message]}"
  else
    puts "❌ Logout failed"
    puts "   Status: #{logout_result[:status]}"
    puts "   Body: #{logout_result[:body]}"
    exit 1
  end
  
  # Test 8: Authentication Edge Cases
  puts "\n=== Test 8: Authentication Edge Cases ==="
  
  # Test wrong password
  wrong_password_result = AuthController.login({
    'email' => 'test@example.com',
    'password' => 'wrongpassword'
  })
  
  if wrong_password_result[:status] == 401
    puts "✅ Wrong password properly rejected"
  else
    puts "❌ Wrong password should have been rejected with 401"
    exit 1
  end
  
  # Test nonexistent user
  nonexistent_result = AuthController.login({
    'email' => 'nonexistent@example.com',
    'password' => 'password123'
  })
  
  if nonexistent_result[:status] == 401
    puts "✅ Nonexistent user properly rejected"
  else
    puts "❌ Nonexistent user should have been rejected with 401"
    exit 1
  end
  
  # Test duplicate registration
  duplicate_result = AuthController.register(user_data)
  
  if duplicate_result[:status] == 422
    puts "✅ Duplicate registration properly rejected"
    puts "   Errors: #{duplicate_result[:body][:errors]}"
  else
    puts "❌ Duplicate registration should have been rejected with 422"
    exit 1
  end
  
  puts "\n🎉 All authentication tests passed!"
  puts "✅ Authentication system is working correctly"
  
rescue => e
  puts "❌ Test failed with error: #{e.message}"
  puts "   Backtrace: #{e.backtrace.first(5).join("\n   ")}"
  exit 1
end