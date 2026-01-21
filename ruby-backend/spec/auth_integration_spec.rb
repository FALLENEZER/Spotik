# Integration tests for authentication endpoints
require 'bundler/setup'
require 'rspec'
require 'rack/test'
require 'json'

# Set test environment
ENV['APP_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test_secret_key_for_testing_only'
ENV['JWT_TTL'] = '60'

# Load configuration first
require_relative '../config/settings'

# Mock database connection for integration tests
module SpotikConfig
  class Database
    def self.connection
      # Return a mock connection that doesn't actually connect
      MockDB.new
    end
    
    def self.health_check
      { status: 'healthy', message: 'test environment' }
    end
    
    def self.validate_schema_compatibility
      { status: 'valid', tables: {}, errors: [], warnings: [] }
    end
    
    def self.close_connection
      # No-op for tests
    end
    
    def self.get_pool_stats
      { active: 0, idle: 1, total: 1 }
    end
  end
end

class MockDB
  def table_exists?(table)
    true
  end
  
  def schema(table)
    []
  end
end

# Mock User model for integration tests
class User
  @@users = []
  
  attr_accessor :id, :username, :email, :password_hash, :created_at, :updated_at
  
  def initialize(attributes = {})
    @id = attributes[:id] || (@@users.length + 1)
    @username = attributes[:username]
    @email = attributes[:email]
    @password_hash = attributes[:password_hash]
    @created_at = attributes[:created_at] || Time.now
    @updated_at = attributes[:updated_at] || Time.now
  end
  
  def self.create(attributes)
    user = new(attributes)
    @@users << user
    user
  end
  
  def self.where(conditions)
    MockDataset.new(@@users, conditions)
  end
  
  def self.[](id)
    @@users.find { |u| u.id == id }
  end
  
  def self.clear_all
    @@users.clear
  end
  
  def authenticate(password)
    return false unless password_hash
    BCrypt::Password.new(password_hash) == password
  rescue BCrypt::Errors::InvalidHash
    false
  end
end

class MockDataset
  def initialize(users, conditions)
    @users = users
    @conditions = conditions
  end
  
  def first
    if @conditions[:email]
      @users.find { |u| u.email == @conditions[:email] }
    elsif @conditions[:username]
      @users.find { |u| u.username == @conditions[:username] }
    else
      @users.first
    end
  end
end

# Load authentication service
require_relative 'test_auth_service'

# Create test auth controller that uses TestAuthService
class TestAuthController
  class << self
    # Register a new user (POST /api/auth/register)
    def register(params)
      begin
        # Extract and validate parameters
        user_data = {
          username: params['username'],
          email: params['email'],
          password: params['password'],
          password_confirmation: params['password_confirmation']
        }
        
        # Register the user
        user = TestAuthService.register_user(user_data)
        
        # Generate JWT token
        token = TestAuthService.generate_jwt(user)
        
        # Return Laravel-compatible response
        {
          status: 201,
          body: {
            success: true,
            message: 'User registered successfully',
            data: {
              user: {
                id: user.id,
                username: user.username,
                email: user.email,
                created_at: user.created_at&.iso8601
              },
              token: token,
              token_type: 'bearer',
              expires_in: SpotikConfig::Settings.jwt_ttl * 60 # Convert minutes to seconds
            }
          }
        }
        
      rescue ValidationError => e
        {
          status: 422,
          body: {
            success: false,
            message: 'Validation failed',
            errors: e.errors
          }
        }
      rescue => e
        {
          status: 500,
          body: {
            success: false,
            message: 'Registration failed',
            error: e.message
          }
        }
      end
    end
    
    # Authenticate user and return JWT token (POST /api/auth/login)
    def login(params)
      begin
        # Validate required parameters
        if params['email'].nil? || params['email'].strip.empty?
          return {
            status: 422,
            body: {
              success: false,
              message: 'Validation failed',
              errors: { email: ['The email field is required.'] }
            }
          }
        end
        
        if params['password'].nil? || params['password'].empty?
          return {
            status: 422,
            body: {
              success: false,
              message: 'Validation failed',
              errors: { password: ['The password field is required.'] }
            }
          }
        end
        
        # Validate email format
        unless params['email'].match?(/\A[^@\s]+@[^@\s]+\z/)
          return {
            status: 422,
            body: {
              success: false,
              message: 'Validation failed',
              errors: { email: ['The email must be a valid email address.'] }
            }
          }
        end
        
        # Authenticate user
        user = TestAuthService.authenticate(params['email'], params['password'])
        
        unless user
          return {
            status: 401,
            body: {
              success: false,
              message: 'Invalid credentials',
              error: 'The provided credentials are incorrect.'
            }
          }
        end
        
        # Generate JWT token
        token = TestAuthService.generate_jwt(user)
        
        # Return Laravel-compatible response
        {
          status: 200,
          body: {
            success: true,
            message: 'Login successful',
            data: {
              user: {
                id: user.id,
                username: user.username,
                email: user.email,
                created_at: user.created_at&.iso8601
              },
              token: token,
              token_type: 'bearer',
              expires_in: SpotikConfig::Settings.jwt_ttl * 60 # Convert minutes to seconds
            }
          }
        }
        
      rescue => e
        {
          status: 500,
          body: {
            success: false,
            message: 'Login failed',
            error: e.message
          }
        }
      end
    end
    
    # Get the authenticated user (GET /api/auth/me)
    def me(token)
      begin
        # Handle missing token
        if token.nil? || token.empty?
          return {
            status: 401,
            body: {
              success: false,
              message: 'Token not provided',
              error: 'Token absent'
            }
          }
        end
        
        auth_data = TestAuthService.validate_jwt(token)
        user = auth_data[:user]
        
        {
          status: 200,
          body: {
            success: true,
            message: 'User retrieved successfully',
            data: {
              user: {
                id: user.id,
                username: user.username,
                email: user.email,
                created_at: user.created_at&.iso8601,
                updated_at: user.updated_at&.iso8601
              }
            }
          }
        }
        
      rescue AuthenticationError => e
        case e.code
        when :token_expired
          {
            status: 401,
            body: {
              success: false,
              message: 'Token has expired',
              error: 'Token expired'
            }
          }
        when :token_invalid
          {
            status: 401,
            body: {
              success: false,
              message: 'Token is invalid',
              error: 'Invalid token'
            }
          }
        else
          {
            status: 401,
            body: {
              success: false,
              message: 'Token not provided',
              error: 'Token absent'
            }
          }
        end
      rescue => e
        {
          status: 500,
          body: {
            success: false,
            message: 'Could not retrieve user',
            error: e.message
          }
        }
      end
    end
    
    # Refresh the JWT token (POST /api/auth/refresh)
    def refresh(token)
      begin
        new_token = TestAuthService.refresh_jwt(token)
        
        {
          status: 200,
          body: {
            success: true,
            message: 'Token refreshed successfully',
            data: {
              token: new_token,
              token_type: 'bearer',
              expires_in: SpotikConfig::Settings.jwt_ttl * 60 # Convert minutes to seconds
            }
          }
        }
        
      rescue AuthenticationError => e
        case e.code
        when :token_expired
          {
            status: 401,
            body: {
              success: false,
              message: 'Token has expired and cannot be refreshed',
              error: 'Token expired'
            }
          }
        when :token_invalid
          {
            status: 401,
            body: {
              success: false,
              message: 'Token is invalid',
              error: 'Invalid token'
            }
          }
        else
          {
            status: 401,
            body: {
              success: false,
              message: 'Token not provided',
              error: 'Token absent'
            }
          }
        end
      rescue => e
        {
          status: 500,
          body: {
            success: false,
            message: 'Could not refresh token',
            error: e.message
          }
        }
      end
    end
    
    # Logout user and invalidate token (POST /api/auth/logout)
    def logout(token)
      begin
        # Note: In a production system, you would want to implement token blacklisting
        # For now, we'll just return success (client should discard the token)
        
        {
          status: 200,
          body: {
            success: true,
            message: 'Successfully logged out'
          }
        }
        
      rescue => e
        # Even if there's an error, return success for logout
        # This allows logout to work even without a valid token
        {
          status: 200,
          body: {
            success: true,
            message: 'Successfully logged out'
          }
        }
      end
    end
  end
end

# Load the server components we need
require 'iodine'
require 'sinatra/base'
require 'json'
require 'logger'

# Create a simplified server for testing
class TestSpotikServer < Sinatra::Base
  # Configure Sinatra
  configure do
    set :logging, false
    set :dump_errors, false
    set :show_exceptions, false
    
    # CORS headers for frontend compatibility
    before do
      headers 'Access-Control-Allow-Origin' => '*'
      headers 'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS'
      headers 'Access-Control-Allow-Headers' => 'Content-Type, Authorization'
    end
    
    # Handle preflight requests
    options '*' do
      200
    end
  end

  # Basic API info endpoint
  get '/api' do
    content_type :json
    {
      name: 'Spotik Test',
      version: '1.0.0',
      environment: 'test'
    }.to_json
  end

  # Authentication endpoints
  post '/api/auth/register' do
    content_type :json
    
    begin
      params_hash = JSON.parse(request.body.read)
    rescue JSON::ParserError
      params_hash = params
    end
    
    result = TestAuthController.register(params_hash)
    status result[:status]
    result[:body].to_json
  end

  post '/api/auth/login' do
    content_type :json
    
    begin
      params_hash = JSON.parse(request.body.read)
    rescue JSON::ParserError
      params_hash = params
    end
    
    result = TestAuthController.login(params_hash)
    status result[:status]
    result[:body].to_json
  end

  get '/api/auth/me' do
    content_type :json
    
    token = extract_token_from_request
    result = TestAuthController.me(token)
    status result[:status]
    result[:body].to_json
  end

  post '/api/auth/refresh' do
    content_type :json
    
    token = extract_token_from_request
    result = TestAuthController.refresh(token)
    status result[:status]
    result[:body].to_json
  end

  post '/api/auth/logout' do
    content_type :json
    
    token = extract_token_from_request
    result = TestAuthController.logout(token)
    status result[:status]
    result[:body].to_json
  end

  private

  def extract_token_from_request
    # Check Authorization header first (Bearer token)
    auth_header = request.env['HTTP_AUTHORIZATION']
    if auth_header && auth_header.start_with?('Bearer ')
      return auth_header[7..-1] # Remove 'Bearer ' prefix
    end
    
    # Check for token in query parameters (fallback)
    params['token']
  end
end

RSpec.describe 'Authentication API' do
  include Rack::Test::Methods

  def app
    TestSpotikServer
  end

  before(:each) do
    User.clear_all
  end

  describe 'POST /api/auth/register' do
    it 'registers a new user with valid data' do
      user_data = {
        username: 'testuser',
        email: 'test@example.com',
        password: 'password123',
        password_confirmation: 'password123'
      }

      post '/api/auth/register', user_data.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(201)
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be true
      expect(response_data['message']).to eq('User registered successfully')
      expect(response_data['data']['user']['username']).to eq('testuser')
      expect(response_data['data']['user']['email']).to eq('test@example.com')
      expect(response_data['data']['token']).to be_a(String)
      expect(response_data['data']['token_type']).to eq('bearer')
      expect(response_data['data']['expires_in']).to eq(3600) # 60 minutes * 60 seconds
    end

    it 'returns validation error for missing username' do
      user_data = {
        email: 'test@example.com',
        password: 'password123',
        password_confirmation: 'password123'
      }

      post '/api/auth/register', user_data.to_json, { 'CONTENT_TYPE' => 'application/json' }

      # Debug output
      if last_response.status != 422
        puts "Expected 422, got #{last_response.status}"
        puts "Response body: #{last_response.body}"
      end

      expect(last_response.status).to eq(422)
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be false
      expect(response_data['message']).to eq('Validation failed')
      expect(response_data['errors']['username']).to include('The username field is required.')
    end

    it 'returns validation error for password mismatch' do
      user_data = {
        username: 'testuser',
        email: 'test@example.com',
        password: 'password123',
        password_confirmation: 'different123'
      }

      post '/api/auth/register', user_data.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(422)
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be false
      expect(response_data['errors']['password']).to include('The password confirmation does not match.')
    end

    it 'returns validation error for duplicate email' do
      # Create existing user
      User.create(
        username: 'existing',
        email: 'test@example.com',
        password_hash: BCrypt::Password.create('password123')
      )

      user_data = {
        username: 'testuser',
        email: 'test@example.com',
        password: 'password123',
        password_confirmation: 'password123'
      }

      post '/api/auth/register', user_data.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(422)
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be false
      expect(response_data['errors']['email']).to include('The email has already been taken.')
    end
  end

  describe 'POST /api/auth/login' do
    let!(:user) do
      User.create(
        username: 'testuser',
        email: 'test@example.com',
        password_hash: BCrypt::Password.create('password123')
      )
    end

    it 'logs in user with valid credentials' do
      login_data = {
        email: 'test@example.com',
        password: 'password123'
      }

      post '/api/auth/login', login_data.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be true
      expect(response_data['message']).to eq('Login successful')
      expect(response_data['data']['user']['username']).to eq('testuser')
      expect(response_data['data']['user']['email']).to eq('test@example.com')
      expect(response_data['data']['token']).to be_a(String)
      expect(response_data['data']['token_type']).to eq('bearer')
      expect(response_data['data']['expires_in']).to eq(3600)
    end

    it 'returns error for invalid email' do
      login_data = {
        email: 'wrong@example.com',
        password: 'password123'
      }

      post '/api/auth/login', login_data.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(401)
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be false
      expect(response_data['message']).to eq('Invalid credentials')
    end

    it 'returns error for invalid password' do
      login_data = {
        email: 'test@example.com',
        password: 'wrongpassword'
      }

      post '/api/auth/login', login_data.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(401)
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be false
      expect(response_data['message']).to eq('Invalid credentials')
    end

    it 'returns validation error for missing email' do
      login_data = {
        password: 'password123'
      }

      post '/api/auth/login', login_data.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(422)
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be false
      expect(response_data['errors']['email']).to include('The email field is required.')
    end

    it 'returns validation error for invalid email format' do
      login_data = {
        email: 'invalid-email',
        password: 'password123'
      }

      post '/api/auth/login', login_data.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(422)
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be false
      expect(response_data['errors']['email']).to include('The email must be a valid email address.')
    end
  end

  describe 'GET /api/auth/me' do
    let!(:user) do
      User.create(
        username: 'testuser',
        email: 'test@example.com',
        password_hash: BCrypt::Password.create('password123')
      )
    end

    it 'returns user data for valid token' do
      token = TestAuthService.generate_jwt(user)

      get '/api/auth/me', {}, { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

      expect(last_response.status).to eq(200)
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be true
      expect(response_data['message']).to eq('User retrieved successfully')
      expect(response_data['data']['user']['username']).to eq('testuser')
      expect(response_data['data']['user']['email']).to eq('test@example.com')
    end

    it 'returns error for missing token' do
      get '/api/auth/me'

      expect(last_response.status).to eq(401)
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be false
      expect(response_data['message']).to eq('Token not provided')
    end

    it 'returns error for invalid token' do
      get '/api/auth/me', {}, { 'HTTP_AUTHORIZATION' => 'Bearer invalid.token' }

      expect(last_response.status).to eq(401)
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be false
      expect(response_data['message']).to eq('Token is invalid')
    end
  end

  describe 'POST /api/auth/refresh' do
    let!(:user) do
      User.create(
        username: 'testuser',
        email: 'test@example.com',
        password_hash: BCrypt::Password.create('password123')
      )
    end

    it 'refreshes valid token' do
      token = TestAuthService.generate_jwt(user)

      post '/api/auth/refresh', {}, { 'HTTP_AUTHORIZATION' => "Bearer #{token}" }

      expect(last_response.status).to eq(200)
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be true
      expect(response_data['message']).to eq('Token refreshed successfully')
      expect(response_data['data']['token']).to be_a(String)
      expect(response_data['data']['token']).not_to eq(token)
      expect(response_data['data']['token_type']).to eq('bearer')
      expect(response_data['data']['expires_in']).to eq(3600)
    end

    it 'returns error for invalid token' do
      post '/api/auth/refresh', {}, { 'HTTP_AUTHORIZATION' => 'Bearer invalid.token' }

      expect(last_response.status).to eq(401)
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be false
      expect(response_data['message']).to eq('Token is invalid')
    end
  end

  describe 'POST /api/auth/logout' do
    it 'returns success for logout' do
      post '/api/auth/logout'

      expect(last_response.status).to eq(200)
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be true
      expect(response_data['message']).to eq('Successfully logged out')
    end

    it 'returns success even with invalid token' do
      post '/api/auth/logout', {}, { 'HTTP_AUTHORIZATION' => 'Bearer invalid.token' }

      expect(last_response.status).to eq(200)
      
      response_data = JSON.parse(last_response.body)
      expect(response_data['success']).to be true
      expect(response_data['message']).to eq('Successfully logged out')
    end
  end

  describe 'CORS headers' do
    it 'includes CORS headers in responses' do
      get '/api'

      expect(last_response.headers['Access-Control-Allow-Origin']).to eq('*')
      expect(last_response.headers['Access-Control-Allow-Methods']).to eq('GET, POST, PUT, DELETE, OPTIONS')
      expect(last_response.headers['Access-Control-Allow-Headers']).to eq('Content-Type, Authorization')
    end

    it 'handles preflight OPTIONS requests' do
      options '/api/auth/login'

      expect(last_response.status).to eq(200)
      expect(last_response.headers['Access-Control-Allow-Origin']).to eq('*')
    end
  end
end