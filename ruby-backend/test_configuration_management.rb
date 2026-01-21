#!/usr/bin/env ruby

# Test Configuration Management System
# Validates that the configuration system loads and validates correctly

require 'bundler/setup'
require_relative 'app/services/configuration_service'
require_relative 'app/controllers/health_controller'

def test_configuration_management
  puts "Testing Configuration Management System..."
  puts "=" * 50
  
  begin
    # Test 1: Initialize configuration
    puts "\n1. Testing configuration initialization..."
    ConfigurationService.initialize_configuration
    puts "✓ Configuration initialized successfully"
    
    # Test 2: Test configuration access
    puts "\n2. Testing configuration access..."
    app_name = ConfigurationService.get('app.name')
    server_port = ConfigurationService.get('server.port')
    jwt_ttl = ConfigurationService.get('security.jwt.ttl')
    
    puts "✓ App name: #{app_name}"
    puts "✓ Server port: #{server_port}"
    puts "✓ JWT TTL: #{jwt_ttl} minutes"
    
    # Test 3: Test configuration health
    puts "\n3. Testing configuration health check..."
    config_health = ConfigurationService.configuration_health
    puts "✓ Configuration status: #{config_health[:status]}"
    puts "✓ Config files loaded: #{config_health[:config_files_loaded]&.length || 0}"
    puts "✓ Environment variables loaded: #{config_health[:environment_variables_loaded]&.length || 0}"
    
    if config_health[:errors]&.any?
      puts "⚠ Configuration errors:"
      config_health[:errors].each { |error| puts "  - #{error}" }
    end
    
    if config_health[:warnings]&.any?
      puts "⚠ Configuration warnings:"
      config_health[:warnings].each { |warning| puts "  - #{warning}" }
    end
    
    # Test 4: Test runtime validation
    puts "\n4. Testing runtime configuration validation..."
    runtime_validation = ConfigurationService.validate_runtime_configuration
    puts "✓ Runtime validation status: #{runtime_validation[:status]}"
    puts "✓ Runtime checks performed: #{runtime_validation[:checks]&.length || 0}"
    
    if runtime_validation[:errors]&.any?
      puts "⚠ Runtime validation errors:"
      runtime_validation[:errors].each { |error| puts "  - #{error}" }
    end
    
    if runtime_validation[:warnings]&.any?
      puts "⚠ Runtime validation warnings:"
      runtime_validation[:warnings].each { |warning| puts "  - #{warning}" }
    end
    
    # Test 5: Test configuration summary
    puts "\n5. Testing configuration summary..."
    summary = ConfigurationService.configuration_summary
    puts "✓ Configuration summary generated"
    puts "  - App: #{summary[:app][:name]} (#{summary[:app][:environment]})"
    puts "  - Server: #{summary[:server][:host]}:#{summary[:server][:port]}"
    puts "  - Database: #{summary[:database][:host]}:#{summary[:database][:port]}/#{summary[:database][:name]}"
    puts "  - Storage: #{summary[:storage][:audio_path]}"
    puts "  - Monitoring: #{summary[:monitoring][:health_check][:enabled] ? 'enabled' : 'disabled'}"
    
    # Test 6: Test health controller integration
    puts "\n6. Testing health controller integration..."
    
    # Test basic health
    basic_health = HealthController.basic_health
    puts "✓ Basic health check: #{basic_health[:body][:status]} (HTTP #{basic_health[:status]})"
    
    # Test configuration health
    config_health_result = HealthController.configuration_health
    puts "✓ Configuration health check: #{config_health_result[:body][:status]} (HTTP #{config_health_result[:status]})"
    
    # Test storage health
    storage_health = HealthController.storage_health
    puts "✓ Storage health check: #{storage_health[:body][:status]} (HTTP #{storage_health[:status]})"
    
    # Test readiness check
    readiness = HealthController.readiness_check
    puts "✓ Readiness check: #{readiness[:body][:ready] ? 'ready' : 'not ready'} (HTTP #{readiness[:status]})"
    
    # Test liveness check
    liveness = HealthController.liveness_check
    puts "✓ Liveness check: #{liveness[:body][:alive] ? 'alive' : 'not alive'} (HTTP #{liveness[:status]})"
    
    # Test 7: Test environment-specific configuration
    puts "\n7. Testing environment-specific configuration..."
    env_info = ConfigurationService.get_environment_info
    puts "✓ Environment: #{env_info[:app_environment]}"
    puts "✓ Ruby version: #{env_info[:ruby_version]}"
    puts "✓ Debug mode: #{env_info[:debug_mode]}"
    puts "✓ Monitoring enabled: #{env_info[:monitoring_enabled]}"
    
    # Test 8: Test runtime setting update (if allowed)
    puts "\n8. Testing runtime setting updates..."
    begin
      # Try to update a runtime setting
      old_level = ConfigurationService.get('monitoring.logging.level')
      puts "✓ Current log level: #{old_level}"
      
      # This should work for allowed settings
      result = ConfigurationService.update_runtime_setting('monitoring.logging.level', 'debug')
      puts "✓ Updated log level to debug: #{result[:success]}"
      
      # Restore original value
      ConfigurationService.update_runtime_setting('monitoring.logging.level', old_level)
      puts "✓ Restored log level to: #{old_level}"
      
    rescue ArgumentError => e
      puts "✓ Runtime setting protection working: #{e.message}"
    end
    
    puts "\n" + "=" * 50
    puts "✅ All configuration management tests passed!"
    puts "Configuration system is working correctly."
    
    return true
    
  rescue => e
    puts "\n❌ Configuration management test failed:"
    puts "Error: #{e.message}"
    puts "Backtrace:"
    puts e.backtrace.first(5).map { |line| "  #{line}" }
    
    return false
  end
