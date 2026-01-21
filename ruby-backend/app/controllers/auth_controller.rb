# Authentication controller - Laravel API compatibility
require 'json'
require_relative '../services/auth_service'

class AuthController
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
        user = AuthService.register_user(user_data)
        
        # Generate JWT token
        token = AuthService.generate_jwt(user)
        
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
        user = AuthService.authenticate(params['email'], params['password'])
        
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
        token = AuthService.generate_jwt(user)
        
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
        auth_data = AuthService.validate_jwt(token)
        
        unless auth_data
          return {
            status: 401,
            body: {
              success: false,
              message: 'Token not provided or invalid',
              error: 'Token absent or invalid'
            }
          }
        end
        
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
        when :token_absent
          {
            status: 401,
            body: {
              success: false,
              message: 'Token not provided',
              error: 'Token absent'
            }
          }
        else
          {
            status: 401,
            body: {
              success: false,
              message: 'Authentication failed',
              error: e.message
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
        new_token = AuthService.refresh_jwt(token)
        
        unless new_token
          return {
            status: 401,
            body: {
              success: false,
              message: 'Token not provided or invalid',
              error: 'Token absent or invalid'
            }
          }
        end
        
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