# Track Management Endpoints Implementation

## Overview

This document describes the implementation of track management endpoints for the Ruby Backend Migration project. The implementation provides full compatibility with the existing Laravel API format while adding the track upload, voting, and streaming functionality.

## Implemented Endpoints

### 1. GET /api/rooms/:id/tracks - Get room track queue

**Purpose**: Retrieve the track queue for a specific room, ordered by vote score (descending) then upload time (ascending).

**Authentication**: Required (JWT token)

**Authorization**: User must be a participant of the room

**Response Format**:
```json
{
  "tracks": [
    {
      "id": "uuid",
      "original_name": "Song Name.mp3",
      "duration_seconds": 180,
      "formatted_duration": "3:00",
      "file_size_bytes": 5242880,
      "formatted_file_size": "5.0 MB",
      "mime_type": "audio/mpeg",
      "vote_score": 3,
      "votes_count": 3,
      "uploader": {
        "id": "uuid",
        "username": "username"
      },
      "user_has_voted": true,
      "created_at": "2024-01-01T12:00:00Z",
      "file_url": "/api/tracks/uuid/stream"
    }
  ],
  "total_count": 1
}
```

### 2. POST /api/rooms/:id/tracks - Upload new track

**Purpose**: Upload a new audio file to a room's track queue.

**Authentication**: Required (JWT token)

**Authorization**: User must be a participant of the room

**Request Format**: Multipart form data with `audio_file` field

**Supported Formats**: MP3, WAV, M4A (max 50MB)

**Response Format**:
```json
{
  "message": "Track uploaded successfully",
  "track": {
    "id": "uuid",
    "original_name": "Song Name.mp3",
    "duration_seconds": 180,
    "formatted_duration": "3:00",
    "file_size_bytes": 5242880,
    "formatted_file_size": "5.0 MB",
    "mime_type": "audio/mpeg",
    "vote_score": 0,
    "uploader": {
      "id": "uuid",
      "username": "username"
    },
    "user_has_voted": false,
    "votes_count": 0,
    "created_at": "2024-01-01T12:00:00Z",
    "file_url": "/api/tracks/uuid/stream"
  }
}
```

**Auto-playback**: If no track is currently playing and this is the first track in the queue, playback will start automatically.

### 3. POST /api/tracks/:id/vote - Vote for track

**Purpose**: Add a vote for a specific track.

**Authentication**: Required (JWT token)

**Authorization**: User must be a participant of the track's room

**Response Format**:
```json
{
  "message": "Vote added successfully",
  "vote_score": 3,
  "user_has_voted": true
}
```

**Behavior**: 
- Prevents duplicate votes from the same user
- Updates track vote score
- Reorders track queue based on new vote counts

### 4. DELETE /api/tracks/:id/vote - Remove vote

**Purpose**: Remove a user's vote from a specific track.

**Authentication**: Required (JWT token)

**Authorization**: User must be a participant of the track's room

**Response Format**:
```json
{
  "message": "Vote removed successfully",
  "vote_score": 2,
  "user_has_voted": false
}
```

### 5. GET /api/tracks/:id/stream - Stream track audio file

**Purpose**: Stream the audio file for a specific track.

**Authentication**: Required (JWT token)

**Authorization**: User must be a participant of the track's room

**Features**:
- HTTP Range request support for audio seeking
- Proper MIME type headers
- Caching headers for performance
- Content-Disposition header with original filename

## Implementation Details

### File Service (FileService)

**Location**: `ruby-backend/app/services/file_service.rb`

**Key Features**:
- Audio file validation (format, size, content)
- Secure file storage with UUID filenames
- Basic audio metadata extraction
- File serving with proper headers
- File cleanup on errors

**Supported Formats**:
- MP3 (audio/mpeg)
- WAV (audio/wav)
- M4A (audio/mp4, audio/x-m4a)

**Validation**:
- File size limit: 50MB
- MIME type validation
- File extension validation
- Basic audio header validation
- Empty file detection

### Track Controller (TrackController)

**Location**: `ruby-backend/app/controllers/track_controller.rb`

**Key Methods**:
- `index(room_id, token)` - Get track queue
- `store(room_id, file_data, token)` - Upload track
- `vote(track_id, token)` - Vote for track
- `unvote(track_id, token)` - Remove vote
- `stream(track_id, token, range_header)` - Stream audio

