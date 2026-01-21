# Authentication service tests
require_relative 'spec_helper'
require_relative '../app/services/auth_service'

RSpec.describe AuthService do
  before(:each) do
    # Clean up users before each test
    User.dataset.delete
  end

  describe '.authenticate' do
    let(:user) do
      User.create(
        username: 'testuser',
        email: 'test@example.com',
        password_hash: BCrypt::Password.create('password123')
      )
    end

    it 'authenticates user with valid credentials' do
      result = AuthService.authenticate('test@example.com', 'password123')
      expect(result).to eq(user)
    end

    it 'returns nil for invalid email' do
      result = AuthService.authenticate('wrong@example.com', 'password123')
      expect(result).to be_nil
    end

    it 'returns nil for invalid password' do
      user # Create user
      result = AuthService.authenticate('test@example.com', 'wrongpassword')
      expect(result).to be_nil
    end

    it 'returns nil for nil email' do
      result = AuthService.authenticate(nil, 'password123')
      expect(result).to be_nil
    end

    it 'returns nil for nil password' do
      result = AuthService.authenticate('test@example.com', nil)
      expect(result).to be_nil
    end

    it 'handles email case insensitivity' do
      user # Create user
      result = AuthService.authenticate('TEST@EXAMPLE.COM', 'password123')
      expect(result).to eq(user)
    end

    it 'handles email with whitespace' do
      user # Create user
      result = AuthService.authenticate('  test@example.com  ', 'password123')
      expect(result).to eq(user)
    end
  end

  describe '.generate_jwt' do
    let(:user) do
      User.create(
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
      auth_data = AuthService.validate_jwt(token)
      
      expect(auth_data[:user].id).to eq(user.id)
      expect(auth_data[:payload]['user_id']).to eq(user.id)
      expect(auth_data[:payload]['username']).to eq(user.username)
      expect(auth_data[:payload]['email']).to eq(user.email)
    end

    it 'includes standard JWT claims' do
      token = AuthService.generate_jwt(user)
      auth_data = AuthService.validate_jwt(token)
      payload = auth_data[:payload]
      
      expect(payload['iss']).to eq('spotik-ruby')
      expect(payload['sub']).to eq(user.id.to_s)
      expect(payload['iat']).to be_a(Integer)
      expect(payload['exp']).to be_a(Integer)
      expect(payload['nbf']).to be_a(Integer)
      expect(payload['jti']).to be_a(String)
    end

    it 'sets correct expiration time' do
      token = AuthService.generate_jwt(user)
      auth_data = AuthService.validate_jwt(token)
      payload = auth_data[:payload]
      
      expected_exp = payload['iat'] + (SpotikConfig::Settings.jwt_ttl * 60)
      expect(payload['exp']).to eq(expected_exp)
    end
  end

  describe '.validate_jwt' do
    let(:user) do
      User.create(
        username: 'testuser',
        email: 'test@example.com',
        password_hash: BCrypt::Password.create('password123')
      )
    end

    it 'validates a valid token' do
      token = AuthService.generate_jwt(user)
      auth_data = AuthService.validate_jwt(token)
      
      expect(auth_data[:user]).to eq(user)
      expect(auth_data[:token]).to eq(token)
      expect(auth_data[:payload]).to be_a(Hash)
    end

    it 'handles Bearer prefix in token' do
      token = AuthService.generate_jwt(user)
      bearer_token = "Bearer #{token}"
      auth_data = AuthService.validate_jwt(bearer_token)
      
      expect(auth_data[:user]).to eq(user)
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

    it 'raises AuthenticationError for token with non-existent user' do
      # Create token for non-existent user
      payload = {
        iss: 'spotik-ruby',
        iat: Time.now.to_i,
        exp: Time.now.to_i + 3600,
        nbf: Time.now.to_i,
        sub: '99999', # Non-existent user ID
        jti: SecureRandom.hex(16),
        user_id: 99999,
        username: 'nonexistent',
        email: 'nonexistent@example.com'
      }
      
      invalid_token = JWT.encode(payload, SpotikConfig::Settings.jwt_secret, 'HS256')
      
      expect(AuthService.validate_jwt(invalid_token)).to be_nil
    end
  end

  describe '.register_user' do
    it 'creates a new user with valid data' do
      user_data = {
        username: 'newuser',
        email: 'new@example.com',
        password: 'password123',
        password_confirmation: 'password123'
      }
      
      user = AuthService.register_user(user_data)
      
      expect(user).to be_a(User)
      expect(user.username).to eq('newuser')
      expect(user.email).to eq('new@example.com')
      expect(user.authenticate('password123')).to be_truthy
    end

    it 'normalizes email to lowercase' do
      user_data = {
        username: 'newuser',
        email: 'NEW@EXAMPLE.COM',
        password: 'password123',
        password_confirmation: 'password123'
      }
      
      user = AuthService.register_user(user_data)
      expect(user.email).to eq('new@example.com')
    end

    it 'trims whitespace from username and email' do
      user_data = {
        username: '  newuser  ',
        email: '  new@example.com  ',
        password: 'password123',
        password_confirmation: 'password123'
      }
      
      user = AuthService.register_user(user_data)
      expect(user.username).to eq('newuser')
      expect(user.email).to eq('new@example.com')
    end

    it 'raises ValidationError for missing username' do
      user_data = {
        email: 'new@example.com',
        password: 'password123',
        password_confirmation: 'password123'
      }
      
      expect {
        AuthService.register_user(user_data)
      }.to raise_error(ValidationError) do |error|
        expect(error.errors[:username]).to include('The username field is required.')
      end
    end

    it 'raises ValidationError for missing email' do
      user_data = {
        username: 'newuser',
        password: 'password123',
        password_confirmation: 'password123'
      }
      
      expect {
        AuthService.register_user(user_data)
      }.to raise_error(ValidationError) do |error|
        expect(error.errors[:email]).to include('The email field is required.')
      end
    end

    it 'raises ValidationError for missing password' do
      user_data = {
        username: 'newuser',
        email: 'new@example.com',
        password_confirmation: 'password123'
      }
      
      expect {
        AuthService.register_user(user_data)
      }.to raise_error(ValidationError) do |error|
        expect(error.errors[:password]).to include('The password field is required.')
      end
    end

    it 'raises ValidationError for short password' do
      user_data = {
        username: 'newuser',
        email: 'new@example.com',
        password: '123',
        password_confirmation: '123'
      }
      
      expect {
        AuthService.register_user(user_data)
      }.to raise_error(ValidationError) do |error|
        expect(error.errors[:password]).to include('The password must be at least 8 characters.')
      end
    end

    it 'raises ValidationError for password confirmation mismatch' do
      user_data = {
        username: 'newuser',
        email: 'new@example.com',
        password: 'password123',
        password_confirmation: 'different123'
      }
      
      expect {
        AuthService.register_user(user_data)
      }.to raise_error(ValidationError) do |error|
        expect(error.errors[:password]).to include('The password confirmation does not match.')
      end
    end

    it 'raises ValidationError for invalid email format' do
      user_data = {
        username: 'newuser',
        email: 'invalid-email',
        password: 'password123',
        password_confirmation: 'password123'
      }
      
      expect {
        AuthService.register_user(user_data)
      }.to raise_error(ValidationError) do |error|
        expect(error.errors[:email]).to include('The email must be a valid email address.')
      end
    end

    it 'raises ValidationError for duplicate email' do
      # Create first user
      User.create(
        username: 'firstuser',
        email: 'test@example.com',
        password_hash: BCrypt::Password.create('password123')
      )
      
      user_data = {
        username: 'seconduser',
        email: 'test@example.com',
        password: 'password123',
        password_confirmation: 'password123'
      }
      
      expect {
        AuthService.register_user(user_data)
      }.to raise_error(ValidationError) do |error|
        expect(error.errors[:email]).to include('The email has already been taken.')
      end
    end

    it 'raises ValidationError for duplicate username' do
      # Create first user
      User.create(
        username: 'testuser',
        email: 'first@example.com',
        password_hash: BCrypt::Password.create('password123')
      )
      
      user_data = {
        username: 'testuser',
        email: 'second@example.com',
        password: 'password123',
        password_confirmation: 'password123'
      }
      
      expect {
        AuthService.register_user(user_data)
      }.to raise_error(ValidationError) do |error|
        expect(error.errors[:username]).to include('The username has already been taken.')
      end
    end
  end

  describe '.current_user_from_token' do
    let(:user) do
      User.create(
        username: 'testuser',
        email: 'test@example.com',
        password_hash: BCrypt::Password.create('password123')
      )
    end

    it 'returns user for valid token' do
      token = AuthService.generate_jwt(user)
      result = AuthService.current_user_from_token(token)
      expect(result).to eq(user)
    end

    it 'raises AuthenticationError for invalid token' do
      expect {
        AuthService.current_user_from_token('invalid.token')
      }.to raise_error(AuthenticationError)
    end
  end

  describe '.refresh_jwt' do
    let(:user) do
      User.create(
        username: 'testuser',
        email: 'test@example.com',
        password_hash: BCrypt::Password.create('password123')
      )
    end

    it 'refreshes a valid token' do
      original_token = AuthService.generate_jwt(user)
      new_token = AuthService.refresh_jwt(original_token)
      
      expect(new_token).to be_a(String)
      expect(new_token).not_to eq(original_token)
      
      # Verify new token is valid
      auth_data = AuthService.validate_jwt(new_token)
      expect(auth_data[:user]).to eq(user)
    end

    it 'raises AuthenticationError for invalid token' do
      expect {
        AuthService.refresh_jwt('invalid.token')
      }.to raise_error(AuthenticationError)
    end
  end
end