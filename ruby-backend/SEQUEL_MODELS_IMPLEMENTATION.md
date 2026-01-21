# Sequel Models Implementation

## Overview

This document describes the implementation of Sequel models that are fully compatible with the existing Laravel database schema. The models maintain complete compatibility with the existing PostgreSQL database structure while providing Ruby-native functionality.

## Implemented Models

### 1. User Model (`app/models/user.rb`)

**Laravel Compatibility:**
- Uses existing `users` table structure
- Compatible with Laravel bcrypt password hashing
- Maintains same validation rules as Laravel User model
- Implements JWT methods for authentication compatibility

**Key Features:**
- Password hashing with BCrypt (Laravel compatible)
- User authentication methods
- Associations with rooms, tracks, and votes
- JSON serialization matching Laravel API format
- Validation rules equivalent to Laravel

**Associations:**
- `administered_rooms` - Rooms where user is administrator
- `room_participants` - Join records for room participation
- `uploaded_tracks` - Tracks uploaded by user
- `track_votes` - Votes cast by user
- `rooms` - Many-to-many through room_participants
- `voted_tracks` - Many-to-many through track_votes

### 2. Room Model (`app/models/room.rb`)

**Laravel Compatibility:**
- Uses existing `rooms` table structure
- Implements all playback control methods from Laravel Room model
- Maintains same participant management logic
- Compatible track queue ordering (vote_score DESC, created_at ASC)

**Key Features:**
- Playback control (start, pause, resume, stop, skip)
- Participant management (add, remove, check membership)
- Track queue management with voting-based ordering
- Current playback position calculation
- Real-time state management

**Associations:**
- `administrator` - User who created the room
- `current_track` - Currently playing track
- `tracks` - All tracks in room
- `participants` - Join records for participants
- `users` - Many-to-many through room_participants

### 3. Track Model (`app/models/track.rb`)

**Laravel Compatibility:**
- Uses existing `tracks` table structure
- Maintains same file validation constants
- Implements vote management methods from Laravel
- Compatible file handling and metadata extraction

**Key Features:**
- Audio file validation (MP3, WAV, M4A)
- Vote management (add, remove, toggle votes)
- File size and duration formatting
- File existence checking and cleanup
- Vote score recalculation

**Associations:**
- `room` - Room containing this track
- `uploader` - User who uploaded the track
- `votes` - Vote records for this track
- `voters` - Many-to-many through track_votes

### 4. RoomParticipant Model (`app/models/room_participant.rb`)

**Laravel Compatibility:**
- Uses existing `room_participants` table structure
- Maintains unique constraint on room_id + user_id
- Implements duration calculation from Laravel model

**Key Features:**
- Join table with metadata (joined_at timestamp)
- Duration in room calculation
- Administrator status checking
- Automatic timestamp management

**Associations:**
- `room` - Room being participated in
- `user` - User participating

### 5. TrackVote Model (`app/models/track_vote.rb`)

**Laravel Compatibility:**
- Uses existing `track_votes` table structure
- Maintains unique constraint on track_id + user_id
- Implements vote score updating from Laravel model

**Key Features:**
- Vote tracking with timestamps
- Automatic track vote_score updating
- Uploader vote detection
- Room association through track

**Associations:**
- `track` - Track being voted for
- `user` - User casting the vote

## Database Compatibility

### Schema Compatibility
All models use the existing Laravel database schema without modifications:

- **users**: id, username, email, password_hash, created_at, updated_at
- **rooms**: id, name, administrator_id, current_track_id, playback_started_at, playback_paused_at, is_playing, created_at, updated_at
- **tracks**: id, room_id, uploader_id, filename, original_name, file_path, duration_seconds, file_size_bytes, mime_type, vote_score, created_at, updated_at
- **room_participants**: id, room_id, user_id, joined_at
- **track_votes**: id, track_id, user_id, created_at

### Foreign Key Constraints
All foreign key relationships are maintained:
- rooms.administrator_id → users.id
- rooms.current_track_id → tracks.id
- tracks.room_id → rooms.id
- tracks.uploader_id → users.id
- room_participants.room_id → rooms.id
- room_participants.user_id → users.id
- track_votes.track_id → tracks.id
- track_votes.user_id → users.id

### Indexes
All existing indexes are preserved and utilized:
- Performance indexes for queue ordering
- Unique constraints for preventing duplicates
- Foreign key indexes for relationship queries

## Key Implementation Details

### 1. Laravel Method Compatibility

All critical methods from Laravel models are implemented:

