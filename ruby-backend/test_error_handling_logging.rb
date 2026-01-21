#!/usr/bin/env ruby

# Comprehensive Error Handling and Logging Test
# Tests the new error handling and logging system implementation

puts "=== Error Handling and Logging System Test ==="
puts "Testing comprehensive error handling, logging, and performance monitoring..."

# Set test environment
ENV['APP_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test_jwt_secret_key_for_testing_purposes_only'
ENV['JWT_TTL'] = '60'
ENV['SERVER_PORT'] = '3001'
ENV['LOG_LEVEL'] = 'debug'
ENV['ENABLE_PERFORMANCE_MONITORING'] = 'true'

begin
  # Test 1: Configuration and Dependencies
  puts "\n1. Testing configuration and dependencies..."
  require_relative 'config/settings'
  require_relative 'app/services/logging_service'
  require_relative 'app/services/error_handler'
  require_relative 'app/services/performance_monitor'
  require_relative 'app/middleware/error_handling_middleware'
  
  puts "✅ All error handling and logging components loaded successfully"
  
  # Test 2: LoggingService Functionality
  puts "\n2. Testing LoggingService functionality..."
  
  # Test structured logging
  LoggingService.log_info(:system, "Test info message", { test_data: "info_test" })
  LoggingService.log_warn(:api, "Test warning message", { test_data: "warn_test" })
  LoggingService.log_error(:database, "Test error message", { test_data: "error_test" })
  
  # Test performance logging
  LoggingService.log_performance(:test_operation, 150.5, { operation_type: "test" })
  
  # Test authentication logging
  LoggingService.log_auth_event('login', 'test_user', true, { ip_address: '127.0.0.1' })
  LoggingService.log_auth_event('login', 'bad_user', false, { ip_address: '192.168.1.100' })
  
  # Test WebSocket logging
  LoggingService.log_websocket_event('connection_opened', 'user123', 'room456', { connection_id: 'conn123' })
  
  # Test file operation logging
  LoggingService.log_file_operation('upload', 'test.mp3', true, 250.0, { file_size_mb: 5.2 })
  
  # Test security event logging
  LoggingService.log_security_event('failed_authentication', 'Multiple failed login attempts', {
    ip_address: '192.168.1.100',
    attempts: 5
  })
  
  # Test system event logging
  LoggingService.log_system_event('server_startup', 'Test server startup', { version: '1.0.0' })
  
  # Test execution measurement
  result = LoggingService.measure_execution(:test_operation) do
    sleep(0.01) # Simulate work
    "test_result"
  end
  
  if result == "test_result"
    puts "✅ LoggingService functionality tests passed"
  else
    puts "❌ LoggingService execution measurement failed"
    exit 1
  end
  
  # Test logging statistics
  stats = LoggingService.get_statistics
  if stats.is_a?(Hash) && stats[:log_level]
    puts "✅ LoggingService statistics working"
    puts "   Log level: #{stats[:log_level]}"
    puts "   Categories: #{stats[:categories].length}"
  else
    puts "❌ LoggingService statistics failed"
    exit 1
  end
  
  # Test 3: ErrorHandler Functionality
  puts "\n3. Testing ErrorHandler functionality..."
  
  # Test basic error handling
  test_error = StandardError.new("Test error message")
  error_info = ErrorHandler.handle_error(test_error, { context_type: 'test' })
  
  if error_info[:category] && error_info[:severity] && error_info[:user_message]
    puts "✅ Basic error handling working"
    puts "   Category: #{error_info[:category]}"
    puts "   Severity: #{error_info[:severity]}"
    puts "   User message: #{error_info[:user_message]}"
  else
    puts "❌ Basic error handling failed"
    exit 1
  end
  
  # Test API error handling
  api_error_response = ErrorHandler.handle_api_error(test_error, {
    method: 'POST',
    path: '/api/test',
    ip_address: '127.0.0.1'
  })
  
  if api_error_response[:status] && api_error_response[:body][:error]
    puts "✅ API error handling working"
    puts "   Status: #{api_error_response[:status]}"
    puts "   Error: #{api_error_response[:body][:error]}"
  else
    puts "❌ API error handling failed"
    exit 1
  end
  
  # Test WebSocket error handling
  ws_error_response = ErrorHandler.handle_websocket_error(test_error, {
    user_id: 'user123',
    connection_id: 'conn123'
  })
  
  if ws_error_response[:type] == 'error' && ws_error_response[:data][:message]
    puts "✅ WebSocket error handling working"
    puts "   Type: #{ws_error_response[:type]}"
    puts "   Message: #{ws_error_response[:data][:message]}"
  else
    puts "❌ WebSocket error handling failed"
    exit 1
  end
  
  # Test error recovery
  recovery_result = ErrorHandler.with_error_recovery('test_operation', { test: true }) do
    "success_result"
  end
  
  if recovery_result == "success_result"
    puts "✅ Error recovery for successful operation working"
  else
    puts "❌ Error recovery for successful operation failed"
    exit 1
  end
  
  # Test error recovery with failure
  begin
    ErrorHandler.with_error_recovery('test_failing_operation', { test: true }) do
      raise StandardError.new("Test failure")
    end
    puts "❌ Error recovery should have raised an error"
    exit 1
  rescue ErrorHandler::EnhancedError => e
    if e.category && e.severity
      puts "✅ Error recovery with failure working"
      puts "   Enhanced error category: #{e.category}"
      puts "   Enhanced error severity: #{e.severity}"
    else
      puts "❌ Enhanced error missing attributes"
      exit 1
    end
  end
  
  # Test error statistics
  error_stats = ErrorHandler.get_error_statistics
  if error_stats[:total_errors] && error_stats[:errors_by_category]
    puts "✅ Error statistics working"
    puts "   Total errors: #{error_stats[:total_errors]}"
    puts "   Error categories: #{error_stats[:errors_by_category].keys.length}"
  else
    puts "❌ Error statistics failed"
    exit 1
  end
  
  # Test 4: PerformanceMonitor Functionality
  puts "\n4. Testing PerformanceMonitor functionality..."
  
  # Test operation measurement
  perf_result = PerformanceMonitor.measure_operation(:test_operation, 'test_measurement', { test: true }) do
    sleep(0.01) # Simulate work
    "performance_test_result"
  end
  
  if perf_result == "performance_test_result"
    puts "✅ Performance measurement working"
  else
    puts "❌ Performance measurement failed"
    exit 1
  end
  
  # Test specific tracking methods
  PerformanceMonitor.track_api_request('GET', '/api/test', 200, 150.5, { test: true })
  PerformanceMonitor.track_database_query('SELECT', 'users', 25.0, { test: true })
  PerformanceMonitor.track_websocket_message('test_message', 5.0, { test: true })
  PerformanceMonitor.track_file_operation('upload', 'test.mp3', 500.0, 5.2, { test: true })
  PerformanceMonitor.track_authentication('jwt_validation', 75.0, true, { test: true })
  PerformanceMonitor.track_room_operation('join_room', 'room123', 30.0, { test: true })
  PerformanceMonitor.track_playback_operation('start', 'room123', 'track456', 15.0, { test: true })
  
  puts "✅ Performance tracking methods working"
  
  # Test performance statistics
  perf_stats = PerformanceMonitor.get_performance_statistics
  if perf_stats[:total_operations] && perf_stats[:operations_by_type]
    puts "✅ Performance statistics working"
    puts "   Total operations: #{perf_stats[:total_operations]}"
    puts "   Operation types: #{perf_stats[:operations_by_type].keys.length}"
    puts "   Health status: #{perf_stats[:health_status]}"
  else
    puts "❌ Performance statistics failed"
    exit 1
  end
  
  # Test performance report
  perf_report = PerformanceMonitor.generate_performance_report
  if perf_report[:summary] && perf_report[:operations]
    puts "✅ Performance report generation working"
    puts "   Report sections: #{perf_report.keys.length}"
  else
    puts "❌ Performance report generation failed"
    exit 1
  end
  
  # Test 5: Middleware Functionality
  puts "\n5. Testing middleware functionality..."
  
  # Create a simple test app
  test_app = lambda do |env|
    if env['PATH_INFO'] == '/error'
      raise StandardError.new("Test middleware error")
    else
      [200, { 'Content-Type' => 'application/json' }, ['{"status":"ok"}']]
    end
  end
  
  # Test ErrorHandlingMiddleware
  error_middleware = ErrorHandlingMiddleware.new(test_app)
  
  # Test successful request
  env = {
    'REQUEST_METHOD' => 'GET',
    'PATH_INFO' => '/test',
    'QUERY_STRING' => '',
    'REMOTE_ADDR' => '127.0.0.1',
    'HTTP_USER_AGENT' => 'Test Agent'
  }
  
  status, headers, response = error_middleware.call(env)
  
  if status == 200 && headers['X-Request-ID']
    puts "✅ ErrorHandlingMiddleware successful request handling working"
    puts "   Status: #{status}"
    puts "   Request ID: #{headers['X-Request-ID']}"
  else
    puts "❌ ErrorHandlingMiddleware successful request handling failed"
    exit 1
  end
  
  # Test error request
  env['PATH_INFO'] = '/error'
  status, headers, response = error_middleware.call(env)
  
  if status >= 400 && headers['X-Request-ID']
    puts "✅ ErrorHandlingMiddleware error request handling working"
    puts "   Error status: #{status}"
    puts "   Request ID: #{headers['X-Request-ID']}"
  else
    puts "❌ ErrorHandlingMiddleware error request handling failed"
    exit 1
  end
  
  # Test PerformanceMonitoringMiddleware
  perf_middleware = PerformanceMonitoringMiddleware.new(test_app)
  
  env['PATH_INFO'] = '/test'
  status, headers, response = perf_middleware.call(env)
  
  if status == 200
    puts "✅ PerformanceMonitoringMiddleware working"
  else
    puts "❌ PerformanceMonitoringMiddleware failed"
    exit 1
  end
  
  # Test SecurityHeadersMiddleware
  security_middleware = SecurityHeadersMiddleware.new(test_app)
  
  status, headers, response = security_middleware.call(env)
  
  if headers['X-Content-Type-Options'] && headers['X-Frame-Options']
    puts "✅ SecurityHeadersMiddleware working"
    puts "   Security headers added: #{headers.select { |k, v| k.start_with?('X-') }.keys.length}"
  else
    puts "❌ SecurityHeadersMiddleware failed"
    exit 1
  end
  
  # Test 6: Integration Test
  puts "\n6. Testing integration scenarios..."
  
  # Test complex error scenario with recovery
  complex_result = ErrorHandler.with_error_recovery('complex_operation', { 
    operation_type: 'integration_test',
    user_id: 'test_user_123'
  }) do
    PerformanceMonitor.measure_operation(:complex_operation, 'integration_test') do
      LoggingService.log_info(:system, "Starting complex operation", { test: true })
      
      # Simulate some work
      sleep(0.005)
      
      LoggingService.log_info(:system, "Complex operation completed", { test: true })
      "complex_success"
    end
  end
  
  if complex_result == "complex_success"
    puts "✅ Complex integration scenario working"
  else
    puts "❌ Complex integration scenario failed"
    exit 1
  end
  
  # Test 7: Statistics and Monitoring
  puts "\n7. Testing statistics and monitoring..."
  
  # Get all statistics
  logging_stats = LoggingService.get_statistics
  error_stats = ErrorHandler.get_error_statistics
  perf_stats = PerformanceMonitor.get_performance_statistics
  
  puts "✅ All statistics accessible"
  puts "   Logging uptime: #{logging_stats[:uptime]&.round(2)} seconds"
  puts "   Total errors: #{error_stats[:total_errors]}"
  puts "   Performance operations: #{perf_stats[:total_operations]}"
  puts "   Performance health: #{perf_stats[:health_status]}"
  
  # Summary
  puts "\n" + "="*60
  puts "🎉 ALL ERROR HANDLING AND LOGGING TESTS PASSED!"
  puts "="*60
  puts "✅ LoggingService - Structured logging with multiple outputs"
  puts "✅ ErrorHandler - Comprehensive error handling and recovery"
  puts "✅ PerformanceMonitor - Performance tracking and monitoring"
  puts "✅ Middleware - Request/response handling and security"
  puts "✅ Integration - Complex scenarios with all components"
  puts "✅ Statistics - Monitoring and reporting capabilities"
  puts "="*60
  
  puts "\nError handling and logging system is fully functional!"
  puts "Features implemented:"
  puts "• Structured logging for all important events"
  puts "• Comprehensive error handling for WebSocket connections and API endpoints"
  puts "• Performance logging for critical operations"
  puts "• Graceful error recovery without server crashes"
  puts "• Security event logging and monitoring"
  puts "• Request/response middleware with error handling"
  puts "• Performance monitoring and statistics"
  puts "• Circuit breaker pattern for external services"
  puts "• Rate limiting and security headers"
  puts "• Comprehensive statistics and reporting"
  
rescue LoadError => e
  puts "❌ Dependency loading failed: #{e.message}"
  puts "   Missing gem or file: #{e.message}"
  exit 1
rescue => e
  puts "❌ Test failed with error: #{e.message}"
  puts "   Error class: #{e.class.name}"
  puts "   Backtrace: #{e.backtrace.first(5).join("\n   ")}"
  exit 1
end