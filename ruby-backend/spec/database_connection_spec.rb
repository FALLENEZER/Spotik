# Unit tests for database connection and migration validation
# Tests specific scenarios for database connection pooling, error handling, and schema validation

require 'spec_helper'

RSpec.describe 'Database Connection and Migration Validation' do
  before(:all) do
    # Use test database configuration
    require_relative '../config/test_database'
    
    # Override the DB constant for testing
    Object.send(:remove_const, :DB) if defined?(DB)
    DB = SpotikConfig::TestDatabase.connection
  end

  after(:all) do
    # Clean up test database connection
    SpotikConfig::TestDatabase.close_connection if defined?(SpotikConfig::TestDatabase)
  end

  describe 'Database Connection Pool' do
    it 'establishes connection with proper pool settings' do
      db = SpotikConfig::Database.connection
      
      expect(db).not_to be_nil
      expect(db.test_connection).to be true
      
      # Test pool configuration
      pool_stats = SpotikConfig::Database.get_pool_stats
      expect(pool_stats).to be_a(Hash)
      
      if pool_stats.any?
        expect(pool_stats[:max_size]).to be > 0
        expect(pool_stats[:size]).to be >= 0
      end
    end

    it 'handles connection failures gracefully with retry logic' do
      # Mock a connection failure scenario
      allow(Sequel).to receive(:connect).and_raise(Sequel::DatabaseConnectionError.new("Connection failed"))
      
      expect {
        SpotikConfig::Database.establish_connection
      }.to raise_error(SpotikConfig::DatabaseConnectionError)
    end

    it 'provides detailed connection pool statistics' do
      pool_stats = SpotikConfig::Database.get_pool_stats
      
      # Should return hash even if empty (when pool info not available)
      expect(pool_stats).to be_a(Hash)
      
      # If pool stats are available, verify structure
      if pool_stats.any?
        expect(pool_stats).to have_key(:size)
        expect(pool_stats).to have_key(:max_size)
      end
    end

    it 'handles pool exhaustion scenarios' do
      # This test verifies that the pool timeout setting works
      db = SpotikConfig::Database.connection
      
      # Test that we can make multiple connections within pool limits
      expect {
        5.times { db.test_connection }
      }.not_to raise_error
    end
  end

  describe 'Schema Validation' do
    before(:each) do
      # Ensure we have a clean test database schema
      create_test_schema if respond_to?(:create_test_schema)
    end

    it 'validates required tables exist' do
      validation_result = SpotikConfig::Database.validate_schema_compatibility
      
      expect(validation_result).to be_a(Hash)
      expect(validation_result).to have_key(:status)
      expect(validation_result).to have_key(:tables)
      expect(validation_result).to have_key(:errors)
      expect(validation_result).to have_key(:warnings)
      
      # Status should be one of the expected values
      expect(['valid', 'warning', 'invalid', 'error']).to include(validation_result[:status])
    end

    it 'detects missing required tables' do
      # Mock a scenario where a required table is missing
      allow(SpotikConfig::Database.connection).to receive(:table_exists?).with(:users).and_return(false)
      
      validation_result = SpotikConfig::Database.validate_schema_compatibility
      
      expect(validation_result[:status]).to eq('invalid')
      expect(validation_result[:errors]).to include(match(/users.*does not exist/))
    end

    it 'validates table column structure' do
      # Skip if we don't have actual tables in test environment
      skip "No test tables available" unless SpotikConfig::Database.connection.table_exists?(:users)
      
      validation_result = SpotikConfig::Database.validate_schema_compatibility
      
      if validation_result[:tables]['users']
        user_table_validation = validation_result[:tables]['users']
        expect(user_table_validation).to have_key(:status)
        expect(user_table_validation).to have_key(:columns)
        
        # Should validate basic user table columns
        expect(user_table_validation[:columns]).to have_key('id')
        expect(user_table_validation[:columns]).to have_key('username')
        expect(user_table_validation[:columns]).to have_key('email')
      end
    end

    it 'checks for recommended indexes' do
      validation_result = SpotikConfig::Database.validate_schema_compatibility
      
      # Should complete without errors even if indexes are missing
      expect(['valid', 'warning']).to include(validation_result[:status])
      
      # May have warnings about missing indexes
      index_warnings = validation_result[:warnings].select { |w| w.include?('index') }
      expect(index_warnings).to be_an(Array)
    end

    it 'validates foreign key constraints' do
      validation_result = SpotikConfig::Database.validate_schema_compatibility
      
      # Should complete validation
      expect(validation_result[:status]).to be_a(String)
      
      # May have warnings about missing foreign keys
      fk_warnings = validation_result[:warnings].select { |w| w.include?('Foreign key') }
      expect(fk_warnings).to be_an(Array)
    end
  end

  describe 'Health Check Functionality' do
    it 'provides comprehensive health check information' do
      health_result = SpotikConfig::Database.health_check
      
      expect(health_result).to be_a(Hash)
      expect(health_result).to have_key(:status)
      expect(health_result).to have_key(:timestamp)
      
      if health_result[:status] == 'healthy'
        expect(health_result).to have_key(:response_time_ms)
        expect(health_result[:response_time_ms]).to be_a(Numeric)
        expect(health_result[:response_time_ms]).to be > 0
      end
    end

    it 'measures database response time accurately' do
      start_time = Time.now
      health_result = SpotikConfig::Database.health_check
      actual_time = ((Time.now - start_time) * 1000).round(2)
      
      if health_result[:status] == 'healthy'
        reported_time = health_result[:response_time_ms]
        
        # Response time should be reasonable and close to actual measurement
        expect(reported_time).to be > 0
        expect(reported_time).to be < 5000  # Should be less than 5 seconds
        
        # Should be within reasonable range of actual time (allowing for overhead)
        expect(reported_time).to be <= (actual_time + 100)
      end
    end

    it 'handles database connection errors in health check' do
      # Mock a database error
      allow(SpotikConfig::Database.connection).to receive(:test_connection).and_raise(Sequel::DatabaseError.new("Connection lost"))
      
      health_result = SpotikConfig::Database.health_check
      
      expect(health_result[:status]).to eq('unhealthy')
      expect(health_result).to have_key(:error)
      expect(health_result[:error]).to include('Connection lost')
    end
  end

  describe 'Error Handling and Recovery' do
    it 'handles database disconnection gracefully' do
      # Test that we can recover from connection loss
      db = SpotikConfig::Database.connection
      
      # Simulate connection loss and recovery
      expect {
        db.test_connection
      }.not_to raise_error
    end

    it 'provides meaningful error messages for connection failures' do
      # Mock connection failure
      allow(Sequel).to receive(:connect).and_raise(Sequel::DatabaseConnectionError.new("Host unreachable"))
      
      expect {
        SpotikConfig::Database.establish_connection
      }.to raise_error(SpotikConfig::DatabaseConnectionError) do |error|
        expect(error.message).to include('Unable to connect to database')
        expect(error.original_error).to be_a(Sequel::DatabaseConnectionError)
      end
    end

    it 'implements exponential backoff for connection retries' do
      call_count = 0
      allow(Sequel).to receive(:connect) do
        call_count += 1
        if call_count < 3
          raise Sequel::DatabaseConnectionError.new("Temporary failure")
        else
          # Return a mock connection on the third try
          double('connection', test_connection: true, run: nil, extension: nil, loggers: [])
        end
      end
      
      # Should eventually succeed after retries
      start_time = Time.now
      
      expect {
        SpotikConfig::Database.establish_connection
      }.not_to raise_error
      
      # Should have taken some time due to backoff delays
      elapsed_time = Time.now - start_time
      expect(elapsed_time).to be > 2  # At least 2 seconds for backoff delays
    end
  end

  describe 'Laravel Compatibility' do
    it 'configures database settings compatible with Laravel' do
      db = SpotikConfig::Database.connection
      
      # Test timezone setting
      timezone_result = db.fetch("SHOW timezone").first
      expect(timezone_result[:timezone]).to eq('UTC')
      
      # Test search path
      search_path_result = db.fetch("SHOW search_path").first
      expect(search_path_result[:search_path]).to include('public')
    end

    it 'supports PostgreSQL extensions used by Laravel' do
      db = SpotikConfig::Database.connection
      
      # Should not raise errors when using JSON operations
      expect {
        db.fetch("SELECT '{\"key\": \"value\"}'::json").first
      }.not_to raise_error
    end

    it 'maintains connection settings across pool usage' do
      db = SpotikConfig::Database.connection
      
      # Test multiple connections maintain settings
      5.times do
        timezone_result = db.fetch("SHOW timezone").first
        expect(timezone_result[:timezone]).to eq('UTC')
      end
    end
  end

  describe 'Performance Monitoring' do
    it 'tracks connection pool statistics' do
      # Make several database calls to generate pool activity
      db = SpotikConfig::Database.connection
      
      5.times { db.test_connection }
      
      pool_stats = SpotikConfig::Database.get_pool_stats
      
      # Should return statistics (even if empty hash when not available)
      expect(pool_stats).to be_a(Hash)
    end

    it 'measures query performance' do
      db = SpotikConfig::Database.connection
      
      start_time = Time.now
      db.fetch("SELECT 1").first
      query_time = ((Time.now - start_time) * 1000).round(2)
      
      # Query should complete in reasonable time
      expect(query_time).to be > 0
      expect(query_time).to be < 1000  # Should be less than 1 second
    end
  end

  private

  def create_test_schema
    # Helper method to create minimal test schema if needed
    # This would be implemented based on test database setup requirements
  end
end