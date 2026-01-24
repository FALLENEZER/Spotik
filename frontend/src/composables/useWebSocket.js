import { computed, onUnmounted, watch } from 'vue'
import { useWebSocketStore } from '@/stores/websocket'
import { useAuthStore } from '@/stores/auth'

/**
 * Composable for managing WebSocket connections with automatic authentication
 * and lifecycle management
 */
export function useWebSocket() {
  const websocketStore = useWebSocketStore()
  const authStore = useAuthStore()

  // Computed properties for reactive connection state
  const isConnected = computed(() => websocketStore.isConnected())
  const isConnecting = computed(() => websocketStore.isConnecting())
  const isReconnecting = computed(() => websocketStore.isReconnecting())
  const connectionError = computed(() => websocketStore.error)
  const connectionInfo = computed(() => websocketStore.getConnectionInfo())

  // Auto-connect when authenticated
  const initializeConnection = () => {
    if (import.meta.env.VITE_USE_WEBSOCKETS === 'false') {
      console.log('WebSockets are disabled via configuration')
      return
    }

    if (authStore.isAuthenticated && authStore.token && !websocketStore.connected) {
      console.log('Initializing WebSocket connection with authentication')
      websocketStore.connect(authStore.token)
    }
  }

  // Auto-disconnect when unauthenticated
  const cleanupConnection = () => {
    if (websocketStore.connected || websocketStore.connecting) {
      console.log('Cleaning up WebSocket connection')
      websocketStore.disconnect()
    }
  }

  // Watch for authentication changes
  const stopAuthWatcher = watch(
    () => authStore.isAuthenticated,
    isAuthenticated => {
      if (isAuthenticated) {
        initializeConnection()
      } else {
        cleanupConnection()
      }
    },
    { immediate: true }
  )

  // Watch for token changes (token refresh)
  const stopTokenWatcher = watch(
    () => authStore.token,
    (newToken, oldToken) => {
      if (newToken && newToken !== oldToken && authStore.isAuthenticated) {
        console.log('Token changed, reconnecting WebSocket')
        websocketStore.disconnect()
        setTimeout(() => {
          websocketStore.connect(newToken)
        }, 100)
      }
    }
  )

  // Connection management methods
  const connect = () => {
    if (!authStore.isAuthenticated || !authStore.token) {
      console.error('Cannot connect WebSocket: not authenticated')
      return false
    }
    websocketStore.connect(authStore.token)
    return true
  }

  const disconnect = () => {
    websocketStore.disconnect()
  }

  const forceReconnect = () => {
    if (!authStore.isAuthenticated || !authStore.token) {
      console.error('Cannot reconnect WebSocket: not authenticated')
      return false
    }
    websocketStore.forceReconnect()
    return true
  }

  const joinRoom = roomId => {
    if (import.meta.env.VITE_USE_WEBSOCKETS === 'false') {
      return true // Simulate success
    }

    if (!isConnected.value) {
      console.error('Cannot join room: WebSocket not connected')
      return false
    }
    return websocketStore.joinRoom(roomId)
  }

  const leaveRoom = () => {
    if (import.meta.env.VITE_USE_WEBSOCKETS === 'false') return

    websocketStore.leaveRoom()
  }

  // Cleanup on unmount
  onUnmounted(() => {
    stopAuthWatcher()
    stopTokenWatcher()
  })

  return {
    // State
    isConnected,
    isConnecting,
    isReconnecting,
    connectionError,
    connectionInfo,

    // Methods
    connect,
    disconnect,
    forceReconnect,
    joinRoom,
    leaveRoom,
    initializeConnection,
    cleanupConnection,
  }
}

/**
 * Composable for room-specific WebSocket functionality
 */
export function useRoomWebSocket(roomId) {
  const websocket = useWebSocket()

  // Auto-join room when connected and roomId is provided
  const joinRoomWhenReady = () => {
    if (websocket.isConnected.value && roomId) {
      return websocket.joinRoom(roomId)
    }
    return false
  }

  // Watch for connection state changes to auto-join room
  const stopConnectionWatcher = watch(websocket.isConnected, connected => {
    if (connected && roomId) {
      console.log(`Auto-joining room ${roomId} after connection`)
      joinRoomWhenReady()
    }
  })

  // Cleanup on unmount
  onUnmounted(() => {
    stopConnectionWatcher()
    websocket.leaveRoom()
  })

  return {
    ...websocket,
    joinRoomWhenReady,
  }
}
