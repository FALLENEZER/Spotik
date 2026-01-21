# Test database configuration for Ruby backend
# Uses SQLite in-memory database for testing

require 'sequel'
require 'logger'

module SpotikConfig
  class TestDatabase
    class << self
      def connection
        @connection ||= establish_connection
      end

      def establish_connection
        # Use SQLite in-memory database for testing
        db = Sequel.sqlite
        
        # Create test schema
        create_test_schema(db)
        
        # Configure database settings
        configure_database(db)
        
        db
      end

      def create_test_schema(db)
        # Create users table
        db.create_table :users do
          String :id, primary_key: true  # UUID string primary key (Laravel compatibility)
          String :username, null: false, unique: true
          String :email, null: false, unique: true
          String :password_hash, null: false
          DateTime :created_at
          DateTime :updated_at
        end

        # Create rooms table
        db.create_table :rooms do
          String :id, primary_key: true  # UUID string primary key (Laravel compatibility)
          String :name, null: false
          String :administrator_id, null: false
          String :current_track_id
          DateTime :playback_started_at
          DateTime :playback_paused_at
          TrueClass :is_playing, default: false
          DateTime :created_at
          DateTime :updated_at
        end

        # Create tracks table
        db.create_table :tracks do
          String :id, primary_key: true  # UUID string primary key (Laravel compatibility)
          String :room_id, null: false
          String :uploader_id, null: false
          String :filename, null: false
          String :original_name, null: false
          String :file_path, null: false
          Integer :duration_seconds, null: false
          Integer :file_size_bytes, null: false
          String :mime_type, null: false
          Integer :vote_score, default: 0
          DateTime :created_at
          DateTime :updated_at
        end

        # Create room_participants table
        db.create_table :room_participants do
          String :id, primary_key: true  # UUID string primary key (Laravel compatibility)
          String :room_id, null: false
          String :user_id, null: false
          DateTime :joined_at
          
          unique [:room_id, :user_id]
        end

        # Create track_votes table
        db.create_table :track_votes do
          String :id, primary_key: true  # UUID string primary key (Laravel compatibility)
          String :track_id, null: false
          String :user_id, null: false
          DateTime :created_at
          
          unique [:track_id, :user_id]
        end
      end

      def configure_database(db)
        # Enable foreign key constraints
        db.run("PRAGMA foreign_keys = ON")
      end

      def health_check
        connection.test_connection
        { status: 'healthy', database: 'connected' }
      rescue => e
        { status: 'unhealthy', database: 'disconnected', error: e.message }
      end

      def close_connection
        @connection&.disconnect
        @connection = nil
      end

      def reset_database
        close_connection
        @connection = nil
      end
    end
  end
end