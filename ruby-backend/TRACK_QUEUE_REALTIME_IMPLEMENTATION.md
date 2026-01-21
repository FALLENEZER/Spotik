# Track Queue Real-time Management Implementation

## Overview

This document describes the implementation of Task 9.1: "Create track queue management with real-time updates" for the Ruby Backend Migration project. The implementation provides comprehensive real-time track queue management with WebSocket notifications, voting system, and proper queue ordering.

## Features Implemented

### 1. Track Addition with Real-time Updates

**Location**: `app/controllers/track_controller.rb` - `store` method

**Functionality**:
- Tracks are automatically added to the room's queue upon successful upload
- WebSocket notifications are broadcast to all room participants
- Auto-start playback for the first track in an empty room
- Queue position and total track count included in notifications

**WebSocket Event**: `track_added`
```json
{
  "type": "track_added",
  "data": {
    "track": { /* track data */ },
    "room_id": "uuid",
    "uploader": { /* user data */ },
    "queue_position": 1,
    "total_tracks": 5,
    "updated_queue": [ /* full queue array */ ],
    "message": "username added a new track: Song.mp3",
    "timestamp": 1640995200.123
  }
}
```

### 2. Voting System with Real-time Vote Count Updates

**Location**: `app/controllers/track_controller.rb` - `vote` and `unvote` methods

**Functionality**:
- Users can vote for tracks to increase their priority in the queue
- Vote counts are updated in real-time across all connected clients
- Duplicate votes are prevented (one vote per user per track)
- Vote removal is supported with real-time updates

**WebSocket Events**: `track_voted` and `track_unvoted`
```json
{
  "type": "track_voted",
  "data": {
    "track": { /* track data with updated vote_score */ },
    "room_id": "uuid",
    "voter": { /* user data */ },
    "new_vote_score": 3,
    "updated_queue": [ /* reordered queue */ ],
    "message": "username voted for Song.mp3",
    "timestamp": 1640995200.123
  }
}
```

### 3. Queue Reordering Based on Votes and Upload Time

**Location**: `app/models/room.rb` - `track_queue` method

**Ordering Logic**:
1. **Primary**: Vote score (highest first)
2. **Secondary**: Upload time (oldest first) - acts as tiebreaker

**Implementation**:
```ruby
def track_queue
  tracks_dataset.order(Sequel.desc(:vote_score), :created_at)
end
```

**Queue Change Detection**:
- Implemented in `TrackController.check_queue_order_changed`
- Compares queue order before and after vote changes
- Only broadcasts reorder events when actual position changes occur

### 4. Track Queue Broadcasting to All Room Participants

**Location**: `app/services/room_manager.rb` - `broadcast_to_room` method

**Broadcasting Infrastructure**:
- Uses existing WebSocket connection system
- Broadcasts to all authenticated users in a room
- Includes comprehensive room state in broadcasts
- Handles connection failures gracefully

**WebSocket Event**: `queue_reordered`
```json
{
  "type": "queue_reordered",
  "data": {
    "room_id": "uuid",
    "updated_queue": [ /* full reordered queue */ ],
    "reorder_reason": "vote_added",
    "affected_track": { /* track that caused reorder */ },
    "message": "Queue reordered due to vote for Song.mp3",
    "timestamp": 1640995200.123
  }
}
```

### 5. Enhanced Track Queue Retrieval

**Location**: `app/controllers/track_controller.rb` - `index` method

**User-specific Data**:
- `user_has_voted`: Boolean indicating if current user voted for each track
- `votes_count`: Current vote count for each track
- `queue_position`: Position in the queue (1-based)
- `voters`: List of usernames who voted (debug mode only)

**Response Format**:
```json
{
  "tracks": [
    {
      "id": "uuid",
      "original_name": "Song.mp3",
      "vote_score": 3,
      "user_has_voted": true,
      "votes_count": 3,
      "queue_position": 1,
      /* ... other track data ... */
    }
  ],
  "total_count": 5
}
```

### 6. WebSocket Integration

**Location**: `app/websocket/connection.rb`

**New WebSocket Message Types**:
- `get_track_queue`: Request current track queue
- `vote_track`: Vote for a track via WebSocket
  - `vote_type`: "up" to add vote, "remove" to remove vote
  - `track_id`: ID of track to vote for

**Enhanced Vote Handling**:
- Delegates to TrackController methods for consistency
- Provides immediate feedback to the voting user
- Ensures HTTP API and WebSocket API behave identically

## Requirements Satisfaction

### Requirement 4.3: Track Addition to Queue
✅ **Implemented**: Tracks are automatically added to room queue upon upload