**Error Handling**:
- Authentication errors (401)
- Authorization errors (403)
- Not found errors (404)
- Validation errors (422)
- Server errors (500)

### Database Models

**Track Model** (`ruby-backend/app/models/track.rb`):
- Vote management methods
- File URL generation
- Formatted duration and file size
- Laravel compatibility methods

**TrackVote Model** (`ruby-backend/app/models/track_vote.rb`):
- Unique vote constraints
- Automatic vote score updates
- User and track associations

**Room Model** (`ruby-backend/app/models/room.rb`):
- Track queue ordering method
- Participant management
- Playback control methods

## Server Integration

The track management endpoints are integrated into the main server (`ruby-backend/server.rb`) with the following routes:

```ruby
# Track management endpoints
get '/api/rooms/:id/tracks'
post '/api/rooms/:id/tracks'

# Track voting endpoints  
post '/api/tracks/:id/vote'
delete '/api/tracks/:id/vote'

# Track streaming endpoint
get '/api/tracks/:id/stream'
```

## File Storage

**Storage Directory**: `./storage/tracks/`

**File Naming**: UUID-based filenames to prevent conflicts and enhance security

**File Structure**:
```
storage/
└── tracks/
    ├── 550e8400-e29b-41d4-a716-446655440000.mp3
    ├── 6ba7b810-9dad-11d1-80b4-00c04fd430c8.wav
    └── 6ba7b811-9dad-11d1-80b4-00c04fd430c8.m4a
```

## Testing

### Logic Tests

**File**: `ruby-backend/test_track_logic.rb`

**Coverage**:
- File validation logic
- Vote counting logic
- Track queue ordering logic
- API response formatting
- Error handling

**Results**: All tests passing ✅

### Integration Tests

**File**: `ruby-backend/test_track_endpoints.rb`

**Coverage**:
- Full endpoint testing with HTTP requests
- File upload testing
- Authentication and authorization
- Error scenarios

**Note**: Requires running server for full integration testing

## Laravel Compatibility

The implementation maintains full compatibility with the existing Laravel API:

### Response Formats
- Identical JSON structure
- Same HTTP status codes
- Compatible error messages
- Same field names and types

### Behavior
- Same validation rules
- Same authorization logic
- Same file handling
- Same voting mechanics

### Database Schema
- Uses existing PostgreSQL tables
- Compatible with existing data
- Same foreign key relationships
- Same constraints and indexes

## WebSocket Integration (TODO)

The implementation includes placeholders for WebSocket event broadcasting:

- `track_added` - When a track is uploaded
- `track_voted` - When a track receives a vote
- `track_unvoted` - When a vote is removed
- `playback_started` - When auto-playback begins

These will be implemented when the WebSocket system is added in future tasks.

## Performance Considerations

### File Handling
- Streaming support for large audio files
- HTTP Range request support for seeking
- Proper caching headers
- Efficient file validation

### Database
- Optimized track queue queries
- Vote counting with database constraints
- Proper indexing on vote_score and created_at

### Memory Management
- File cleanup on errors
- Streaming responses for large files
- Minimal memory footprint for file operations

## Security Features

### File Upload Security
- MIME type validation
- File extension validation
- File size limits
- Content validation
- Secure filename generation

### Access Control
- JWT authentication required
- Room participation validation
- User authorization checks
- File access permissions

## Error Handling

### Validation Errors
- Comprehensive file validation
- Clear error messages
- Laravel-compatible error format
- Proper HTTP status codes

### Runtime Errors
- Graceful error handling
- File cleanup on failures
- Detailed logging
- User-friendly error messages

## Future Enhancements

### Planned Features
1. WebSocket event broadcasting
2. Advanced audio metadata extraction
3. Thumbnail generation for audio files
4. Playlist management
5. Track history and analytics

### Performance Optimizations
1. File caching strategies
2. CDN integration for file serving
3. Background processing for file uploads
4. Database query optimization

## Conclusion

The track management endpoints implementation provides a complete, Laravel-compatible solution for audio file upload, voting, and streaming. The implementation includes comprehensive validation, security features, and error handling while maintaining full compatibility with the existing frontend application.

All core functionality has been implemented and tested, with the system ready for integration with the WebSocket broadcasting system in future development phases.