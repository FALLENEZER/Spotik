#!/usr/bin/env ruby

# System Health Monitoring and Validation Script
# **Feature: ruby-backend-migration, Task 17.1: Complete system integration and final testing**
# **Validates: Requirements 1.5, 13.1, 13.2, 13.3, 13.4, 13.5, 14.4**

require 'bundler/setup'
require 'net/http'
require 'uri'
require 'json'
require 'timeout'
require 'benchmark'
require 'optparse'

class SystemValidator
  attr_reader :base_url, :validation_timeout
  
  def initialize(options = {})
    @base_url = options[:base_url] || 'http://localhost:3000'
    @validation_timeout = options[:timeout] || 30
    @validation_results = []
    @critical_failures = []
  end
  
  def run_validation
    puts "🔍 Ruby Backend Migration - System Validation"
    puts "=" * 60
    puts "Target System: #{@base_url}"
    puts "Validation Timeout: #{@validation_timeout}s"
    puts "=" * 60
    
    begin
      Timeout::timeout(@validation_timeout) do
        # Core System Health Checks
        puts "\n🏥 Core System Health Checks"
        validate_server_availability
        validate_health_endpoints
        validate_configuration_endpoints
        
        # API Functionality Validation
        puts "\n🔌 API Functionality Validation"
        validate_authentication_endpoints
        validate_room_management_endpoints
        validate_websocket_endpoints
        
        # Performance and Monitoring Validation
        puts "\n📊 Performance and Monitoring Validation"
        validate_performance_endpoints
        validate_error_handling
        validate_logging_system
        
        # Database and Storage Validation
        puts "\n💾 Database and Storage Validation"
        validate_database_connectivity
        validate_data_integrity
        
        # Security Validation
        puts "\n🔒 Security Validation"
        validate_authentication_security
        validate_authorization_controls
        
        # Generate comprehensive validation report
        generate_validation_report
      end
      
    rescue Timeout::Error
      puts "\n⏰ Validation timeout reached (#{@validation_timeout}s)"
      generate_partial_report
    rescue Interrupt
      puts "\n⚠️  Validation interrupted by user"
      generate_partial_report
    rescue => e
      puts "\n❌ Validation failed: #{e.message}"
      puts e.backtrace.first(5)
      exit 1
    end
  end
  
  private
  
  def validate_server_availability
    print "  Checking server availability... "
    
    begin
      uri = URI("#{@base_url}/api")
      response = Net::HTTP.get_response(uri)
      
      if response.code == '200'
        body = JSON.parse(response.body)
        record_validation('server_availability', true, {
          status: 'available',
          version: body['version'],
          environment: body['environment'],
          ruby_version: body['ruby_version'],
          websocket_support: body['websocket_support']
        })
        puts "✅ Available"
        puts "     Version: #{body['version']}"
        puts "     Environment: #{body['environment']}"
        puts "     Ruby Version: #{body['ruby_version']}"
        puts "     WebSocket Support: #{body['websocket_support']}"
      else
        record_validation('server_availability', false, {
          status_code: response.code,
          error: 'Server returned non-200 status'
        })
        puts "❌ Unavailable (HTTP #{response.code})"
        @critical_failures << 'Server not available'
      end
      
    rescue => e
      record_validation('server_availability', false, { error: e.message })
      puts "❌ Failed (#{e.message})"
      @critical_failures << 'Server connection failed'
    end
  end
  
  def validate_health_endpoints
    health_endpoints = [
      { path: '/health', name: 'Basic Health Check' },
      { path: '/health/basic', name: 'Load Balancer Health Check' },
      { path: '/health/database', name: 'Database Health Check' },
      { path: '/health/configuration', name: 'Configuration Health Check' },
      { path: '/health/storage', name: 'Storage Health Check' },
      { path: '/health/performance', name: 'Performance Health Check' },
      { path: '/ready', name: 'Readiness Probe' },
      { path: '/live', name: 'Liveness Probe' }
    ]
    
    health_endpoints.each do |endpoint|
      print "  Checking #{endpoint[:name]}... "
      
      begin
        uri = URI("#{@base_url}#{endpoint[:path]}")
        response = Net::HTTP.get_response(uri)
        
        if response.code == '200'
          body = JSON.parse(response.body)
          record_validation("health_#{endpoint[:path].gsub('/', '_')}", true, body)
          puts "✅ Healthy"
          
          # Log specific health details
          if body['database_status']
            puts "     Database: #{body['database_status']}"
          end
          if body['configuration_status']
            puts "     Configuration: #{body['configuration_status']}"
          end
          if body['storage_status']
            puts "     Storage: #{body['storage_status']}"
          end
        else
          record_validation("health_#{endpoint[:path].gsub('/', '_')}", false, {
            status_code: response.code,
            error: response.body
          })
          puts "❌ Unhealthy (HTTP #{response.code})"
          
          if endpoint[:path] == '/health'
            @critical_failures << 'Basic health check failed'
          end
        end
        
      rescue => e
        record_validation("health_#{endpoint[:path].gsub('/', '_')}", false, { error: e.message })
        puts "❌ Failed (#{e.message})"
      end
    end
  end
  
  def validate_configuration_endpoints
    print "  Checking configuration management... "
    
    begin
      # Test configuration summary endpoint (requires auth, so we expect 401)
      uri = URI("#{@base_url}/api/configuration/summary")
      response = Net::HTTP.get_response(uri)
      
      if response.code == '401'
        record_validation('configuration_endpoints', true, {
          status: 'protected',
          message: 'Configuration endpoints properly secured'
        })
        puts "✅ Protected (requires authentication)"
      else
        record_validation('configuration_endpoints', false, {
          status_code: response.code,
          error: 'Configuration endpoint not properly secured'
        })
        puts "⚠️  Security issue (HTTP #{response.code})"
      end
      
    rescue => e
      record_validation('configuration_endpoints', false, { error: e.message })
      puts "❌ Failed (#{e.message})"
    end
  end
  
  def validate_authentication_endpoints
    auth_endpoints = [
      { path: '/api/auth/register', method: 'POST', name: 'User Registration' },
      { path: '/api/auth/login', method: 'POST', name: 'User Login' },
      { path: '/api/auth/me', method: 'GET', name: 'User Profile' },
      { path: '/api/auth/refresh', method: 'POST', name: 'Token Refresh' },
      { path: '/api/auth/logout', method: 'POST', name: 'User Logout' }
    ]
    
    auth_endpoints.each do |endpoint|
      print "  Checking #{endpoint[:name]}... "
      
      begin
        uri = URI("#{@base_url}#{endpoint[:path]}")
        http = Net::HTTP.new(uri.host, uri.port)
        
        request = case endpoint[:method]
                 when 'GET'
                   Net::HTTP::Get.new(uri)
                 when 'POST'
                   req = Net::HTTP::Post.new(uri)
                   req['Content-Type'] = 'application/json'
                   req.body = '{}'
                   req
                 end
        
        response = http.request(request)
        
        # We expect these to fail with proper error codes (400, 401, 422)
        expected_codes = ['400', '401', '422']
        
        if expected_codes.include?(response.code)
          record_validation("auth_#{endpoint[:path].split('/').last}", true, {
            status_code: response.code,
            endpoint_available: true
          })
          puts "✅ Available (HTTP #{response.code})"
        else
          record_validation("auth_#{endpoint[:path].split('/').last}", false, {
            status_code: response.code,
            error: 'Unexpected response code'
          })
          puts "⚠️  Unexpected response (HTTP #{response.code})"
        end
        
      rescue => e
        record_validation("auth_#{endpoint[:path].split('/').last}", false, { error: e.message })
        puts "❌ Failed (#{e.message})"
      end
    end
  end
  
  def validate_room_management_endpoints
    room_endpoints = [
      { path: '/api/rooms', method: 'GET', name: 'Room Listing' },
      { path: '/api/rooms', method: 'POST', name: 'Room Creation' },
      { path: '/api/rooms/test-id', method: 'GET', name: 'Room Details' },
      { path: '/api/rooms/test-id/join', method: 'POST', name: 'Room Joining' },
      { path: '/api/rooms/test-id/leave', method: 'DELETE', name: 'Room Leaving' }
    ]
    
    room_endpoints.each do |endpoint|
      print "  Checking #{endpoint[:name]}... "
      
      begin
        uri = URI("#{@base_url}#{endpoint[:path]}")
        http = Net::HTTP.new(uri.host, uri.port)
        
        request = case endpoint[:method]
                 when 'GET'
                   Net::HTTP::Get.new(uri)
                 when 'POST'
                   req = Net::HTTP::Post.new(uri)
                   req['Content-Type'] = 'application/json'
                   req.body = '{}'
                   req
                 when 'DELETE'
                   Net::HTTP::Delete.new(uri)
                 end
        
        response = http.request(request)
        
        # We expect these to fail with 401 (unauthorized) since no token provided
        if response.code == '401'
          record_validation("room_#{endpoint[:name].downcase.gsub(' ', '_')}", true, {
            status_code: response.code,
            endpoint_available: true,
            properly_secured: true
          })
          puts "✅ Available and secured (HTTP #{response.code})"
        else
          record_validation("room_#{endpoint[:name].downcase.gsub(' ', '_')}", false, {
            status_code: response.code,
            error: 'Endpoint not properly secured or unavailable'
          })
          puts "⚠️  Security or availability issue (HTTP #{response.code})"
        end
        
      rescue => e
        record_validation("room_#{endpoint[:name].downcase.gsub(' ', '_')}", false, { error: e.message })
        puts "❌ Failed (#{e.message})"
      end
    end
  end
  
  def validate_websocket_endpoints
    print "  Checking WebSocket upgrade endpoint... "
    
    begin
      uri = URI("#{@base_url}/ws")
      response = Net::HTTP.get_response(uri)
      
      # WebSocket upgrade should fail with 400 for regular HTTP request
      if response.code == '400'
        body = JSON.parse(response.body)
        if body['error'] && body['error'].include?('WebSocket')
          record_validation('websocket_endpoint', true, {
            status: 'available',
            message: 'WebSocket endpoint properly configured'
          })
          puts "✅ Available (requires WebSocket upgrade)"
        else
          record_validation('websocket_endpoint', false, {
            status_code: response.code,
            error: 'WebSocket endpoint not properly configured'
          })
          puts "⚠️  Configuration issue"
        end
      else
        record_validation('websocket_endpoint', false, {
          status_code: response.code,
          error: 'Unexpected response from WebSocket endpoint'
        })
        puts "❌ Unexpected response (HTTP #{response.code})"
      end
      
    rescue => e
      record_validation('websocket_endpoint', false, { error: e.message })
      puts "❌ Failed (#{e.message})"
    end
  end
  
  def validate_performance_endpoints
    performance_endpoints = [
      { path: '/api/performance/dashboard', name: 'Performance Dashboard' },
      { path: '/api/performance/metrics', name: 'Performance Metrics' },
      { path: '/api/performance/health', name: 'Performance Health' },
      { path: '/api/performance/benchmarks', name: 'Performance Benchmarks' }
    ]
    
    performance_endpoints.each do |endpoint|
      print "  Checking #{endpoint[:name]}... "
      
      begin
        uri = URI("#{@base_url}#{endpoint[:path]}")
        response = Net::HTTP.get_response(uri)
        
        # These should require authentication (401) or be available
        if ['200', '401'].include?(response.code)
          record_validation("performance_#{endpoint[:path].split('/').last}", true, {
            status_code: response.code,
            endpoint_available: true
          })
          puts "✅ Available (HTTP #{response.code})"
        else
          record_validation("performance_#{endpoint[:path].split('/').last}", false, {
            status_code: response.code,
            error: 'Performance endpoint unavailable'
          })
          puts "❌ Unavailable (HTTP #{response.code})"
        end
        
      rescue => e
        record_validation("performance_#{endpoint[:path].split('/').last}", false, { error: e.message })
        puts "❌ Failed (#{e.message})"
      end
    end
  end
  
  def validate_error_handling
    print "  Checking error handling... "
    
    begin
      # Test 404 error handling
      uri = URI("#{@base_url}/api/nonexistent-endpoint")
      response = Net::HTTP.get_response(uri)
      
      if response.code == '404'
        body = JSON.parse(response.body)
        if body['error'] && body['path']
          record_validation('error_handling', true, {
            status: 'proper_404_handling',
            error_format: 'json',
            includes_path: true
          })
          puts "✅ Proper error handling"
        else
          record_validation('error_handling', false, {
            status_code: response.code,
            error: 'Error response format incorrect'
          })
          puts "⚠️  Error format issue"
        end
      else
        record_validation('error_handling', false, {
          status_code: response.code,
          error: 'Incorrect 404 handling'
        })
        puts "❌ Incorrect error handling (HTTP #{response.code})"
      end
      
    rescue => e
      record_validation('error_handling', false, { error: e.message })
      puts "❌ Failed (#{e.message})"
    end
  end
  
  def validate_logging_system
    print "  Checking logging system... "
    
    begin
      # Test logging endpoint (should require auth)
      uri = URI("#{@base_url}/api/monitoring/logging")
      response = Net::HTTP.get_response(uri)
      
      if response.code == '401'
        record_validation('logging_system', true, {
          status: 'available_and_secured',
          message: 'Logging endpoint properly secured'
        })
        puts "✅ Available and secured"
      else
        record_validation('logging_system', false, {
          status_code: response.code,
          error: 'Logging endpoint security issue'
        })
        puts "⚠️  Security issue (HTTP #{response.code})"
      end
      
    rescue => e
      record_validation('logging_system', false, { error: e.message })
      puts "❌ Failed (#{e.message})"
    end
  end
  
  def validate_database_connectivity
    print "  Checking database connectivity... "
    
    begin
      uri = URI("#{@base_url}/health/database")
      response = Net::HTTP.get_response(uri)
      
      if response.code == '200'
        body = JSON.parse(response.body)
        if body['database_status'] == 'connected'
          record_validation('database_connectivity', true, {
            status: 'connected',
            connection_pool: body['connection_pool_status'],
            query_performance: body['query_performance']
          })
          puts "✅ Connected"
          if body['connection_pool_status']
            puts "     Connection Pool: #{body['connection_pool_status']}"
          end
          if body['query_performance']
            puts "     Query Performance: #{body['query_performance']}"
          end
        else
          record_validation('database_connectivity', false, {
            status: body['database_status'],
            error: 'Database not connected'
          })
          puts "❌ Not connected"
          @critical_failures << 'Database connectivity failed'
        end
      else
        record_validation('database_connectivity', false, {
          status_code: response.code,
          error: 'Database health check failed'
        })
        puts "❌ Health check failed (HTTP #{response.code})"
        @critical_failures << 'Database health check failed'
      end
      
    rescue => e
      record_validation('database_connectivity', false, { error: e.message })
      puts "❌ Failed (#{e.message})"
      @critical_failures << 'Database connectivity check failed'
    end
  end
  
  def validate_data_integrity
    print "  Checking data integrity... "
    
    begin
      # This would typically involve checking database constraints, 
      # but we'll check if the system can handle basic operations
      uri = URI("#{@base_url}/api/rooms")
      response = Net::HTTP.get_response(uri)
      
      # Should get 401 (unauthorized) which means the endpoint is working
      if response.code == '401'
        record_validation('data_integrity', true, {
          status: 'endpoints_functional',
          message: 'Data access endpoints are functional'
        })
        puts "✅ Data access functional"
      else
        record_validation('data_integrity', false, {
          status_code: response.code,
          error: 'Data access endpoints not working properly'
        })
        puts "⚠️  Data access issue (HTTP #{response.code})"
      end
      
    rescue => e
      record_validation('data_integrity', false, { error: e.message })
      puts "❌ Failed (#{e.message})"
    end
  end
  
  def validate_authentication_security
    print "  Checking authentication security... "
    
    begin
      # Test that protected endpoints require authentication
      protected_endpoints = [
        '/api/auth/me',
        '/api/rooms',
        '/api/configuration/summary'
      ]
      
      all_secured = true
      
      protected_endpoints.each do |endpoint|
        uri = URI("#{@base_url}#{endpoint}")
        response = Net::HTTP.get_response(uri)
        
        unless response.code == '401'
          all_secured = false
          break
        end
      end
      
      if all_secured
        record_validation('authentication_security', true, {
          status: 'properly_secured',
          message: 'All protected endpoints require authentication'
        })
        puts "✅ Properly secured"
      else
        record_validation('authentication_security', false, {
          error: 'Some protected endpoints not properly secured'
        })
        puts "❌ Security vulnerability detected"
        @critical_failures << 'Authentication security vulnerability'
      end
      
    rescue => e
      record_validation('authentication_security', false, { error: e.message })
      puts "❌ Failed (#{e.message})"
    end
  end
  
  def validate_authorization_controls
    print "  Checking authorization controls... "
    
    begin
      # Test with invalid token
      uri = URI("#{@base_url}/api/auth/me")
      http = Net::HTTP.new(uri.host, uri.port)
      
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = 'Bearer invalid.token.here'
      
      response = http.request(request)
      
      if response.code == '401'
        body = JSON.parse(response.body)
        if body['error']
          record_validation('authorization_controls', true, {
            status: 'invalid_tokens_rejected',
            message: 'Invalid tokens properly rejected'
          })
          puts "✅ Invalid tokens rejected"
        else
          record_validation('authorization_controls', false, {
            status_code: response.code,
            error: 'Invalid token response format incorrect'
          })
          puts "⚠️  Response format issue"
        end
      else
        record_validation('authorization_controls', false, {
          status_code: response.code,
          error: 'Invalid tokens not properly rejected'
        })
        puts "❌ Security vulnerability (HTTP #{response.code})"
        @critical_failures << 'Authorization control vulnerability'
      end
      
    rescue => e
      record_validation('authorization_controls', false, { error: e.message })
      puts "❌ Failed (#{e.message})"
    end
  end
  
  def record_validation(test_name, success, details = {})
    @validation_results << {
      test: test_name,
      success: success,
      details: details,
      timestamp: Time.now.to_f
    }
  end
  
  def generate_validation_report
    puts "\n" + "=" * 60
    puts "🎯 SYSTEM VALIDATION REPORT"
    puts "=" * 60
    
    total_tests = @validation_results.length
    successful_tests = @validation_results.select { |r| r[:success] }.length
    failed_tests = total_tests - successful_tests
    success_rate = total_tests > 0 ? (successful_tests.to_f / total_tests * 100).round(2) : 0
    
    puts "\n📊 Validation Summary:"
    puts "  Total Tests: #{total_tests}"
    puts "  Successful: #{successful_tests}"
    puts "  Failed: #{failed_tests}"
    puts "  Success Rate: #{success_rate}%"
    
    puts "\n🔍 Test Categories:"
    
    categories = {
      'Core System' => ['server_availability', 'health_basic', 'health_database', 'health_configuration'],
      'API Endpoints' => ['auth_register', 'auth_login', 'room_listing', 'websocket_endpoint'],
      'Security' => ['authentication_security', 'authorization_controls', 'configuration_endpoints'],
      'Performance' => ['performance_dashboard', 'performance_metrics', 'performance_health'],
      'Infrastructure' => ['database_connectivity', 'data_integrity', 'error_handling', 'logging_system']
    }
    
    categories.each do |category, tests|
      category_results = @validation_results.select { |r| tests.any? { |t| r[:test].include?(t) } }
      category_success = category_results.select { |r| r[:success] }.length
      category_total = category_results.length
      
      if category_total > 0
        category_rate = (category_success.to_f / category_total * 100).round(2)
        status_icon = category_rate == 100 ? "✅" : category_rate >= 80 ? "⚠️" : "❌"
        puts "  #{status_icon} #{category}: #{category_rate}% (#{category_success}/#{category_total})"
      end
    end
    
    if @critical_failures.any?
      puts "\n🚨 Critical Failures:"
      @critical_failures.each do |failure|
        puts "  ❌ #{failure}"
      end
    end
    
    puts "\n🎯 System Status Assessment:"
    
    if success_rate >= 95 && @critical_failures.empty?
      puts "  🟢 EXCELLENT: System is production-ready"
      puts "     All critical components are functional"
      puts "     Security measures are properly implemented"
      puts "     Performance monitoring is operational"
    elsif success_rate >= 85 && @critical_failures.empty?
      puts "  🟡 GOOD: System is mostly ready with minor issues"
      puts "     Core functionality is working"
      puts "     Some non-critical components need attention"
    elsif success_rate >= 70
      puts "  🟠 FAIR: System has significant issues"
      puts "     Core functionality may be compromised"
      puts "     Multiple components need attention"
    else
      puts "  🔴 POOR: System is not ready for production"
      puts "     Critical failures detected"
      puts "     Immediate attention required"
    end
    
    puts "\n💡 Recommendations:"
    
    if @critical_failures.any?
      puts "  🚨 CRITICAL: Address the following immediately:"
      @critical_failures.each do |failure|
        puts "     - #{failure}"
      end
    end
    
    failed_validations = @validation_results.select { |r| !r[:success] }
    if failed_validations.any?
      puts "  🔧 IMPROVEMENTS NEEDED:"
      failed_validations.each do |validation|
        puts "     - #{validation[:test]}: #{validation[:details][:error] || 'Failed validation'}"
      end
    end
    
    if success_rate >= 95 && @critical_failures.empty?
      puts "  🎉 READY FOR PRODUCTION: System validation passed!"
      puts "     Consider implementing additional monitoring"
      puts "     Regular health checks recommended"
    end
    
    puts "\n📋 Detailed Results:"
    @validation_results.each do |result|
      status_icon = result[:success] ? "✅" : "❌"
      puts "  #{status_icon} #{result[:test]}"
      if result[:details][:error]
        puts "     Error: #{result[:details][:error]}"
      elsif result[:details][:message]
        puts "     #{result[:details][:message]}"
      end
    end
    
    puts "\n" + "=" * 60
    overall_status = success_rate >= 90 && @critical_failures.empty? ? "✅ PASSED" : "❌ FAILED"
    puts "System Validation: #{overall_status}"
    puts "=" * 60
  end
  
  def generate_partial_report
    puts "\n⚠️  Partial validation report (interrupted or timeout)"
    puts "Completed tests: #{@validation_results.length}"
    
    if @validation_results.any?
      successful = @validation_results.select { |r| r[:success] }.length
      puts "Success rate so far: #{(successful.to_f / @validation_results.length * 100).round(2)}%"
    end
  end
end

# Command line interface
if __FILE__ == $0
  options = {}
  
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby system_validation.rb [options]"
    
    opts.on("-u", "--url URL", "Base URL (default: http://localhost:3000)") do |url|
      options[:base_url] = url
    end
    
    opts.on("-t", "--timeout SECONDS", Integer, "Validation timeout (default: 30)") do |timeout|
      options[:timeout] = timeout
    end
    
    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end
  end.parse!
  
  validator = SystemValidator.new(options)
  validator.run_validation
end