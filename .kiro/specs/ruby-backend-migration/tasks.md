# Implementation Plan: Ruby Backend Migration

## Overview

Данный план описывает пошаговую миграцию существующего Laravel бэкенда приложения Spotik на Ruby с встроенными WebSocket'ами. Каждая задача построена инкрементально, обеспечивая постепенную замену функциональности с сохранением совместимости с существующим фронтендом.

## Tasks

- [x] 1. Setup Ruby project structure and core dependencies
  - Create Ruby project directory structure
  - Setup Gemfile with required dependencies (iodine, sinatra, sequel, jwt, bcrypt)
  - Configure database connection to existing PostgreSQL
  - Create basic server.rb file with Iodine initialization
  - _Requirements: 1.1, 8.1, 14.1_

- [x] 2. Implement database models and compatibility layer
  - [x] 2.1 Create Sequel models for existing database schema
    - Implement User model with existing table structure
    - Implement Room model with relationships and methods
    - Implement Track model with vote counting functionality
    - Implement TrackVote and RoomParticipant models
    - _Requirements: 8.2, 8.4_
  
  - [x] 2.2 Write property test for database compatibility
    - **Property 13: Database Compatibility**
    - **Validates: Requirements 8.3, 8.5**
  
  - [x] 2.3 Create database connection and migration validation
    - Setup connection pooling and error handling
    - Validate existing schema compatibility on startup
    - Implement database health check endpoint
    - _Requirements: 8.1, 14.4_

- [x] 3. Implement authentication system
  - [x] 3.1 Create authentication service and JWT handling
    - Implement password hashing compatibility with Laravel bcrypt
    - Create JWT token generation and validation
    - Implement user registration and login logic
    - _Requirements: 2.1, 2.2, 2.3_
  
  - [x] 3.2 Write property test for authentication compatibility
    - **Property 3: Authentication Compatibility**
    - **Validates: Requirements 2.1, 2.3**
  
  - [x] 3.3 Write property test for JWT token management
    - **Property 4: JWT Token Management**
    - **Validates: Requirements 2.2, 2.4, 2.5**

- [x] 4. Create HTTP REST API endpoints
  - [x] 4.1 Implement authentication endpoints
    - POST /api/auth/login - User login
    - POST /api/auth/register - User registration
    - GET /api/auth/me - Get current user info
    - _Requirements: 9.1, 9.2_
  
  - [x] 4.2 Implement room management endpoints
    - GET /api/rooms - List all rooms
    - POST /api/rooms - Create new room
    - GET /api/rooms/:id - Get room details
    - POST /api/rooms/:id/join - Join room
    - DELETE /api/rooms/:id/leave - Leave room
    - _Requirements: 3.1, 3.2, 3.3, 9.1_
  
  - [x] 4.3 Implement track management endpoints
    - GET /api/rooms/:id/tracks - Get room track queue
    - POST /api/rooms/:id/tracks - Upload new track
    - POST /api/tracks/:id/vote - Vote for track
    - DELETE /api/tracks/:id/vote - Remove vote
    - _Requirements: 4.1, 4.3, 6.1, 6.2_
  
  - [x] 4.4 Write property test for HTTP API compatibility
    - **Property 2: HTTP API Compatibility**
    - **Validates: Requirements 1.3, 9.1, 9.2, 9.3, 9.4, 9.5**

- [x] 5. Checkpoint - Ensure basic API functionality works
  - Ensure all tests pass, ask the user if questions arise.

- [x] 6. Implement file upload and storage system
  - [x] 6.1 Create file service for audio file handling
    - Implement file upload validation (MP3, WAV, M4A)
    - Create file storage in compatible directory structure
    - Implement audio metadata extraction (duration, file size)
    - Add file serving with proper MIME types and caching headers
    - _Requirements: 4.1, 4.2, 4.4, 10.1, 10.2, 10.3, 10.5_
  
  - [x] 6.2 Write property test for audio file validation
    - **Property 6: Audio File Upload and Validation**
    - **Validates: Requirements 4.1, 4.2, 4.4**
  
  - [x] 6.3 Write property test for file storage compatibility
    - **Property 14: File Storage Compatibility**
    - **Validates: Requirements 10.1, 10.2, 10.3, 10.5**
  
  - [x] 6.4 Write property test for file access control
    - **Property 15: File Access Control**
    - **Validates: Requirements 10.4**

- [x] 7. Implement WebSocket connection handling
  - [x] 7.1 Create WebSocket connection class and authentication
    - Implement WebSocket upgrade handling in Sinatra
    - Create WebSocketConnection class with authentication
    - Implement connection lifecycle management (open, close, error)
    - Add JWT token validation for WebSocket connections
    - _Requirements: 1.2, 7.2, 7.3_
  
  - [x] 7.2 Write property test for WebSocket connection support
    - **Property 1: WebSocket Connection Support**
    - **Validates: Requirements 1.2, 7.2**
  
  - [x] 7.3 Write property test for WebSocket authentication
    - **Property 11: WebSocket Authentication**
    - **Validates: Requirements 7.3**

