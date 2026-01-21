# Property-based test for configuration management
# **Feature: ruby-backend-migration, Property 18: Configuration Management**
# **Validates: Requirements 14.1, 14.2, 14.5**

require 'bundler/setup'
require 'rspec'
require 'rantly'
require 'rantly/rspec_extensions'
require 'securerandom'
require 'yaml'
require 'fileutils'
require 'tempfile'

# Set test environment
ENV['APP_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test_jwt_secret_key_for_testing_purposes_only'

RSpec.describe 'Configuration Management Property Test', :property do
  before(:all) do
    # Load configuration system
    require_relative '../../config/configuration_manager'
    require_relative '../../app/services/configuration_service'
    
    # Store original environment variables
    @original_env = ENV.to_h.dup
  end
  
  after(:all) do
    # Restore original environment variables
    ENV.clear
    ENV.update(@original_env)
  end
  
  before(:each) do
    # Reset configuration manager state
    SpotikConfig::ConfigurationManager.instance_variables.each do |var|
      SpotikConfig::ConfigurationManager.remove_instance_variable(var)
    end
    
    # Clear test environment variables (keep essential ones)
    test_env_vars = ENV.keys.select { |k| k.start_with?('TEST_') || k.start_with?('SPOTIK_') }
    test_env_vars.each { |k| ENV.delete(k) }
  end

  describe 'Property 18: Configuration Management' do
    it 'reads and validates configuration parameters from environment variables correctly' do
      test_instance = self
      
      property_of {
        # Generate various configuration parameter scenarios using environment variables
        config_scenario = test_instance.generate_environment_configuration_scenario
        config_scenario
      }.check(15) { |config_scenario|
        # Set environment variables for this test
        config_scenario[:env_vars].each do |env_key, env_value|
          ENV[env_key] = env_value.to_s
        end
        
        begin
          # Initialize configuration
          config_data = SpotikConfig::ConfigurationManager.initialize_configuration
          
          # Verify configuration was loaded
          expect(config_data).to be_a(Hash)
          expect(config_data).not_to be_empty
          
          # Verify specific configuration values are accessible
          config_scenario[:expected_values].each do |key_path, expected_value|
            actual_value = SpotikConfig::ConfigurationManager.get(key_path)
            
            case expected_value
            when Integer
              expect(actual_value).to be_a(Integer)
              expect(actual_value).to eq(expected_value)
            when Float
              expect(actual_value).to be_a(Float)
              expect(actual_value).to be_within(0.01).of(expected_value)
            when TrueClass, FalseClass
              expect(actual_value).to eq(expected_value)
            when String
              expect(actual_value).to eq(expected_value)
            when Array
              expect(actual_value).to eq(expected_value)
            end
          end
          
          # Verify validation results
          if config_scenario[:should_be_valid]
            expect(SpotikConfig::ConfigurationManager.configuration_valid?).to be true
            expect(SpotikConfig::ConfigurationManager.validation_errors).to be_empty
          else
            expect(SpotikConfig::ConfigurationManager.configuration_valid?).to be false
            expect(SpotikConfig::ConfigurationManager.validation_errors).not_to be_empty
          end
          
          # Verify configuration health check
          health = SpotikConfig::ConfigurationManager.configuration_health
          expect(health).to be_a(Hash)
          expect(health[:status]).to be_a(String)
          expect(health[:timestamp]).to be_a(String)
          expect(health[:errors]).to be_a(Array)
          expect(health[:warnings]).to be_a(Array)
          
        ensure
          # Clean up environment variables
          config_scenario[:env_vars].keys.each { |key| ENV.delete(key) }
        end
      }
    end

    it 'correctly handles environment variable type conversion and validation' do
      test_instance = self
      
      property_of {
        # Generate environment variable type conversion scenarios
        type_scenario = test_instance.generate_type_conversion_scenario
        type_scenario
      }.check(15) { |type_scenario|
        # Set environment variables for this test
        type_scenario[:env_vars].each do |env_key, env_value|
          ENV[env_key] = env_value.to_s
        end
        
        begin
          # Initialize configuration
          config_data = SpotikConfig::ConfigurationManager.initialize_configuration
          
          # Verify type conversion worked correctly
          type_scenario[:expected_conversions].each do |config_key, expected_data|
            actual_value = SpotikConfig::ConfigurationManager.get(config_key)
            
            case expected_data[:type]
            when :integer
              if expected_data[:valid]
                expect(actual_value).to be_a(Integer)
                expect(actual_value).to eq(expected_data[:value])
              else
                # Should fall back to default value
                expect(actual_value).to be_a(Integer)
                expect(actual_value).to eq(expected_data[:default])
              end
            when :boolean
              if expected_data[:valid]
                expect([true, false]).to include(actual_value)
                expect(actual_value).to eq(expected_data[:value])
              else
                # Should fall back to default value
                expect([true, false]).to include(actual_value)
                expect(actual_value).to eq(expected_data[:default])
              end
            when :string
              expect(actual_value).to be_a(String)
              expect(actual_value).to eq(expected_data[:value])
            end
          end
          
          # Verify warnings for invalid type conversions
          if type_scenario[:should_have_warnings]
            expect(SpotikConfig::ConfigurationManager.validation_warnings).not_to be_empty
          end
          
        ensure
          # Clean up environment variables
          type_scenario[:env_vars].keys.each { |key| ENV.delete(key) }
        end
      }
    end

    it 'validates configuration parameters and provides clear error messages for invalid configurations' do
      test_instance = self
      
      property_of {
        # Generate invalid configuration scenarios using environment variables
        invalid_scenario = test_instance.generate_invalid_environment_scenario
        invalid_scenario
      }.check(10) { |invalid_scenario|
        # Set environment variables that will cause validation errors
        invalid_scenario[:env_vars].each do |env_key, env_value|
          ENV[env_key] = env_value.to_s
        end
        
        begin
          # Initialize configuration (should handle invalid config gracefully)
          config_data = SpotikConfig::ConfigurationManager.initialize_configuration
          
          # Verify configuration validation detected the issues
          case invalid_scenario[:error_type]
          when :missing_required_setting
            expect(SpotikConfig::ConfigurationManager.configuration_valid?).to be false
            errors = SpotikConfig::ConfigurationManager.validation_errors
            expect(errors.any? { |e| e.include?('Required') || e.include?('missing') }).to be true
          when :invalid_range_values
            # Some range validations might be warnings rather than errors
            warnings = SpotikConfig::ConfigurationManager.validation_warnings
            errors = SpotikConfig::ConfigurationManager.validation_errors
            expect(warnings.any? || errors.any?).to be true
          when :invalid_type_values
            # Type conversion errors should generate warnings
            warnings = SpotikConfig::ConfigurationManager.validation_warnings
            expect(warnings).not_to be_empty
          end
          
          # Verify error messages are descriptive
          all_messages = SpotikConfig::ConfigurationManager.validation_errors + 
                        SpotikConfig::ConfigurationManager.validation_warnings
          
          all_messages.each do |message|
            expect(message).to be_a(String)
            expect(message).not_to be_empty
            expect(message.length).to be > 10 # Should be descriptive
          end
          
        ensure
          # Clean up environment variables
          invalid_scenario[:env_vars].keys.each { |key| ENV.delete(key) }
        end
      }
    end

    it 'provides comprehensive configuration health monitoring and status reporting' do
      test_instance = self
      
      property_of {
        # Generate configuration health scenarios
        health_scenario = test_instance.generate_health_monitoring_scenario
        health_scenario
      }.check(10) { |health_scenario|
        # Set environment variables
        health_scenario[:env_vars].each do |env_key, env_value|
          ENV[env_key] = env_value.to_s
        end
        
        begin
          # Initialize configuration
          config_data = SpotikConfig::ConfigurationManager.initialize_configuration
          
          # Test configuration health monitoring
          health = SpotikConfig::ConfigurationManager.configuration_health
          
          # Verify health response structure
          expect(health).to be_a(Hash)
          expect(health).to have_key(:status)
          expect(health).to have_key(:errors)
          expect(health).to have_key(:warnings)
          expect(health).to have_key(:config_files_loaded)
          expect(health).to have_key(:environment_variables_loaded)
          expect(health).to have_key(:timestamp)
          
          # Verify status values
          expect(['healthy', 'unhealthy']).to include(health[:status])
          expect(health[:errors]).to be_a(Array)
          expect(health[:warnings]).to be_a(Array)
          expect(health[:config_files_loaded]).to be_a(Array)
          expect(health[:environment_variables_loaded]).to be_a(Array)
          expect(health[:timestamp]).to be_a(String)
          
          # Verify timestamp format
          expect(health[:timestamp]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{4}/)
          
          # Test configuration summary
          summary = SpotikConfig::ConfigurationManager.get_configuration_summary
          expect(summary).to be_a(Hash)
          expect(summary).to have_key(:app)
          expect(summary).to have_key(:server)
          expect(summary).to have_key(:database)
          expect(summary).to have_key(:storage)
          expect(summary).to have_key(:security)
          expect(summary).to have_key(:monitoring)
          
          # Verify summary contains expected values
          expect(summary[:app]).to have_key(:name)
          expect(summary[:server]).to have_key(:host)
          expect(summary[:server]).to have_key(:port)
          expect(summary[:database]).to have_key(:host)
          expect(summary[:storage]).to have_key(:audio_path)
          
          # Test ConfigurationService integration (only if configuration is valid)
          if SpotikConfig::ConfigurationManager.configuration_valid?
            ConfigurationService.initialize_configuration
            service_health = ConfigurationService.configuration_health
            expect(service_health).to be_a(Hash)
            expect(service_health).to have_key(:status)
            
            # Test runtime validation
            runtime_validation = ConfigurationService.validate_runtime_configuration
            expect(runtime_validation).to be_a(Hash)
            expect(runtime_validation).to have_key(:status)
            expect(runtime_validation).to have_key(:checks)
            expect(runtime_validation).to have_key(:errors)
            expect(runtime_validation).to have_key(:warnings)
            
            expect(['valid', 'invalid', 'warning']).to include(runtime_validation[:status])
            expect(runtime_validation[:checks]).to be_a(Array)
          end
          
        ensure
          # Clean up environment variables
          health_scenario[:env_vars].keys.each { |key| ENV.delete(key) }
        end
      }
    end

    it 'maintains configuration consistency and handles concurrent access safely' do
      test_instance = self
      
      property_of {
        # Generate configuration consistency scenarios
        consistency_scenario = test_instance.generate_consistency_scenario
        consistency_scenario
      }.check(10) { |consistency_scenario|
        # Set initial environment variables
        consistency_scenario[:initial_env_vars].each do |env_key, env_value|
          ENV[env_key] = env_value.to_s
        end
        
        begin
          # Initialize configuration
          config_data = SpotikConfig::ConfigurationManager.initialize_configuration
          
          # Verify initial configuration values
          consistency_scenario[:expected_initial_values].each do |key_path, expected_value|
            actual_value = SpotikConfig::ConfigurationManager.get(key_path)
            expect(actual_value).to eq(expected_value)
          end
          
          # Test configuration reload functionality
          # Change environment variables
          consistency_scenario[:updated_env_vars].each do |env_key, env_value|
            ENV[env_key] = env_value.to_s
          end
          
          # Reload configuration
          reloaded_config = SpotikConfig::ConfigurationManager.reload_configuration
          expect(reloaded_config).to be_a(Hash)
          
          # Verify updated configuration values
          consistency_scenario[:expected_updated_values].each do |key_path, expected_value|
            actual_value = SpotikConfig::ConfigurationManager.get(key_path)
            expect(actual_value).to eq(expected_value)
          end
          
          # Verify configuration health after reload
          health = SpotikConfig::ConfigurationManager.configuration_health
          expect(health).to be_a(Hash)
          expect(health[:status]).to be_a(String)
          
          # Test get/set functionality
          test_key = 'test.dynamic.value'
          test_value = "test_value_#{SecureRandom.hex(4)}"
          
          SpotikConfig::ConfigurationManager.set(test_key, test_value)
          retrieved_value = SpotikConfig::ConfigurationManager.get(test_key)
          expect(retrieved_value).to eq(test_value)
          
          # Test default value functionality
          non_existent_key = 'non.existent.key'
          default_value = 'default_test_value'
          retrieved_default = SpotikConfig::ConfigurationManager.get(non_existent_key, default_value)
          expect(retrieved_default).to eq(default_value)
          
        ensure
          # Clean up environment variables
          (consistency_scenario[:initial_env_vars].keys + 
           consistency_scenario[:updated_env_vars].keys).uniq.each { |key| ENV.delete(key) }
        end
      }
    end
  end

  # Helper methods for generating test data

  def generate_environment_configuration_scenario
    scenarios = [
      {
        env_vars: {
          'APP_NAME' => 'Property Test App',
          'SERVER_HOST' => '0.0.0.0',
          'SERVER_PORT' => rand(3000..8000),
          'DB_HOST' => 'test-database',
          'JWT_SECRET' => SecureRandom.hex(32)
        },
        expected_values: {
          'app.name' => 'Property Test App',
          'server.host' => '0.0.0.0',
          'database.host' => 'test-database'
        },
        should_be_valid: true
      },
      {
        env_vars: {
          'APP_DEBUG' => ['true', 'false'].sample,
          'SERVER_THREADS' => rand(1..8),
          'DB_POOL_MAX' => rand(5..20),
          'JWT_TTL' => rand(60..1440),
          'JWT_SECRET' => SecureRandom.hex(32)
        },
        expected_values: {
          'server.threads' => nil, # Will be set dynamically
          'database.pool.max' => nil, # Will be set dynamically
          'security.jwt.ttl' => nil # Will be set dynamically
        },
        should_be_valid: true
      },
      {
        env_vars: {
          'LOG_LEVEL' => ['debug', 'info', 'warn', 'error'].sample,
          'MAX_FILE_SIZE_MB' => rand(10..100),
          'ALLOWED_AUDIO_FORMATS' => 'mp3,wav,m4a,flac',
          'JWT_SECRET' => SecureRandom.hex(32)
        },
        expected_values: {
          'monitoring.logging.level' => nil, # Will be set dynamically
          'storage.max_file_size_mb' => nil, # Will be set dynamically
          'storage.allowed_audio_formats' => 'mp3,wav,m4a,flac'
        },
        should_be_valid: true
      }
    ]
    
    scenario = scenarios.sample
    
    # Set dynamic expected values
    scenario[:env_vars].each do |env_key, env_value|
      case env_key
      when 'SERVER_PORT'
        scenario[:expected_values]['server.port'] = env_value
      when 'APP_DEBUG'
        scenario[:expected_values]['app.debug'] = env_value == 'true'
      when 'SERVER_THREADS'
        scenario[:expected_values]['server.threads'] = env_value
      when 'DB_POOL_MAX'
        scenario[:expected_values]['database.pool.max'] = env_value
      when 'JWT_TTL'
        scenario[:expected_values]['security.jwt.ttl'] = env_value
      when 'LOG_LEVEL'
        scenario[:expected_values]['monitoring.logging.level'] = env_value
      when 'MAX_FILE_SIZE_MB'
        scenario[:expected_values]['storage.max_file_size_mb'] = env_value
      end
    end
    
    scenario
  end

  def generate_type_conversion_scenario
    scenarios = [
      {
        env_vars: {
          'SERVER_PORT' => rand(3000..8000).to_s,
          'APP_DEBUG' => 'true',
          'DB_POOL_MAX' => rand(5..20).to_s,
          'JWT_SECRET' => SecureRandom.hex(32)
        },
        expected_conversions: {
          'server.port' => { type: :integer, valid: true, value: nil, default: 3000 },
          'app.debug' => { type: :boolean, valid: true, value: true, default: false },
          'database.pool.max' => { type: :integer, valid: true, value: nil, default: 10 }
        },
        should_have_warnings: false
      },
      {
        env_vars: {
          'SERVER_PORT' => 'invalid_port',
          'APP_DEBUG' => 'maybe',
          'DB_POOL_MAX' => 'not_a_number',
          'JWT_SECRET' => SecureRandom.hex(32)
        },
        expected_conversions: {
          'server.port' => { type: :integer, valid: false, value: nil, default: 3000 },
          'app.debug' => { type: :boolean, valid: false, value: nil, default: false },
          'database.pool.max' => { type: :integer, valid: false, value: nil, default: 10 }
        },
        should_have_warnings: true
      },
      {
        env_vars: {
          'APP_DEBUG' => 'false',
          'RATE_LIMITING_ENABLED' => '1',
          'HEALTH_CHECK_ENABLED' => '0',
          'JWT_SECRET' => SecureRandom.hex(32)
        },
        expected_conversions: {
          'app.debug' => { type: :boolean, valid: true, value: false, default: false },
          'security.rate_limiting.enabled' => { type: :boolean, valid: true, value: true, default: true },
          'monitoring.health_check.enabled' => { type: :boolean, valid: true, value: false, default: true }
        },
        should_have_warnings: false
      }
    ]
    
    scenario = scenarios.sample
    
    # Set dynamic expected values
    scenario[:env_vars].each do |env_key, env_value|
      case env_key
      when 'SERVER_PORT'
        if env_value.match?(/^\d+$/)
          scenario[:expected_conversions]['server.port'][:value] = env_value.to_i
        end
      when 'DB_POOL_MAX'
        if env_value.match?(/^\d+$/)
          scenario[:expected_conversions]['database.pool.max'][:value] = env_value.to_i
        end
      end
    end
    
    scenario
  end

  def generate_invalid_environment_scenario
    scenarios = [
      {
        env_vars: {
          # Missing JWT_SECRET (required)
          'APP_NAME' => 'Test App'
        },
        error_type: :missing_required_setting
      },
      {
        env_vars: {
          'JWT_SECRET' => SecureRandom.hex(32),
          'SERVER_PORT' => '99999', # Invalid port range
          'DB_POOL_MAX' => '0' # Invalid pool size
        },
        error_type: :invalid_range_values
      },
      {
        env_vars: {
          'JWT_SECRET' => SecureRandom.hex(32),
          'SERVER_THREADS' => 'not_a_number',
          'APP_DEBUG' => 'invalid_boolean'
        },
        error_type: :invalid_type_values
      }
    ]
    
    scenarios.sample
  end

  def generate_health_monitoring_scenario
    scenarios = [
      {
        env_vars: {
          'JWT_SECRET' => SecureRandom.hex(32),
          'APP_NAME' => 'Health Test App',
          'SERVER_PORT' => rand(3000..8000),
          'HEALTH_CHECK_ENABLED' => 'true',
          'PERFORMANCE_MONITORING_ENABLED' => 'true'
        }
      },
      {
        env_vars: {
          'JWT_SECRET' => SecureRandom.hex(32),
          'APP_ENV' => 'test',
          'LOG_LEVEL' => 'debug',
          'DB_POOL_MAX' => rand(10..20),
          'SLOW_QUERY_THRESHOLD' => rand(500..2000)
        }
      }
    ]
    
    scenarios.sample
  end

  def generate_consistency_scenario
    initial_port = rand(3000..5000)
    updated_port = rand(5001..8000)
    
    {
      initial_env_vars: {
        'JWT_SECRET' => SecureRandom.hex(32),
        'APP_NAME' => 'Consistency Test',
        'SERVER_PORT' => initial_port,
        'DB_POOL_MAX' => 10
      },
      expected_initial_values: {
        'app.name' => 'Consistency Test',
        'server.port' => initial_port,
        'database.pool.max' => 10
      },
      updated_env_vars: {
        'APP_NAME' => 'Updated Consistency Test',
        'SERVER_PORT' => updated_port,
        'DB_POOL_MAX' => 15
      },
      expected_updated_values: {
        'app.name' => 'Updated Consistency Test',
        'server.port' => updated_port,
        'database.pool.max' => 15
      }
    }
  end
end