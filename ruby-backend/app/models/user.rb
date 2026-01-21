# User model - Compatible with Laravel users table
require 'sequel'
require 'bcrypt'
require 'securerandom'

class User < Sequel::Model
  # Use existing Laravel table structure
  set_dataset :users
  
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
  one_to_many :administered_rooms, class: :Room, key: :administrator_id
  one_to_many :room_participants, class: :RoomParticipant, key: :user_id
  one_to_many :uploaded_tracks, class: :Track, key: :uploader_id
  one_to_many :track_votes, class: :TrackVote, key: :user_id
  
  # Many-to-many associations
  many_to_many :rooms, join_table: :room_participants, left_key: :user_id, right_key: :room_id
  many_to_many :voted_tracks, class: :Track, join_table: :track_votes, left_key: :user_id, right_key: :track_id
  
  # Validation rules (compatible with Laravel validation)
  def validate
    super
    validates_presence [:username, :email, :password_hash]
    validates_unique :username
    validates_unique :email
    validates_max_length 50, :username
    validates_max_length 255, :email
    validates_format /\A[^@\s]+@[^@\s]+\z/, :email, message: 'must be a valid email address'
  end
  
  # Class methods for validation rules (Laravel compatibility)
  def self.validation_rules
    {
      username: 'required|string|max:50|unique:users,username',
      email: 'required|string|email|max:255|unique:users,email',
      password: 'required|string|min:8|confirmed'
    }
  end
  
  def self.update_validation_rules(user_id)
    {
      username: "sometimes|string|max:50|unique:users,username,#{user_id}",
      email: "sometimes|string|email|max:255|unique:users,email,#{user_id}",
      password: 'sometimes|string|min:8|confirmed'
    }
  end
  
  # Password handling (Laravel bcrypt compatibility)
  def password=(new_password)
    self.password_hash = BCrypt::Password.create(new_password)
  end
  
  def authenticate(password)
    BCrypt::Password.new(password_hash) == password
  rescue BCrypt::Errors::InvalidHash
    false
  end
  
  # Laravel compatibility method
  def get_auth_password
    password_hash
  end
  
  # Room administration methods
  def administrator_of?(room)
    room.administrator_id == id
  end
  
  def participant_of?(room)
    room_participants_dataset.where(room_id: room.id).count > 0
  end
  
  def has_voted_for?(track)
    track_votes_dataset.where(track_id: track.id).count > 0
  end
  
  # JWT methods (Laravel JWT compatibility)
  def jwt_identifier
    id
  end
  
  def jwt_custom_claims
    {}
  end
  
  # Serialization for API responses (Laravel format compatibility)
  def to_hash
    {
      id: id,
      username: username,
      email: email,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
  end
  
  def to_json(*args)
    to_hash.to_json(*args)
  end
  
  # Hide sensitive fields in JSON output
  def values
    super.except(:password_hash)
  end
  
  # Association dependency cleanup
  add_association_dependencies administered_rooms: :destroy
  add_association_dependencies room_participants: :destroy
  add_association_dependencies uploaded_tracks: :destroy
  add_association_dependencies track_votes: :destroy
end