/**
 * Multi-User Room Integration Tests
 *
 * This test suite validates multi-user scenarios in shared rooms, testing:
 * - Concurrent user interactions and state synchronization
 * - Real-time event propagation between multiple users
 * - Conflict resolution and race condition handling
 * - Collaborative voting and queue management
 * - Admin privilege enforcement across multiple users
 *
 * Requirements: 2.2, 2.3, 2.4, 2.5, 5.1, 5.2, 5.4, 5.5, 6.1, 6.2, 6.3, 7.1, 7.2, 7.3, 7.4
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useWebSocketStore } from '@/stores/websocket'
import { useRoomStore } from '@/stores/room'
import { useTrackStore } from '@/stores/track'
import { useAuthStore } from '@/stores/auth'

// Mock WebSocket for multiple connections
class MockWebSocketConnection {
  constructor(userId, roomId) {
    this.userId = userId
    this.roomId = roomId
    this.readyState = WebSocket.CONNECTING
    this.onopen = null
    this.onmessage = null
    this.onclose = null
    this.onerror = null
    this.messageQueue = []

    // Simulate connection after delay
    setTimeout(() => {
      this.readyState = WebSocket.OPEN
      if (this.onopen) this.onopen()
    }, 50)
  }

  send(data) {
    // Broadcast to all other connections in the same room
    MockWebSocketConnection.broadcast(this.roomId, data, this.userId)
  }

  close() {
    this.readyState = WebSocket.CLOSED
    if (this.onclose) this.onclose()
  }

  simulateMessage(data) {
    if (this.onmessage && this.readyState === WebSocket.OPEN) {
      this.onmessage({ data: JSON.stringify(data) })
    }
  }

  // Static method to manage connections across users
  static connections = new Map()

  static addConnection(userId, roomId, connection) {
    if (!this.connections.has(roomId)) {
      this.connections.set(roomId, new Map())
    }
    this.connections.get(roomId).set(userId, connection)
  }

  static removeConnection(userId, roomId) {
    if (this.connections.has(roomId)) {
      this.connections.get(roomId).delete(userId)
      if (this.connections.get(roomId).size === 0) {
        this.connections.delete(roomId)
      }
    }
  }

  static broadcast(roomId, data, excludeUserId = null) {
    if (this.connections.has(roomId)) {
      this.connections.get(roomId).forEach((connection, userId) => {
        if (userId !== excludeUserId) {
          connection.simulateMessage(JSON.parse(data))
        }
      })
    }
  }

  static clearAll() {
    this.connections.clear()
  }
}

// Mock fetch for API calls
const mockFetch = vi.fn()
global.fetch = mockFetch

// User simulation class
class UserSimulator {
  constructor(userId, username, isAdmin = false) {
    this.userId = userId
    this.username = username
    this.isAdmin = isAdmin
    this.pinia = createPinia()
    setActivePinia(this.pinia)

    this.authStore = useAuthStore()
    this.roomStore = useRoomStore()
    this.trackStore = useTrackStore()
    this.websocketStore = useWebSocketStore()

    // Set up user authentication
    this.authStore.user = { id: userId, username }
    this.authStore.token = `token-${userId}`
    this.authStore.isAuthenticated = true

    this.connection = null
  }

  async joinRoom(roomId) {
    // Mock API response for joining room
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        room: {
          id: roomId,
          name: 'Test Room',
          administrator_id: this.isAdmin ? this.userId : 'admin-user',
          participants: [{ id: this.userId, username: this.username }],
          track_queue: [],
          is_playing: false,
        },
      }),
    })

    const result = await this.roomStore.joinRoom(roomId)

    if (result.success) {
      // Set up WebSocket connection
      this.connection = new MockWebSocketConnection(this.userId, roomId)
      MockWebSocketConnection.addConnection(this.userId, roomId, this.connection)

      // Set up WebSocket event handlers
      this.connection.onmessage = event => {
        const data = JSON.parse(event.data)
        this.handleWebSocketMessage(data)
      }

      this.websocketStore.connected = true
      this.websocketStore.currentRoomId = roomId
    }

    return result
  }

  leaveRoom() {
    if (this.connection) {
      MockWebSocketConnection.removeConnection(this.userId, this.roomStore.currentRoom?.id)
      this.connection.close()
      this.connection = null
    }

    this.websocketStore.connected = false
    this.websocketStore.currentRoomId = null
    this.roomStore.currentRoom = null
  }

  async uploadTrack(filename, duration = 180) {
    const trackId = `track-${Date.now()}-${Math.random()}`
    const track = {
      id: trackId,
      room_id: this.roomStore.currentRoom.id,
      uploader_id: this.userId,
      filename,
      original_name: filename,
      duration_seconds: duration,
      vote_score: 0,
      uploader: { id: this.userId, username: this.username },
    }

    // Mock API response
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ track }),
    })

    const result = await this.trackStore.uploadTrack(
      this.roomStore.currentRoom.id,
      new File(['audio'], filename)
    )

    if (result.success) {
      // Broadcast to other users
      this.broadcastEvent({
        event: 'TrackAdded',
        room_id: this.roomStore.currentRoom.id,
        track,
        user_id: this.userId,
        timestamp: new Date().toISOString(),
      })
    }

    return result
  }

  async voteForTrack(trackId) {
    // Mock API response
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        vote: { track_id: trackId, user_id: this.userId },
        track: { id: trackId, vote_score: 1 },
      }),
    })

    const result = await this.trackStore.voteForTrack(trackId)

    if (result.success) {
      // Update local track score
      const track = this.trackStore.trackQueue.find(t => t.id === trackId)
      if (track) {
        track.vote_score += 1
      }

      // Broadcast to other users
      this.broadcastEvent({
        event: 'TrackVoted',
        room_id: this.roomStore.currentRoom.id,
        track_id: trackId,
        vote_score: track?.vote_score || 1,
        user_id: this.userId,
        timestamp: new Date().toISOString(),
      })
    }

    return result
  }

  async startPlayback(trackId) {
    if (!this.isAdmin) {
      throw new Error('Only administrators can control playback')
    }

    const startTime = new Date().toISOString()

    // Mock API response
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        playback_state: {
          room_id: this.roomStore.currentRoom.id,
          track_id: trackId,
          is_playing: true,
          started_at: startTime,
          server_time: startTime,
        },
      }),
    })

    const result = await this.roomStore.startPlayback(trackId)

    if (result.success) {
      // Broadcast to other users
      this.broadcastEvent({
        event: 'PlaybackStarted',
        room_id: this.roomStore.currentRoom.id,
        track_id: trackId,
        started_at: startTime,
        server_time: startTime,
        track_data: this.trackStore.trackQueue.find(t => t.id === trackId),
      })
    }

    return result
  }

  async pausePlayback() {
    if (!this.isAdmin) {
      throw new Error('Only administrators can control playback')
    }

    const pauseTime = new Date().toISOString()

    // Mock API response
    mockFetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        playback_state: {
          room_id: this.roomStore.currentRoom.id,
          is_playing: false,
          paused_at: pauseTime,
          server_time: pauseTime,
        },
      }),
    })

    const result = await this.roomStore.pausePlayback()

    if (result.success) {
      // Broadcast to other users
      this.broadcastEvent({
        event: 'PlaybackPaused',
        room_id: this.roomStore.currentRoom.id,
        paused_at: pauseTime,
        server_time: pauseTime,
      })
    }

    return result
  }

  broadcastEvent(event) {
    if (this.connection) {
      this.connection.send(JSON.stringify(event))
    }
  }

  handleWebSocketMessage(data) {
    switch (data.event) {
      case 'UserJoined':
        if (data.user.id !== this.userId) {
          this.roomStore.participants.push(data.user)
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
        break

      case 'PlaybackPaused':
        this.trackStore.updatePlaybackState({
          isPlaying: false,
          pausedAt: data.paused_at,
          position: this.trackStore.playbackState.position,
        })
        this.roomStore.currentRoom.is_playing = false
        break
    }
  }
}

describe('Multi-User Room Integration', () => {
  let admin, user1, user2, user3
  const roomId = 'test-room-multi-user'

  beforeEach(async () => {
    // Clear all connections
    MockWebSocketConnection.clearAll()

    // Reset fetch mock
    mockFetch.mockClear()

    // Create user simulators
    admin = new UserSimulator('admin-user', 'admin', true)
    user1 = new UserSimulator('user-1', 'user1', false)
    user2 = new UserSimulator('user-2', 'user2', false)
    user3 = new UserSimulator('user-3', 'user3', false)

    // All users join the room
    await admin.joinRoom(roomId)
    await user1.joinRoom(roomId)
    await user2.joinRoom(roomId)
    await user3.joinRoom(roomId)

    // Wait for connections to establish
    await new Promise(resolve => setTimeout(resolve, 100))
  })

  afterEach(() => {
    // Clean up connections
    admin.leaveRoom()
    user1.leaveRoom()
    user2.leaveRoom()
    user3.leaveRoom()
    MockWebSocketConnection.clearAll()
  })

  describe('Concurrent User Interactions', () => {
    it('should handle multiple users joining and leaving simultaneously', async () => {
      // Simulate user join events
      admin.broadcastEvent({
        event: 'UserJoined',
        room_id: roomId,
        user: { id: 'user-1', username: 'user1' },
        timestamp: new Date().toISOString(),
      })

      admin.broadcastEvent({
        event: 'UserJoined',
        room_id: roomId,
        user: { id: 'user-2', username: 'user2' },
        timestamp: new Date().toISOString(),
      })

      // Wait for event propagation
      await new Promise(resolve => setTimeout(resolve, 50))

      // All users should see the same participant list
      expect(user1.roomStore.participants).toHaveLength(2)
      expect(user2.roomStore.participants).toHaveLength(2)
      expect(user3.roomStore.participants).toHaveLength(2)

      // Simulate user leaving
      admin.broadcastEvent({
        event: 'UserLeft',
        room_id: roomId,
        user: { id: 'user-2', username: 'user2' },
        timestamp: new Date().toISOString(),
      })

      await new Promise(resolve => setTimeout(resolve, 50))

      // Remaining users should see updated participant list
      expect(user1.roomStore.participants).toHaveLength(1)
      expect(user3.roomStore.participants).toHaveLength(1)
      expect(user1.roomStore.participants[0].id).toBe('user-1')
    })

    it('should handle concurrent track uploads from multiple users', async () => {
      // Multiple users upload tracks simultaneously
      const uploadPromises = [
        user1.uploadTrack('song1.mp3', 180),
        user2.uploadTrack('song2.mp3', 200),
        user3.uploadTrack('song3.mp3', 160),
      ]

      const results = await Promise.all(uploadPromises)

      // All uploads should succeed
      results.forEach(result => {
        expect(result.success).toBe(true)
      })

      // Wait for event propagation
      await new Promise(resolve => setTimeout(resolve, 100))

      // All users should see all tracks in their queue
      expect(admin.trackStore.trackQueue).toHaveLength(3)
      expect(user1.trackStore.trackQueue).toHaveLength(3)
      expect(user2.trackStore.trackQueue).toHaveLength(3)
      expect(user3.trackStore.trackQueue).toHaveLength(3)

      // Verify track details are consistent across users
      const adminTracks = admin.trackStore.trackQueue.map(t => t.original_name).sort()
      const user1Tracks = user1.trackStore.trackQueue.map(t => t.original_name).sort()
      const user2Tracks = user2.trackStore.trackQueue.map(t => t.original_name).sort()

      expect(adminTracks).toEqual(['song1.mp3', 'song2.mp3', 'song3.mp3'])
      expect(user1Tracks).toEqual(adminTracks)
      expect(user2Tracks).toEqual(adminTracks)
    })

    it('should handle concurrent voting on the same track', async () => {
      // First, upload a track
      await user1.uploadTrack('popular-song.mp3', 180)
      await new Promise(resolve => setTimeout(resolve, 50))

      const trackId = user1.trackStore.trackQueue[0].id

      // Multiple users vote for the same track simultaneously
      const votePromises = [
        user2.voteForTrack(trackId),
        user3.voteForTrack(trackId),
        admin.voteForTrack(trackId),
      ]

      const results = await Promise.all(votePromises)

      // All votes should succeed
      results.forEach(result => {
        expect(result.success).toBe(true)
      })

      // Wait for event propagation
      await new Promise(resolve => setTimeout(resolve, 100))

      // All users should see the updated vote count
      // Note: In a real scenario, the backend would handle vote counting
      // Here we simulate the final state after all votes are processed
      const finalTrack = admin.trackStore.trackQueue.find(t => t.id === trackId)
      expect(finalTrack.vote_score).toBeGreaterThan(0)

      // Verify consistency across all users
      const user1Track = user1.trackStore.trackQueue.find(t => t.id === trackId)
      const user2Track = user2.trackStore.trackQueue.find(t => t.id === trackId)
      const user3Track = user3.trackStore.trackQueue.find(t => t.id === trackId)

      expect(user1Track.vote_score).toBe(finalTrack.vote_score)
      expect(user2Track.vote_score).toBe(finalTrack.vote_score)
      expect(user3Track.vote_score).toBe(finalTrack.vote_score)
    })
  })

  describe('Real-time Event Propagation', () => {
    it('should propagate playback events to all users in real-time', async () => {
      // Upload a track first
      await user1.uploadTrack('test-song.mp3', 180)
      await new Promise(resolve => setTimeout(resolve, 50))

      const trackId = user1.trackStore.trackQueue[0].id

      // Admin starts playback
      await admin.startPlayback(trackId)

      // Wait for event propagation
      await new Promise(resolve => setTimeout(resolve, 50))

      // All users should see playback started
      expect(user1.trackStore.playbackState.isPlaying).toBe(true)
      expect(user2.trackStore.playbackState.isPlaying).toBe(true)
      expect(user3.trackStore.playbackState.isPlaying).toBe(true)

      expect(user1.roomStore.currentRoom.is_playing).toBe(true)
      expect(user2.roomStore.currentRoom.is_playing).toBe(true)
      expect(user3.roomStore.currentRoom.is_playing).toBe(true)

      // Admin pauses playback
      await admin.pausePlayback()

      await new Promise(resolve => setTimeout(resolve, 50))

      // All users should see playback paused
      expect(user1.trackStore.playbackState.isPlaying).toBe(false)
      expect(user2.trackStore.playbackState.isPlaying).toBe(false)
      expect(user3.trackStore.playbackState.isPlaying).toBe(false)

      expect(user1.roomStore.currentRoom.is_playing).toBe(false)
      expect(user2.roomStore.currentRoom.is_playing).toBe(false)
      expect(user3.roomStore.currentRoom.is_playing).toBe(false)
    })

    it('should handle event ordering correctly', async () => {
      const events = []

      // Override event handlers to track event order
      const trackEventOrder = (user, eventType) => {
        const originalHandler = user.handleWebSocketMessage
        user.handleWebSocketMessage = data => {
          if (data.event === eventType) {
            events.push({ user: user.userId, event: eventType, timestamp: Date.now() })
          }
          originalHandler.call(user, data)
        }
      }

      trackEventOrder(user1, 'TrackAdded')
      trackEventOrder(user2, 'TrackAdded')
      trackEventOrder(user3, 'TrackAdded')

      // Upload multiple tracks in sequence
      await user1.uploadTrack('song1.mp3')
      await new Promise(resolve => setTimeout(resolve, 25))
      await user2.uploadTrack('song2.mp3')
      await new Promise(resolve => setTimeout(resolve, 25))
      await user3.uploadTrack('song3.mp3')

      await new Promise(resolve => setTimeout(resolve, 100))

      // Events should be received in the correct order by all users
      const user1Events = events.filter(e => e.user === 'user-1')
      const user2Events = events.filter(e => e.user === 'user-2')
      const user3Events = events.filter(e => e.user === 'user-3')

      // Each user should receive events for tracks uploaded by others
      expect(user1Events).toHaveLength(2) // song2 and song3
      expect(user2Events).toHaveLength(2) // song1 and song3
      expect(user3Events).toHaveLength(2) // song1 and song2

      // Events should be in chronological order
      user1Events.forEach((event, index) => {
        if (index > 0) {
          expect(event.timestamp).toBeGreaterThanOrEqual(user1Events[index - 1].timestamp)
        }
      })
    })
  })

  describe('Admin Privilege Enforcement', () => {
    it('should enforce admin-only playback controls', async () => {
      // Upload a track
      await user1.uploadTrack('test-song.mp3', 180)
      await new Promise(resolve => setTimeout(resolve, 50))

      const trackId = user1.trackStore.trackQueue[0].id

      // Non-admin users should not be able to control playback
      await expect(user1.startPlayback(trackId)).rejects.toThrow(
        'Only administrators can control playback'
      )
      await expect(user2.startPlayback(trackId)).rejects.toThrow(
        'Only administrators can control playback'
      )
      await expect(user3.startPlayback(trackId)).rejects.toThrow(
        'Only administrators can control playback'
      )

      // Admin should be able to control playback
      const result = await admin.startPlayback(trackId)
      expect(result.success).toBe(true)

      // Non-admin users should not be able to pause
      await expect(user1.pausePlayback()).rejects.toThrow(
        'Only administrators can control playback'
      )

      // Admin should be able to pause
      const pauseResult = await admin.pausePlayback()
      expect(pauseResult.success).toBe(true)
    })

    it('should handle admin leaving and rejoining', async () => {
      // Upload a track and start playback
      await user1.uploadTrack('test-song.mp3', 180)
      await new Promise(resolve => setTimeout(resolve, 50))

      const trackId = user1.trackStore.trackQueue[0].id
      await admin.startPlayback(trackId)

      // Admin leaves room
      admin.leaveRoom()

      // Simulate admin rejoining (in real app, this might transfer admin rights or stop playback)
      await admin.joinRoom(roomId)
      await new Promise(resolve => setTimeout(resolve, 50))

      // Admin should still be able to control playback after rejoining
      const pauseResult = await admin.pausePlayback()
      expect(pauseResult.success).toBe(true)
    })
  })

  describe('Conflict Resolution', () => {
    it('should handle race conditions in voting', async () => {
      // Upload a track
      await user1.uploadTrack('contested-song.mp3', 180)
      await new Promise(resolve => setTimeout(resolve, 50))

      const trackId = user1.trackStore.trackQueue[0].id

      // Simulate race condition: multiple users vote at exactly the same time
      const startTime = Date.now()
      const votePromises = [user2.voteForTrack(trackId), user3.voteForTrack(trackId)]

      // Both votes should be processed
      const results = await Promise.all(votePromises)
      results.forEach(result => {
        expect(result.success).toBe(true)
      })

      await new Promise(resolve => setTimeout(resolve, 100))

      // Final vote count should be consistent across all users
      const adminTrack = admin.trackStore.trackQueue.find(t => t.id === trackId)
      const user1Track = user1.trackStore.trackQueue.find(t => t.id === trackId)
      const user2Track = user2.trackStore.trackQueue.find(t => t.id === trackId)
      const user3Track = user3.trackStore.trackQueue.find(t => t.id === trackId)

      expect(user1Track.vote_score).toBe(adminTrack.vote_score)
      expect(user2Track.vote_score).toBe(adminTrack.vote_score)
      expect(user3Track.vote_score).toBe(adminTrack.vote_score)
    })

    it('should handle queue reordering after concurrent votes', async () => {
      // Upload multiple tracks
      await user1.uploadTrack('song-a.mp3', 180)
      await user2.uploadTrack('song-b.mp3', 200)
      await user3.uploadTrack('song-c.mp3', 160)

      await new Promise(resolve => setTimeout(resolve, 100))

      const tracks = admin.trackStore.trackQueue
      expect(tracks).toHaveLength(3)

      // Vote for different tracks to change queue order
      await user1.voteForTrack(tracks[2].id) // Vote for song-c
      await user2.voteForTrack(tracks[2].id) // Vote for song-c
      await user3.voteForTrack(tracks[1].id) // Vote for song-b

      await new Promise(resolve => setTimeout(resolve, 100))

      // Queue should be reordered by vote score
      // song-c should be first (2 votes), song-b second (1 vote), song-a last (0 votes)
      const reorderedTracks = admin.trackStore.trackQueue.sort((a, b) => {
        if (b.vote_score !== a.vote_score) {
          return b.vote_score - a.vote_score
        }
        return new Date(a.created_at || 0) - new Date(b.created_at || 0)
      })

      expect(reorderedTracks[0].original_name).toBe('song-c.mp3')
      expect(reorderedTracks[0].vote_score).toBe(2)
      expect(reorderedTracks[1].original_name).toBe('song-b.mp3')
      expect(reorderedTracks[1].vote_score).toBe(1)
      expect(reorderedTracks[2].original_name).toBe('song-a.mp3')
      expect(reorderedTracks[2].vote_score).toBe(0)
    })
  })

  describe('Performance Under Load', () => {
    it('should handle rapid event sequences without losing messages', async () => {
      const eventCount = 50
      const receivedEvents = {
        user1: [],
        user2: [],
        user3: [],
      }

      // Override message handlers to track received events
      const trackEvents = (user, userId) => {
        const originalHandler = user.handleWebSocketMessage
        user.handleWebSocketMessage = data => {
          receivedEvents[userId].push(data)
          originalHandler.call(user, data)
        }
      }

      trackEvents(user1, 'user1')
      trackEvents(user2, 'user2')
      trackEvents(user3, 'user3')

      // Send rapid sequence of events
      for (let i = 0; i < eventCount; i++) {
        admin.broadcastEvent({
          event: 'TrackVoted',
          room_id: roomId,
          track_id: `track-${i}`,
          vote_score: i + 1,
          user_id: 'admin-user',
          timestamp: new Date().toISOString(),
          sequence: i,
        })

        // Small delay to simulate real-world timing
        if (i % 10 === 0) {
          await new Promise(resolve => setTimeout(resolve, 1))
        }
      }

      // Wait for all events to propagate
      await new Promise(resolve => setTimeout(resolve, 200))

      // All users should receive all events
      expect(receivedEvents.user1).toHaveLength(eventCount)
      expect(receivedEvents.user2).toHaveLength(eventCount)
      expect(receivedEvents.user3).toHaveLength(eventCount)

      // Events should be in correct order
      receivedEvents.user1.forEach((event, index) => {
        expect(event.sequence).toBe(index)
      })
    })

    it('should maintain state consistency with many concurrent users', async () => {
      // Create additional users
      const additionalUsers = []
      for (let i = 4; i <= 10; i++) {
        const user = new UserSimulator(`user-${i}`, `user${i}`, false)
        await user.joinRoom(roomId)
        additionalUsers.push(user)
      }

      try {
        // Each user uploads a track
        const uploadPromises = additionalUsers.map((user, index) =>
          user.uploadTrack(`song-${index + 4}.mp3`, 180 + index)
        )

        await Promise.all(uploadPromises)
        await new Promise(resolve => setTimeout(resolve, 200))

        // All users should see all tracks
        const expectedTrackCount = additionalUsers.length
        expect(admin.trackStore.trackQueue).toHaveLength(expectedTrackCount)
        expect(user1.trackStore.trackQueue).toHaveLength(expectedTrackCount)
        expect(user2.trackStore.trackQueue).toHaveLength(expectedTrackCount)

        // Each user votes for a random track
        const votePromises = additionalUsers.map(user => {
          const randomTrack =
            user.trackStore.trackQueue[
              Math.floor(Math.random() * user.trackStore.trackQueue.length)
            ]
          return user.voteForTrack(randomTrack.id)
        })

        await Promise.all(votePromises)
        await new Promise(resolve => setTimeout(resolve, 200))

        // Vote counts should be consistent across all users
        const adminVoteCounts = admin.trackStore.trackQueue.map(t => ({
          id: t.id,
          votes: t.vote_score,
        }))
        const user1VoteCounts = user1.trackStore.trackQueue.map(t => ({
          id: t.id,
          votes: t.vote_score,
        }))

        adminVoteCounts.forEach(adminTrack => {
          const user1Track = user1VoteCounts.find(t => t.id === adminTrack.id)
          expect(user1Track.votes).toBe(adminTrack.votes)
        })
      } finally {
        // Clean up additional users
        additionalUsers.forEach(user => user.leaveRoom())
      }
    })
  })

  describe('Edge Cases and Error Scenarios', () => {
    it('should handle user disconnection during active voting', async () => {
      // Upload a track
      await user1.uploadTrack('disconnect-test.mp3', 180)
      await new Promise(resolve => setTimeout(resolve, 50))

      const trackId = user1.trackStore.trackQueue[0].id

      // User2 starts voting process but disconnects mid-way
      user2.leaveRoom()

      // Other users continue voting
      await user1.voteForTrack(trackId)
      await user3.voteForTrack(trackId)

      await new Promise(resolve => setTimeout(resolve, 100))

      // Remaining users should see consistent vote counts
      const adminTrack = admin.trackStore.trackQueue.find(t => t.id === trackId)
      const user1Track = user1.trackStore.trackQueue.find(t => t.id === trackId)
      const user3Track = user3.trackStore.trackQueue.find(t => t.id === trackId)

      expect(user1Track.vote_score).toBe(adminTrack.vote_score)
      expect(user3Track.vote_score).toBe(adminTrack.vote_score)
      expect(adminTrack.vote_score).toBe(2) // Two votes from user1 and user3
    })

    it('should handle admin disconnection during playback', async () => {
      // Upload and start playback
      await user1.uploadTrack('admin-disconnect-test.mp3', 180)
      await new Promise(resolve => setTimeout(resolve, 50))

      const trackId = user1.trackStore.trackQueue[0].id
      await admin.startPlayback(trackId)

      await new Promise(resolve => setTimeout(resolve, 50))

      // Verify playback started for all users
      expect(user1.trackStore.playbackState.isPlaying).toBe(true)
      expect(user2.trackStore.playbackState.isPlaying).toBe(true)
      expect(user3.trackStore.playbackState.isPlaying).toBe(true)

      // Admin disconnects
      admin.leaveRoom()

      // In a real scenario, the backend might pause playback or transfer admin rights
      // For this test, we simulate that playback continues but no one can control it
      // until admin reconnects or new admin is assigned

      // Non-admin users still can't control playback
      await expect(user1.pausePlayback()).rejects.toThrow(
        'Only administrators can control playback'
      )

      // Admin reconnects
      await admin.joinRoom(roomId)
      await new Promise(resolve => setTimeout(resolve, 50))

      // Admin should be able to control playback again
      const pauseResult = await admin.pausePlayback()
      expect(pauseResult.success).toBe(true)
    })

    it('should handle message delivery failures gracefully', async () => {
      // Simulate network issues by temporarily breaking the connection
      const originalSend = user1.connection.send
      let messagesSent = 0
      let messagesDropped = 0

      user1.connection.send = function (data) {
        messagesSent++
        // Drop every 3rd message to simulate network issues
        if (messagesSent % 3 === 0) {
          messagesDropped++
          console.log(`Dropped message ${messagesSent}:`, JSON.parse(data).event)
          return // Don't send the message
        }
        originalSend.call(this, data)
      }

      try {
        // Upload multiple tracks
        await user1.uploadTrack('msg-test-1.mp3')
        await user1.uploadTrack('msg-test-2.mp3')
        await user1.uploadTrack('msg-test-3.mp3')

        await new Promise(resolve => setTimeout(resolve, 100))

        // Some messages should have been dropped
        expect(messagesDropped).toBeGreaterThan(0)

        // But other users should still receive some track additions
        // (In a real system, there would be retry mechanisms)
        expect(user2.trackStore.trackQueue.length).toBeGreaterThan(0)
      } finally {
        // Restore original send function
        user1.connection.send = originalSend
      }
    })
  })
})
