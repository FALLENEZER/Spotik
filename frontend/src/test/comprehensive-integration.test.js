/**
 * Comprehensive Integration Tests
 *
 * This test suite validates the integration of all major components working together:
 * - Multi-user scenarios with cross-browser synchronization
 * - WebSocket reconnection during active collaboration
 * - Audio synchronization resilience across network issues
 * - End-to-end workflows under various failure conditions
 *
 * Requirements: All requirements (1-10) - Integration testing
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useWebSocketStore } from '@/stores/websocket'
import { useRoomStore } from '@/stores/room'
import { useTrackStore } from '@/stores/track'
import { useAuthStore } from '@/stores/auth'
import { useAudioPlayer } from '@/composables/useAudioPlayer'

// Comprehensive test environment that combines all previous mocks
class IntegratedTestEnvironment {
  constructor() {
    this.users = new Map()
    this.rooms = new Map()
    this.networkConditions = {
      latency: 50,
      jitter: 10,
      dropRate: 0.05,
      disconnectionRate: 0.01,
    }
    this.serverTime = Date.now()
    this.messageQueue = []
  }

  createUser(userId, username, browserType = 'chrome', isAdmin = false) {
    const user = new IntegratedUser(userId, username, browserType, isAdmin, this)
    this.users.set(userId, user)
    return user
  }

  createRoom(roomId, adminUserId) {
    const room = {
      id: roomId,
      name: `Room ${roomId}`,
      administrator_id: adminUserId,
      participants: [],
      track_queue: [],
      is_playing: false,
      current_track_id: null,
      playback_started_at: null,
      playback_paused_at: null,
    }
    this.rooms.set(roomId, room)
    return room
  }

  simulateNetworkIssues(severity = 'mild') {
    const profiles = {
      mild: { latency: 100, jitter: 20, dropRate: 0.1, disconnectionRate: 0.02 },
      moderate: { latency: 200, jitter: 50, dropRate: 0.2, disconnectionRate: 0.05 },
      severe: { latency: 500, jitter: 100, dropRate: 0.4, disconnectionRate: 0.1 },
    }

    this.networkConditions = profiles[severity] || profiles.mild
  }

  restoreNetworkConditions() {
    this.networkConditions = {
      latency: 50,
      jitter: 10,
      dropRate: 0.05,
      disconnectionRate: 0.01,
    }
  }

  broadcastToRoom(roomId, message, excludeUserId = null) {
    const room = this.rooms.get(roomId)
    if (!room) return

    room.participants.forEach(participantId => {
      if (participantId !== excludeUserId) {
        const user = this.users.get(participantId)
        if (user && user.isConnected()) {
          // Simulate network conditions
          const shouldDrop = Math.random() < this.networkConditions.dropRate
          const shouldDisconnect = Math.random() < this.networkConditions.disconnectionRate

          if (shouldDisconnect) {
            user.simulateDisconnection()
          } else if (!shouldDrop) {
            const delay =
              this.networkConditions.latency + (Math.random() - 0.5) * this.networkConditions.jitter

            setTimeout(
              () => {
                user.receiveMessage(message)
              },
              Math.max(0, delay)
            )
          }
        }
      }
    })
  }

  getServerTime() {
    return new Date(this.serverTime).toISOString()
  }

  advanceServerTime(ms) {
    this.serverTime += ms
  }
}

class IntegratedUser {
  constructor(userId, username, browserType, isAdmin, environment) {
    this.userId = userId
    this.username = username
    this.browserType = browserType
    this.isAdmin = isAdmin
    this.environment = environment

    // Set up Pinia stores
    this.pinia = createPinia()
    setActivePinia(this.pinia)

    this.authStore = useAuthStore()
    this.roomStore = useRoomStore()
    this.trackStore = useTrackStore()
    this.websocketStore = useWebSocketStore()
    this.audioPlayer = useAudioPlayer()

    // Connection state
    this.connected = false
    this.reconnectAttempts = 0
    this.messageQueue = []

    // Browser-specific characteristics
    this.browserProfile = this.getBrowserProfile(browserType)

    // Set up authentication
    this.authStore.user = { id: userId, username }
    this.authStore.token = `token-${userId}`
    this.authStore.isAuthenticated = true

    // Mock audio element
    this.setupAudioElement()
  }

  getBrowserProfile(browserType) {
    const profiles = {
      chrome: { timerPrecision: 0.1, audioLatency: 10, syncTolerance: 0.1 },
      firefox: { timerPrecision: 1.0, audioLatency: 15, syncTolerance: 0.15 },
      safari: { timerPrecision: 1.0, audioLatency: 25, syncTolerance: 0.2 },
      edge: { timerPrecision: 0.1, audioLatency: 12, syncTolerance: 0.12 },
    }

    return profiles[browserType] || profiles.chrome
  }

  setupAudioElement() {
    const mockAudio = {
      currentTime: 0,
      duration: 180,
      paused: true,
      volume: 0.75,
      src: '',

      play: vi.fn().mockResolvedValue(),
      pause: vi.fn(),
      load: vi.fn(),

      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
      dispatchEvent: vi.fn(),
    }

    // Apply browser-specific timing precision
    Object.defineProperty(mockAudio, 'currentTime', {
      get: () => {
        const precision = this.browserProfile.timerPrecision / 1000
        return Math.round(mockAudio._currentTime / precision) * precision
      },
      set: value => {
        mockAudio._currentTime = value
      },
    })

    mockAudio._currentTime = 0

    global.Audio = vi.fn(() => mockAudio)
    this.audioElement = mockAudio
  }

  async connect() {
    // Simulate connection delay based on network conditions
    const delay = this.environment.networkConditions.latency

    return new Promise(resolve => {
      setTimeout(() => {
        this.connected = true
        this.reconnectAttempts = 0
        this.processQueuedMessages()
        resolve(true)
      }, delay)
    })
  }

  simulateDisconnection() {
    this.connected = false
    this.reconnectAttempts++

    // Attempt reconnection with exponential backoff
    const backoffDelay = Math.min(1000 * Math.pow(2, this.reconnectAttempts - 1), 30000)

    setTimeout(() => {
      if (!this.connected && this.reconnectAttempts < 5) {
        this.connect()
      }
    }, backoffDelay)
  }

  isConnected() {
    return this.connected
  }

  async joinRoom(roomId) {
    const room = this.environment.rooms.get(roomId)
    if (!room) {
      throw new Error('Room not found')
    }

    // Add to room participants
    if (!room.participants.includes(this.userId)) {
      room.participants.push(this.userId)
    }

    // Update local state
    this.roomStore.currentRoom = { ...room }
    this.roomStore.participants = room.participants.map(id => {
      const user = this.environment.users.get(id)
      return { id, username: user?.username || `user-${id}` }
    })

    // Broadcast join event
    this.environment.broadcastToRoom(
      roomId,
      {
        event: 'UserJoined',
        room_id: roomId,
        user: { id: this.userId, username: this.username },
        timestamp: this.environment.getServerTime(),
      },
      this.userId
    )

    return { success: true }
  }

  async uploadTrack(filename, duration = 180) {
    const roomId = this.roomStore.currentRoom?.id
    if (!roomId) {
      throw new Error('Not in a room')
    }

    const track = {
      id: `track-${Date.now()}-${Math.random()}`,
      room_id: roomId,
      uploader_id: this.userId,
      filename,
      original_name: filename,
      duration_seconds: duration,
      vote_score: 0,
      uploader: { id: this.userId, username: this.username },
      created_at: this.environment.getServerTime(),
    }

    // Add to room's track queue
    const room = this.environment.rooms.get(roomId)
    room.track_queue.push(track)

    // Update local state
    this.trackStore.trackQueue.push(track)

    // Broadcast track added event
    this.sendMessage({
      event: 'TrackAdded',
      room_id: roomId,
      track,
      user_id: this.userId,
      timestamp: this.environment.getServerTime(),
    })

    return { success: true, track }
  }

  async voteForTrack(trackId) {
    const roomId = this.roomStore.currentRoom?.id
    if (!roomId) {
      throw new Error('Not in a room')
    }

    const room = this.environment.rooms.get(roomId)
    const track = room.track_queue.find(t => t.id === trackId)

    if (!track) {
      throw new Error('Track not found')
    }

    // Update vote score
    track.vote_score += 1

    // Update local state
    const localTrack = this.trackStore.trackQueue.find(t => t.id === trackId)
    if (localTrack) {
      localTrack.vote_score = track.vote_score
    }

    // Reorder queue by vote score
    room.track_queue.sort((a, b) => {
      if (b.vote_score !== a.vote_score) {
        return b.vote_score - a.vote_score
      }
      return new Date(a.created_at) - new Date(b.created_at)
    })

    // Broadcast vote event
    this.sendMessage({
      event: 'TrackVoted',
      room_id: roomId,
      track_id: trackId,
      vote_score: track.vote_score,
      user_id: this.userId,
      timestamp: this.environment.getServerTime(),
    })

    return { success: true }
  }

  async startPlayback(trackId) {
    if (!this.isAdmin) {
      throw new Error('Only administrators can control playback')
    }

    const roomId = this.roomStore.currentRoom?.id
    const room = this.environment.rooms.get(roomId)
    const track = room.track_queue.find(t => t.id === trackId)

    if (!track) {
      throw new Error('Track not found')
    }

    const startTime = this.environment.getServerTime()

    // Update room state
    room.is_playing = true
    room.current_track_id = trackId
    room.playback_started_at = startTime
    room.playback_paused_at = null

    // Update local state
    this.roomStore.currentRoom.is_playing = true
    this.roomStore.currentRoom.current_track_id = trackId

    this.trackStore.updatePlaybackState({
      isPlaying: true,
      startedAt: startTime,
      pausedAt: null,
      position: 0,
      duration: track.duration_seconds,
    })

    this.trackStore.setCurrentTrack(track)

    // Broadcast playback started event
    this.sendMessage({
      event: 'PlaybackStarted',
      room_id: roomId,
      track_id: trackId,
      started_at: startTime,
      server_time: startTime,
      track_data: track,
    })

    return { success: true }
  }

  async pausePlayback() {
    if (!this.isAdmin) {
      throw new Error('Only administrators can control playback')
    }

    const roomId = this.roomStore.currentRoom?.id
    const room = this.environment.rooms.get(roomId)
    const pauseTime = this.environment.getServerTime()

    // Calculate current position
    const startTime = new Date(room.playback_started_at).getTime()
    const currentTime = new Date(pauseTime).getTime()
    const position = (currentTime - startTime) / 1000

    // Update room state
    room.is_playing = false
    room.playback_paused_at = pauseTime

    // Update local state
    this.roomStore.currentRoom.is_playing = false
    this.trackStore.updatePlaybackState({
      isPlaying: false,
      pausedAt: pauseTime,
      position,
    })

    // Broadcast pause event
    this.sendMessage({
      event: 'PlaybackPaused',
      room_id: roomId,
      paused_at: pauseTime,
      position,
      server_time: pauseTime,
    })

    return { success: true }
  }

  sendMessage(message) {
    if (this.connected) {
      this.environment.broadcastToRoom(message.room_id, message, this.userId)
    } else {
      // Queue message for later delivery
      this.messageQueue.push({
        message,
        timestamp: Date.now(),
        attempts: 0,
      })
    }
  }

  receiveMessage(message) {
    this.handleWebSocketMessage(message)
  }

  processQueuedMessages() {
    const messages = [...this.messageQueue]
    this.messageQueue = []

    messages.forEach(({ message }) => {
      this.sendMessage(message)
    })
  }

  handleWebSocketMessage(data) {
    switch (data.event) {
      case 'UserJoined':
        if (data.user.id !== this.userId) {
          const existingParticipant = this.roomStore.participants.find(p => p.id === data.user.id)
          if (!existingParticipant) {
            this.roomStore.participants.push(data.user)
          }
        }
        break

      case 'UserLeft':
        if (data.user.id !== this.userId) {
          const index = this.roomStore.participants.findIndex(p => p.id === data.user.id)
          if (index !== -1) {
            this.roomStore.participants.splice(index, 1)
          }
        }
        break

      case 'TrackAdded':
        if (data.user_id !== this.userId) {
          this.trackStore.trackQueue.push(data.track)
        }
        break

      case 'TrackVoted':
        if (data.user_id !== this.userId) {
          const track = this.trackStore.trackQueue.find(t => t.id === data.track_id)
          if (track) {
            track.vote_score = data.vote_score
          }

          // Reorder queue
          this.trackStore.trackQueue.sort((a, b) => {
            if (b.vote_score !== a.vote_score) {
              return b.vote_score - a.vote_score
            }
            return new Date(a.created_at || 0) - new Date(b.created_at || 0)
          })
        }
        break

      case 'PlaybackStarted':
        this.trackStore.updatePlaybackState({
          isPlaying: true,
          startedAt: data.started_at,
          pausedAt: null,
          position: 0,
          duration: data.track_data?.duration_seconds || 0,
        })
        this.trackStore.setCurrentTrack(data.track_data)
        this.roomStore.currentRoom.is_playing = true
        this.roomStore.currentRoom.current_track_id = data.track_id

        // Synchronize audio playback
        this.synchronizeAudio()
        break

      case 'PlaybackPaused':
        this.trackStore.updatePlaybackState({
          isPlaying: false,
          pausedAt: data.paused_at,
          position: data.position || this.trackStore.playbackState.position,
        })
        this.roomStore.currentRoom.is_playing = false

        // Pause audio
        if (this.audioElement) {
          this.audioElement.pause()
        }
        break
    }
  }

  synchronizeAudio() {
    if (!this.audioElement || !this.trackStore.playbackState.isPlaying) {
      return
    }

    // Calculate expected position based on server time
    const startTime = new Date(this.trackStore.playbackState.startedAt).getTime()
    const currentTime = this.environment.serverTime
    const expectedPosition = (currentTime - startTime) / 1000

    // Apply browser-specific sync tolerance
    const tolerance = this.browserProfile.syncTolerance
    const actualPosition = this.audioElement.currentTime
    const difference = Math.abs(expectedPosition - actualPosition)

    if (difference > tolerance) {
      // Sync audio position
      this.audioElement.currentTime = Math.max(0, expectedPosition)

      // Start playback if not already playing
      if (this.audioElement.paused) {
        this.audioElement.play()
      }
    }
  }

  getConnectionHealth() {
    return {
      connected: this.connected,
      reconnectAttempts: this.reconnectAttempts,
      queuedMessages: this.messageQueue.length,
      browserType: this.browserType,
      syncTolerance: this.browserProfile.syncTolerance,
    }
  }
}

describe('Comprehensive Integration Tests', () => {
  let testEnv
  let admin, user1, user2, user3
  const roomId = 'integration-test-room'

  beforeEach(async () => {
    vi.useFakeTimers()

    // Create test environment
    testEnv = new IntegratedTestEnvironment()

    // Create users with different browser types
    admin = testEnv.createUser('admin', 'admin', 'chrome', true)
    user1 = testEnv.createUser('user1', 'user1', 'firefox', false)
    user2 = testEnv.createUser('user2', 'user2', 'safari', false)
    user3 = testEnv.createUser('user3', 'user3', 'edge', false)

    // Create room
    testEnv.createRoom(roomId, 'admin')

    // Connect all users
    await Promise.all([admin.connect(), user1.connect(), user2.connect(), user3.connect()])

    // All users join the room
    await Promise.all([
      admin.joinRoom(roomId),
      user1.joinRoom(roomId),
      user2.joinRoom(roomId),
      user3.joinRoom(roomId),
    ])

    // Wait for join events to propagate
    vi.advanceTimersByTime(100)
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  describe('Multi-User Cross-Browser Scenarios', () => {
    it('should handle collaborative music session across different browsers', async () => {
      // Phase 1: Track uploads from different browsers
      await user1.uploadTrack('firefox-song.mp3', 200) // Firefox user
      await user2.uploadTrack('safari-song.mp3', 180) // Safari user
      await user3.uploadTrack('edge-song.mp3', 220) // Edge user

      vi.advanceTimersByTime(200) // Wait for events to propagate

      // All users should see all tracks
      expect(admin.trackStore.trackQueue).toHaveLength(3)
      expect(user1.trackStore.trackQueue).toHaveLength(3)
      expect(user2.trackStore.trackQueue).toHaveLength(3)
      expect(user3.trackStore.trackQueue).toHaveLength(3)

      // Phase 2: Collaborative voting
      const firstTrack = admin.trackStore.trackQueue[0]

      // Multiple users vote for the same track
      await user1.voteForTrack(firstTrack.id)
      await user2.voteForTrack(firstTrack.id)
      await admin.voteForTrack(firstTrack.id)

      vi.advanceTimersByTime(200)

      // Vote counts should be consistent across all browsers
      const adminTrack = admin.trackStore.trackQueue.find(t => t.id === firstTrack.id)
      const user1Track = user1.trackStore.trackQueue.find(t => t.id === firstTrack.id)
      const user2Track = user2.trackStore.trackQueue.find(t => t.id === firstTrack.id)
      const user3Track = user3.trackStore.trackQueue.find(t => t.id === firstTrack.id)

      expect(adminTrack.vote_score).toBe(3)
      expect(user1Track.vote_score).toBe(3)
      expect(user2Track.vote_score).toBe(3)
      expect(user3Track.vote_score).toBe(3)

      // Phase 3: Synchronized playback across browsers
      await admin.startPlayback(firstTrack.id)

      vi.advanceTimersByTime(100)

      // All users should have synchronized playback state
      expect(user1.trackStore.playbackState.isPlaying).toBe(true)
      expect(user2.trackStore.playbackState.isPlaying).toBe(true)
      expect(user3.trackStore.playbackState.isPlaying).toBe(true)

      // Audio elements should be synchronized within browser-specific tolerances
      const positions = [
        user1.audioElement.currentTime,
        user2.audioElement.currentTime,
        user3.audioElement.currentTime,
      ]

      const avgPosition = positions.reduce((a, b) => a + b, 0) / positions.length

      positions.forEach((position, index) => {
        const user = [user1, user2, user3][index]
        const tolerance = user.browserProfile.syncTolerance
        expect(Math.abs(position - avgPosition)).toBeLessThan(tolerance)
      })
    })

    it('should maintain sync accuracy across different browser timing precisions', async () => {
      // Upload and start playback
      await user1.uploadTrack('timing-test.mp3', 300)
      vi.advanceTimersByTime(100)

      const track = admin.trackStore.trackQueue[0]
      await admin.startPlayback(track.id)

      // Simulate time progression
      testEnv.advanceServerTime(10000) // 10 seconds
      vi.advanceTimersByTime(100)

      // Force synchronization for all users
      admin.synchronizeAudio()
      user1.synchronizeAudio()
      user2.synchronizeAudio()
      user3.synchronizeAudio()

      // Check synchronization accuracy across browsers
      const expectedPosition = 10.0 // 10 seconds
      const users = [admin, user1, user2, user3]
      const browserTypes = ['chrome', 'firefox', 'safari', 'edge']

      users.forEach((user, index) => {
        const actualPosition = user.audioElement.currentTime
        const tolerance = user.browserProfile.syncTolerance
        const difference = Math.abs(actualPosition - expectedPosition)

        expect(difference).toBeLessThan(tolerance)

        console.log(
          `${browserTypes[index]}: Position ${actualPosition.toFixed(3)}s (expected: ${expectedPosition}s, tolerance: ${tolerance}s)`
        )
      })
    })
  })

  describe('WebSocket Reconnection During Active Collaboration', () => {
    it('should handle user disconnection during active voting session', async () => {
      // Set up active session
      await user1.uploadTrack('disconnect-test.mp3', 180)
      vi.advanceTimersByTime(100)

      const track = admin.trackStore.trackQueue[0]

      // Start voting session
      await admin.voteForTrack(track.id)
      await user3.voteForTrack(track.id)

      // User2 disconnects mid-session
      user2.simulateDisconnection()
      expect(user2.isConnected()).toBe(false)

      // User2 tries to vote while disconnected (should be queued)
      await user2.voteForTrack(track.id)
      expect(user2.messageQueue.length).toBe(1)

      // Other users continue voting
      await user1.voteForTrack(track.id)

      vi.advanceTimersByTime(200)

      // User2 reconnects
      vi.advanceTimersByTime(2000) // Wait for reconnection backoff
      expect(user2.isConnected()).toBe(true)

      // Queued vote should be processed
      vi.advanceTimersByTime(200)
      expect(user2.messageQueue.length).toBe(0)

      // Final vote count should include all votes
      const finalTrack = admin.trackStore.trackQueue.find(t => t.id === track.id)
      expect(finalTrack.vote_score).toBe(4) // All 4 users voted
    })

    it('should maintain playback synchronization through connection issues', async () => {
      // Start playback
      await user1.uploadTrack('sync-resilience-test.mp3', 240)
      vi.advanceTimersByTime(100)

      const track = admin.trackStore.trackQueue[0]
      await admin.startPlayback(track.id)

      // Simulate playback progression
      testEnv.advanceServerTime(5000) // 5 seconds
      vi.advanceTimersByTime(100)

      // User2 disconnects during playback
      user2.simulateDisconnection()

      // Continue playback progression
      testEnv.advanceServerTime(3000) // 3 more seconds (8 total)
      vi.advanceTimersByTime(100)

      // User2 reconnects
      vi.advanceTimersByTime(2000)
      expect(user2.isConnected()).toBe(true)

      // User2 should resynchronize to current position
      user2.synchronizeAudio()

      const expectedPosition = 8.0
      const actualPosition = user2.audioElement.currentTime
      const tolerance = user2.browserProfile.syncTolerance

      expect(Math.abs(actualPosition - expectedPosition)).toBeLessThan(tolerance)

      // All users should still be synchronized
      const allPositions = [
        admin.audioElement.currentTime,
        user1.audioElement.currentTime,
        user2.audioElement.currentTime,
        user3.audioElement.currentTime,
      ]

      const avgPosition = allPositions.reduce((a, b) => a + b, 0) / allPositions.length
      const maxDeviation = Math.max(...allPositions.map(pos => Math.abs(pos - avgPosition)))

      expect(maxDeviation).toBeLessThan(0.5) // Within 500ms of each other
    })

    it('should handle admin disconnection and recovery', async () => {
      // Set up playback
      await user1.uploadTrack('admin-disconnect-test.mp3', 180)
      vi.advanceTimersByTime(100)

      const track = admin.trackStore.trackQueue[0]
      await admin.startPlayback(track.id)

      vi.advanceTimersByTime(100)

      // Verify playback started for all users
      expect(user1.trackStore.playbackState.isPlaying).toBe(true)
      expect(user2.trackStore.playbackState.isPlaying).toBe(true)
      expect(user3.trackStore.playbackState.isPlaying).toBe(true)

      // Admin disconnects
      admin.simulateDisconnection()
      expect(admin.isConnected()).toBe(false)

      // Non-admin users can't control playback
      await expect(user1.pausePlayback()).rejects.toThrow(
        'Only administrators can control playback'
      )

      // Admin reconnects
      vi.advanceTimersByTime(2000)
      expect(admin.isConnected()).toBe(true)

      // Admin should be able to control playback again
      const pauseResult = await admin.pausePlayback()
      expect(pauseResult.success).toBe(true)

      vi.advanceTimersByTime(100)

      // All users should see paused state
      expect(user1.trackStore.playbackState.isPlaying).toBe(false)
      expect(user2.trackStore.playbackState.isPlaying).toBe(false)
      expect(user3.trackStore.playbackState.isPlaying).toBe(false)
    })
  })

  describe('Network Resilience and Error Recovery', () => {
    it('should handle poor network conditions gracefully', async () => {
      // Simulate poor network conditions
      testEnv.simulateNetworkIssues('moderate')

      // Attempt collaborative session under poor conditions
      const uploadPromises = [
        user1.uploadTrack('poor-network-1.mp3'),
        user2.uploadTrack('poor-network-2.mp3'),
        user3.uploadTrack('poor-network-3.mp3'),
      ]

      await Promise.all(uploadPromises)
      vi.advanceTimersByTime(500) // Allow extra time for poor network

      // Some uploads should succeed despite network issues
      expect(admin.trackStore.trackQueue.length).toBeGreaterThan(0)

      // Start voting under poor conditions
      const track = admin.trackStore.trackQueue[0]
      const votePromises = [
        admin.voteForTrack(track.id),
        user1.voteForTrack(track.id),
        user2.voteForTrack(track.id),
        user3.voteForTrack(track.id),
      ]

      await Promise.all(votePromises)
      vi.advanceTimersByTime(1000) // Extra time for poor network

      // Some votes should get through
      const finalTrack = admin.trackStore.trackQueue.find(t => t.id === track.id)
      expect(finalTrack.vote_score).toBeGreaterThan(0)

      // Restore network conditions
      testEnv.restoreNetworkConditions()
      vi.advanceTimersByTime(200)

      // System should recover and process any queued messages
      const healthReports = [admin, user1, user2, user3].map(user => user.getConnectionHealth())

      healthReports.forEach(report => {
        expect(report.connected).toBe(true)
        // Some users might have queued messages due to network issues
        expect(report.queuedMessages).toBeGreaterThanOrEqual(0)
      })
    })

    it('should maintain data consistency through multiple connection failures', async () => {
      // Set up initial state
      await user1.uploadTrack('consistency-test.mp3', 180)
      vi.advanceTimersByTime(100)

      const track = admin.trackStore.trackQueue[0]

      // Simulate cascade of connection failures
      const disconnectionSequence = [
        () => user2.simulateDisconnection(),
        () => user3.simulateDisconnection(),
        () => user1.simulateDisconnection(),
        () => admin.simulateDisconnection(),
      ]

      // Execute disconnections with delays
      for (let i = 0; i < disconnectionSequence.length; i++) {
        disconnectionSequence[i]()
        vi.advanceTimersByTime(500)

        // Try to vote during disconnection
        try {
          await [admin, user1, user2, user3][i].voteForTrack(track.id)
        } catch (error) {
          // Expected for disconnected users
        }
      }

      // Wait for all users to reconnect
      vi.advanceTimersByTime(5000)

      // Verify all users are reconnected
      expect(admin.isConnected()).toBe(true)
      expect(user1.isConnected()).toBe(true)
      expect(user2.isConnected()).toBe(true)
      expect(user3.isConnected()).toBe(true)

      // Process any queued messages
      vi.advanceTimersByTime(500)

      // State should be consistent across all users
      const trackStates = [admin, user1, user2, user3].map(user => {
        const userTrack = user.trackStore.trackQueue.find(t => t.id === track.id)
        return userTrack ? userTrack.vote_score : 0
      })

      // All users should have the same vote count
      const uniqueVoteCounts = [...new Set(trackStates)]
      expect(uniqueVoteCounts.length).toBe(1) // All should be the same

      console.log('Final vote counts across users:', trackStates)
    })
  })

  describe('Performance Under Load', () => {
    it('should handle high-frequency events across multiple browsers', async () => {
      const eventCount = 50
      const events = []

      // Generate rapid sequence of events
      for (let i = 0; i < eventCount; i++) {
        const user = [admin, user1, user2, user3][i % 4]
        const eventType = ['upload', 'vote', 'vote', 'vote'][i % 4] // More votes than uploads

        if (eventType === 'upload') {
          const uploadPromise = user.uploadTrack(`rapid-${i}.mp3`, 180)
          events.push(uploadPromise)
        } else if (eventType === 'vote' && admin.trackStore.trackQueue.length > 0) {
          const randomTrack =
            admin.trackStore.trackQueue[
              Math.floor(Math.random() * admin.trackStore.trackQueue.length)
            ]
          const votePromise = user.voteForTrack(randomTrack.id)
          events.push(votePromise)
        }

        // Small delay between events
        if (i % 10 === 0) {
          vi.advanceTimersByTime(50)
        }
      }

      // Wait for all events to complete
      await Promise.allSettled(events)
      vi.advanceTimersByTime(1000)

      // System should remain stable
      const healthReports = [admin, user1, user2, user3].map(user => user.getConnectionHealth())

      healthReports.forEach((report, index) => {
        expect(report.connected).toBe(true)
        console.log(`User ${index} health:`, report)
      })

      // Track queues should be consistent
      const queueLengths = [admin, user1, user2, user3].map(
        user => user.trackStore.trackQueue.length
      )
      const uniqueLengths = [...new Set(queueLengths)]

      expect(uniqueLengths.length).toBe(1) // All should have same queue length
      expect(queueLengths[0]).toBeGreaterThan(0) // Should have some tracks
    })

    it('should maintain performance with many concurrent users', async () => {
      // Create additional users
      const additionalUsers = []
      for (let i = 4; i < 12; i++) {
        const browserType = ['chrome', 'firefox', 'safari', 'edge'][i % 4]
        const user = testEnv.createUser(`user${i}`, `user${i}`, browserType, false)
        await user.connect()
        await user.joinRoom(roomId)
        additionalUsers.push(user)
      }

      vi.advanceTimersByTime(200)

      // All users upload tracks simultaneously
      const allUsers = [admin, user1, user2, user3, ...additionalUsers]
      const uploadPromises = allUsers.map((user, index) =>
        user.uploadTrack(`concurrent-${index}.mp3`, 180)
      )

      await Promise.all(uploadPromises)
      vi.advanceTimersByTime(500)

      // Verify all tracks were uploaded
      expect(admin.trackStore.trackQueue.length).toBe(allUsers.length)

      // All users vote for random tracks
      const votePromises = allUsers.map(user => {
        const randomTrack =
          user.trackStore.trackQueue[Math.floor(Math.random() * user.trackStore.trackQueue.length)]
        return user.voteForTrack(randomTrack.id)
      })

      await Promise.all(votePromises)
      vi.advanceTimersByTime(500)

      // Start playback with many users
      const topTrack = admin.trackStore.trackQueue.sort((a, b) => b.vote_score - a.vote_score)[0]
      await admin.startPlayback(topTrack.id)

      vi.advanceTimersByTime(200)

      // All users should be synchronized
      const playbackStates = allUsers.map(user => user.trackStore.playbackState.isPlaying)
      expect(playbackStates.every(state => state === true)).toBe(true)

      // Audio synchronization should work across all users
      const positions = allUsers.map(user => user.audioElement.currentTime)
      const avgPosition = positions.reduce((a, b) => a + b, 0) / positions.length
      const maxDeviation = Math.max(...positions.map(pos => Math.abs(pos - avgPosition)))

      expect(maxDeviation).toBeLessThan(1.0) // Within 1 second for large group

      console.log(
        `Performance test with ${allUsers.length} users: Max deviation ${maxDeviation.toFixed(3)}s`
      )
    })
  })

  describe('Edge Cases and Recovery Scenarios', () => {
    it('should handle simultaneous admin disconnection and user actions', async () => {
      // Set up playback
      await user1.uploadTrack('edge-case-test.mp3', 180)
      vi.advanceTimersByTime(100)

      const track = admin.trackStore.trackQueue[0]
      await admin.startPlayback(track.id)

      // Admin disconnects at the same time users try to vote
      admin.simulateDisconnection()

      const votePromises = [
        user1.voteForTrack(track.id),
        user2.voteForTrack(track.id),
        user3.voteForTrack(track.id),
      ]

      await Promise.all(votePromises)
      vi.advanceTimersByTime(200)

      // Votes should still be processed
      const votedTrack = user1.trackStore.trackQueue.find(t => t.id === track.id)
      expect(votedTrack.vote_score).toBe(3)

      // Admin reconnects
      vi.advanceTimersByTime(2000)
      expect(admin.isConnected()).toBe(true)

      // Admin should see updated vote count
      vi.advanceTimersByTime(200)
      const adminTrack = admin.trackStore.trackQueue.find(t => t.id === track.id)
      expect(adminTrack.vote_score).toBe(3)

      // Playback should still be active
      expect(user1.trackStore.playbackState.isPlaying).toBe(true)
      expect(user2.trackStore.playbackState.isPlaying).toBe(true)
      expect(user3.trackStore.playbackState.isPlaying).toBe(true)
    })

    it('should recover from complete system failure', async () => {
      // Set up complex state
      await user1.uploadTrack('recovery-test-1.mp3', 180)
      await user2.uploadTrack('recovery-test-2.mp3', 200)
      vi.advanceTimersByTime(100)

      await admin.voteForTrack(admin.trackStore.trackQueue[0].id)
      await user3.voteForTrack(admin.trackStore.trackQueue[1].id)

      await admin.startPlayback(admin.trackStore.trackQueue[0].id)
      vi.advanceTimersByTime(100)

      // Simulate complete system failure - all users disconnect
      admin.simulateDisconnection()
      user1.simulateDisconnection()
      user2.simulateDisconnection()
      user3.simulateDisconnection()

      expect(admin.isConnected()).toBe(false)
      expect(user1.isConnected()).toBe(false)
      expect(user2.isConnected()).toBe(false)
      expect(user3.isConnected()).toBe(false)

      // Wait for all users to reconnect
      vi.advanceTimersByTime(5000)

      // All users should be reconnected
      expect(admin.isConnected()).toBe(true)
      expect(user1.isConnected()).toBe(true)
      expect(user2.isConnected()).toBe(true)
      expect(user3.isConnected()).toBe(true)

      // State should be recovered
      expect(admin.trackStore.trackQueue.length).toBe(2)
      expect(user1.trackStore.trackQueue.length).toBe(2)
      expect(user2.trackStore.trackQueue.length).toBe(2)
      expect(user3.trackStore.trackQueue.length).toBe(2)

      // Admin should be able to control playback
      const pauseResult = await admin.pausePlayback()
      expect(pauseResult.success).toBe(true)

      vi.advanceTimersByTime(100)

      // All users should see paused state
      expect(user1.trackStore.playbackState.isPlaying).toBe(false)
      expect(user2.trackStore.playbackState.isPlaying).toBe(false)
      expect(user3.trackStore.playbackState.isPlaying).toBe(false)
    })
  })
})
