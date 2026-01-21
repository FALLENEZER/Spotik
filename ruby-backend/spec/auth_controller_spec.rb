# Authentication controller tests
require_relative 'spec_helper'
require_relative '../app/controllers/auth_controller'

RSpec.describe AuthController do
  before(:each) do
    # Clean up users before each test
    User.dataset.delete
  end

  describe '.register' do
    it 'registers a new user with valid data' do
      params = {
        'username' => 'testuser',
        'email' => 'test@example.com',
        'password' => 'password123',
        'password_confirmation' => 'password123'
      }
      
      result = AuthController.register(params)
      
      expect(result[:status]).to eq(201)
      expect(result[:body][:success]).to be true
      expect(result[:body][:message]).to eq('User registered successfully')
      expect(result[:body][:data][:user][:username]).to eq('testuser')
      expect(result[:body][:data][:user][:email]).to eq('test@example.com')
      expect(result[:body][:data][:token]).to be_a(String)
      expect(result[:body][:data][:token_type]).to eq('bearer')
      expect(result[:body][:data][:expires_in]).to eq(SpotikConfig::Settings.jwt_ttl * 60)
    end

    it 'returns validation error for missing username' do
      params = {
        'email' => 'test@example.com',
        'password' => 'password123',
        'password_confirmation' => 'password123'
      }
      
      result = AuthController.register(params)
      
      expect(result[:status]).to eq(422)
      expect(result[:body][:success]).to be false
      expect(result[:body][:message]).to eq('Validation failed')
      expect(result[:body][:errors][:username]).to include('The username field is required.')
    end

    it 'returns validation error for password mismatch' do
      params = {
        'username' => 'testuser',
        'email' => 'test@example.com',
        'password' => 'password123',
        'password_confirmation' => 'different123'
      }
      
      result = AuthController.register(params)
      
      expect(result[:status]).to eq(422)
      expect(result[:body][:success]).to be false
      expect(result[:body][:errors][:password]).to include('The password confirmation does not match.')
    end

    it 'returns validation error for duplicate email' do
      # Create existing user
      User.create(
        username: 'existing',
        email: 'test@example.com',
        password_hash: BCrypt::Password.create('password123')
      )
      
      params = {
        'username' => 'testuser',
        'email' => 'test@example.com',
        'password' => 'password123',
        'password_confirmation' => 'password123'
      }
      
      result = AuthController.register(params)
      
      expect(result[:status]).to eq(422)
      expect(result[:body][:success]).to be false
      expect(result[:body][:errors][:email]).to include('The email has already been taken.')
    end
  end

  describe '.login' do
    let(:user) do
      User.create(
        username: 'testuser',
        email: 'test@example.com',
        password_hash: BCrypt::Password.create('password123')
      )
    end

    it 'logs in user with valid credentials' do
      user # Create user
      
      params = {
        'email' => 'test@example.com',
        'password' => 'password123'
      }
      
      result = AuthController.login(params)
      
      expect(result[:status]).to eq(200)
      expect(result[:body][:success]).to be true
      expect(result[:body][:message]).to eq('Login successful')
      expect(result[:body][:data][:user][:id]).to eq(user.id)
      expect(result[:body][:data][:user][:username]).to eq('testuser')
      expect(result[:body][:data][:user][:email]).to eq('test@example.com')
      expect(result[:body][:data][:token]).to be_a(String)
      expect(result[:body][:data][:token_type]).to eq('bearer')
      expect(result[:body][:data][:expires_in]).to eq(SpotikConfig::Settings.jwt_ttl * 60)
    end

    it 'returns error for invalid email' do
      params = {
        'email' => 'wrong@example.com',
        'password' => 'password123'
      }
      
      result = AuthController.login(params)
      
      expect(result[:status]).to eq(401)
      expect(result[:body][:success]).to be false
      expect(result[:body][:message]).to eq('Invalid credentials')
    end

    it 'returns error for invalid password' do
      user # Create user
      
      params = {
        'email' => 'test@example.com',
        'password' => 'wrongpassword'
      }
      
      result = AuthController.login(params)
      
      expect(result[:status]).to eq(401)
      expect(result[:body][:success]).to be false
      expect(result[:body][:message]).to eq('Invalid credentials')
    end

    it 'returns validation error for missing email' do
      params = {
        'password' => 'password123'
      }
      
      result = AuthController.login(params)
      
      expect(result[:status]).to eq(422)
      expect(result[:body][:success]).to be false
      expect(result[:body][:message]).to eq('Validation failed')
      expect(result[:body][:errors][:email]).to include('The email field is required.')
    end

    it 'returns validation error for missing password' do
      params = {
        'email' => 'test@example.com'
      }
      
      result = AuthController.login(params)
      
      expect(result[:status]).to eq(422)
      expect(result[:body][:success]).to be false
      expect(result[:body][:message]).to eq('Validation failed')
      expect(result[:body][:errors][:password]).to include('The password field is required.')
    end

    it 'returns validation error for invalid email format' do
      params = {
        'email' => 'invalid-email',
        'password' => 'password123'
      }
      
      result = AuthController.login(params)
      
      expect(result[:status]).to eq(422)
      expect(result[:body][:success]).to be false
      expect(result[:body][:errors][:email]).to include('The email must be a valid email address.')
    end
  end

  describe '.me' do
    let(:user) do
      User.create(
        username: 'testuser',
        email: 'test@example.com',
        password_hash: BCrypt::Password.create('password123')
      )
    end

    it 'returns user data for valid token' do
      token = AuthService.generate_jwt(user)
      result = AuthController.me(token)
      
      expect(result[:status]).to eq(200)
      expect(result[:body][:success]).to be true
      expect(result[:body][:message]).to eq('User retrieved successfully')
      expect(result[:body][:data][:user][:id]).to eq(user.id)
      expect(result[:body][:data][:user][:username]).to eq('testuser')
      expect(result[:body][:data][:user][:email]).to eq('test@example.com')
    end

    it 'returns error for invalid token' do
      result = AuthController.me('invalid.token')
      
      expect(result[:status]).to eq(401)
      expect(result[:body][:success]).to be false
      expect(result[:body][:message]).to eq('Token is invalid')
    end

    it 'returns error for expired token' do
      # Create an expired token
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
      result = AuthController.me(expired_token)
      
      expect(result[:status]).to eq(401)
      expect(result[:body][:success]).to be false
      expect(result[:body][:message]).to eq('Token has expired')
    end
  end

  describe '.refresh' do
    let(:user) do
      User.create(
        username: 'testuser',
        email: 'test@example.com',
        password_hash: BCrypt::Password.create('password123')
      )
    end

    it 'refreshes valid token' do
      token = AuthService.generate_jwt(user)
      result = AuthController.refresh(token)
      
      expect(result[:status]).to eq(200)
      expect(result[:body][:success]).to be true
      expect(result[:body][:message]).to eq('Token refreshed successfully')
      expect(result[:body][:data][:token]).to be_a(String)
      expect(result[:body][:data][:token]).not_to eq(token)
      expect(result[:body][:data][:token_type]).to eq('bearer')
      expect(result[:body][:data][:expires_in]).to eq(SpotikConfig::Settings.jwt_ttl * 60)
    end

    it 'returns error for invalid token' do
      result = AuthController.refresh('invalid.token')
      
      expect(result[:status]).to eq(401)
      expect(result[:body][:success]).to be false
      expect(result[:body][:message]).to eq('Token is invalid')
    end
  end

  describe '.logout' do
    it 'returns success for logout' do
      result = AuthController.logout('any.token')
      
      expect(result[:status]).to eq(200)
      expect(result[:body][:success]).to be true
      expect(result[:body][:message]).to eq('Successfully logged out')
    end

    it 'returns success even without token' do
      result = AuthController.logout(nil)
      
      expect(result[:status]).to eq(200)
      expect(result[:body][:success]).to be true
      expect(result[:body][:message]).to eq('Successfully logged out')
    end
  end
end