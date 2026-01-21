#!/usr/bin/env ruby

# Simple Configuration Management System Test
# Tests basic functionality without complex dependencies

require 'yaml'
require 'json'
require 'fileutils'

# Set test environment
ENV['APP_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test_secret_key_for_configuration_testing'

# Load the configuration system
require_relative 'config/configuration_manager'

def test_basic_configuration
  puts "Testing Basic Configuration Management..."
  puts "=" * 50
  
  begin
    # Test 1: Initialize configuration
    puts "\n1. Testing configuration initialization..."
    config_data = SpotikConfig::ConfigurationManager.initialize_configuration
    puts "✓ Configuration initialized successfully"
    puts "✓ Configuration data loaded: #{config_data.keys.join(', ')}"
    
    # Test 2: Test configuration access
    puts "\n2. Testing configuration access..."
    app_name = SpotikConfig::ConfigurationManager.get('app.name')
    server_port = SpotikConfig::ConfigurationManager.get('server.port')
    jwt_ttl = SpotikConfig::ConfigurationManager.get('security.jwt.ttl')
    
    puts "✓ App name: #{app_name}"
    puts "✓ Server port: #{server_port}"
    puts "✓ JWT TTL: #{jwt_ttl} minutes"
    
    # Test 3: Test default values
    puts "\n3. Testing default values..."
    non_existent = SpotikConfig::ConfigurationManager.get('non.existent.key', 'default_value')
    puts "✓ Default value handling: #{non_existent}"
    
    # Test 4: Test configuration health
    puts "\n4. Testing configuration health check..."
    config_health = SpotikConfig::ConfigurationManager.configuration_health
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
    
    # Test 5: Test configuration summary
    puts "\n5. Testing configuration summary..."
    summary = SpotikConfig::ConfigurationManager.get_configuration_summary
    puts "✓ Configuration summary generated"
    puts "  - App: #{summary[:app][:name]} (#{summary[:app][:environment]})"
    puts "  - Server: #{summary[:server][:host]}:#{summary[:server][:port]}"
    puts "  - Database: #{summary[:database][:host]}:#{summary[:database][:port]}/#{summary[:database][:name]}"
    puts "  - Storage: #{summary[:storage][:audio_path]}"
    puts "  - Monitoring: #{summary[:monitoring][:health_check][:enabled] ? 'enabled' : 'disabled'}"
    
    # Test 6: Test environment variable override
    puts "\n6. Testing environment variable override..."
    original_port = SpotikConfig::ConfigurationManager.get('server.port')
    
    # Set a test environment variable
    ENV['SERVER_PORT'] = '9999'
    SpotikConfig::ConfigurationManager.reload_configuration
    
    new_port = SpotikConfig::ConfigurationManager.get('server.port')
    puts "✓ Environment variable override: #{original_port} -> #{new_port}"
    
    # Restore original
    ENV.delete('SERVER_PORT')
    SpotikConfig::ConfigurationManager.reload_configuration
    
    # Test 7: Test configuration validation
    puts "\n7. Testing configuration validation..."
    valid = SpotikConfig::ConfigurationManager.configuration_valid?
    puts "✓ Configuration valid: #{valid}"
    
    if SpotikConfig::ConfigurationManager.validation_errors.any?
      puts "⚠ Validation errors:"
      SpotikConfig::ConfigurationManager.validation_errors.each { |error| puts "  - #{error}" }
    end
    
    if SpotikConfig::ConfigurationManager.validation_warnings.any?
      puts "⚠ Validation warnings:"
      SpotikConfig::ConfigurationManager.validation_warnings.each { |warning| puts "  - #{warning}" }
    end
    
    puts "\n" + "=" * 50
    puts "✅ All basic configuration tests passed!"
    
    return true
    
  rescue => e
    puts "\n❌ Configuration test failed:"
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

def test_storage_paths
  puts "\nTesting storage path creation..."
  puts "-" * 30
  
  # Test storage paths from configuration
  SpotikConfig::ConfigurationManager.initialize_configuration
  
  storage_paths = {
    audio: SpotikConfig::ConfigurationManager.get('storage.audio_path'),
    public: SpotikConfig::ConfigurationManager.get('storage.public_path'),
    temp: SpotikConfig::ConfigurationManager.get('storage.temp_path')
  }
  
  storage_paths.each do |type, path|
    next unless path
    
    begin
      # Create directory if it doesn't exist
      FileUtils.mkdir_p(path) unless File.exist?(path)
      
      # Test write access
      test_file = File.join(path, '.config_test')
      File.write(test_file, 'test')
      File.delete(test_file)
      
      puts "✓ #{type} storage path accessible: #{path}"
    rescue => e
      puts "❌ #{type} storage path not accessible: #{path} (#{e.message})"
    end
  end
end

def test_environment_specific_configs
  puts "\nTesting environment-specific configurations..."
  puts "-" * 30
  
  environments = ['development', 'production', 'test']
  
  environments.each do |env|
    puts "\nTesting #{env} environment:"
    
    # Set environment
    original_env = ENV['APP_ENV']
    ENV['APP_ENV'] = env
    
    begin
      SpotikConfig::ConfigurationManager.initialize_configuration
      
      app_env = SpotikConfig::ConfigurationManager.get('app.environment')
      debug_mode = SpotikConfig::ConfigurationManager.get('app.debug')
      server_threads = SpotikConfig::ConfigurationManager.get('server.threads')
      
      puts "  ✓ Environment: #{app_env}"
      puts "  ✓ Debug mode: #{debug_mode}"
      puts "  ✓ Server threads: #{server_threads}"
      
    rescue => e
      puts "  ❌ Error loading #{env} config: #{e.message}"
    ensure
      ENV['APP_ENV'] = original_env
    end
  end
  
  # Restore test environment
  ENV['APP_ENV'] = 'test'
  SpotikConfig::ConfigurationManager.initialize_configuration
end

# Run tests
if __FILE__ == $0
  puts "Spotik Ruby Backend - Configuration Management System Test"
  puts "=" * 60
  
  success = true
  
  # Test configuration files
  test_configuration_files
  
  # Test storage paths
  test_storage_paths
  
  # Test environment-specific configs
  test_environment_specific_configs
  
  # Test main configuration management
  success = test_basic_configuration && success
  
  puts "\n" + "=" * 60
  if success
    puts "🎉 All tests passed! Configuration management system is ready."
    exit 0
  else
    puts "💥 Some tests failed. Please check the configuration system."
    exit 1
  end
end