**User Model:**
- `authenticate(password)` - Password verification
- `administrator_of?(room)` - Check room administration
- `participant_of?(room)` - Check room participation
- `has_voted_for?(track)` - Check track voting

**Room Model:**
- `start_track(track)` - Begin track playback
- `pause_playback()` - Pause current track
- `resume_playback()` - Resume paused track
- `current_playback_position()` - Calculate position
- `add_participant(user)` - Add user to room
- `track_queue()` - Get ordered track queue

**Track Model:**
- `add_vote(user)` - Add user vote
- `remove_vote(user)` - Remove user vote
- `toggle_vote(user)` - Toggle user vote
- `recalculate_vote_score()` - Update vote count

### 2. JSON Serialization

All models implement `to_hash` and `to_json` methods that produce output compatible with Laravel's API responses:

```ruby
# User JSON output
{
  id: "uuid",
  username: "string",
  email: "string", 
  created_at: "ISO8601",
  updated_at: "ISO8601"
}

# Room JSON output  
{
  id: "uuid",
  name: "string",
  administrator_id: "uuid",
  administrator: { user_object },
  current_track_id: "uuid",
  current_track: { track_object },
  is_playing: boolean,
  participants: [{ participant_objects }],
  created_at: "ISO8601",
  updated_at: "ISO8601"
}
```

### 3. Validation Rules

Validation rules match Laravel's validation exactly:

```ruby
# User validation
validates_presence [:username, :email, :password_hash]
validates_unique :username, :email
validates_max_length 50, :username
validates_max_length 255, :email

# Room validation
validates_presence [:name, :administrator_id]
validates_max_length 100, :name
validates_foreign_key :administrator_id, User
```

### 4. Association Hooks

Model hooks maintain data integrity:

```ruby
# TrackVote hooks
def after_create
  track&.update(vote_score: track.vote_score + 1)
end

def after_destroy  
  track&.update(vote_score: [track.vote_score - 1, 0].max)
end

# Track hooks
def before_destroy
  delete_file  # Clean up audio file
end
```

## Usage Examples

### Basic Model Operations

```ruby
# Create user
user = User.create(
  username: 'testuser',
  email: 'test@example.com', 
  password: 'password123'
)

# Create room
room = Room.create(
  name: 'My Room',
  administrator_id: user.id
)

# Add participant
room.add_participant(user)

# Upload track
track = Track.create(
  room_id: room.id,
  uploader_id: user.id,
  filename: 'song.mp3',
  original_name: 'My Song.mp3',
  file_path: '/path/to/song.mp3',
  duration_seconds: 180,
  file_size_bytes: 5000000,
  mime_type: 'audio/mpeg'
)

# Vote for track
track.add_vote(user)

# Start playback
room.start_track(track)
```

### Association Queries

```ruby
# Get user's rooms
user.rooms.each do |room|
  puts "Room: #{room.name}"
end

# Get room's track queue
room.track_queue.each do |track|
  puts "#{track.original_name} - #{track.vote_score} votes"
end

# Get track voters
track.voters.each do |voter|
  puts "Voted by: #{voter.username}"
end
```

## Testing and Validation

### Model Structure Validation
Run `ruby validate_models.rb` to verify model structure and implementation.

### Database Connection Testing
The `ModelLoader` module provides health check functionality:

```ruby
health = ModelLoader.health_check
puts health[:database][:status]  # 'healthy' or 'unhealthy'
puts health[:models]             # Record counts per model
```

### Schema Compatibility Verification
The model loader automatically verifies schema compatibility on startup:

```ruby
ModelLoader.verify_schema_compatibility
# Checks all required tables and columns exist
```

## Migration Notes

### From Laravel to Ruby
1. **No Database Changes Required** - Models work with existing schema
2. **Data Preservation** - All existing data remains accessible
3. **API Compatibility** - JSON output matches Laravel format
4. **Method Compatibility** - All critical Laravel methods implemented
5. **Validation Compatibility** - Same validation rules and error messages

### Performance Considerations
- Connection pooling configured for optimal performance
- Existing database indexes utilized for query optimization
- Lazy loading implemented for associations
- Efficient vote counting and queue ordering

## Requirements Satisfied

This implementation satisfies the following requirements:

- **8.2**: Uses same Database_Schema as Legacy_System
- **8.4**: Supports existing indices and constraints
- **2.1**: Compatible password hashing with Laravel bcrypt
- **3.1-3.4**: Room management functionality preserved
- **4.1-4.3**: Track upload and queue management maintained
- **6.1-6.3**: Voting system functionality preserved

The Sequel models provide a complete, compatible replacement for Laravel Eloquent models while maintaining full backward compatibility with the existing database and API contracts.