### Requirement 4.5: WebSocket Notifications on Track Addition
✅ **Implemented**: `track_added` event broadcast to all room participants

### Requirement 6.1: Vote Count Increases
✅ **Implemented**: Vote score increments when users vote for tracks

### Requirement 6.2: Vote Count Decreases
✅ **Implemented**: Vote score decrements when users remove votes

### Requirement 6.3: Queue Ordering
✅ **Implemented**: Queue ordered by vote score (desc) then upload time (asc)

### Requirement 6.4: Queue Updates to All Participants
✅ **Implemented**: `queue_reordered` event broadcast when order changes

### Requirement 6.5: Voting Notifications via WebSocket
✅ **Implemented**: `track_voted` and `track_unvoted` events broadcast

## Technical Implementation Details

### Queue Ordering Algorithm

```ruby
# Primary sort: vote_score descending
# Secondary sort: created_at ascending (tiebreaker)
tracks_dataset.order(Sequel.desc(:vote_score), :created_at)
```

**Example Queue Order**:
1. Track A: 5 votes, uploaded 2 hours ago
2. Track B: 3 votes, uploaded 1 hour ago  
3. Track C: 3 votes, uploaded 3 hours ago (older wins tiebreaker)
4. Track D: 0 votes, uploaded 30 minutes ago

### Real-time Broadcasting Flow

1. **User Action** (vote, upload, etc.)
2. **Database Update** (vote count, track creation)
3. **Queue Recalculation** (new ordering)
4. **Event Broadcasting** (WebSocket to all room participants)
5. **Client Updates** (UI reflects new state)

### Error Handling

- **Authentication Failures**: Proper error responses for invalid tokens
- **Permission Checks**: Users must be room participants to vote/upload
- **Duplicate Votes**: Prevented with appropriate error messages
- **Broadcasting Failures**: Logged but don't prevent operation completion
- **Database Errors**: Proper rollback and error reporting

### Performance Considerations

- **Queue Caching**: Room state cached for 5 seconds to reduce database load
- **Efficient Queries**: Single query for track queue with proper indexing
- **Minimal Broadcasting**: Only broadcast when actual changes occur
- **Connection Management**: Proper cleanup of WebSocket connections

## Testing

### Logic Tests
- Queue ordering algorithm verified
- Queue reordering detection tested
- WebSocket event structure validation
- User-specific data formatting

### Integration Points
- TrackController HTTP API endpoints
- WebSocket message handling
- RoomManager broadcasting
- Database model relationships

## Files Modified

1. **`app/controllers/track_controller.rb`**
   - Enhanced `store` method with real-time broadcasting
   - Enhanced `vote` and `unvote` methods with queue reordering
   - Enhanced `index` method with user-specific data
   - Added `check_queue_order_changed` helper method

2. **`app/websocket/connection.rb`**
   - Enhanced `handle_vote_track` to use TrackController
   - Added `handle_get_track_queue` method
   - Improved consistency between HTTP and WebSocket APIs

3. **`app/models/room.rb`**
   - Enhanced `track_queue` method
   - Added `track_queue_with_positions` method
   - Improved `next_track` method to exclude current track

## WebSocket Event Summary

| Event Type | Trigger | Purpose |
|------------|---------|---------|
| `track_added` | Track upload | Notify all participants of new track |
| `track_voted` | User votes | Update vote counts and queue order |
| `track_unvoted` | User removes vote | Update vote counts and queue order |
| `queue_reordered` | Queue order changes | Notify of new queue arrangement |
| `playback_started` | Auto-start playback | Notify of automatic playback start |

## Future Enhancements

1. **Vote Limits**: Implement maximum votes per user
2. **Track Skipping**: Allow users to vote to skip current track
3. **Queue Manipulation**: Allow administrators to manually reorder queue
4. **Vote History**: Track voting history for analytics
5. **Real-time Sync**: Ensure queue state consistency across all clients

## Conclusion

Task 9.1 has been successfully implemented with comprehensive real-time track queue management. The system provides:

- ✅ Real-time track addition with WebSocket notifications
- ✅ Voting system with live vote count updates  
- ✅ Intelligent queue reordering based on votes and upload time
- ✅ Broadcasting of all queue changes to room participants
- ✅ User-specific voting data in API responses
- ✅ Consistent behavior between HTTP and WebSocket APIs

The implementation satisfies all specified requirements (4.3, 4.5, 6.1, 6.2, 6.3, 6.4, 6.5) and provides a solid foundation for the real-time collaborative music experience in Spotik.