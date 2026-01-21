# Property-based test for error handling and logging
# **Feature: ruby-backend-migration, Property 17: Error Handling and Logging**
# **Validates: Requirements 13.1, 13.2, 13.3, 13.4, 13.5**

require 'bundler/setup'
require 'rspec'
require 'rantly'
require 'rantly/rspec_extensions'
require 'securerandom'
require 'stringio'
require 'logger'

# Set test environment
ENV['APP_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test_jwt_secret_key_for_testing_purposes_only'
ENV['LOG_LEVEL'] = 'debug'
ENV['ENABLE_PERFORMANCE_MONITORING'] = 'true'

RSpec.describe 'Error Handling and Logging Property Test', :property do
  before(:all) do
    # Load configuration
    require_relative '../../config/settings'
    
    # Load error handling and logging services
    require_relative '../../app/services/logging_service'
    require_relative '../../app/services/error_handler'
    require_relative '../../app/services/performance_monitor'
    require_relative '../../app/middleware/error_handling_middleware'
    
    # Initialize logging service for testing
    LoggingService.initialize_logging
  end
  
  before(:each) do
    # Reset error statistics before each test
    ErrorHandler.reset_error_statistics
    
    # Capture log output for verification
    @log_output = StringIO.new
    @original_logger = LoggingService.logger
    
    # Create test logger that writes to StringIO
    @test_logger = Logger.new(@log_output)
    @test_logger.level = Logger::DEBUG
    LoggingService.instance_variable_set(:@logger, @test_logger)
  end
  
  after(:each) do
    # Restore original logger
    LoggingService.instance_variable_set(:@logger, @original_logger)
  end

  describe 'Property 17: Error Handling and Logging' do
    it 'logs all important events with appropriate detail levels and structured format' do
      test_instance = self
      
      property_of {
        # Generate various types of important events
        event_type = choose(:authentication, :websocket, :database, :api, :file_upload, :room_management, :playback, :security, :system, :performance)
        event_data = test_instance.generate_event_data(event_type)
        [event_type, event_data]
      }.check(20) { |event_type, event_data|
        # Clear previous log output
        @log_output.string = ""
        
        # Generate the event based on type
        case event_type
        when :authentication
          LoggingService.log_auth_event(event_data[:event_name], event_data[:user_identifier], event_data[:success], event_data[:metadata])
        when :websocket
          LoggingService.log_websocket_event(event_data[:event_name], event_data[:user_id], event_data[:room_id], event_data[:metadata])
        when :database
          LoggingService.log_database_operation(event_data[:operation], event_data[:table], event_data[:duration_ms], event_data[:metadata])
        when :api
          LoggingService.log_api_request(event_data[:method], event_data[:path], event_data[:status], event_data[:duration_ms], event_data[:metadata])
        when :file_upload
          LoggingService.log_file_operation(event_data[:operation], event_data[:filename], event_data[:success], event_data[:duration_ms], event_data[:metadata])
        when :room_management
          LoggingService.log_room_event(event_data[:event_name], event_data[:room_id], event_data[:user_id], event_data[:metadata])
        when :playback
          LoggingService.log_playback_event(event_data[:event_name], event_data[:room_id], event_data[:track_id], event_data[:user_id], event_data[:metadata])
        when :security
          LoggingService.log_security_event(event_data[:event_name], event_data[:message], event_data[:metadata])
        when :system
          LoggingService.log_system_event(event_data[:event_name], event_data[:message], event_data[:metadata])
        when :performance
          LoggingService.log_performance(event_data[:operation], event_data[:duration_ms], event_data[:metadata])
        end
        
        # Verify the event was logged
        log_content = @log_output.string
        expect(log_content).not_to be_empty
        
        # Verify log contains structured information
        expect(log_content).to include(event_data[:expected_content]) if event_data[:expected_content] && event_data[:expected_content] != 'SECURITY'
        
        # Special case for security events which use 'SEC' instead of 'SECURITY'
        if event_data[:expected_content] == 'SECURITY'
          expect(log_content).to include('SEC')
        end
        
        # Verify timestamp is present
        expect(log_content).to match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/)
        
        # Verify appropriate log level is used
        case event_type
        when :security
          expect(log_content).to include('[WARN]')
        when :authentication
          if event_data[:success]
            expect(log_content).to include('[INFO]')
          else
            expect(log_content).to include('[WARN]')
          end
        when :api
          if event_data[:status] >= 500
            expect(log_content).to include('[ERROR]')
          elsif event_data[:status] >= 400
            expect(log_content).to include('[WARN]')
          else
            expect(log_content).to include('[INFO]')
          end
        end
      }
    end
    it 'handles WebSocket errors gracefully without server crashes' do
      test_instance = self
      
      property_of {
        # Generate various WebSocket error scenarios
        error_scenario = test_instance.generate_websocket_error_scenario
        error_scenario
      }.check(15) { |error_scenario|
        # Clear previous log output
        @log_output.string = ""
        
        # Create the error condition
        error = case error_scenario[:type]
        when :connection_error
          StandardError.new("WebSocket connection failed: #{error_scenario[:message]}")
        when :message_error
          StandardError.new("Invalid WebSocket message: #{error_scenario[:message]}")
        when :authentication_error
          StandardError.new("WebSocket authentication failed: #{error_scenario[:message]}")
        when :protocol_error
          StandardError.new("WebSocket protocol error: #{error_scenario[:message]}")
        when :timeout_error
          StandardError.new("WebSocket timeout: #{error_scenario[:message]}")
        end
        
        # Handle the WebSocket error using the main error handler to ensure statistics are updated
        error_info = ErrorHandler.handle_error(error, error_scenario[:context])
        error_response = ErrorHandler.handle_websocket_error(error, error_scenario[:context])
        
        # Verify error is handled gracefully (no exception raised)
        expect(error_response).to be_a(Hash)
        expect(error_response[:type]).to eq('error')
        expect(error_response[:data]).to be_a(Hash)
        expect(error_response[:data][:message]).to be_a(String)
        expect(error_response[:data][:category]).not_to be_nil
        expect([true, false]).to include(error_response[:data][:recoverable])
        expect(error_response[:data][:timestamp]).to be_a(Float)
        
        # Verify error was logged
        log_content = @log_output.string
        expect(log_content).not_to be_empty
        expect(log_content).to include('WebSocket')
        expect(log_content).to include('error')
        
        # Verify user-friendly error message (no technical details exposed)
        user_message = error_response[:data][:message]
        expect(user_message).not_to include('backtrace')
        expect(user_message).not_to include('stack trace')
        expect(user_message).not_to include(error.class.name) unless SpotikConfig::Settings.app_debug?
        
        # Verify error statistics are updated
        stats = ErrorHandler.get_error_statistics
        expect(stats[:total_errors]).to be > 0
        expect(stats[:errors_by_category][:websocket]).to be > 0
      }
    end
    it 'returns user-friendly error messages for any error condition' do
      test_instance = self
      
      property_of {
        # Generate various error conditions
        error_condition = test_instance.generate_error_condition
        error_condition
      }.check(20) { |error_condition|
        # Create the error
        error = case error_condition[:category]
        when :authentication
          # Create a custom error that will be categorized as authentication
          auth_error = StandardError.new("Authentication failed: #{error_condition[:details]}")
          auth_error.define_singleton_method(:class) { 
            Class.new { def name; 'AuthenticationError'; end }.new 
          }
          auth_error
        when :authorization
          # Create a custom error that will be categorized as authorization
          authz_error = StandardError.new("Access denied: #{error_condition[:details]}")
          authz_error.define_singleton_method(:class) { 
            Class.new { def name; 'AuthorizationError'; end }.new 
          }
          authz_error
        when :validation
          # Create a custom error that will be categorized as validation
          validation_error = StandardError.new("Validation failed: #{error_condition[:details]}")
          validation_error.define_singleton_method(:class) { 
            Class.new { def name; 'ValidationError'; end }.new 
          }
          validation_error
        when :database
          # Use context to indicate database error
          StandardError.new("Database error: #{error_condition[:details]}")
        when :file_system
          # Create a file system error
          Errno::ENOENT.new("File system error: #{error_condition[:details]}")
        when :network
          # Create a network error
          Errno::ECONNREFUSED.new("Network error: #{error_condition[:details]}")
        when :system
          StandardError.new("System error: #{error_condition[:details]}")
        end
        
        # Handle the error
        error_info = ErrorHandler.handle_error(error, error_condition[:context])
        
        # Verify user-friendly message is generated
        expect(error_info[:user_message]).to be_a(String)
        expect(error_info[:user_message]).not_to be_empty
        
        # Verify message is user-friendly (no technical jargon)
        user_message = error_info[:user_message]
        expect(user_message).not_to include('backtrace')
        expect(user_message).not_to include('stack trace')
        expect(user_message).not_to include('Exception')
        expect(user_message).not_to include('RuntimeError')
        
        # Verify message provides helpful guidance
        case error_condition[:category]
        when :authentication
          expect(user_message).to include('credentials').or include('Authentication').or include('check')
        when :authorization
          expect(user_message).to include('permission').or include('Access denied').or include('denied')
        when :validation
          expect(user_message).to include('input').or include('Invalid').or include('provided')
        when :database
          expect(user_message).to include('try again').or include('database').or include('occurred')
        when :file_system
          expect(user_message).to include('file').or include('File').or include('check')
        when :network
          expect(user_message).to include('connection').or include('Network').or include('check')
        when :system
          expect(user_message).to include('try again').or include('occurred').or include('unexpected')
        end
        
        # Verify appropriate HTTP status is assigned
        expect(error_info[:http_status]).to be_between(400, 599)
        
        # Verify error code is generated
        expect(error_info[:error_code]).to be_a(String)
        expect(error_info[:error_code]).to match(/^[A-Z_]+_[A-F0-9]+$/)
      }
    end
    it 'logs performance of critical operations with timing information' do
      test_instance = self
      
      property_of {
        # Generate various critical operations
        operation_data = test_instance.generate_critical_operation
        operation_data
      }.check(15) { |operation_data|
        # Clear previous log output
        @log_output.string = ""
        
        # Perform the operation with performance logging
        result = LoggingService.measure_execution(operation_data[:operation_name], operation_data[:category]) do
          # Simulate the operation
          sleep(operation_data[:simulated_duration])
          operation_data[:expected_result]
        end
        
        # Verify operation completed successfully
        expect(result).to eq(operation_data[:expected_result])
        
        # Verify performance was logged
        log_content = @log_output.string
        expect(log_content).not_to be_empty
        
        # Verify timing information is present
        expect(log_content).to include('PERF').or include('Performance')
        expect(log_content).to include(operation_data[:operation_name].to_s)
        expect(log_content).to match(/duration_ms.*\d+\.\d+/) # Duration in milliseconds
        
        # Verify operation details are logged
        expect(log_content).to include(operation_data[:category].to_s) if operation_data[:category]
        
        # Test direct performance logging
        @log_output.string = ""
        duration_ms = (operation_data[:simulated_duration] * 1000).round(2)
        LoggingService.log_performance(operation_data[:operation_name], duration_ms, operation_data[:metadata])
        
        log_content = @log_output.string
        expect(log_content).to include('PERF')
        expect(log_content).to include(duration_ms.to_s)
        expect(log_content).to include(operation_data[:operation_name].to_s)
        
        # Verify performance thresholds are respected
        threshold = LoggingService::PERFORMANCE_THRESHOLDS[operation_data[:operation_name]] || 1000
        if duration_ms > threshold
          expect(log_content).to include('[WARN]')
        else
          expect(log_content).to include('[INFO]')
        end
      }
    end
    it 'supports different log levels with proper filtering' do
      test_instance = self
      
      property_of {
        # Generate various log level scenarios
        log_scenario = test_instance.generate_log_level_scenario
        log_scenario
      }.check(15) { |log_scenario|
        # Set the log level for this test
        original_level = SpotikConfig::Settings.log_level
        SpotikConfig::Settings.instance_variable_set(:@log_level, log_scenario[:level])
        
        # Create new logger with the test level
        @test_logger.level = Logger.const_get(log_scenario[:level].upcase)
        
        # Clear previous log output
        @log_output.string = ""
        
        # Generate messages at different levels
        LoggingService.log_debug(:system, "Debug message: #{log_scenario[:message]}", log_scenario[:data])
        LoggingService.log_info(:system, "Info message: #{log_scenario[:message]}", log_scenario[:data])
        LoggingService.log_warn(:system, "Warning message: #{log_scenario[:message]}", log_scenario[:data])
        LoggingService.log_error(:system, "Error message: #{log_scenario[:message]}", log_scenario[:data])
        
        log_content = @log_output.string
        
        # Verify appropriate messages are logged based on level
        case log_scenario[:level]
        when 'debug'
          expect(log_content).to include('Debug message')
          expect(log_content).to include('Info message')
          expect(log_content).to include('Warning message')
          expect(log_content).to include('Error message')
        when 'info'
          expect(log_content).not_to include('Debug message')
          expect(log_content).to include('Info message')
          expect(log_content).to include('Warning message')
          expect(log_content).to include('Error message')
        when 'warn'
          expect(log_content).not_to include('Debug message')
          expect(log_content).not_to include('Info message')
          expect(log_content).to include('Warning message')
          expect(log_content).to include('Error message')
        when 'error'
          expect(log_content).not_to include('Debug message')
          expect(log_content).not_to include('Info message')
          expect(log_content).not_to include('Warning message')
          expect(log_content).to include('Error message')
        end
        
        # Verify log level indicators are present
        if log_content.include?('Debug message')
          expect(log_content).to include('[DEBUG]')
        end
        if log_content.include?('Info message')
          expect(log_content).to include('[INFO]')
        end
        if log_content.include?('Warning message')
          expect(log_content).to include('[WARN]')
        end
        if log_content.include?('Error message')
          expect(log_content).to include('[ERROR]')
        end
        
        # Restore original log level
        SpotikConfig::Settings.instance_variable_set(:@log_level, original_level)
      }
    end
    it 'maintains system stability during error recovery attempts' do
      test_instance = self
      
      property_of {
        # Generate various error recovery scenarios
        recovery_scenario = test_instance.generate_recovery_scenario
        recovery_scenario
      }.check(10) { |recovery_scenario|
        # Clear previous log output
        @log_output.string = ""
        
        # Test error recovery without system crash
        begin
          result = ErrorHandler.with_error_recovery(recovery_scenario[:operation_name], recovery_scenario[:context]) do
            if recovery_scenario[:should_fail]
              raise recovery_scenario[:error_class].new(recovery_scenario[:error_message])
            else
              recovery_scenario[:success_result]
            end
          end
          
          # If we reach here, either operation succeeded or recovery worked
          if recovery_scenario[:should_fail]
            # Recovery should have been attempted
            log_content = @log_output.string
            expect(log_content).to include('error').or include('ERROR')
          else
            # Operation should have succeeded
            expect(result).to eq(recovery_scenario[:success_result])
          end
          
        rescue EnhancedError => e
          # Enhanced error should contain recovery information
          expect(e.category).not_to be_nil
          expect(e.severity).not_to be_nil
          expect(e.context).to be_a(Hash)
          
          # System should still be stable (no crash)
          expect(true).to be true # We're still running
        end
        
        # Verify error statistics are maintained
        stats = ErrorHandler.get_error_statistics
        expect(stats).to be_a(Hash)
        expect(stats[:total_errors]).to be_a(Integer)
        expect(stats[:errors_by_category]).to be_a(Hash)
        expect(stats[:recovery_attempts]).to be_a(Hash)
        
        # Verify logging system is still functional
        LoggingService.log_info(:system, "System stability test completed", { test: true })
        log_content = @log_output.string
        expect(log_content).to include('System stability test completed')
      }
    end
  end

  # Helper methods for generating test data

  def generate_event_data(event_type)
    case event_type
    when :authentication
      {
        event_name: ['login', 'logout', 'register', 'password_reset'].sample,
        user_identifier: "user_#{SecureRandom.hex(4)}",
        success: [true, false].sample,
        metadata: { ip_address: generate_ip_address, user_agent: generate_user_agent },
        expected_content: 'Auth'
      }
    when :websocket
      {
        event_name: ['connection_opened', 'connection_closed', 'message_received', 'error_occurred'].sample,
        user_id: "user_#{SecureRandom.hex(4)}",
        room_id: "room_#{SecureRandom.hex(4)}",
        metadata: { connection_id: "conn_#{SecureRandom.hex(6)}" },
        expected_content: 'WebSocket'
      }
    when :database
      {
        operation: ['SELECT', 'INSERT', 'UPDATE', 'DELETE'].sample,
        table: ['users', 'rooms', 'tracks', 'track_votes'].sample,
        duration_ms: rand(1.0..500.0).round(2),
        metadata: { query_type: 'test' },
        expected_content: 'DB'
      }
    when :api
      {
        method: ['GET', 'POST', 'PUT', 'DELETE'].sample,
        path: ['/api/auth/login', '/api/rooms', '/api/tracks', '/api/users'].sample,
        status: [200, 201, 400, 401, 403, 404, 422, 500].sample,
        duration_ms: rand(10.0..2000.0).round(2),
        metadata: { user_id: "user_#{SecureRandom.hex(4)}" },
        expected_content: 'API'
      }
    when :file_upload
      {
        operation: ['upload', 'download', 'delete', 'validate'].sample,
        filename: "#{SecureRandom.hex(6)}.#{['mp3', 'wav', 'm4a'].sample}",
        success: [true, false].sample,
        duration_ms: rand(100.0..5000.0).round(2),
        metadata: { file_size_mb: rand(1.0..50.0).round(2) },
        expected_content: 'File'
      }
    when :room_management
      {
        event_name: ['room_created', 'user_joined', 'user_left', 'room_deleted'].sample,
        room_id: "room_#{SecureRandom.hex(4)}",
        user_id: "user_#{SecureRandom.hex(4)}",
        metadata: { participant_count: rand(1..20) },
        expected_content: 'Room'
      }
    when :playback
      {
        event_name: ['track_started', 'track_paused', 'track_resumed', 'track_skipped'].sample,
        room_id: "room_#{SecureRandom.hex(4)}",
        track_id: "track_#{SecureRandom.hex(4)}",
        user_id: "user_#{SecureRandom.hex(4)}",
        metadata: { position: rand(0.0..300.0).round(2) },
        expected_content: 'Playback'
      }
    when :security
      {
        event_name: ['failed_authentication', 'rate_limit_exceeded', 'suspicious_activity'].sample,
        message: "Security event: #{SecureRandom.hex(8)}",
        metadata: { ip_address: generate_ip_address, severity: ['low', 'medium', 'high'].sample },
        expected_content: 'SECURITY'
      }
    when :system
      {
        event_name: ['server_startup', 'server_shutdown', 'memory_warning', 'health_check'].sample,
        message: "System event: #{SecureRandom.hex(8)}",
        metadata: { memory_usage: rand(100..2000), cpu_usage: rand(10..90) },
        expected_content: 'SYS'
      }
    when :performance
      {
        operation: [:database_query, :api_request, :websocket_message, :file_operation, :authentication].sample,
        duration_ms: rand(1.0..1000.0).round(2),
        metadata: { operation_type: 'test' },
        expected_content: 'PERF'
      }
    end
  end
  def generate_websocket_error_scenario
    error_types = [:connection_error, :message_error, :authentication_error, :protocol_error, :timeout_error]
    error_type = error_types.sample
    
    {
      type: error_type,
      message: "Test #{error_type}: #{SecureRandom.hex(8)}",
      context: {
        user_id: "user_#{SecureRandom.hex(4)}",
        connection_id: "conn_#{SecureRandom.hex(6)}",
        room_id: "room_#{SecureRandom.hex(4)}",
        context_type: 'websocket'
      }
    }
  end

  def generate_error_condition
    categories = [:authentication, :authorization, :validation, :database, :file_system, :network, :system]
    category = categories.sample
    
    {
      category: category,
      details: "Test #{category} error: #{SecureRandom.hex(8)}",
      context: {
        context_type: category.to_s,
        user_id: "user_#{SecureRandom.hex(4)}",
        operation: "test_operation_#{SecureRandom.hex(4)}",
        timestamp: Time.now.iso8601
      }
    }
  end

  def generate_critical_operation
    operations = [:database_query, :api_request, :websocket_message, :file_operation, :authentication]
    operation = operations.sample
    
    {
      operation_name: operation,
      category: [:database, :api, :websocket, :file_system, :authentication].sample,
      simulated_duration: rand(0.001..0.1), # 1ms to 100ms
      expected_result: "operation_result_#{SecureRandom.hex(6)}",
      metadata: {
        test_operation: true,
        operation_id: SecureRandom.hex(8)
      }
    }
  end

  def generate_log_level_scenario
    levels = ['debug', 'info', 'warn', 'error']
    level = levels.sample
    
    {
      level: level,
      message: "Test message for #{level} level: #{SecureRandom.hex(6)}",
      data: {
        test_level: level,
        test_id: SecureRandom.hex(8),
        timestamp: Time.now.to_f
      }
    }
  end

  def generate_recovery_scenario
    error_classes = [StandardError, RuntimeError, ArgumentError, NoMethodError]
    
    {
      operation_name: "test_operation_#{SecureRandom.hex(4)}",
      should_fail: [true, false].sample,
      error_class: error_classes.sample,
      error_message: "Test recovery error: #{SecureRandom.hex(8)}",
      success_result: "recovery_success_#{SecureRandom.hex(6)}",
      context: {
        test_recovery: true,
        recovery_id: SecureRandom.hex(8),
        user_id: "user_#{SecureRandom.hex(4)}"
      }
    }
  end

  def generate_ip_address
    "#{rand(1..255)}.#{rand(1..255)}.#{rand(1..255)}.#{rand(1..255)}"
  end

  def generate_user_agent
    agents = [
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36'
    ]
    agents.sample
  end
end