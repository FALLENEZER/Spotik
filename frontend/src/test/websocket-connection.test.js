import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useWebSocketStore } from '@/stores/websocket'

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

describe('WebSocket Store', () => {
  let store

  beforeEach(() => {
    setActivePinia(createPinia())
    store = useWebSocketStore()

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
  })

  afterEach(() => {
    vi.unstubAllGlobals()
  })

  describe('Connection Management', () => {
    it('should initialize with disconnected state', () => {
      expect(store.connected).toBe(false)
      expect(store.connecting).toBe(false)
      expect(store.connectionState).toBe('disconnected')
      expect(store.error).toBe(null)
      expect(store.reconnectAttempts).toBe(0)
    })

    it('should connect with valid token', async () => {
      const token = 'valid-jwt-token'

      store.connect(token)

      expect(store.connecting).toBe(true)
      expect(store.connectionState).toBe('connecting')

      // Simulate successful connection
      const connectedCallback = mockPusherConnection.bind.mock.calls.find(
        call => call[0] === 'connected'
      )[1]
      connectedCallback()

      expect(store.connected).toBe(true)
      expect(store.connecting).toBe(false)
      expect(store.connectionState).toBe('connected')
      expect(store.reconnectAttempts).toBe(0)
    })

    it('should handle connection errors', () => {
      const token = 'valid-jwt-token'

      store.connect(token)

      // Simulate connection error
      const errorCallback = mockPusherConnection.bind.mock.calls.find(
        call => call[0] === 'error'
      )[1]
      errorCallback({ message: 'Connection failed' })

      expect(store.error).toBe('Connection failed')
      expect(store.connecting).toBe(false)
    })

    it('should implement exponential backoff for reconnection', () => {
      vi.useFakeTimers()

      const token = 'valid-jwt-token'
      store.connect(token)

      // Simulate connection then disconnection
      const connectedCallback = mockPusherConnection.bind.mock.calls.find(
        call => call[0] === 'connected'
      )[1]
      connectedCallback()

      const disconnectedCallback = mockPusherConnection.bind.mock.calls.find(
        call => call[0] === 'disconnected'
      )[1]
      disconnectedCallback()

      expect(store.connectionState).toBe('reconnecting')

      // Check that reconnection is scheduled
      expect(store.reconnectAttempts).toBe(0)

      // Fast forward time to trigger first reconnection attempt
      vi.advanceTimersByTime(2000) // Should be around 1s + jitter

      expect(store.reconnectAttempts).toBe(1)

      vi.useRealTimers()
    })

    it('should stop reconnection after max attempts', () => {
      vi.useFakeTimers()

      const token = 'valid-jwt-token'
      store.maxReconnectAttempts = 3
      store.connect(token)

      // Simulate multiple failed reconnection attempts
      for (let i = 0; i < 4; i++) {
        const errorCallback = mockPusherConnection.bind.mock.calls.find(
          call => call[0] === 'error'
        )[1]
        errorCallback({ message: 'Connection failed' })

        if (i < 3) {
          vi.advanceTimersByTime(10000) // Advance enough time for reconnection
        }
      }

      expect(store.reconnectAttempts).toBe(3)
      expect(store.connectionState).toBe('disconnected')
      expect(store.error).toBe('Failed to reconnect after maximum attempts')

      vi.useRealTimers()
    })

    it('should disconnect cleanly', () => {
      const token = 'valid-jwt-token'
      store.connect(token)

      // Simulate connection
      const connectedCallback = mockPusherConnection.bind.mock.calls.find(
        call => call[0] === 'connected'
      )[1]
      connectedCallback()

      store.disconnect()

      expect(store.connected).toBe(false)
      expect(store.connecting).toBe(false)
      expect(store.connectionState).toBe('disconnected')
      expect(store.error).toBe(null)
      expect(mockEcho.disconnect).toHaveBeenCalled()
    })

    it('should force reconnection', () => {
      const token = 'valid-jwt-token'
      store.connect(token)

      // Simulate connection
      const connectedCallback = mockPusherConnection.bind.mock.calls.find(
        call => call[0] === 'connected'
      )[1]
      connectedCallback()

      store.forceReconnect()

      expect(mockEcho.disconnect).toHaveBeenCalled()
      expect(store.reconnectAttempts).toBe(0)
    })
  })

  describe('Room Management', () => {
    beforeEach(() => {
      const token = 'valid-jwt-token'
      store.connect(token)

      // Simulate successful connection
      const connectedCallback = mockPusherConnection.bind.mock.calls.find(
        call => call[0] === 'connected'
      )[1]
      connectedCallback()
    })

    it('should join room when connected', () => {
      const roomId = 'test-room-id'

      const result = store.joinRoom(roomId)

      expect(result).toBe(true)
      expect(mockEcho.private).toHaveBeenCalledWith(`room.${roomId}`)
      expect(mockChannel.listen).toHaveBeenCalledWith('UserJoined', expect.any(Function))
      expect(mockChannel.listen).toHaveBeenCalledWith('UserLeft', expect.any(Function))
      expect(mockChannel.listen).toHaveBeenCalledWith('TrackAdded', expect.any(Function))
      expect(mockChannel.listen).toHaveBeenCalledWith('PlaybackStarted', expect.any(Function))
    })

    it('should not join room when disconnected', () => {
      store.connected = false

      const result = store.joinRoom('test-room-id')

      expect(result).toBe(false)
      expect(store.error).toBe('WebSocket not connected')
      expect(mockEcho.private).not.toHaveBeenCalled()
    })

    it('should leave room cleanly', () => {
      const roomId = 'test-room-id'
      store.joinRoom(roomId)

      store.leaveRoom()

      expect(mockChannel.stopListening).toHaveBeenCalled()
      expect(mockEcho.leave).toHaveBeenCalledWith('room.test-room')
      expect(store.roomChannel).toBe(null)
    })

    it('should handle room channel errors', () => {
      const roomId = 'test-room-id'
      store.joinRoom(roomId)

      // Simulate channel error
      const errorCallback = mockChannel.error.mock.calls[0][0]
      errorCallback({ type: 'AuthError', message: 'Authentication failed' })

      expect(store.error).toBe('Authentication failed for room')
    })
  })

  describe('Utility Methods', () => {
    it('should provide connection status methods', () => {
      expect(store.isConnected()).toBe(false)
      expect(store.isConnecting()).toBe(false)
      expect(store.isReconnecting()).toBe(false)

      store.connecting = true
      expect(store.isConnecting()).toBe(true)

      store.connecting = false
      store.connected = true
      store.connectionState = 'connected'
      expect(store.isConnected()).toBe(true)

      store.connectionState = 'reconnecting'
      expect(store.isReconnecting()).toBe(true)
    })

    it('should provide connection info', () => {
      const info = store.getConnectionInfo()

      expect(info).toEqual({
        connected: false,
        connecting: false,
        connectionState: 'disconnected',
        reconnectAttempts: 0,
        maxReconnectAttempts: 10,
        hasToken: false,
        error: null,
      })
    })
  })
})
