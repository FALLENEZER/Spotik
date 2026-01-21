# Database configuration for Ruby backend
# Compatible with existing PostgreSQL database from Laravel

require 'sequel'
require 'logger'

module SpotikConfig
  class Database
    class << self
      attr_reader :connection_pool_stats
      
      def connection
        @connection ||= establish_connection
      end

      def establish_connection
        database_url = build_database_url
        
        # Enhanced connection pool settings
        pool_options = {
          max_connections: ENV.fetch('DB_POOL_MAX', 10).to_i,
          pool_timeout: ENV.fetch('DB_POOL_TIMEOUT', 5).to_i,
          pool_sleep_time: ENV.fetch('DB_POOL_SLEEP_TIME', 0.001).to_f,
          test: true,  # Test connections before use
          logger: setup_logger,
          # Connection retry settings
          connect_timeout: ENV.fetch('DB_CONNECT_TIMEOUT', 10).to_i,
          read_timeout: ENV.fetch('DB_READ_TIMEOUT', 30).to_i,
          # Pool validation
          pool_class: :threaded,
          after_connect: proc do |conn|
            # Set connection-specific settings
            conn.exec("SET application_name = 'spotik_ruby_backend'")
            conn.exec("SET statement_timeout = '30s'")
            conn.exec("SET lock_timeout = '10s'")
          end
        }
        
        # Create connection with enhanced error handling
        db = nil
        retry_count = 0
        max_retries = 3
        
        begin
          db = Sequel.connect(database_url, pool_options)
          
          # Test the connection immediately
          db.test_connection
          
          # Configure database settings for compatibility
          configure_database(db)
          
          # Initialize connection pool monitoring
          initialize_pool_monitoring(db)
          
          $logger&.info "Database connection established successfully"
          $logger&.info "Connection pool: max=#{pool_options[:max_connections]}, timeout=#{pool_options[:pool_timeout]}s"
          
        rescue => e
          retry_count += 1
          $logger&.error "Database connection attempt #{retry_count} failed: #{e.message}"
          
          if retry_count < max_retries
            sleep_time = retry_count * 2  # Exponential backoff
            $logger&.info "Retrying database connection in #{sleep_time} seconds..."
            sleep(sleep_time)
            retry
          else
            $logger&.error "Failed to establish database connection after #{max_retries} attempts"
            raise DatabaseConnectionError.new("Unable to connect to database: #{e.message}", e)
          end
        end
        
        db
      end

      def build_database_url
        host = ENV.fetch('DB_HOST', 'localhost')
        port = ENV.fetch('DB_PORT', 5432)
        database = ENV.fetch('DB_NAME', 'spotik')
        username = ENV.fetch('DB_USER', 'spotik_user')
        password = ENV.fetch('DB_PASSWORD', 'spotik_password')

        "postgres://#{username}:#{password}@#{host}:#{port}/#{database}"
      end

      def configure_database(db)
        # Set timezone to UTC (Laravel default)
        db.run("SET timezone = 'UTC'")
        
        # Set search path to public schema
        db.run("SET search_path TO public")
        
        # Configure for Laravel compatibility
        db.extension :pg_json
        db.extension :pg_array
        db.extension :pg_timestamptz
        
        # Enable SQL logging in development
        if ENV['APP_ENV'] == 'development' && ENV['LOG_LEVEL'] == 'debug'
          db.loggers << Logger.new($stdout)
        end
      end

      def setup_logger
        return nil unless ENV['APP_ENV'] == 'development'
        
        logger = Logger.new($stdout)
        logger.level = Logger::INFO
        logger.formatter = proc do |severity, datetime, progname, msg|
          "[#{datetime}] #{severity}: #{msg}\n"
        end
        logger
      end

      def health_check
        start_time = Time.now
        
        begin
          # Test basic connection
          connection.test_connection
          
          # Test a simple query
          result = connection.fetch("SELECT 1 as test").first
          raise "Query test failed" unless result[:test] == 1
          
          # Get connection pool stats
          pool_stats = get_pool_stats
          
          # Calculate response time
          response_time = ((Time.now - start_time) * 1000).round(2)
          
          {
            status: 'healthy',
            database: 'connected',
            response_time_ms: response_time,
            pool_stats: pool_stats,
            timestamp: Time.now.iso8601
          }
        rescue => e
          response_time = ((Time.now - start_time) * 1000).round(2)
          
          {
            status: 'unhealthy',
            database: 'disconnected',
            error: e.message,
            response_time_ms: response_time,
            timestamp: Time.now.iso8601
          }
        end
      end

      def validate_schema_compatibility
        $logger&.info "Validating database schema compatibility with Laravel..."
        
        required_tables = %w[users rooms tracks room_participants track_votes]
        validation_results = {
          status: 'valid',
          tables: {},
          errors: [],
          warnings: []
        }
        
        begin
          # Check if all required tables exist
          required_tables.each do |table_name|
            table_sym = table_name.to_sym
            
            if connection.table_exists?(table_sym)
              # Validate table structure
              table_validation = validate_table_structure(table_sym)
              validation_results[:tables][table_name] = table_validation
              
              if table_validation[:status] == 'invalid'
                validation_results[:status] = 'invalid'
                validation_results[:errors] += table_validation[:errors]
              elsif table_validation[:status] == 'warning'
                validation_results[:warnings] += table_validation[:warnings]
              end
            else
              validation_results[:status] = 'invalid'
              validation_results[:errors] << "Required table '#{table_name}' does not exist"
            end
          end
          
          # Validate indexes for performance
          validate_required_indexes(validation_results)
          
          # Validate foreign key constraints
          validate_foreign_key_constraints(validation_results)
          
          $logger&.info "Schema validation completed: #{validation_results[:status]}"
          
          if validation_results[:errors].any?
            $logger&.error "Schema validation errors: #{validation_results[:errors].join(', ')}"
          end
          
          if validation_results[:warnings].any?
            $logger&.warn "Schema validation warnings: #{validation_results[:warnings].join(', ')}"
          end
          
        rescue => e
          validation_results[:status] = 'error'
          validation_results[:errors] << "Schema validation failed: #{e.message}"
          $logger&.error "Schema validation error: #{e.message}"
        end
        
        validation_results
      end

      def get_pool_stats
        return {} unless @connection
        
        pool = @connection.pool
        {
          size: pool.size,
          max_size: pool.max_size,
          allocated: pool.allocated,
          available: pool.available
        }
      rescue => e
        $logger&.warn "Could not retrieve pool stats: #{e.message}"
        {}
      end

      def initialize_pool_monitoring(db)
        @connection_pool_stats = {
          created_at: Time.now,
          total_connections: 0,
          failed_connections: 0,
          pool_exhaustions: 0
        }
        
        # Monitor pool events if supported
        if db.pool.respond_to?(:connection_created)
          db.pool.extend(PoolMonitoring)
        end
      end

      def validate_table_structure(table_name)
        result = {
          status: 'valid',
          columns: {},
          errors: [],
          warnings: []
        }
        
        begin
          schema = connection.schema(table_name)
          required_columns = get_required_columns_for_table(table_name)
          
          # Check required columns
          existing_columns = schema.map { |col| col[0].to_s }
          
          required_columns.each do |col_name, col_spec|
            if existing_columns.include?(col_name)
              # Validate column type if specified
              column_info = schema.find { |col| col[0].to_s == col_name }
              if column_info && col_spec[:type]
                actual_type = column_info[1][:type]
                expected_type = col_spec[:type]
                
                unless types_compatible?(actual_type, expected_type)
                  result[:warnings] << "Column #{table_name}.#{col_name} type mismatch: expected #{expected_type}, got #{actual_type}"
                  result[:status] = 'warning' if result[:status] == 'valid'
                end
              end
              
              result[:columns][col_name] = 'present'
            else
              result[:errors] << "Required column '#{col_name}' missing from table '#{table_name}'"
              result[:status] = 'invalid'
            end
          end
          
        rescue => e
          result[:status] = 'error'
          result[:errors] << "Failed to validate table #{table_name}: #{e.message}"
        end
        
        result
      end

      def get_required_columns_for_table(table_name)
        case table_name.to_s
        when 'users'
          {
            'id' => { type: :uuid, nullable: false },
            'username' => { type: :string, nullable: false },
            'email' => { type: :string, nullable: false },
            'password_hash' => { type: :string, nullable: false },
            'created_at' => { type: :datetime, nullable: true },
            'updated_at' => { type: :datetime, nullable: true }
          }
        when 'rooms'
          {
            'id' => { type: :uuid, nullable: false },
            'name' => { type: :string, nullable: false },
            'administrator_id' => { type: :uuid, nullable: false },
            'current_track_id' => { type: :uuid, nullable: true },
            'playback_started_at' => { type: :datetime, nullable: true },
            'playback_paused_at' => { type: :datetime, nullable: true },
            'is_playing' => { type: :boolean, nullable: false },
            'created_at' => { type: :datetime, nullable: true },
            'updated_at' => { type: :datetime, nullable: true }
          }
        when 'tracks'
          {
            'id' => { type: :uuid, nullable: false },
            'room_id' => { type: :uuid, nullable: false },
            'uploader_id' => { type: :uuid, nullable: false },
            'filename' => { type: :string, nullable: false },
            'original_name' => { type: :string, nullable: false },
            'file_path' => { type: :string, nullable: false },
            'duration_seconds' => { type: :integer, nullable: false },
            'file_size_bytes' => { type: :integer, nullable: false },
            'mime_type' => { type: :string, nullable: false },
            'vote_score' => { type: :integer, nullable: false },
            'created_at' => { type: :datetime, nullable: true },
            'updated_at' => { type: :datetime, nullable: true }
          }
        when 'room_participants'
          {
            'id' => { type: :uuid, nullable: false },
            'room_id' => { type: :uuid, nullable: false },
            'user_id' => { type: :uuid, nullable: false },
            'joined_at' => { type: :datetime, nullable: true }
          }
        when 'track_votes'
          {
            'id' => { type: :uuid, nullable: false },
            'track_id' => { type: :uuid, nullable: false },
            'user_id' => { type: :uuid, nullable: false },
            'created_at' => { type: :datetime, nullable: true }
          }
        else
          {}
        end
      end

      def types_compatible?(actual_type, expected_type)
        # Handle common type variations between PostgreSQL and Sequel
        type_mappings = {
          uuid: [:uuid, :string],
          string: [:string, :text, :varchar],
          integer: [:integer, :bigint, :int],
          datetime: [:datetime, :timestamp, :timestamptz],
          boolean: [:boolean, :bool]
        }
        
        compatible_types = type_mappings[expected_type] || [expected_type]
        compatible_types.include?(actual_type)
      end

      def validate_required_indexes(validation_results)
        # Check for performance-critical indexes
        required_indexes = {
          'users' => ['username', 'email'],
          'rooms' => ['administrator_id'],
          'tracks' => ['room_id', 'uploader_id'],
          'room_participants' => ['room_id', 'user_id'],
          'track_votes' => ['track_id', 'user_id']
        }
        
        required_indexes.each do |table, columns|
          columns.each do |column|
            unless index_exists?(table, column)
              validation_results[:warnings] << "Recommended index missing on #{table}.#{column}"
            end
          end
        end
      end

      def validate_foreign_key_constraints(validation_results)
        # Check for foreign key constraints
        foreign_keys = {
          'rooms' => { 'administrator_id' => 'users.id' },
          'tracks' => { 'room_id' => 'rooms.id', 'uploader_id' => 'users.id' },
          'room_participants' => { 'room_id' => 'rooms.id', 'user_id' => 'users.id' },
          'track_votes' => { 'track_id' => 'tracks.id', 'user_id' => 'users.id' }
        }
        
        foreign_keys.each do |table, constraints|
          constraints.each do |column, reference|
            unless foreign_key_exists?(table, column, reference)
              validation_results[:warnings] << "Foreign key constraint missing: #{table}.#{column} -> #{reference}"
            end
          end
        end
      end

      def index_exists?(table, column)
        # Check if index exists on column
        indexes = connection.indexes(table.to_sym)
        indexes.any? { |name, info| info[:columns].include?(column.to_sym) }
      rescue => e
        $logger&.warn "Could not check index for #{table}.#{column}: #{e.message}"
        false
      end

      def foreign_key_exists?(table, column, reference)
        # Check if foreign key constraint exists
        foreign_keys = connection.foreign_key_list(table.to_sym)
        foreign_keys.any? { |fk| fk[:columns].include?(column.to_sym) }
      rescue => e
        $logger&.warn "Could not check foreign key for #{table}.#{column}: #{e.message}"
        false
      end

      def close_connection
        @connection&.disconnect
        @connection = nil
        @connection_pool_stats = nil
      end
    end
  end

  # Custom error class for database connection issues
  class DatabaseConnectionError < StandardError
    attr_reader :original_error
    
    def initialize(message, original_error = nil)
      super(message)
      @original_error = original_error
    end
  end

  # Module to extend connection pool for monitoring
  module PoolMonitoring
    def connection_created
      SpotikConfig::Database.instance_variable_get(:@connection_pool_stats)[:total_connections] += 1
      super if defined?(super)
    end
    
    def connection_failed
      SpotikConfig::Database.instance_variable_get(:@connection_pool_stats)[:failed_connections] += 1
      super if defined?(super)
    end
  end
end