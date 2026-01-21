# RoomParticipant model - Compatible with Laravel room_participants table
require 'sequel'
require 'securerandom'

class RoomParticipant < Sequel::Model
  # Use existing Laravel table structure
  set_dataset :room_participants
  
  # Plugins for enhanced functionality
  plugin :validation_helpers
  
  # Allow setting id for UUID compatibility
  unrestrict_primary_key
  
  # UUID generation for primary key (Laravel compatibility)
  def before_create
    super
    self.id ||= SecureRandom.uuid
  end
  
  # Associations
  many_to_one :room, class: :Room, key: :room_id
  many_to_one :user, class: :User, key: :user_id
  
  # Validation rules (compatible with Laravel validation)
  def validate
    super
    validates_presence [:room_id, :user_id]
    # Note: room_id and user_id are UUIDs (strings), not integers in Laravel compatibility mode
    validates_unique [:room_id, :user_id], message: 'user is already a participant in this room'
  end
  
  # Class methods for validation rules (Laravel compatibility)
  def self.validation_rules
    {
      room_id: 'required|uuid|exists:rooms,id',
      user_id: 'required|uuid|exists:users,id'
    }
  end
  
  # Duration in room calculation (Laravel compatibility)
  def duration_in_room
    return 'Just joined' unless joined_at
    
    duration = Time.now - joined_at
    
    case duration
    when 0..59
      'Just joined'
    when 60..3599
      minutes = (duration / 60).to_i
      "#{minutes} minute#{'s' if minutes != 1}"
    when 3600..86399
      hours = (duration / 3600).to_i
      "#{hours} hour#{'s' if hours != 1}"
    else
      days = (duration / 86400).to_i
      "#{days} day#{'s' if days != 1}"
    end
  end
  
  # Check if user is room administrator (Laravel compatibility)
  def administrator?
    room.administrator_id == user_id
  end
  
  # Serialization for API responses (Laravel format compatibility)
  def to_hash
    {
      id: id,
      room_id: room_id,
      user_id: user_id,
      user: user&.to_hash,
      joined_at: joined_at&.iso8601,
      duration_in_room: duration_in_room,
      is_administrator: administrator?
    }
  end
  
  def to_json(*args)
    to_hash.to_json(*args)
  end
  
  # Hooks for model events (Laravel compatibility)
  def before_create
    self.joined_at ||= Time.now
    super
  end
end