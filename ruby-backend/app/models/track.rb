# Track model - Compatible with Laravel tracks table
require 'sequel'
require 'mime/types'
require 'securerandom'

class Track < Sequel::Model
  # Use existing Laravel table structure
  set_dataset :tracks
  
  # Plugins for enhanced functionality
  plugin :validation_helpers
  plugin :timestamps, update_on_create: true
  plugin :association_dependencies
  
  # Allow setting id for UUID compatibility
  unrestrict_primary_key
  
  # UUID generation for primary key (Laravel compatibility)
  def before_create
    super
    self.id ||= SecureRandom.uuid
  end
  
  # Associations
  many_to_one :room, class: :Room, key: :room_id
  many_to_one :uploader, class: :User, key: :uploader_id
  one_to_many :votes, class: :TrackVote, key: :track_id
  
  # Many-to-many association with users through track_votes
  many_to_many :voters, class: :User, join_table: :track_votes, left_key: :track_id, right_key: :user_id
  
  # Constants (Laravel compatibility)
  SUPPORTED_MIME_TYPES = [
    'audio/mpeg',     # MP3
    'audio/wav',      # WAV
    'audio/mp4',      # M4A
    'audio/x-m4a'     # M4A alternative
  ].freeze
  
  SUPPORTED_EXTENSIONS = %w[mp3 wav m4a].freeze
  MAX_FILE_SIZE = 50 * 1024 * 1024  # 50MB in bytes
  
  # Validation rules (compatible with Laravel validation)
  def validate
    super
    validates_presence [:room_id, :uploader_id, :filename, :original_name, :file_path, :duration_seconds, :file_size_bytes, :mime_type]
    # Note: Foreign key validation is handled by database constraints
    validates_max_length 255, :filename
    validates_max_length 255, :original_name
    validates_max_length 500, :file_path
    validates_max_length 100, :mime_type
    validates_integer :duration_seconds
    validates_integer :file_size_bytes
    validates_integer :vote_score
    validates_includes SUPPORTED_MIME_TYPES, :mime_type, message: 'must be a supported audio format'
  end
  
  # Class methods for validation rules (Laravel compatibility)
  def self.validation_rules
    max_size = MAX_FILE_SIZE / 1024  # Convert to KB for validation
    mime_types = SUPPORTED_MIME_TYPES.join(',')
    extensions = SUPPORTED_EXTENSIONS.join(',')
    
    {
      room_id: 'required|uuid|exists:rooms,id',
      uploader_id: 'required|uuid|exists:users,id',
      audio_file: "required|file|mimes:#{extensions}|mimetypes:#{mime_types}|max:#{max_size}",
      original_name: 'sometimes|string|max:255'
    }
  end
  
  def self.update_validation_rules
    {
      original_name: 'sometimes|string|max:255',
      vote_score: 'sometimes|integer|min:0'
    }
  end
  
  # File URL for streaming (Laravel compatibility)
  def file_url
    "/api/tracks/#{id}/stream"
  end
  
  # Formatted duration (MM:SS) (Laravel compatibility)
  def formatted_duration
    minutes = duration_seconds / 60
    seconds = duration_seconds % 60
    format('%d:%02d', minutes, seconds)
  end
  
  # Formatted file size (Laravel compatibility)
  def formatted_file_size
    bytes = file_size_bytes.to_f
    units = %w[B KB MB GB]
    
    units.each_with_index do |unit, i|
      return "#{bytes.round(2)} #{unit}" if bytes < 1024 || i == units.length - 1
      bytes /= 1024
    end
  end
  
  # Vote management methods (Laravel compatibility)
  def add_vote(user)
    votes_dataset.first_or_create(user_id: user.id) do |vote|
      vote.created_at = Time.now
    end
  end
  
  def remove_vote(user)
    vote = votes_dataset.where(user_id: user.id).first
    return false unless vote
    
    vote.destroy
    true
  end
  
  def toggle_vote(user)
    if has_vote_from?(user)
      remove_vote(user)
      false  # Vote removed
    else
      add_vote(user)
      true   # Vote added
    end
  end
  
  def has_vote_from?(user)
    votes_dataset.where(user_id: user.id).count > 0
  end
  
  # Recalculate vote score from actual votes (Laravel compatibility)
  def recalculate_vote_score
    actual_score = votes.count
    update(vote_score: actual_score)
  end
  
  # File existence check (Laravel compatibility)
  def file_exists?
    File.exist?(file_path)
  end
  
  # Delete file from storage (Laravel compatibility)
  def delete_file
    return true unless file_exists?
    
    File.delete(file_path)
    true
  rescue => e
    puts "Error deleting file #{file_path}: #{e.message}"
    false
  end
  
  # Class methods for file validation (Laravel compatibility)
  def self.supported_mime_type?(mime_type)
    SUPPORTED_MIME_TYPES.include?(mime_type)
  end
  
  def self.supported_extension?(extension)
    SUPPORTED_EXTENSIONS.include?(extension.downcase)
  end
  
  # Serialization for API responses (Laravel format compatibility)
  def to_hash
    {
      id: id,
      room_id: room_id,
      uploader_id: uploader_id,
      uploader: uploader&.to_hash,
      filename: filename,
      original_name: original_name,
      file_path: file_path,
      file_url: file_url,
      duration_seconds: duration_seconds,
      formatted_duration: formatted_duration,
      file_size_bytes: file_size_bytes,
      formatted_file_size: formatted_file_size,
      mime_type: mime_type,
      vote_score: vote_score,
      vote_count: votes.count,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
  end
  
  def to_json(*args)
    to_hash.to_json(*args)
  end
  
  # Hooks for model events (Laravel compatibility)
  def before_destroy
    delete_file
    super
  end
  
  # Association dependency cleanup
  add_association_dependencies votes: :destroy
end