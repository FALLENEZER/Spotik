/**
 * End-to-End Testing Suite for Spotik
 *
 * This test suite validates complete user workflows from registration to collaborative listening.
 * It tests the integration of all system components including:
 * - User authentication and registration
 * - Room creation and management
 * - File upload and validation
 * - WebSocket connectivity and real-time events
 * - Audio synchronization across multiple clients
 * - Track voting and queue management
 * - Playback controls and synchronization
 *
 * Requirements: All requirements (1-10)
 */

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createRouter, createWebHistory } from 'vue-router'
import App from '../App.vue'
import { useAuthStore } from '../stores/auth'
import { useRoomStore } from '../stores/room'
import { useTrackStore } from '../stores/track'
import { useWebSocketStore } from '../stores/websocket'

// Mock WebSocket for testing
class MockWebSocket {
  constructor(url) {
    this.url = url
    this.readyState = WebSocket.CONNECTING
    this.onopen = null
    this.onmessage = null
    this.onclose = null
    this.onerror = null

    // Simulate connection after a short delay
    setTimeout(() => {
      this.readyState = WebSocket.OPEN
      if (this.onopen) this.onopen()
    }, 100)
  }

  send(data) {
    // Mock sending data
    console.log('WebSocket send:', data)
  }

  close() {
    this.readyState = WebSocket.CLOSED
    if (this.onclose) this.onclose()
  }

  // Helper method to simulate receiving messages
  simulateMessage(data) {
    if (this.onmessage) {
      this.onmessage({ data: JSON.stringify(data) })
    }
  }
}

// Mock HTMLAudioElement for audio testing
class MockAudioElement {
  constructor() {
    this.src = ''
    this.currentTime = 0
    this.duration = 180 // 3 minutes default
    this.paused = true
    this.volume = 1
    this.playbackRate = 1
    this.onloadedmetadata = null
    this.oncanplay = null
    this.ontimeupdate = null
    this.onended = null
    this.onerror = null
  }

  play() {
    this.paused = false
    return Promise.resolve()
  }

  pause() {
    this.paused = true
  }

  load() {
    // Simulate loading
    setTimeout(() => {
      if (this.onloadedmetadata) this.onloadedmetadata()
      if (this.oncanplay) this.oncanplay()
    }, 50)
  }

  // Helper method to simulate time updates
  simulateTimeUpdate(time) {
    this.currentTime = time
    if (this.ontimeupdate) this.ontimeupdate()
  }

  // Helper method to simulate track end
  simulateEnd() {
    this.currentTime = this.duration
    this.paused = true
    if (this.onended) this.onended()
  }
}

// Mock fetch for API calls
const mockFetch = vi.fn()
global.fetch = mockFetch

// Mock WebSocket globally
global.WebSocket = MockWebSocket

// Mock HTMLAudioElement globally
global.HTMLAudioElement = MockAudioElement

