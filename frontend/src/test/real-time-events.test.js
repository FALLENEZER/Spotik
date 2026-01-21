import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useWebSocketStore } from '@/stores/websocket'
import { useRoomStore } from '@/stores/room'
import { useTrackStore } from '@/stores/track'

// Mock Laravel Echo and Pusher
const mockPusherConnection = {
  bind: vi.fn(),
  unbind: vi.fn(),
  state: 'connected',
}

const mockPusher = {
  connection: mockPusherConnection,
  disconnect: vi.fn(),
  subscribe: vi.fn(),
  unsubscribe: vi.fn(),
}

const mockEcho = {
  connector: {
    pusher: mockPusher,
  },
  private: vi.fn(),
  leave: vi.fn(),
  disconnect: vi.fn(),
}

const mockChannel = {
  listen: vi.fn().mockReturnThis(),
  stopListening: vi.fn(),
  error: vi.fn().mockReturnThis(),
  name: 'room.test-room',
}

// Mock modules
vi.mock('laravel-echo', () => ({
  default: vi.fn(() => mockEcho),
}))

vi.mock('pusher-js', () => ({
  default: vi.fn(),
}))

describe('Real-time Event Handling', () => {
  let websocketStore, roomStore, trackStore

  beforeEach(() => {
    setActivePinia(createPinia())
    websocketStore = useWebSocketStore()
    roomStore = useRoomStore()
    trackStore = useTrackStore()

    // Reset mocks
    vi.clearAllMocks()
    mockEcho.private.mockReturnValue(mockChannel)

    // Mock environment variables
    vi.stubGlobal('import.meta', {
      env: {
        VITE_PUSHER_APP_KEY: 'test-key',
        VITE_PUSHER_APP_CLUSTER: 'mt1',
        VITE_PUSHER_HOST: '127.0.0.1',
        VITE_PUSHER_PORT: '6001',
        VITE_PUSHER_SCHEME: 'http',
        VITE_API_URL: 'http://localhost:8000/api',
      },
    })

    // Set up initial room state
    roomStore.currentRoom = {
      id: 'test-room-id',
      name: 'Test Room',
      administrator_id: 'admin-user-id',
    }
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  describe('User Join/Leave Events', () => {
    beforeEach(() => {
      // Connect and join room
      websocketStore.connect('test-token')
      const connectedCallback = mockPusherConnection.bind.mock.calls.find(
        call => call[0] === 'connected'
      )[1]
      connectedCallback()
      websocketStore.joinRoom('test-room-id')
    })

    it('should handle UserJoined events', () => {
      // Get the UserJoined event listener
      const userJoinedListener = mockChannel.listen.mock.calls.find(
        call => call[0] === 'UserJoined'
      )[1]

      const mockUser = {
        id: 'new-user-id',
        username: 'newuser',
        email: 'newuser@example.com',
      }

      const joinEvent = {
        user: mockUser,
        room_id: 'test-room-id',
        timestamp: new Date().toISOString(),
      }

      // Simulate UserJoined event
      userJoinedListener(joinEvent)

      // Verify participant was added
      expect(roomStore.participants).toContainEqual(mockUser)
    })

    it('should handle UserLeft events', () => {
      // Set up initial participants
      const existingUser = {
        id: 'existing-user-id',
        username: 'existinguser',
      }
      roomStore.participants = [existingUser]

      // Get the UserLeft event listener
      const userLeftListener = mockChannel.listen.mock.calls.find(call => call[0] === 'UserLeft')[1]

      const leaveEvent = {
        user: existingUser,
        room_id: 'test-room-id',
        timestamp: new Date().toISOString(),
      }

      // Simulate UserLeft event
      userLeftListener(leaveEvent)

      // Verify participant was removed
      expect(roomStore.participants).not.toContainEqual(existingUser)
    })

    it('should handle errors in user events gracefully', () => {
      const userJoinedListener = mockChannel.listen.mock.calls.find(
        call => call[0] === 'UserJoined'
      )[1]

      // Mock console.error to verify error handling
      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {})

      // Simulate event with invalid data that will cause an error
      userJoinedListener({ invalid: 'data' })

      // Verify error was logged but didn't crash
      expect(consoleSpy).toHaveBeenCalledWith('Error handling UserJoined event:', expect.any(Error))

      consoleSpy.mockRestore()
    })
  })

  describe('Track Events', () => {
    beforeEach(() => {
      // Connect and join room
      websocketStore.connect('test-token')
      const connectedCallback = mockPusherConnection.bind.mock.calls.find(
        call => call[0] === 'connected'
      )[1]
      connectedCallback()
      websocketStore.joinRoom('test-room-id')
    })

    it('should handle TrackAdded events', () => {
      const trackAddedListener = mockChannel.listen.mock.calls.find(
        call => call[0] === 'TrackAdded'
      )[1]

      const mockTrack = {
        id: 'new-track-id',
        original_name: 'New Song.mp3',
        duration_seconds: 180,
        vote_score: 0,
        uploader: { username: 'uploader' },
      }

      const trackEvent = {
        track: mockTrack,
        room_id: 'test-room-id',
        timestamp: new Date().toISOString(),
      }

      // Simulate TrackAdded event
      trackAddedListener(trackEvent)

      // Verify track was added to queue
      expect(trackStore.trackQueue).toContainEqual(mockTrack)
    })

    it('should handle TrackVoted events', () => {
      // Set up initial track
      const existingTrack = {
        id: 'existing-track-id',
        vote_score: 5,
      }
      trackStore.trackQueue = [existingTrack]

      const trackVotedListener = mockChannel.listen.mock.calls.find(
        call => call[0] === 'TrackVoted'
      )[1]

      const voteEvent = {
        track_id: 'existing-track-id',
        vote_score: 6,
        user_id: 'voter-id',
        room_id: 'test-room-id',
        timestamp: new Date().toISOString(),
      }

      // Simulate TrackVoted event
      trackVotedListener(voteEvent)

      // Verify track vote was updated
      expect(trackStore.trackQueue[0].vote_score).toBe(6)
    })

    it('should handle TrackRemoved events', () => {
      // Set up initial track
      const existingTrack = {
        id: 'track-to-remove',
        original_name: 'Track to Remove.mp3',
      }
      trackStore.trackQueue = [existingTrack]

      const trackRemovedListener = mockChannel.listen.mock.calls.find(
        call => call[0] === 'TrackRemoved'
      )[1]

      const removeEvent = {
        track_id: 'track-to-remove',
        room_id: 'test-room-id',
        timestamp: new Date().toISOString(),
      }

      // Simulate TrackRemoved event
      trackRemovedListener(removeEvent)

      // Verify track was removed from queue
      expect(trackStore.trackQueue).not.toContainEqual(existingTrack)
    })
  })

  describe('Playback Events', () => {
    beforeEach(() => {
      // Connect and join room
      websocketStore.connect('test-token')
      const connectedCallback = mockPusherConnection.bind.mock.calls.find(
        call => call[0] === 'connected'
      )[1]
      connectedCallback()
      websocketStore.joinRoom('test-room-id')
    })

    it('should handle PlaybackStarted events', () => {
      const playbackStartedListener = mockChannel.listen.mock.calls.find(
        call => call[0] === 'PlaybackStarted'
      )[1]

      const mockTrack = {
        id: 'playing-track-id',
        original_name: 'Playing Song.mp3',
        duration_seconds: 240,
      }

      const playbackEvent = {
        track: mockTrack,
        started_at: new Date().toISOString(),
        room_id: 'test-room-id',
        server_time: new Date().toISOString(),
      }

      // Simulate PlaybackStarted event
      playbackStartedListener(playbackEvent)

      // Verify current track and playback state were updated
      expect(trackStore.currentTrack).toEqual(mockTrack)
      expect(trackStore.playbackState.isPlaying).toBe(true)
      expect(trackStore.playbackState.startedAt).toBe(playbackEvent.started_at)
      expect(trackStore.playbackState.duration).toBe(240)
    })

    it('should handle PlaybackPaused events', () => {
      // Set up initial playing state
      trackStore.playbackState = {
        isPlaying: true,
        startedAt: new Date().toISOString(),
        pausedAt: null,
        position: 0,
      }

      const playbackPausedListener = mockChannel.listen.mock.calls.find(
        call => call[0] === 'PlaybackPaused'
      )[1]

      const pauseEvent = {
        track: { id: 'current-track' },
        paused_at: new Date().toISOString(),
        position: 60,
        room_id: 'test-room-id',
        server_time: new Date().toISOString(),
      }

      // Simulate PlaybackPaused event
      playbackPausedListener(pauseEvent)

      // Verify playback state was updated
      expect(trackStore.playbackState.isPlaying).toBe(false)
      expect(trackStore.playbackState.pausedAt).toBe(pauseEvent.paused_at)
      expect(trackStore.playbackState.position).toBe(60)
    })

    it('should handle PlaybackResumed events', () => {
      // Set up initial paused state
      trackStore.playbackState = {
        isPlaying: false,
        startedAt: null,
        pausedAt: new Date().toISOString(),
        position: 60,
      }

      const playbackResumedListener = mockChannel.listen.mock.calls.find(
        call => call[0] === 'PlaybackResumed'
      )[1]

      const resumeEvent = {
        track: { id: 'current-track' },
        started_at: new Date().toISOString(),
        room_id: 'test-room-id',
        server_time: new Date().toISOString(),
      }

      // Simulate PlaybackResumed event
      playbackResumedListener(resumeEvent)

      // Verify playback state was updated
      expect(trackStore.playbackState.isPlaying).toBe(true)
      expect(trackStore.playbackState.startedAt).toBe(resumeEvent.started_at)
      expect(trackStore.playbackState.pausedAt).toBe(null)
    })

    it('should handle TrackSkipped events with next track', () => {
      const trackSkippedListener = mockChannel.listen.mock.calls.find(
        call => call[0] === 'TrackSkipped'
      )[1]

      const nextTrack = {
        id: 'next-track-id',
        original_name: 'Next Song.mp3',
        duration_seconds: 200,
      }

      const skipEvent = {
        skipped_track: { id: 'old-track' },
        next_track: nextTrack,
        started_at: new Date().toISOString(),
        room_id: 'test-room-id',
        timestamp: new Date().toISOString(),
      }

      // Simulate TrackSkipped event
      trackSkippedListener(skipEvent)

      // Verify next track is now current and playing
      expect(trackStore.currentTrack).toEqual(nextTrack)
      expect(trackStore.playbackState.isPlaying).toBe(true)
      expect(trackStore.playbackState.startedAt).toBe(skipEvent.started_at)
      expect(trackStore.playbackState.position).toBe(0)
      expect(trackStore.playbackState.duration).toBe(200)
    })

    it('should handle TrackSkipped events without next track', () => {
      // Set up initial playing state
      trackStore.currentTrack = { id: 'current-track' }
      trackStore.playbackState = { isPlaying: true }

      const trackSkippedListener = mockChannel.listen.mock.calls.find(
        call => call[0] === 'TrackSkipped'
      )[1]

      const skipEvent = {
        skipped_track: { id: 'current-track' },
        next_track: null,
        room_id: 'test-room-id',
        timestamp: new Date().toISOString(),
      }

      // Simulate TrackSkipped event
      trackSkippedListener(skipEvent)

      // Verify playback stopped
      expect(trackStore.currentTrack).toBe(null)
      expect(trackStore.playbackState.isPlaying).toBe(false)
      expect(trackStore.playbackState.startedAt).toBe(null)
      expect(trackStore.playbackState.position).toBe(0)
      expect(trackStore.playbackState.duration).toBe(0)
    })
  })

  describe('Room Events', () => {
    beforeEach(() => {
      // Connect and join room
      websocketStore.connect('test-token')
      const connectedCallback = mockPusherConnection.bind.mock.calls.find(
        call => call[0] === 'connected'
      )[1]
      connectedCallback()
      websocketStore.joinRoom('test-room-id')
    })

    it('should handle RoomUpdated events', () => {
      const roomUpdatedListener = mockChannel.listen.mock.calls.find(
        call => call[0] === 'RoomUpdated'
      )[1]

      const updatedRoom = {
        id: 'test-room-id',
        name: 'Updated Room Name',
        description: 'New description',
        is_playing: true,
      }

      const roomEvent = {
        room: updatedRoom,
        timestamp: new Date().toISOString(),
      }

      // Simulate RoomUpdated event
      roomUpdatedListener(roomEvent)

      // Verify room state was updated
      expect(roomStore.currentRoom.name).toBe('Updated Room Name')
      expect(roomStore.currentRoom.description).toBe('New description')
      expect(roomStore.currentRoom.is_playing).toBe(true)
    })
  })

  describe('Error Handling', () => {
    beforeEach(() => {
      // Connect and join room
      websocketStore.connect('test-token')
      const connectedCallback = mockPusherConnection.bind.mock.calls.find(
        call => call[0] === 'connected'
      )[1]
      connectedCallback()
      websocketStore.joinRoom('test-room-id')
    })

    it('should handle errors in event listeners gracefully', () => {
      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {})

      // Get various event listeners
      const userJoinedListener = mockChannel.listen.mock.calls.find(
        call => call[0] === 'UserJoined'
      )[1]
      const trackAddedListener = mockChannel.listen.mock.calls.find(
        call => call[0] === 'TrackAdded'
      )[1]
      const playbackStartedListener = mockChannel.listen.mock.calls.find(
        call => call[0] === 'PlaybackStarted'
      )[1]

      // Simulate events with invalid data that will cause errors
      userJoinedListener({ invalid: 'data' })
      trackAddedListener({ invalid: 'data' })
      playbackStartedListener({ invalid: 'data' })

      // Verify errors were logged (at least one error should be logged)
      expect(consoleSpy).toHaveBeenCalledWith(
        expect.stringMatching(/Error handling .* event:/),
        expect.any(Error)
      )
      expect(consoleSpy.mock.calls.length).toBeGreaterThan(0)

      consoleSpy.mockRestore()
    })

    it('should handle channel errors properly', () => {
      const errorCallback = mockChannel.error.mock.calls[0][0]

      // Simulate authentication error
      errorCallback({ type: 'AuthError', message: 'Authentication failed' })

      expect(websocketStore.error).toBe('Authentication failed for room')
    })
  })
})