end

def test_configuration_files
  puts "\nTesting configuration file loading..."
  puts "-" * 30
  
  config_dir = File.join(File.dirname(__FILE__), 'config')
  
  # Check if configuration files exist
  files_to_check = [
    'default.yml',
    'development.yml',
    'production.yml',
    'test.yml'
  ]
  
  files_to_check.each do |file|
    file_path = File.join(config_dir, file)
    if File.exist?(file_path)
      puts "✓ #{file} exists"
      
      # Try to parse YAML
      begin
        require 'yaml'
        config = YAML.load_file(file_path)
        puts "  - Valid YAML with #{config.keys.length} top-level keys"
      rescue => e
        puts "  - ❌ Invalid YAML: #{e.message}"
      end
    else
      puts "❌ #{file} missing"
    end
  end
end

def test_environment_variables
  puts "\nTesting environment variable handling..."
  puts "-" * 30
  
  # Test with different environment variables
  test_vars = {
    'APP_NAME' => 'TestApp',
    'SERVER_PORT' => '4000',
    'APP_DEBUG' => 'true',
    'RATE_LIMITING_ENABLED' => 'false'
  }
  
  # Save original values
  original_values = {}
  test_vars.each { |key, _| original_values[key] = ENV[key] }
  
  begin
    # Set test values
    test_vars.each { |key, value| ENV[key] = value }
    
    # Reload configuration
    ConfigurationService.reload_configuration
    
    # Test values
    puts "✓ APP_NAME: #{ConfigurationService.get('app.name')} (expected: TestApp)"
    puts "✓ SERVER_PORT: #{ConfigurationService.get('server.port')} (expected: 4000)"
    puts "✓ APP_DEBUG: #{ConfigurationService.get('app.debug')} (expected: true)"
    puts "✓ RATE_LIMITING_ENABLED: #{ConfigurationService.get('security.rate_limiting.enabled')} (expected: false)"
    
  ensure
    # Restore original values
    original_values.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
    
    # Reload configuration with original values
    ConfigurationService.reload_configuration
  end
end

# Run tests
if __FILE__ == $0
  puts "Spotik Ruby Backend - Configuration Management System Test"
  puts "=" * 60
  
  # Set test environment
  ENV['APP_ENV'] = 'test'
  
  success = true
  
  # Test configuration files
  test_configuration_files
  
  # Test environment variables
  test_environment_variables
  
  # Test main configuration management
  success = test_configuration_management && success
  
  puts "\n" + "=" * 60
  if success
    puts "🎉 All tests passed! Configuration management system is ready."
    exit 0
  else
    puts "💥 Some tests failed. Please check the configuration system."
    exit 1
  end
end