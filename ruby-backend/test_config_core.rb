#!/usr/bin/env ruby

# Core Configuration Management System Test
# Tests basic functionality without external dependencies

require 'yaml'
require 'fileutils'

# Set test environment
ENV['APP_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test_secret_key_for_configuration_testing'

puts "Spotik Ruby Backend - Configuration Management System Test"
puts "=" * 60

def test_yaml_files
  puts "\n1. Testing YAML configuration files..."
  
  config_dir = File.join(File.dirname(__FILE__), 'config')
  files_to_check = ['default.yml', 'development.yml', 'production.yml', 'test.yml']
  
  files_to_check.each do |file|
    file_path = File.join(config_dir, file)
    if File.exist?(file_path)
      puts "✓ #{file} exists"
      
      begin
        config = YAML.load_file(file_path)
        puts "  - Valid YAML with #{config.keys.length} top-level keys: #{config.keys.join(', ')}"
      rescue => e
        puts "  - ❌ Invalid YAML: #{e.message}"
        return false
      end
    else
      puts "❌ #{file} missing"
      return false
    end
  end
  
  true
end

def test_storage_directories
  puts "\n2. Testing storage directory creation..."
  
  # Test storage paths
  storage_paths = {
    'audio' => './storage/test/audio',
    'public' => './storage/test/public', 
    'temp' => './storage/test/temp'
  }
  
  storage_paths.each do |type, path|
    begin
      FileUtils.mkdir_p(path) unless File.exist?(path)
      
      # Test write access
      test_file = File.join(path, '.config_test')
      File.write(test_file, 'test')
      File.delete(test_file)
      
      puts "✓ #{type} storage path accessible: #{path}"
    rescue => e
      puts "❌ #{type} storage path not accessible: #{path} (#{e.message})"
      return false
    end
  end
  
  true
end

def test_environment_variables
  puts "\n3. Testing environment variable handling..."
  
  # Test basic environment variables
  test_vars = {
    'APP_NAME' => 'TestApp',
    'SERVER_PORT' => '4000',
    'APP_DEBUG' => 'true'
  }
  
  # Save original values
  original_values = {}
  test_vars.each { |key, _| original_values[key] = ENV[key] }
  
  begin
    # Set test values
    test_vars.each { |key, value| ENV[key] = value }
    
    puts "✓ Environment variables set:"
    test_vars.each { |key, value| puts "  - #{key}=#{value}" }
    
    # Test access
    puts "✓ Environment variable access:"
    puts "  - APP_NAME: #{ENV['APP_NAME']}"
    puts "  - SERVER_PORT: #{ENV['SERVER_PORT']}"
    puts "  - APP_DEBUG: #{ENV['APP_DEBUG']}"
    
  ensure
    # Restore original values
    original_values.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
  end
  
  true
end

def test_configuration_manager_basic
  puts "\n4. Testing Configuration Manager basic functionality..."
  
  begin
    # Load the configuration manager
    require_relative 'config/configuration_manager'
    
    puts "✓ Configuration Manager loaded successfully"
    
    # Test initialization
    config_data = SpotikConfig::ConfigurationManager.initialize_configuration
    puts "✓ Configuration initialized"
    puts "  - Top-level keys: #{config_data.keys.join(', ')}"
    
    # Test basic access
    app_name = SpotikConfig::ConfigurationManager.get('app.name', 'DefaultApp')
    puts "✓ Configuration access works: app.name = #{app_name}"
    
    # Test default values
    non_existent = SpotikConfig::ConfigurationManager.get('non.existent.key', 'default_value')
    puts "✓ Default value handling: #{non_existent}"
    
    # Test health check
    health = SpotikConfig::ConfigurationManager.configuration_health
    puts "✓ Configuration health: #{health[:status]}"
    
    if health[:errors] && health[:errors].any?
      puts "⚠ Configuration errors:"
      health[:errors].each { |error| puts "  - #{error}" }
    end
    
    if health[:warnings] && health[:warnings].any?
      puts "⚠ Configuration warnings:"
      health[:warnings].each { |warning| puts "  - #{warning}" }
    end
    
    # Test configuration summary
    summary = SpotikConfig::ConfigurationManager.get_configuration_summary
    puts "✓ Configuration summary generated"
    puts "  - App: #{summary[:app][:name]} (#{summary[:app][:environment]})"
    puts "  - Server: #{summary[:server][:host]}:#{summary[:server][:port]}"
    
    return true
    
  rescue => e
    puts "❌ Configuration Manager test failed: #{e.message}"
    puts "Backtrace:"
    puts e.backtrace.first(3).map { |line| "  #{line}" }
    return false
  end
end

def test_health_controller_basic
  puts "\n5. Testing Health Controller basic functionality..."
  
  begin
    # Load the health controller
    require_relative 'app/controllers/health_controller'
    
    puts "✓ Health Controller loaded successfully"
    
    # Test basic health check
    basic_health = HealthController.basic_health
    puts "✓ Basic health check: #{basic_health[:body][:status]} (HTTP #{basic_health[:status]})"
    
    # Test liveness check
    liveness = HealthController.liveness_check
    puts "✓ Liveness check: #{liveness[:body][:alive] ? 'alive' : 'not alive'} (HTTP #{liveness[:status]})"
    
    return true
    
  rescue => e
    puts "❌ Health Controller test failed: #{e.message}"
    puts "Backtrace:"
    puts e.backtrace.first(3).map { |line| "  #{line}" }
    return false
  end
end

# Run all tests
success = true

success = test_yaml_files && success
success = test_storage_directories && success  
success = test_environment_variables && success
success = test_configuration_manager_basic && success
success = test_health_controller_basic && success

puts "\n" + "=" * 60
if success
  puts "🎉 All core configuration tests passed!"
  puts "Configuration management system is working correctly."
  exit 0
else
  puts "💥 Some tests failed. Please check the configuration system."
  exit 1
end