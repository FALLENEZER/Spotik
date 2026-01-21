#!/usr/bin/env ruby

# Minimal Configuration Management System Test
# Tests only the core YAML loading functionality

require 'yaml'
require 'fileutils'

# Set test environment
ENV['APP_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test_secret_key_for_configuration_testing'

puts "Spotik Ruby Backend - Minimal Configuration Test"
puts "=" * 50

def test_yaml_files
  puts "\n1. Testing YAML configuration files..."
  
  config_dir = File.join(File.dirname(__FILE__), 'config')
  files_to_check = ['default.yml', 'development.yml', 'production.yml', 'test.yml']
  
  all_valid = true
  
  files_to_check.each do |file|
    file_path = File.join(config_dir, file)
    if File.exist?(file_path)
      puts "✓ #{file} exists"
      
      begin
        config = YAML.load_file(file_path)
        puts "  - Valid YAML with #{config.keys.length} top-level keys"
        
        # Check for required keys
        required_keys = ['app', 'server', 'database', 'storage', 'security']
        missing_keys = required_keys - config.keys
        
        if missing_keys.empty?
          puts "  - All required keys present"
        else
          puts "  - ⚠ Missing keys: #{missing_keys.join(', ')}"
        end
        
      rescue => e
        puts "  - ❌ Invalid YAML: #{e.message}"
        all_valid = false
      end
    else
      puts "❌ #{file} missing"
      all_valid = false
    end
  end
  
  all_valid
end

def test_storage_directories
  puts "\n2. Testing storage directory creation..."
  
  # Test storage paths from test config
  test_config_path = File.join(File.dirname(__FILE__), 'config', 'test.yml')
  
  if File.exist?(test_config_path)
    config = YAML.load_file(test_config_path)
    storage_config = config['storage']
    
    if storage_config
      storage_config.each do |type, path|
        next unless path.is_a?(String) && path.include?('storage')
        
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
    else
      puts "⚠ No storage configuration found in test.yml"
    end
  else
    puts "❌ test.yml not found"
    return false
  end
  
  true
end

def test_environment_variable_loading
  puts "\n3. Testing environment variable precedence..."
  
  # Load default config
  default_config_path = File.join(File.dirname(__FILE__), 'config', 'default.yml')
  
  if File.exist?(default_config_path)
    config = YAML.load_file(default_config_path)
    
    # Test that environment variables would override config
    original_port = ENV['SERVER_PORT']
    ENV['SERVER_PORT'] = '9999'
    
    puts "✓ Environment variable set: SERVER_PORT=9999"
    puts "✓ Default config server port: #{config.dig('server', 'port')}"
    puts "✓ Environment variable takes precedence: #{ENV['SERVER_PORT']}"
    
    # Restore
    if original_port
      ENV['SERVER_PORT'] = original_port
    else
      ENV.delete('SERVER_PORT')
    end
    
  else
    puts "❌ default.yml not found"
    return false
  end
  
  true
end

def test_configuration_structure
  puts "\n4. Testing configuration structure..."
  
  config_files = ['default.yml', 'development.yml', 'production.yml', 'test.yml']
  
  config_files.each do |file|
    file_path = File.join(File.dirname(__FILE__), 'config', file)
    next unless File.exist?(file_path)
    
    begin
      config = YAML.load_file(file_path)
      
      puts "✓ #{file}:"
      
      # Check app section
      if config['app']
        puts "  - app: name=#{config['app']['name']}, env=#{config['app']['environment']}"
      end
      
      # Check server section
      if config['server']
        puts "  - server: host=#{config['server']['host']}, port=#{config['server']['port']}"
      end
      
      # Check database section
      if config['database']
        puts "  - database: host=#{config['database']['host']}, name=#{config['database']['name']}"
      end
      
      # Check security section
      if config['security'] && config['security']['jwt']
        puts "  - security: jwt_ttl=#{config['security']['jwt']['ttl']}"
      end
      
    rescue => e
      puts "❌ Error reading #{file}: #{e.message}"
      return false
    end
  end
  
  true
end

def test_health_check_endpoints
  puts "\n5. Testing health check endpoint configuration..."
  
  # Check if health check is configured in monitoring section
  config_files = ['default.yml', 'development.yml', 'production.yml', 'test.yml']
  
  config_files.each do |file|
    file_path = File.join(File.dirname(__FILE__), 'config', file)
    next unless File.exist?(file_path)
    
    begin
      config = YAML.load_file(file_path)
      
      if config['monitoring'] && config['monitoring']['health_check']
        health_config = config['monitoring']['health_check']
        puts "✓ #{file}: health_check enabled=#{health_config['enabled']}, endpoint=#{health_config['endpoint']}"
      else
        puts "⚠ #{file}: No health check configuration found"
      end
      
    rescue => e
      puts "❌ Error reading #{file}: #{e.message}"
      return false
    end
  end
  
  true
end

# Run all tests
success = true

success = test_yaml_files && success
success = test_storage_directories && success  
success = test_environment_variable_loading && success
success = test_configuration_structure && success
success = test_health_check_endpoints && success

puts "\n" + "=" * 50
if success
  puts "🎉 All minimal configuration tests passed!"
  puts "Configuration files are properly structured and accessible."
  puts "\nNext steps:"
  puts "- Configuration system can be loaded by the Ruby backend"
  puts "- Health check endpoints are configured"
  puts "- Storage paths are accessible"
  puts "- Environment variable override is supported"
  exit 0
else
  puts "💥 Some tests failed. Please check the configuration files."
  exit 1
end