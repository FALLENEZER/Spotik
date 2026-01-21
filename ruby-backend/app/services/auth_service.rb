# Authentication service - Compatible with Laravel JWT authentication
require 'jwt'
require 'bcrypt'
require 'json'

class AuthService
  # JWT configuration (compatible with Laravel JWT)
  JWT_ALGORITHM = 'HS256'
  JWT_ISSUER = 'spotik-ruby'
  
  class << self
    # Authenticate user with email and password (Laravel compatibility)
    def authenticate(email, password)
      return nil if email.nil? || password.nil?
      
      user = User.where(email: email.strip.downcase).first
      return nil unless user
      
      # Verify password using bcrypt (Laravel compatibility)
      return nil unless user.authenticate(password)
      
      user
    end
    
    # Generate JWT token for user (Laravel JWT compatibility)
    def generate_jwt(user)
      now = Time.now.to_i
      
      payload = {
        # Standard JWT claims (Laravel JWT compatibility)
        iss: JWT_ISSUER,                    # Issuer
        iat: now,                           # Issued at
        exp: now + (SpotikConfig::Settings.jwt_ttl * 60), # Expiration (convert minutes to seconds)
        nbf: now,                           # Not before
        sub: user.id.to_s,                  # Subject (user ID)
        jti: generate_jti,                  # JWT ID
        
        # Custom claims
        user_id: user.id,
        username: user.username,
        email: user.email
      }
      
      JWT.encode(payload, SpotikConfig::Settings.jwt_secret, JWT_ALGORITHM)
    end
    
    # Validate and decode JWT token
    def validate_jwt(token)
      # Laravel compatibility: return nil for nil/empty tokens instead of raising exception
      if token.nil? || token.empty? || token.strip.empty?
        return nil
      end
      
      # Remove 'Bearer ' prefix if present and strip whitespace
      token = token.gsub(/^Bearer\s+/i, '').strip if token.match?(/^Bearer\s+/i)
      token = token.strip
      
      if token.empty?
        return nil
      end
      
      begin
        decoded = JWT.decode(
          token, 
          SpotikConfig::Settings.jwt_secret, 
          true, 
          { 
            algorithm: JWT_ALGORITHM,
            verify_iss: true,
            iss: JWT_ISSUER,
            verify_iat: true,
            verify_exp: true,
            verify_nbf: true
          }
        )
        
        payload = decoded[0]
        user_id = payload['sub'] || payload['user_id']
        
        # Find user by ID (UUID string)
        user = User[user_id]
        return nil unless user
        
        {
          user: user,
          payload: payload,
          token: token
        }
        
      rescue JWT::ExpiredSignature
        raise AuthenticationError.new('Token has expired', :token_expired)
      rescue JWT::InvalidIssuerError
        raise AuthenticationError.new('Token issuer is invalid', :token_invalid)
      rescue JWT::InvalidIatError
        raise AuthenticationError.new('Token issued at is invalid', :token_invalid)
      rescue JWT::ImmatureSignature
        raise AuthenticationError.new('Token is not yet valid', :token_invalid)
      rescue JWT::InvalidSubError
        raise AuthenticationError.new('Token subject is invalid', :token_invalid)
      rescue JWT::InvalidJtiError
        raise AuthenticationError.new('Token ID is invalid', :token_invalid)
      rescue JWT::DecodeError => e
        raise AuthenticationError.new('Token is invalid', :token_invalid)
      rescue => e
        raise AuthenticationError.new('Token validation failed', :token_error)
      end
    end
    
    # Register new user (Laravel compatibility)
    def register_user(user_data)
      # Validate required fields
      validate_registration_data(user_data)
      
      # Check for existing users
      if User.where(email: user_data[:email].strip.downcase).first
        raise ValidationError.new('Email already exists', { email: ['The email has already been taken.'] })
      end
      
      if User.where(username: user_data[:username].strip).first
        raise ValidationError.new('Username already exists', { username: ['The username has already been taken.'] })
      end
      
      # Create user with bcrypt password hash (Laravel compatibility)
      user = User.create(
        username: user_data[:username].strip,
        email: user_data[:email].strip.downcase,
        password_hash: BCrypt::Password.create(user_data[:password])
      )
      
      user
    rescue Sequel::ValidationFailed => e
      raise ValidationError.new('Validation failed', format_sequel_errors(e))
    rescue Sequel::UniqueConstraintViolation => e
      if e.message.include?('email')
        raise ValidationError.new('Email already exists', { email: ['The email has already been taken.'] })
      elsif e.message.include?('username')
        raise ValidationError.new('Username already exists', { username: ['The username has already been taken.'] })
      else
        raise ValidationError.new('Duplicate entry', { base: ['A user with these details already exists.'] })
      end
    rescue NameError => e
      # Handle case where Sequel is not available (in tests)
      if e.message.include?('Sequel')
        # In test environment, we handle duplicates differently
        raise ValidationError.new('Validation failed', { base: ['Test environment error'] })
      else
        raise e
      end
    end
    
    # Get current user from token
    def current_user_from_token(token)
      auth_data = validate_jwt(token)
      auth_data[:user]
    end
    
    # Refresh JWT token (Laravel JWT compatibility)
    def refresh_jwt(token)
      return nil if token.nil? || token.empty? || token.strip.empty?
      
      auth_data = validate_jwt(token)
      return nil unless auth_data
      
      generate_jwt(auth_data[:user])
    rescue AuthenticationError => e
      # If token is expired, we can still refresh it within grace period
      if e.code == :token_expired
        begin
          # Decode without verification to check if it's within refresh window
          decoded = JWT.decode(token, nil, false)
          payload = decoded[0]
          
          exp_time = Time.at(payload['exp'])
          refresh_window = SpotikConfig::Settings.jwt_ttl * 60 * 2 # 2x TTL for refresh
          
          if Time.now - exp_time <= refresh_window
            user = User[payload['sub']]
            return generate_jwt(user) if user
          end
        rescue
          # If we can't decode at all, re-raise original error
        end
      end
      
      raise e
    end
    
    private
    
    # Generate unique JWT ID
    def generate_jti
      SecureRandom.hex(16)
    end
    
    # Validate registration data (Laravel validation compatibility)
    def validate_registration_data(data)
      errors = {}
      
      # Username validation
      if data[:username].nil? || data[:username].strip.empty?
        errors[:username] = ['The username field is required.']
      elsif data[:username].length > 50
        errors[:username] = ['The username may not be greater than 50 characters.']
      end
      
      # Email validation
      if data[:email].nil? || data[:email].strip.empty?
        errors[:email] = ['The email field is required.']
      elsif data[:email].length > 255
        errors[:email] = ['The email may not be greater than 255 characters.']
      elsif !valid_email?(data[:email])
        errors[:email] = ['The email must be a valid email address.']
      end
      
      # Password validation
      if data[:password].nil? || data[:password].empty?
        errors[:password] = ['The password field is required.']
      elsif data[:password].length < 8
        errors[:password] = ['The password must be at least 8 characters.']
      elsif data[:password] != data[:password_confirmation]
        errors[:password] = ['The password confirmation does not match.']
      end
      
      if errors.any?
        raise ValidationError.new('Validation failed', errors)
      end
    end
    
    # Email validation helper
    def valid_email?(email)
      email.match?(/\A[^@\s]+@[^@\s]+\z/)
    end
    
    # Format Sequel validation errors to Laravel format
    def format_sequel_errors(sequel_error)
      errors = {}
      sequel_error.errors.each do |field, messages|
        errors[field] = Array(messages)
      end
      errors
    end
  end
end

# Custom exception classes for authentication
class AuthenticationError < StandardError
  attr_reader :code, :details
  
  def initialize(message, code = :authentication_failed, details = nil)
    super(message)
    @code = code
    @details = details
  end
end

class ValidationError < StandardError
  attr_reader :errors
  
  def initialize(message, errors = {})
    super(message)
    @errors = errors
  end
end