# Requirements Document

## Introduction

Spotik is a web application that provides collaborative music listening experiences through shared rooms. Users can create or join rooms, upload audio files, and listen to music synchronously with other participants. The system includes voting mechanisms for track ordering and administrative controls for room management.

## Glossary

- **System**: The complete Spotik web application
- **User**: Any registered person using the application
- **Room**: A virtual space where users can listen to music together
- **Room_Administrator**: The user who created a room and has administrative privileges
- **Track**: An audio file uploaded by a user to a room
- **Track_Queue**: The ordered list of tracks waiting to be played in a room
- **Playback_State**: The current playing status (playing/paused) and position of audio in a room
- **Vote**: A user's like/approval of a track that affects queue ordering
- **Score**: The total number of votes a track has received
- **Synchronization**: Ensuring all users hear the same audio at the same time

## Requirements

### Requirement 1: User Authentication

**User Story:** As a visitor, I want to register and login to the system, so that I can access the collaborative music features.

#### Acceptance Criteria

1. WHEN a visitor provides valid registration information, THE System SHALL create a new user account
2. WHEN a user provides valid login credentials, THE System SHALL authenticate them and provide access
3. WHEN a user provides invalid credentials, THE System SHALL reject the login attempt with an error message
4. THE System SHALL use JWT tokens for maintaining user sessions
5. WHEN a user's session expires, THE System SHALL require re-authentication

### Requirement 2: Room Management

**User Story:** As a user, I want to create and join music rooms, so that I can participate in collaborative listening sessions.

#### Acceptance Criteria

1. WHEN an authenticated user creates a room, THE System SHALL establish a new room with that user as Room_Administrator
2. WHEN a user joins an existing room, THE System SHALL add them to the room's participant list
3. WHEN a user leaves a room, THE System SHALL remove them from the participant list
4. THE System SHALL display the current list of participants to all room members
5. WHEN room membership changes, THE System SHALL notify all participants in real-time

### Requirement 3: Audio File Management

**User Story:** As a room participant, I want to upload audio files from my computer, so that I can share music with other room members.

#### Acceptance Criteria

1. WHEN a user uploads a valid audio file, THE System SHALL store it securely using Laravel Storage
2. WHEN a user uploads an invalid file type, THE System SHALL reject the upload with an error message
3. WHEN an audio file is uploaded, THE System SHALL add it to the room's Track_Queue
4. THE System SHALL support common audio formats (MP3, WAV, M4A)
5. WHEN a track is added to the queue, THE System SHALL notify all room participants

### Requirement 4: Synchronized Music Playback

**User Story:** As a room participant, I want to hear music synchronized with other users, so that we can share the listening experience together.

#### Acceptance Criteria

1. WHEN a track starts playing, THE System SHALL broadcast the start time to all participants
2. WHEN the Room_Administrator pauses playback, THE System SHALL pause for all participants simultaneously
3. WHEN the Room_Administrator resumes playback, THE System SHALL resume for all participants from the correct position
4. THE System SHALL calculate playback position using server timestamps to maintain synchronization
5. WHEN playback state changes, THE System SHALL notify all participants in real-time via WebSocket

### Requirement 5: Track Queue and Voting

**User Story:** As a room participant, I want to vote for tracks I like, so that popular music plays sooner in the queue.

#### Acceptance Criteria

1. WHEN a user votes for a track, THE System SHALL increment that track's Score
2. WHEN a user removes their vote, THE System SHALL decrement the track's Score
3. THE System SHALL order the Track_Queue by Score (highest first), then by upload time
4. WHEN queue ordering changes, THE System SHALL update the display for all participants
5. WHEN voting occurs, THE System SHALL notify all room participants in real-time

### Requirement 6: Room Administration

**User Story:** As a Room_Administrator, I want to control playback and manage the room, so that I can moderate the listening experience.

#### Acceptance Criteria

1. WHEN a Room_Administrator pauses a track, THE System SHALL pause playback for all participants
2. WHEN a Room_Administrator resumes a track, THE System SHALL resume playback for all participants
3. WHEN a Room_Administrator skips a track, THE System SHALL move to the next track in the queue
4. THE System SHALL restrict playback controls to Room_Administrator only
5. WHEN administrative actions occur, THE System SHALL notify all participants immediately

### Requirement 7: Real-time Communication

**User Story:** As a room participant, I want to receive immediate updates about room activities, so that I stay synchronized with other users.

#### Acceptance Criteria

1. WHEN a user joins or leaves a room, THE System SHALL broadcast this event to all participants
2. WHEN a track is added to the queue, THE System SHALL notify all room members immediately
3. WHEN voting occurs, THE System SHALL update vote counts for all participants in real-time
4. WHEN playback state changes, THE System SHALL synchronize all participants immediately
5. THE System SHALL use WebSocket connections for all real-time communications

### Requirement 8: Data Persistence and Storage

**User Story:** As a system administrator, I want user data and audio files to be stored reliably, so that the service remains available and data is not lost.

#### Acceptance Criteria

1. THE System SHALL store user accounts in PostgreSQL database
2. THE System SHALL store room information and track metadata in PostgreSQL
3. THE System SHALL store audio files using Laravel Storage system
4. THE System SHALL use Redis for WebSocket broadcasting and real-time state management
5. WHEN storing data, THE System SHALL ensure data integrity and consistency

### Requirement 9: Web Application Interface

**User Story:** As a user, I want an intuitive web interface, so that I can easily navigate and use all features.

#### Acceptance Criteria

1. THE System SHALL provide a registration and login interface
2. THE System SHALL display a list of available rooms for joining
3. WHEN in a room, THE System SHALL show the participant list, track queue, and playback controls
4. THE System SHALL provide an interface for uploading audio files
5. THE System SHALL display voting options for each track in the queue

### Requirement 10: System Architecture and Deployment

**User Story:** As a developer, I want the system to be containerized and production-ready, so that it can be deployed reliably.

#### Acceptance Criteria

1. THE System SHALL be containerized using Docker with separate containers for backend, frontend, PostgreSQL, and Redis
2. THE System SHALL use Laravel 12 in API mode for the backend
3. THE System SHALL use Vue 3 with Composition API for the frontend
4. THE System SHALL include docker-compose configuration for easy deployment
5. THE System SHALL follow production-ready code structure and practices