- [x] 8. Implement room management and real-time events
  - [x] 8.1 Create room manager with WebSocket broadcasting
    - Implement room join/leave functionality with WebSocket notifications
    - Create participant list management
    - Implement room state broadcasting to all participants
    - Add room cleanup when users disconnect
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_
  
  - [x] 8.2 Write property test for room membership management
    - **Property 5: Room Membership Management**
    - **Validates: Requirements 3.1, 3.2, 3.3, 3.4**
  
  - [x] 8.3 Write property test for connection cleanup
    - **Property 12: Connection Cleanup**
    - **Validates: Requirements 7.5**

- [x] 9. Implement track queue and voting system
  - [x] 9.1 Create track queue management with real-time updates
    - Implement track addition to queue with WebSocket notifications
    - Create voting system with real-time vote count updates
    - Implement queue reordering based on votes and upload time
    - Add track queue broadcasting to all room participants
    - _Requirements: 4.3, 4.5, 6.1, 6.2, 6.3, 6.4, 6.5_
  
  - [x] 9.2 Write property test for track queue management
    - **Property 7: Track Queue Management**
    - **Validates: Requirements 4.3, 6.3**
  
  - [x] 9.3 Write property test for voting system integrity
    - **Property 9: Voting System Integrity**
    - **Validates: Requirements 6.1, 6.2**

- [-] 10. Implement synchronized playback control
  - [-] 10.1 Create playback controller with timestamp synchronization
    - Implement play/pause/resume/skip controls for room administrators
    - Create server-side playback position calculation
    - Implement playback state broadcasting with accurate timestamps
    - Add playback synchronization logic for all room participants
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_
  
  - [-] 10.2 Write property test for synchronized playback control
    - **Property 8: Synchronized Playback Control**
    - **Validates: Requirements 5.1, 5.2, 5.3, 5.4**

- [ ] 11. Implement comprehensive real-time event broadcasting
  - [x] 11.1 Create unified event broadcasting system
    - Implement Pub/Sub system using Iodine's native capabilities
    - Create event serialization and broadcasting to room participants
    - Implement event types for all room activities (join/leave, tracks, voting, playback)
    - Add event delivery confirmation and error handling
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5_
  
  - [x] 11.2 Write property test for real-time event broadcasting
    - **Property 10: Real-time Event Broadcasting**
    - **Validates: Requirements 3.5, 4.5, 5.5, 6.4, 6.5, 11.1, 11.2, 11.3, 11.4**

- [ ] 12. Checkpoint - Ensure all core functionality works
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 13. Implement error handling and logging system
  - [x] 13.1 Create comprehensive error handling and logging
    - Implement structured logging for all important events
    - Create error handling for WebSocket connections and API endpoints
    - Add performance logging for critical operations
    - Implement graceful error recovery without server crashes
    - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.5_
  
  - [x] 13.2 Write property test for error handling and logging
    - **Property 17: Error Handling and Logging**
    - **Validates: Requirements 13.1, 13.2, 13.3, 13.4, 13.5**

- [ ] 14. Implement configuration and deployment setup
  - [x] 14.1 Create configuration management system
    - Implement configuration file loading (database, server, storage)
    - Add environment variable support for all settings
    - Create configuration validation on startup
    - Add health check endpoints for monitoring
    - _Requirements: 14.1, 14.2, 14.4, 14.5_
  
  - [x] 14.2 Create Docker containerization
    - Create Dockerfile for Ruby application
    - Setup docker-compose for development and production
    - Configure container networking and volume mounts
    - Add container health checks and restart policies
    - _Requirements: 14.3_
  
  - [x] 14.3 Write property test for configuration management
    - **Property 18: Configuration Management**
    - **Validates: Requirements 14.1, 14.2, 14.5**

- [ ] 15. Performance optimization and benchmarking
  - [x] 15.1 Implement performance optimizations
    - Optimize database queries with proper indexing
    - Implement connection pooling and resource management
    - Add memory usage optimization for WebSocket connections
    - Create performance monitoring and metrics collection
    - _Requirements: 12.1, 12.2, 12.3, 12.4_
  
  - [x] 15.2 Write property test for performance improvements
    - **Property 16: Performance Improvement**
    - **Validates: Requirements 12.1, 12.2, 12.3, 12.4**

- [ ] 16. Migration validation and compatibility testing
  - [x] 16.1 Create comprehensive compatibility test suite
    - Implement tests comparing Ruby system with Legacy_System behavior
    - Create WebSocket event format validation tests
    - Add API endpoint parity verification tests
    - Implement audio synchronization accuracy tests
    - _Requirements: 15.1, 15.2, 15.3, 15.4, 15.5_
  
  - [x] 16.2 Write property test for legacy system compatibility
    - **Property 19: Legacy System Test Compatibility**
    - **Validates: Requirements 15.1, 15.2, 15.3, 15.4, 15.5**

- [ ] 17. Final integration and deployment preparation
  - [x] 17.1 Complete system integration and final testing
    - Run full end-to-end test suite with multiple concurrent users
    - Perform load testing to verify performance improvements
    - Validate all existing Laravel tests pass with Ruby system
    - Create deployment documentation and migration guide
    - _Requirements: 1.5, 15.1, 15.2, 15.3, 15.4, 15.5_

- [x] 18. Final checkpoint - Complete system validation
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation throughout the migration
- Property tests validate universal correctness properties from the design
- Unit tests validate specific migration scenarios and edge cases
- The migration maintains full backward compatibility with existing data and frontend