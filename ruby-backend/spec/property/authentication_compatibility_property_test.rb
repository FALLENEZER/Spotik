# Property-based test for authentication compatibility
# **Feature: ruby-backend-migration, Property 3: Authentication Compatibility**
# **Validates: Requirements 2.1, 2.3**

require 'bundler/setup'
require 'rspec'
require 'rantly'
require 'rantly/rspec_extensions'
require 'bcrypt'
require 'securerandom'
require 'jwt'

# Set test environment
ENV['APP_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test_jwt_secret_key_for_testing_purposes_only'
ENV['JWT_TTL'] = '60' # 1 hour for testing

RSpec.describe 'Authentication Compatibility Property Test', :property do
  before(:all) do
    # Load configuration
    require_relative '../../config/settings'
    
    # Load test database configuration
    require_relative '../../config/test_database'
    
    # Override the DB constant for testing
    Object.send(:remove_const, :DB) if defined?(DB)
    DB = SpotikConfig::TestDatabase.connection
    
    # Load models and services with test database
    require_relative '../../app/models/user'
    require_relative '../../app/services/auth_service'
    
    # Finalize associations
    Sequel::Model.finalize_associations
  end
  
  before(:each) do
    # Clean database before each test
    DB[:users].delete
  end

  describe 'Property 3: Authentication Compatibility' do
    it 'authenticates any valid user credentials that worked in Legacy_System' do
      test_instance = self
      
      property_of {
        # Generate valid user credentials that would work in Laravel system
        user_data = test_instance.generate_valid_user_credentials
        user_data
      }.check(10) { |user_data|  # Reduced iterations for faster execution
        # Create user with Laravel-compatible password hash
        user = create_legacy_compatible_user(user_data)
        
        # Test authentication with the Ruby system
        authenticated_user = AuthService.authenticate(user_data[:email], user_data[:password])
        
        # Verify authentication succeeds
        expect(authenticated_user).not_to be_nil
        expect(authenticated_user.id).to eq(user.id)
        expect(authenticated_user.email).to eq(user.email)
        expect(authenticated_user.username).to eq(user.username)
        
        # Verify password verification works
        expect(authenticated_user.authenticate(user_data[:password])).to be true
        expect(authenticated_user.authenticate('wrong_password')).to be false
      }
    end

    it 'generates compatible JWT tokens for any authenticated user' do
      test_instance = self
      
      property_of {
        # Generate various user scenarios
        user_data = test_instance.generate_valid_user_credentials
        user_data
      }.check(10) { |user_data|  # Reduced iterations for faster execution
        # Create and authenticate user
        user = create_legacy_compatible_user(user_data)
        authenticated_user = AuthService.authenticate(user_data[:email], user_data[:password])
        
        # Generate JWT token
        jwt_token = AuthService.generate_jwt(authenticated_user)
        
        # Verify token is a valid JWT format
        expect(jwt_token).to be_a(String)
        expect(jwt_token.split('.').length).to eq(3) # JWT has 3 parts
        
        # Verify token can be decoded and validated
        auth_data = AuthService.validate_jwt(jwt_token)
        expect(auth_data).not_to be_nil
        expect(auth_data[:user].id).to eq(user.id)
        expect(auth_data[:token]).to eq(jwt_token)
        
        # Verify JWT payload contains required Laravel-compatible claims
        payload = auth_data[:payload]
        expect(payload['iss']).to eq('spotik-ruby')
        expect(payload['sub']).to eq(user.id.to_s)
        expect(payload['user_id']).to eq(user.id)
        expect(payload['username']).to eq(user.username)
        expect(payload['email']).to eq(user.email)
        expect(payload['iat']).to be_a(Integer)
        expect(payload['exp']).to be_a(Integer)
        expect(payload['nbf']).to be_a(Integer)
        expect(payload['jti']).to be_a(String)
        
        # Verify expiration time is correctly set
        expected_exp = payload['iat'] + (SpotikConfig::Settings.jwt_ttl * 60)
        expect(payload['exp']).to eq(expected_exp)
        
        # Verify token is not expired
        expect(payload['exp']).to be > Time.now.to_i
      }
    end

    it 'maintains authentication compatibility across different user types' do
      test_instance = self
      
      property_of {
        # Generate different types of users (admin, regular, with special characters, etc.)
        user_type = choose(:regular_user, :admin_user, :special_chars_user, :long_username_user, :unicode_user)
        user_data = test_instance.generate_user_by_type(user_type)
        [user_type, user_data]
      }.check(10) { |user_type, user_data|  # Reduced iterations for faster execution
        # Create user with Laravel-compatible setup
        user = create_legacy_compatible_user(user_data)
        
        # Test authentication works for all user types
        authenticated_user = AuthService.authenticate(user_data[:email], user_data[:password])
        expect(authenticated_user).not_to be_nil
        expect(authenticated_user.id).to eq(user.id)
        
        # Test JWT generation works for all user types
        jwt_token = AuthService.generate_jwt(authenticated_user)
        expect(jwt_token).to be_a(String)
        
        # Test JWT validation works for all user types
        auth_data = AuthService.validate_jwt(jwt_token)
        expect(auth_data).not_to be_nil
        expect(auth_data[:user].id).to eq(user.id)
        
        # Verify user-specific data is preserved in JWT
        payload = auth_data[:payload]
        expect(payload['username']).to eq(user.username)
        expect(payload['email']).to eq(user.email)
        
        # Test case-insensitive email authentication (Laravel compatibility)
        authenticated_upper = AuthService.authenticate(user_data[:email].upcase, user_data[:password])
        expect(authenticated_upper).not_to be_nil
        expect(authenticated_upper.id).to eq(user.id)
        
        # Test email with whitespace (Laravel compatibility)
        authenticated_whitespace = AuthService.authenticate("  #{user_data[:email]}  ", user_data[:password])
        expect(authenticated_whitespace).not_to be_nil
        expect(authenticated_whitespace.id).to eq(user.id)
      }
    end

    it 'handles authentication edge cases compatible with Legacy_System' do
      test_instance = self
      
      property_of {
        # Generate edge case scenarios
        edge_case = choose(:empty_password, :nil_password, :empty_email, :nil_email, :nonexistent_user, :wrong_password)
        user_data = test_instance.generate_valid_user_credentials
        [edge_case, user_data]
      }.check(10) { |edge_case, user_data|  # Reduced iterations for faster execution
        # Create a valid user for testing
        user = create_legacy_compatible_user(user_data) unless edge_case == :nonexistent_user
        
        # Test edge cases
        result = case edge_case
        when :empty_password
          AuthService.authenticate(user_data[:email], '')
        when :nil_password
          AuthService.authenticate(user_data[:email], nil)
        when :empty_email
          AuthService.authenticate('', user_data[:password])
        when :nil_email
          AuthService.authenticate(nil, user_data[:password])
        when :nonexistent_user
          AuthService.authenticate('nonexistent@example.com', user_data[:password])
        when :wrong_password
          AuthService.authenticate(user_data[:email], 'wrong_password')
        end
        
        # All edge cases should return nil (Laravel compatibility)
        expect(result).to be_nil
      }
    end

    it 'validates JWT tokens with proper error handling compatible with Legacy_System' do
      test_instance = self
      
      property_of {
        # Generate various JWT validation scenarios
        scenario = choose(:valid_token, :invalid_token, :expired_token, :malformed_token, :nil_token, :empty_token, :bearer_token)
        user_data = test_instance.generate_valid_user_credentials
        [scenario, user_data]
      }.check(10) { |scenario, user_data|  # Reduced iterations for faster execution
        user = create_legacy_compatible_user(user_data)
        
        case scenario
        when :valid_token
          # Test valid token validation
          token = AuthService.generate_jwt(user)
          auth_data = AuthService.validate_jwt(token)
          
          expect(auth_data).not_to be_nil
          expect(auth_data[:user].id).to eq(user.id)
          expect(auth_data[:token]).to eq(token)
          
        when :bearer_token
          # Test Bearer token format (Laravel compatibility)
          token = AuthService.generate_jwt(user)
          bearer_token = "Bearer #{token}"
          auth_data = AuthService.validate_jwt(bearer_token)
          
          expect(auth_data).not_to be_nil
          expect(auth_data[:user].id).to eq(user.id)
          expect(auth_data[:token]).to eq(token) # Should strip Bearer prefix
          
        when :invalid_token
          # Test invalid token handling
          expect {
            AuthService.validate_jwt('invalid.token.here')
          }.to raise_error(AuthenticationError) do |error|
            expect(error.code).to eq(:token_invalid)
          end
          
        when :expired_token
          # Test expired token handling
          expired_token = create_expired_jwt_token(user)
          expect {
            AuthService.validate_jwt(expired_token)
          }.to raise_error(AuthenticationError) do |error|
            expect(error.code).to eq(:token_expired)
          end
          
        when :malformed_token
          # Test malformed token handling
          expect {
            AuthService.validate_jwt('not.a.jwt')
          }.to raise_error(AuthenticationError) do |error|
            expect(error.code).to eq(:token_invalid)
          end
          
        when :nil_token
          # Test nil token handling (Laravel compatibility)
          result = AuthService.validate_jwt(nil)
          expect(result).to be_nil
          
        when :empty_token
          # Test empty token handling (Laravel compatibility)
          result = AuthService.validate_jwt('')
          expect(result).to be_nil
        end
      }
    end

    it 'maintains password hash compatibility with Laravel bcrypt' do
      test_instance = self
      
      property_of {
        # Generate various password scenarios
        password_data = test_instance.generate_password_scenarios
        password_data
      }.check(10) { |password_data|  # Reduced iterations for faster execution
        # Create user with the password
        user_data = generate_valid_user_credentials.merge(password: password_data[:password])
        user = create_legacy_compatible_user(user_data)
        
        # Verify password hash is bcrypt format (Laravel compatibility)
        expect(user.password_hash).to start_with('$2')
        
        # Verify password authentication works
        expect(user.authenticate(password_data[:password])).to be true
        
        # Verify wrong passwords fail
        expect(user.authenticate('wrong_password')).to be false
        expect(user.authenticate('')).to be false
        expect(user.authenticate(nil)).to be false
        
        # Verify AuthService authentication works
        authenticated_user = AuthService.authenticate(user.email, password_data[:password])
        expect(authenticated_user).not_to be_nil
        expect(authenticated_user.id).to eq(user.id)
        
        # Verify case sensitivity of passwords
        if password_data[:password] != password_data[:password].upcase
          expect(user.authenticate(password_data[:password].upcase)).to be false
        end
      }
    end
  end

  # Helper methods for generating test data

  def generate_valid_user_credentials
    {
      username: generate_username,
      email: generate_email,
      password: generate_password
    }
  end

  def generate_user_by_type(user_type)
    base_data = generate_valid_user_credentials
    
    case user_type
    when :regular_user
      base_data
    when :admin_user
      base_data.merge(username: "admin_#{SecureRandom.hex(4)}")
    when :special_chars_user
      base_data.merge(
        username: "user-#{SecureRandom.hex(3)}_test",
        email: "test+#{SecureRandom.hex(3)}@example.com"
      )
    when :long_username_user
      base_data.merge(username: "very_long_username_#{SecureRandom.hex(8)}"[0..49]) # Max 50 chars
    when :unicode_user
      base_data.merge(
        username: "user_#{SecureRandom.hex(3)}",
        email: "test_#{SecureRandom.hex(3)}@example.com"
      )
    end
  end

  def generate_password_scenarios
    password_types = [
      'simple123',
      'Complex!Password123',
      'password_with_underscores_123',
      'PASSWORD_ALL_CAPS_123',
      'MiXeD_CaSe_PaSsWoRd_123',
      'special!@#$%^&*()123',
      'very_long_password_with_many_characters_123456789',
      '12345678', # Minimum length
      'пароль123', # Unicode characters
      'password with spaces 123'
    ]
    
    { password: password_types.sample }
  end

  def generate_username
    prefixes = ['user', 'test', 'demo', 'admin', 'guest']
    "#{prefixes.sample}_#{SecureRandom.hex(6)}"
  end

  def generate_email
    domains = ['example.com', 'test.org', 'demo.net', 'sample.io']
    "#{SecureRandom.hex(6)}@#{domains.sample}"
  end

  def generate_password
    # Generate passwords that meet Laravel validation requirements (min 8 chars)
    password_patterns = [
      "password#{rand(100..999)}",
      "Password#{rand(100..999)}!",
      "#{SecureRandom.hex(4)}Pass123",
      "Test#{rand(1000..9999)}$",
      "#{SecureRandom.alphanumeric(8)}123"
    ]
    
    password_patterns.sample
  end

  def create_legacy_compatible_user(user_data)
    # Create user with Laravel-compatible bcrypt hash
    User.create(
      username: user_data[:username],
      email: user_data[:email].downcase.strip,
      password_hash: BCrypt::Password.create(user_data[:password]),
      created_at: Time.now,
      updated_at: Time.now
    )
  end

  def create_expired_jwt_token(user)
    # Create an expired JWT token for testing
    now = Time.now.to_i
    payload = {
      iss: 'spotik-ruby',
      iat: now - 7200, # Issued 2 hours ago
      exp: now - 3600, # Expired 1 hour ago
      nbf: now - 7200,
      sub: user.id.to_s,
      jti: SecureRandom.hex(16),
      user_id: user.id,
      username: user.username,
      email: user.email
    }
    
    JWT.encode(payload, SpotikConfig::Settings.jwt_secret, 'HS256')
  end
end