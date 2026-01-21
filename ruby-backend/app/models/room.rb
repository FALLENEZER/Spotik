# Room model - Compatible with Laravel rooms table
require 'sequel'
require 'securerandom'

class Room < Sequel::Model
  # Use existing Laravel table structure
  set_dataset :rooms
  
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
  many_to_one :administrator, class: :User, key: :administrator_id
  many_to_one :current_track, class: :Track, key: :current_track_id
  one_to_many :tracks, class: :Track, key: :room_id
  one_to_many :participants, class: :RoomParticipant, key: :room_id
  
  # Many-to-many association with users through room_participants
  many_to_many :users, join_table: :room_participants, left_key: :room_id, right_key: :user_id
  
  # Validation rules (compatible with Laravel validation)
  def validate
    super
    validates_presence [:name, :administrator_id]
    validates_max_length 100, :name
    # Note: Foreign key validation is handled by database constraints
    # validates_foreign_key is not available in Sequel, but we can check manually if needed
  end
  
  # Class methods for validation rules (Laravel compatibility)
  def self.validation_rules
    {
      name: 'required|string|max:100',
      administrator_id: 'required|uuid|exists:users,id'
    }
  end
  
  def self.update_validation_rules
    {
      name: 'sometimes|string|max:100',
      current_track_id: 'sometimes|nullable|uuid|exists:tracks,id',
      is_playing: 'sometimes|boolean'
    }
  end
  
  # Track queue ordered by vote score (desc) then created_at (asc)
  def track_queue
    tracks_dataset.order(Sequel.desc(:vote_score), :created_at)
  end
  
  # Get next track in queue (excluding currently playing track)
  def next_track
    queue = track_queue
    
    # If there's a current track, get the next one after it
    if current_track_id
      queue = queue.exclude(id: current_track_id)
    end
    
    queue.first
  end
  
  # Get track queue as array with position information
  def track_queue_with_positions
    queue = track_queue.to_a
    queue.each_with_index.map do |track, index|
      track_data = track.to_hash
      track_data[:queue_position] = index + 1
      track_data[:is_current] = track.id == current_track_id
      track_data[:is_next] = index == 0 && track.id != current_track_id
      track_data
    end
  end
  
  # Playback position calculation (Laravel compatibility)
  def current_playback_position
    return 0 unless is_playing && playback_started_at
    
    elapsed = Time.now - playback_started_at
    
    # If there was a pause, subtract the paused duration
    if playback_paused_at && playback_paused_at > playback_started_at
      paused_duration = Time.now - playback_paused_at
      elapsed -= paused_duration
    end
    
    [0, elapsed.to_i].max
  end
  
  # Playback control methods (Laravel compatibility)
  def start_track(track)
    update(
      current_track_id: track.id,
      playback_started_at: Time.now,
      playback_paused_at: nil,
      is_playing: true
    )
  end
  
  def pause_playback
    update(
      playback_paused_at: Time.now,
      is_playing: false
    )
  end
  
  def resume_playback
    if playback_paused_at
      paused_duration = Time.now - playback_paused_at
      new_start_time = playback_started_at + paused_duration
      
      update(
        playback_started_at: new_start_time,
        playback_paused_at: nil,
        is_playing: true
      )
    end
  end
  
  def stop_playback
    update(
      current_track_id: nil,
      playback_started_at: nil,
      playback_paused_at: nil,
      is_playing: false
    )
  end
  
  def skip_to_next
    next_track_obj = next_track
    
    if next_track_obj
      start_track(next_track_obj)
    else
      stop_playback
    end
    
    next_track_obj
  end
  
  # Participant management methods (Laravel compatibility)
  def add_participant(user)
    # Check if participant already exists
    existing = participants_dataset.where(user_id: user.id).first
    return existing if existing
    
    # Create new participant with explicit ID
    RoomParticipant.create(
      id: SecureRandom.uuid,
      room_id: id,
      user_id: user.id,
      joined_at: Time.now
    )
  end
  
  def remove_participant(user)
    participants_dataset.where(user_id: user.id).delete > 0
  end
  
  def administered_by?(user)
    administrator_id == user.id
  end
  
  def has_participant?(user)
    # Administrators are always considered participants
    return true if administrator_id == user.id
    
    participants_dataset.where(user_id: user.id).count > 0
  end
  
  # Get participant count (Laravel compatibility)
  def participant_count
    participants.count
  end
  
  # Serialization for API responses (Laravel format compatibility)
  def to_hash
    {
      id: id,
      name: name,
      administrator_id: administrator_id,
      administrator: administrator&.to_hash,
      current_track_id: current_track_id,
      current_track: current_track&.to_hash,
      playback_started_at: playback_started_at&.iso8601,
      playback_paused_at: playback_paused_at&.iso8601,
      is_playing: is_playing,
      participants: participants.map(&:to_hash),
      track_queue: track_queue.map(&:to_hash),
      track_count: tracks.count,
      participant_count: participants.count,
      created_at: created_at&.iso8601,
      updated_at: updated_at&.iso8601
    }
  end
  
  def to_json(*args)
    to_hash.to_json(*args)
  end
  
  # Association dependency cleanup
  add_association_dependencies tracks: :destroy
  add_association_dependencies participants: :destroy
end