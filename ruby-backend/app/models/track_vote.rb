# TrackVote model - Compatible with Laravel track_votes table
require 'sequel'
require 'securerandom'

class TrackVote < Sequel::Model
  # Use existing Laravel table structure
  set_dataset :track_votes
  
  # Plugins for enhanced functionality
  plugin :validation_helpers
  
  # Allow setting id for UUID compatibility (needed for tests)
  unrestrict_primary_key
  
  # UUID generation for primary key (Laravel compatibility)
  def before_create
    self.id ||= SecureRandom.uuid
    self.created_at ||= Time.now
    super
  end
  
  # Associations
  many_to_one :track, class: :Track, key: :track_id
  many_to_one :user, class: :User, key: :user_id
  
  # Validation rules (compatible with Laravel validation)
  def validate
    super
    validates_presence [:track_id, :user_id]
    validates_unique [:track_id, :user_id], message: 'user has already voted for this track'
  end
  
  # Class methods for validation rules (Laravel compatibility)
  def self.validation_rules
    {
      track_id: 'required|uuid|exists:tracks,id',
      user_id: 'required|uuid|exists:users,id'
    }
  end
  
  # Get room through track association (Laravel compatibility)
  def room
    track&.room
  end
  
  # Check if vote is from track uploader (Laravel compatibility)
  def from_uploader?
    user_id == track&.uploader_id
  end
  
  # Serialization for API responses (Laravel format compatibility)
  def to_hash
    {
      id: id,
      track_id: track_id,
      user_id: user_id,
      user: user&.to_hash,
      track: track&.to_hash,
      created_at: created_at&.iso8601,
      is_from_uploader: from_uploader?
    }
  end
  
  def to_json(*args)
    to_hash.to_json(*args)
  end
  
  # Hooks for model events (Laravel compatibility)
  def after_create
    # Update track vote score when vote is created
    track&.update(vote_score: track.vote_score + 1)
    super
  end
  
  def after_destroy
    # Update track vote score when vote is deleted
    track&.update(vote_score: [track.vote_score - 1, 0].max)
    super
  end
end