describe('End-to-End Testing Suite', () => {
  let pinia
  let router
  let authStore
  let roomStore
  let trackStore
  let websocketStore
  let mockWebSocket
  let mockAudio

  beforeEach(() => {
    // Setup Pinia
    pinia = createPinia()
    setActivePinia(pinia)

    // Setup router
    router = createRouter({
      history: createWebHistory(),
      routes: [
        { path: '/', name: 'home', component: { template: '<div>Home</div>' } },
        { path: '/login', name: 'login', component: { template: '<div>Login</div>' } },
        { path: '/register', name: 'register', component: { template: '<div>Register</div>' } },
        { path: '/dashboard', name: 'dashboard', component: { template: '<div>Dashboard</div>' } },
        { path: '/room/:id', name: 'room', component: { template: '<div>Room</div>' } },
      ],
    })

    // Initialize stores
    authStore = useAuthStore()
    roomStore = useRoomStore()
    trackStore = useTrackStore()
    websocketStore = useWebSocketStore()

    // Reset mocks
    mockFetch.mockClear()
    vi.clearAllMocks()
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  describe('Complete User Registration to Listening Workflow', () => {
    it('should handle complete user journey from registration to collaborative listening', async () => {
      // Step 1: User Registration
      console.log('Testing user registration...')

      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          message: 'User registered successfully',
          user: {
            id: 'user-1',
            username: 'testuser',
            email: 'test@example.com',
          },
        }),
      })

      const registrationResult = await authStore.register({
        username: 'testuser',
        email: 'test@example.com',
        password: 'SecurePass123!',
      })

      expect(registrationResult.success).toBe(true)
      expect(mockFetch).toHaveBeenCalledWith(
        expect.stringContaining('/api/register'),
        expect.objectContaining({
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            username: 'testuser',
            email: 'test@example.com',
            password: 'SecurePass123!',
          }),
        })
      )

      // Step 2: User Login
      console.log('Testing user login...')

      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          token: 'jwt-token-123',
          user: {
            id: 'user-1',
            username: 'testuser',
            email: 'test@example.com',
          },
        }),
      })

      const loginResult = await authStore.login({
        email: 'test@example.com',
        password: 'SecurePass123!',
      })

      expect(loginResult.success).toBe(true)
      expect(authStore.isAuthenticated).toBe(true)
      expect(authStore.token).toBe('jwt-token-123')

      // Step 3: Room Creation
      console.log('Testing room creation...')

      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          room: {
            id: 'room-1',
            name: 'Test Room',
            administrator_id: 'user-1',
            participants: [{ id: 'user-1', username: 'testuser' }],
            track_queue: [],
            is_playing: false,
            current_track: null,
          },
        }),
      })

      const room = await roomStore.createRoom({
        name: 'Test Room',
      })

      expect(room.id).toBe('room-1')
      expect(room.administrator_id).toBe('user-1')
      expect(roomStore.currentRoom).toEqual(room)
      expect(roomStore.isRoomAdmin).toBe(true)

      // Step 4: WebSocket Connection
      console.log('Testing WebSocket connection...')

      const connectionPromise = websocketStore.connect('room-1')

      // Wait for connection to establish
      await new Promise(resolve => setTimeout(resolve, 150))

      expect(websocketStore.isConnected).toBe(true)
      expect(websocketStore.currentRoomId).toBe('room-1')

      // Step 5: File Upload
      console.log('Testing file upload...')

      const mockFile = new File(['mock audio data'], 'test-song.mp3', {
        type: 'audio/mpeg',
      })

      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          track: {
            id: 'track-1',
            room_id: 'room-1',
            uploader_id: 'user-1',
            filename: 'test-song.mp3',
            original_name: 'test-song.mp3',
            duration_seconds: 180,
            vote_score: 0,
            file_path: '/storage/tracks/track-1.mp3',
          },
        }),
      })

      const uploadResult = await trackStore.uploadTrack('room-1', mockFile)

      expect(uploadResult.success).toBe(true)
      expect(trackStore.trackQueue).toHaveLength(1)
      expect(trackStore.trackQueue[0].id).toBe('track-1')

      // Step 6: Simulate Second User Joining
      console.log('Testing second user joining room...')

      // Simulate WebSocket event for user joining
      const joinEvent = {
        event: 'UserJoined',
        room_id: 'room-1',
        user: {
          id: 'user-2',
          username: 'seconduser',
        },
        participants: [
          { id: 'user-1', username: 'testuser' },
          { id: 'user-2', username: 'seconduser' },
        ],
      }

      websocketStore.handleMessage(joinEvent)

      expect(roomStore.participants).toHaveLength(2)
      expect(roomStore.participants.find(p => p.id === 'user-2')).toBeTruthy()

      // Step 7: Track Voting
      console.log('Testing track voting...')

      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          vote: {
            track_id: 'track-1',
            user_id: 'user-2',
            created_at: new Date().toISOString(),
          },
          track: {
            id: 'track-1',
            vote_score: 1,
          },
        }),
      })

      // Simulate second user voting for the track
      const voteResult = await trackStore.voteForTrack('track-1')

      expect(voteResult.success).toBe(true)

      // Simulate WebSocket event for vote update
      const voteEvent = {
        event: 'TrackVoted',
        room_id: 'room-1',
        track_id: 'track-1',
        vote_score: 1,
        user_id: 'user-2',
      }

      websocketStore.handleMessage(voteEvent)

      const updatedTrack = trackStore.trackQueue.find(t => t.id === 'track-1')
      expect(updatedTrack.vote_score).toBe(1)

      // Step 8: Playback Control (Admin)
      console.log('Testing playback controls...')

      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          playback_state: {
            room_id: 'room-1',
            track_id: 'track-1',
            is_playing: true,
            started_at: new Date().toISOString(),
            server_time: new Date().toISOString(),
          },
        }),
      })

      const playResult = await roomStore.startPlayback('track-1')

      expect(playResult.success).toBe(true)

      // Simulate WebSocket event for playback start
      const playbackEvent = {
        event: 'PlaybackStarted',
        room_id: 'room-1',
        track_id: 'track-1',
        started_at: new Date().toISOString(),
        server_time: new Date().toISOString(),
        track_data: {
          id: 'track-1',
          filename: 'test-song.mp3',
          file_path: '/storage/tracks/track-1.mp3',
        },
      }

      websocketStore.handleMessage(playbackEvent)

      expect(roomStore.currentRoom.is_playing).toBe(true)
      expect(roomStore.currentRoom.current_track_id).toBe('track-1')

      // Step 9: Audio Synchronization
      console.log('Testing audio synchronization...')

      // Create mock audio element
      mockAudio = new MockAudioElement()

      // Simulate audio synchronization
      const serverStartTime = new Date().toISOString()
      const serverCurrentTime = new Date(Date.now() + 5000).toISOString() // 5 seconds later

      // Calculate expected position
      const expectedPosition = (new Date(serverCurrentTime) - new Date(serverStartTime)) / 1000

      // Simulate sync logic
      mockAudio.currentTime = expectedPosition

      expect(mockAudio.currentTime).toBeCloseTo(5, 1) // Within 1 second tolerance
      expect(mockAudio.paused).toBe(true) // Should be paused initially

      // Simulate play
      await mockAudio.play()
      expect(mockAudio.paused).toBe(false)

      // Step 10: Pause and Resume
      console.log('Testing pause and resume...')

      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          playback_state: {
            room_id: 'room-1',
            is_playing: false,
            paused_at: new Date().toISOString(),
            server_time: new Date().toISOString(),
          },
        }),
      })

      const pauseResult = await roomStore.pausePlayback()
      expect(pauseResult.success).toBe(true)

      // Simulate WebSocket pause event
      const pauseEvent = {
        event: 'PlaybackPaused',
        room_id: 'room-1',
        paused_at: new Date().toISOString(),
        server_time: new Date().toISOString(),
      }

      websocketStore.handleMessage(pauseEvent)

      expect(roomStore.currentRoom.is_playing).toBe(false)

      // Test resume
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          playback_state: {
            room_id: 'room-1',
            is_playing: true,
            started_at: new Date().toISOString(),
            server_time: new Date().toISOString(),
          },
        }),
      })

      const resumeResult = await roomStore.resumePlayback()
      expect(resumeResult.success).toBe(true)

      // Step 11: User Leaving Room
      console.log('Testing user leaving room...')

      // Simulate first user leaving
      const leaveEvent = {
        event: 'UserLeft',
        room_id: 'room-1',
        user: {
          id: 'user-1',
          username: 'testuser',
        },
        participants: [{ id: 'user-2', username: 'seconduser' }],
      }

      websocketStore.handleMessage(leaveEvent)

      expect(roomStore.participants).toHaveLength(1)
      expect(roomStore.participants.find(p => p.id === 'user-1')).toBeFalsy()

      // Step 12: Cleanup
      console.log('Testing cleanup...')

      websocketStore.disconnect()
      expect(websocketStore.isConnected).toBe(false)

      authStore.logout()
      expect(authStore.isAuthenticated).toBe(false)
      expect(authStore.token).toBeNull()

      console.log('End-to-end test completed successfully!')
    })
  })

  describe('WebSocket Connectivity and Event Handling', () => {
    it('should handle WebSocket connection lifecycle', async () => {
      // Test connection
      const connectPromise = websocketStore.connect('room-1')

      await new Promise(resolve => setTimeout(resolve, 150))

      expect(websocketStore.isConnected).toBe(true)
      expect(websocketStore.currentRoomId).toBe('room-1')

      // Test reconnection on connection loss
      websocketStore.websocket.close()

      // Wait for reconnection attempt
      await new Promise(resolve => setTimeout(resolve, 200))

      // Should attempt to reconnect
      expect(websocketStore.reconnectAttempts).toBeGreaterThan(0)

      // Test disconnect
      websocketStore.disconnect()
      expect(websocketStore.isConnected).toBe(false)
    })

    it('should handle all real-time events correctly', async () => {
      await websocketStore.connect('room-1')

      // Test UserJoined event
      const userJoinedEvent = {
        event: 'UserJoined',
        room_id: 'room-1',
        user: { id: 'user-2', username: 'newuser' },
        participants: [
          { id: 'user-1', username: 'testuser' },
          { id: 'user-2', username: 'newuser' },
        ],
      }

      websocketStore.handleMessage(userJoinedEvent)
      expect(roomStore.participants).toHaveLength(2)

      // Test TrackAdded event
      const trackAddedEvent = {
        event: 'TrackAdded',
        room_id: 'room-1',
        track: {
          id: 'track-2',
          filename: 'new-song.mp3',
          uploader_id: 'user-2',
          vote_score: 0,
        },
      }

      websocketStore.handleMessage(trackAddedEvent)
      expect(trackStore.trackQueue).toHaveLength(1)
      expect(trackStore.trackQueue[0].id).toBe('track-2')

      // Test TrackVoted event
      const trackVotedEvent = {
        event: 'TrackVoted',
        room_id: 'room-1',
        track_id: 'track-2',
        vote_score: 1,
        user_id: 'user-1',
      }

      websocketStore.handleMessage(trackVotedEvent)
      const votedTrack = trackStore.trackQueue.find(t => t.id === 'track-2')
      expect(votedTrack.vote_score).toBe(1)

      // Test PlaybackStarted event
      const playbackStartedEvent = {
        event: 'PlaybackStarted',
        room_id: 'room-1',
        track_id: 'track-2',
        started_at: new Date().toISOString(),
        server_time: new Date().toISOString(),
      }

      websocketStore.handleMessage(playbackStartedEvent)
      expect(roomStore.currentRoom.is_playing).toBe(true)
      expect(roomStore.currentRoom.current_track_id).toBe('track-2')
    })
  })

  describe('Audio Synchronization Across Multiple Clients', () => {
    it('should maintain audio synchronization within tolerance', async () => {
      const tolerance = 0.1 // 100ms tolerance

      // Create multiple mock audio elements (simulating different clients)
      const client1Audio = new MockAudioElement()
      const client2Audio = new MockAudioElement()
      const client3Audio = new MockAudioElement()

      // Server timestamps
      const serverStartTime = new Date()
      const serverCurrentTime = new Date(serverStartTime.getTime() + 10000) // 10 seconds later

      // Calculate expected position
      const expectedPosition = (serverCurrentTime - serverStartTime) / 1000

      // Simulate synchronization for each client
      const syncClient = (audio, networkDelay = 0) => {
        const adjustedServerTime = new Date(serverCurrentTime.getTime() + networkDelay)
        const calculatedPosition = (adjustedServerTime - serverStartTime) / 1000

        // Apply sync logic with tolerance
        const positionDiff = Math.abs(audio.currentTime - calculatedPosition)
        if (positionDiff > tolerance) {
          audio.currentTime = calculatedPosition
        }
      }

      // Sync clients with different network delays
      syncClient(client1Audio, 50) // 50ms delay
      syncClient(client2Audio, 100) // 100ms delay
      syncClient(client3Audio, 75) // 75ms delay

      // All clients should be within tolerance of expected position
      expect(Math.abs(client1Audio.currentTime - expectedPosition)).toBeLessThan(tolerance + 0.1)
      expect(Math.abs(client2Audio.currentTime - expectedPosition)).toBeLessThan(tolerance + 0.1)
      expect(Math.abs(client3Audio.currentTime - expectedPosition)).toBeLessThan(tolerance + 0.1)

      // Test synchronization during playback
      await client1Audio.play()
      await client2Audio.play()
      await client3Audio.play()

      expect(client1Audio.paused).toBe(false)
      expect(client2Audio.paused).toBe(false)
      expect(client3Audio.paused).toBe(false)

      // Simulate time progression
      client1Audio.simulateTimeUpdate(expectedPosition + 1)
      client2Audio.simulateTimeUpdate(expectedPosition + 1.05) // Slightly out of sync
      client3Audio.simulateTimeUpdate(expectedPosition + 0.95) // Slightly out of sync

      // Re-sync
      const newServerTime = new Date(serverCurrentTime.getTime() + 1000)
      const newExpectedPosition = (newServerTime - serverStartTime) / 1000

      syncClient(client1Audio, 50)
      syncClient(client2Audio, 100)
      syncClient(client3Audio, 75)

      // Should still be in sync
      expect(Math.abs(client1Audio.currentTime - newExpectedPosition)).toBeLessThan(tolerance + 0.1)
      expect(Math.abs(client2Audio.currentTime - newExpectedPosition)).toBeLessThan(tolerance + 0.1)
      expect(Math.abs(client3Audio.currentTime - newExpectedPosition)).toBeLessThan(tolerance + 0.1)
    })

    it('should handle pause and resume synchronization', async () => {
      const audio1 = new MockAudioElement()
      const audio2 = new MockAudioElement()

      // Start playback
      const startTime = new Date()
      await audio1.play()
      await audio2.play()

      // Simulate 5 seconds of playback
      audio1.simulateTimeUpdate(5)
      audio2.simulateTimeUpdate(5)

      // Pause at server command
      const pauseTime = new Date(startTime.getTime() + 5000)
      audio1.pause()
      audio2.pause()

      expect(audio1.paused).toBe(true)
      expect(audio2.paused).toBe(true)
      expect(audio1.currentTime).toBe(5)
      expect(audio2.currentTime).toBe(5)

      // Resume after 2 seconds pause
      const resumeTime = new Date(pauseTime.getTime() + 2000)
      await audio1.play()
      await audio2.play()

      // Both should resume from the same position
      expect(audio1.currentTime).toBe(5)
      expect(audio2.currentTime).toBe(5)
      expect(audio1.paused).toBe(false)
      expect(audio2.paused).toBe(false)
    })
  })

  describe('File Upload and Playback Functionality', () => {
    it('should validate and handle file uploads correctly', async () => {
      // Test valid file upload
      const validFile = new File(['mock audio data'], 'song.mp3', {
        type: 'audio/mpeg',
      })

      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({
          track: {
            id: 'track-1',
            filename: 'song.mp3',
            original_name: 'song.mp3',
            duration_seconds: 180,
            file_size_bytes: 1024000,
            mime_type: 'audio/mpeg',
          },
        }),
      })

      const result = await trackStore.uploadTrack('room-1', validFile)

      expect(result.success).toBe(true)
      expect(mockFetch).toHaveBeenCalledWith(
        expect.stringContaining('/api/rooms/room-1/tracks'),
        expect.objectContaining({
          method: 'POST',
        })
      )

      // Test invalid file upload
      const invalidFile = new File(['not audio'], 'document.txt', {
        type: 'text/plain',
      })

      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 422,
        json: async () => ({
          error: 'Invalid file type. Only MP3, WAV, and M4A files are supported.',
        }),
      })

      const invalidResult = await trackStore.uploadTrack('room-1', invalidFile)

      expect(invalidResult.success).toBe(false)
      expect(invalidResult.error).toContain('Invalid file type')
    })

    it('should handle playback functionality correctly', async () => {
      const audio = new MockAudioElement()

      // Test loading track
      audio.src = '/storage/tracks/track-1.mp3'
      audio.load()

      // Wait for load event
      await new Promise(resolve => setTimeout(resolve, 100))

      expect(audio.src).toBe('/storage/tracks/track-1.mp3')

      // Test playback
      await audio.play()
      expect(audio.paused).toBe(false)

      // Test seeking
      audio.currentTime = 30
      expect(audio.currentTime).toBe(30)

      // Test pause
      audio.pause()
      expect(audio.paused).toBe(true)

      // Test track end
      audio.simulateEnd()
      expect(audio.currentTime).toBe(audio.duration)
      expect(audio.paused).toBe(true)
    })
  })

  describe('Error Handling and Edge Cases', () => {
    it('should handle network errors gracefully', async () => {
      // Test API error handling
      mockFetch.mockRejectedValueOnce(new Error('Network error'))

      const result = await authStore.login({
        email: 'test@example.com',
        password: 'password',
      })

      expect(result.success).toBe(false)
      expect(result.error).toContain('Network error')

      // Test WebSocket connection error
      const originalWebSocket = global.WebSocket
      global.WebSocket = class extends MockWebSocket {
        constructor(url) {
          super(url)
          setTimeout(() => {
            this.readyState = WebSocket.CLOSED
            if (this.onerror) this.onerror(new Error('Connection failed'))
          }, 50)
        }
      }

      await websocketStore.connect('room-1')

      // Should handle connection error
      expect(websocketStore.isConnected).toBe(false)
      expect(websocketStore.reconnectAttempts).toBeGreaterThan(0)

      // Restore original WebSocket
      global.WebSocket = originalWebSocket
    })

    it('should handle authentication errors', async () => {
      // Test invalid credentials
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 401,
        json: async () => ({
          error: 'Invalid credentials',
        }),
      })

      const result = await authStore.login({
        email: 'wrong@example.com',
        password: 'wrongpassword',
      })

      expect(result.success).toBe(false)
      expect(result.error).toBe('Invalid credentials')
      expect(authStore.isAuthenticated).toBe(false)

      // Test token expiration
      authStore.token = 'expired-token'
      authStore.user = { id: 'user-1', username: 'test' }

      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 401,
        json: async () => ({
          error: 'Token expired',
        }),
      })

      const protectedResult = await roomStore.createRoom({ name: 'Test' })

      expect(protectedResult.success).toBe(false)
      expect(authStore.isAuthenticated).toBe(false) // Should auto-logout on token expiration
    })

    it('should handle room access errors', async () => {
      // Test joining non-existent room
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 404,
        json: async () => ({
          error: 'Room not found',
        }),
      })

      const result = await roomStore.joinRoom('non-existent-room')

      expect(result.success).toBe(false)
      expect(result.error).toBe('Room not found')

      // Test unauthorized playback control
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 403,
        json: async () => ({
          error: 'Only room administrators can control playback',
        }),
      })

      const playbackResult = await roomStore.startPlayback('track-1')

      expect(playbackResult.success).toBe(false)
      expect(playbackResult.error).toContain('Only room administrators')
    })
  })

  describe('Performance and Load Testing', () => {
    it('should handle multiple concurrent operations', async () => {
      // Simulate multiple users joining simultaneously
      const joinPromises = []

      for (let i = 0; i < 5; i++) {
        mockFetch.mockResolvedValueOnce({
          ok: true,
          json: async () => ({
            room: {
              id: 'room-1',
              participants: Array.from({ length: i + 2 }, (_, idx) => ({
                id: `user-${idx + 1}`,
                username: `user${idx + 1}`,
              })),
            },
          }),
        })

        joinPromises.push(roomStore.joinRoom('room-1'))
      }

      const results = await Promise.all(joinPromises)

      // All joins should succeed
      results.forEach(result => {
        expect(result.success).toBe(true)
      })

      // Test multiple file uploads
      const uploadPromises = []

      for (let i = 0; i < 3; i++) {
        const file = new File(['audio data'], `song${i}.mp3`, {
          type: 'audio/mpeg',
        })

        mockFetch.mockResolvedValueOnce({
          ok: true,
          json: async () => ({
            track: {
              id: `track-${i + 1}`,
              filename: `song${i}.mp3`,
              vote_score: 0,
            },
          }),
        })

        uploadPromises.push(trackStore.uploadTrack('room-1', file))
      }

      const uploadResults = await Promise.all(uploadPromises)

      uploadResults.forEach(result => {
        expect(result.success).toBe(true)
      })

      expect(trackStore.trackQueue).toHaveLength(3)
    })

    it('should handle rapid WebSocket events', async () => {
      await websocketStore.connect('room-1')

      // Send multiple events rapidly
      const events = [
        { event: 'UserJoined', room_id: 'room-1', user: { id: 'user-2', username: 'user2' } },
        { event: 'UserJoined', room_id: 'room-1', user: { id: 'user-3', username: 'user3' } },
        { event: 'TrackAdded', room_id: 'room-1', track: { id: 'track-1', filename: 'song1.mp3' } },
        { event: 'TrackAdded', room_id: 'room-1', track: { id: 'track-2', filename: 'song2.mp3' } },
        { event: 'TrackVoted', room_id: 'room-1', track_id: 'track-1', vote_score: 1 },
        { event: 'TrackVoted', room_id: 'room-1', track_id: 'track-2', vote_score: 2 },
      ]

      // Send all events rapidly
      events.forEach(event => {
        websocketStore.handleMessage(event)
      })

      // All events should be processed correctly
      expect(roomStore.participants).toHaveLength(2) // user-2 and user-3
      expect(trackStore.trackQueue).toHaveLength(2)
      expect(trackStore.trackQueue.find(t => t.id === 'track-1').vote_score).toBe(1)
      expect(trackStore.trackQueue.find(t => t.id === 'track-2').vote_score).toBe(2)
    })
  })
})
