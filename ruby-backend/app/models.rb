# Model loader - Establishes database connection and loads all models
# Compatible with existing Laravel PostgreSQL database

require_relative '../config/database'

# Establish database connection
DB = SpotikConfig::Database.connection

# Load all model files
require_relative 'models/user'
require_relative 'models/room'
require_relative 'models/track'
require_relative 'models/room_participant'
require_relative 'models/track_vote'

# Finalize associations after all models are loaded
# This ensures all model classes are available for associations
Sequel::Model.finalize_associations

# Verify database connection and schema compatibility
module ModelLoader
  class << self
    def verify_schema_compatibility
      required_tables = %w[users rooms tracks room_participants track_votes]
      
      required_tables.each do |table|
        unless DB.table_exists?(table.to_sym)
          raise "Required table '#{table}' does not exist in database"
        end
      end
      
      puts "✓ All required database tables found"
      
      # Verify critical columns exist
      verify_table_columns
      
      puts "✓ Database schema compatibility verified"
    end
    
    def verify_table_columns
      # Users table
      verify_columns(:users, %w[id username email password_hash created_at updated_at])
      
      # Rooms table
      verify_columns(:rooms, %w[id name administrator_id current_track_id playback_started_at playback_paused_at is_playing created_at updated_at])
      
      # Tracks table
      verify_columns(:tracks, %w[id room_id uploader_id filename original_name file_path duration_seconds file_size_bytes mime_type vote_score created_at updated_at])
      
      # Room participants table
      verify_columns(:room_participants, %w[id room_id user_id joined_at])
      
      # Track votes table
      verify_columns(:track_votes, %w[id track_id user_id created_at])
    end
    
    def verify_columns(table, required_columns)
      schema = DB.schema(table)
      existing_columns = schema.map { |col| col[0].to_s }
      
      missing_columns = required_columns - existing_columns
      
      if missing_columns.any?
        raise "Table '#{table}' is missing required columns: #{missing_columns.join(', ')}"
      end
    end
    
    def health_check
      {
        database: SpotikConfig::Database.health_check,
        models: {
          user: User.count,
          room: Room.count,
          track: Track.count,
          room_participant: RoomParticipant.count,
          track_vote: TrackVote.count
        }
      }
    rescue => e
      {
        database: { status: 'unhealthy', error: e.message },
        models: { error: e.message }
      }
    end
  end
end

# Verify schema compatibility on load (only in development/test)
if ENV['APP_ENV'] != 'production'
  begin
    ModelLoader.verify_schema_compatibility
  rescue => e
    puts "⚠️  Schema compatibility warning: #{e.message}"
    puts "   This may be expected during initial setup or migrations"
  end
end