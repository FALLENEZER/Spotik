# Unit tests for authentication service (without database)
require 'bundler/setup'
require 'rspec'
require 'jwt'
require 'bcrypt'
require 'json'
require 'securerandom'

# Set test environment
ENV['APP_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test_secret_key_for_testing_only'
ENV['JWT_TTL'] = '60'

# Load only the configuration we need
require_relative '../config/settings'

# Mock User class for testing
class MockUser
  attr_accessor :id, :username, :email, :password_hash, :created_at, :updated_at
  
  def initialize(attributes = {})
    @id = attributes[:id] || rand(1000)
    @username = attributes[:username]
    @email = attributes[:email]
    @password_hash = attributes[:password_hash]
    @created_at = attributes[:created_at] || Time.now
    @updated_at = attributes[:updated_at] || Time.now
  end
  
  def authenticate(password)
    return false unless password_hash
    BCrypt::Password.new(password_hash) == password
  rescue BCrypt::Errors::InvalidHash
    false
  end
  
  def ==(other)
    other.is_a?(MockUser) && other.id == id
  end
end

# Create a mock User constant for the AuthService to use
User = Class.new do
  def self.[](id)
    # This will be stubbed in tests
    nil
  end
end

# Load authentication service with mocked dependencies
require_relative '../app/services/auth_service'

RSpec.describe AuthService do
  describe '.generate_jwt' do
    let(:user) do
      MockUser.new(
        id: 123,
        username: 'testuser',
        email: 'test@example.com',
        password_hash: BCrypt::Password.create('password123')
      )
    end

    it 'generates a valid JWT token' do
      token = AuthService.generate_jwt(user)
      expect(token).to be_a(String)
      expect(token.split('.').length).to eq(3) # JWT has 3 parts
    end

    it 'includes correct user information in token' do
      token = AuthService.generate_jwt(user)
      
      # Decode token manually to verify contents
      decoded = JWT.decode(token, SpotikConfig::Settings.jwt_secret, true, { algorithm: 'HS256' })
      payload = decoded[0]
      
      expect(payload['user_id']).to eq(user.id)
      expect(payload['username']).to eq(user.username)
      expect(payload['email']).to eq(user.email)
    end

    it 'includes standard JWT claims' do
      token = AuthService.generate_jwt(user)
      
      decoded = JWT.decode(token, SpotikConfig::Settings.jwt_secret, true, { algorithm: 'HS256' })
      payload = decoded[0]
      
      expect(payload['iss']).to eq('spotik-ruby')
      expect(payload['sub']).to eq(user.id.to_s)
      expect(payload['iat']).to be_a(Integer)
      expect(payload['exp']).to be_a(Integer)
      expect(payload['nbf']).to be_a(Integer)
      expect(payload['jti']).to be_a(String)
    end

    it 'sets correct expiration time' do
      token = AuthService.generate_jwt(user)
      
      decoded = JWT.decode(token, SpotikConfig::Settings.jwt_secret, true, { algorithm: 'HS256' })
      payload = decoded[0]
      
      expected_exp = payload['iat'] + (SpotikConfig::Settings.jwt_ttl * 60)
      expect(payload['exp']).to eq(expected_exp)
    end
  end

  describe '.validate_jwt (token structure validation)' do
    let(:user) do
      MockUser.new(
        id: 123,
        username: 'testuser',
        email: 'test@example.com'
      )
    end

    it 'handles Bearer prefix in token' do
      token = AuthService.generate_jwt(user)
      bearer_token = "Bearer #{token}"
      
      # Mock User lookup to return our test user
      allow(User).to receive(:[]).with(123).and_return(user)
      
      auth_data = AuthService.validate_jwt(bearer_token)
      expect(auth_data[:token]).to eq(token)
    end

    it 'returns nil for nil token' do
      expect(AuthService.validate_jwt(nil)).to be_nil
    end

    it 'returns nil for empty token' do
      expect(AuthService.validate_jwt('')).to be_nil
    end

    it 'raises AuthenticationError for invalid token' do
      expect {
        AuthService.validate_jwt('invalid.token.here')
      }.to raise_error(AuthenticationError) do |error|
        expect(error.code).to eq(:token_invalid)
      end
    end

    it 'raises AuthenticationError for expired token' do
      # Create an expired token by manipulating the payload
      now = Time.now.to_i
      payload = {
        iss: 'spotik-ruby',
        iat: now - 3600,
        exp: now - 1800, # Expired 30 minutes ago
        nbf: now - 3600,
        sub: user.id.to_s,
        jti: SecureRandom.hex(16),
        user_id: user.id,
        username: user.username,
        email: user.email
      }
      
      expired_token = JWT.encode(payload, SpotikConfig::Settings.jwt_secret, 'HS256')
      
      expect {
        AuthService.validate_jwt(expired_token)
      }.to raise_error(AuthenticationError) do |error|
        expect(error.code).to eq(:token_expired)
      end
    end
  end

  describe 'validation helpers' do
    describe '.valid_email?' do
      it 'validates correct email formats' do
        expect(AuthService.send(:valid_email?, 'test@example.com')).to be true
        expect(AuthService.send(:valid_email?, 'user.name@domain.co.uk')).to be true
        expect(AuthService.send(:valid_email?, 'test+tag@example.org')).to be true
      end

      it 'rejects invalid email formats' do
        expect(AuthService.send(:valid_email?, 'invalid-email')).to be false
        expect(AuthService.send(:valid_email?, '@example.com')).to be false
        expect(AuthService.send(:valid_email?, 'test@')).to be false
      end
    end

    describe '.validate_registration_data' do
      it 'passes validation for valid data' do
        valid_data = {
          username: 'testuser',
          email: 'test@example.com',
          password: 'password123',
          password_confirmation: 'password123'
        }
        
        expect {
          AuthService.send(:validate_registration_data, valid_data)
        }.not_to raise_error
      end

      it 'raises ValidationError for missing username' do
        invalid_data = {
          email: 'test@example.com',
          password: 'password123',
          password_confirmation: 'password123'
        }
        
        expect {
          AuthService.send(:validate_registration_data, invalid_data)
        }.to raise_error(ValidationError) do |error|
          expect(error.errors[:username]).to include('The username field is required.')
        end
      end

      it 'raises ValidationError for missing email' do
        invalid_data = {
          username: 'testuser',
          password: 'password123',
          password_confirmation: 'password123'
        }
        
        expect {
          AuthService.send(:validate_registration_data, invalid_data)
        }.to raise_error(ValidationError) do |error|
          expect(error.errors[:email]).to include('The email field is required.')
        end
      end

      it 'raises ValidationError for short password' do
        invalid_data = {
          username: 'testuser',
          email: 'test@example.com',
          password: '123',
          password_confirmation: '123'
        }
        
        expect {
          AuthService.send(:validate_registration_data, invalid_data)
        }.to raise_error(ValidationError) do |error|
          expect(error.errors[:password]).to include('The password must be at least 8 characters.')
        end
      end

      it 'raises ValidationError for password confirmation mismatch' do
        invalid_data = {
          username: 'testuser',
          email: 'test@example.com',
          password: 'password123',
          password_confirmation: 'different123'
        }
        
        expect {
          AuthService.send(:validate_registration_data, invalid_data)
        }.to raise_error(ValidationError) do |error|
          expect(error.errors[:password]).to include('The password confirmation does not match.')
        end
      end

      it 'raises ValidationError for invalid email format' do
        invalid_data = {
          username: 'testuser',
          email: 'invalid-email',
          password: 'password123',
          password_confirmation: 'password123'
        }
        
        expect {
          AuthService.send(:validate_registration_data, invalid_data)
        }.to raise_error(ValidationError) do |error|
          expect(error.errors[:email]).to include('The email must be a valid email address.')
        end
      end

      it 'raises ValidationError for long username' do
        invalid_data = {
          username: 'a' * 51, # 51 characters
          email: 'test@example.com',
          password: 'password123',
          password_confirmation: 'password123'
        }
        
        expect {
          AuthService.send(:validate_registration_data, invalid_data)
        }.to raise_error(ValidationError) do |error|
          expect(error.errors[:username]).to include('The username may not be greater than 50 characters.')
        end
      end

      it 'raises ValidationError for long email' do
        long_email = 'a' * 250 + '@example.com' # > 255 characters
        invalid_data = {
          username: 'testuser',
          email: long_email,
          password: 'password123',
          password_confirmation: 'password123'
        }
        
        expect {
          AuthService.send(:validate_registration_data, invalid_data)
        }.to raise_error(ValidationError) do |error|
          expect(error.errors[:email]).to include('The email may not be greater than 255 characters.')
        end
      end
    end
  end

  describe 'JWT token generation and validation cycle' do
    let(:user) do
      MockUser.new(
        id: 456,
        username: 'cycletest',
        email: 'cycle@example.com'
      )
    end

    it 'can generate and validate tokens in a complete cycle' do
      # Generate token
      token = AuthService.generate_jwt(user)
      expect(token).to be_a(String)
      
      # Mock User lookup for validation
      allow(User).to receive(:[]).with(456).and_return(user)
      
      # Validate token
      auth_data = AuthService.validate_jwt(token)
      expect(auth_data[:user]).to eq(user)
      expect(auth_data[:token]).to eq(token)
      expect(auth_data[:payload]).to be_a(Hash)
      
      # Verify payload contents
      payload = auth_data[:payload]
      expect(payload['user_id']).to eq(456)
      expect(payload['username']).to eq('cycletest')
      expect(payload['email']).to eq('cycle@example.com')
    end

    it 'generates unique tokens for the same user' do
      token1 = AuthService.generate_jwt(user)
      sleep(1) # Ensure different timestamps
      token2 = AuthService.generate_jwt(user)
      
      expect(token1).not_to eq(token2)
      
      # Both should be valid
      allow(User).to receive(:[]).with(456).and_return(user)
      
      auth_data1 = AuthService.validate_jwt(token1)
      auth_data2 = AuthService.validate_jwt(token2)
      
      expect(auth_data1[:user]).to eq(user)
      expect(auth_data2[:user]).to eq(user)
    end
  end
end