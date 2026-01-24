import { defineStore } from 'pinia'
import { ref } from 'vue'
import Echo from 'laravel-echo'
import Pusher from 'pusher-js'
import { useRoomStore } from './room'
import { useTrackStore } from './track'

// Configure Pusher
window.Pusher = Pusher

export const useWebSocketStore = defineStore('websocket', () => {
  // State
  const echo = ref(null)
  const nativeSocket = ref(null)
  const connected = ref(false)
  const connecting = ref(false)
  const error = ref(null)
  const roomChannel = ref(null)
  const reconnectAttempts = ref(0)
  const maxReconnectAttempts = ref(10)
  const reconnectTimeout = ref(null)
  const currentToken = ref(null)
  const connectionState = ref('disconnected') // 'disconnected', 'connecting', 'connected', 'reconnecting'
  const mode = ref('pusher')

  // Helper functions
  const calculateBackoffDelay = attempt => {
    // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 32s, max 60s
    const baseDelay = 1000
    const maxDelay = 60000
    const delay = Math.min(baseDelay * Math.pow(2, attempt), maxDelay)
    // Add jitter to prevent thundering herd
    const jitter = Math.random() * 0.1 * delay
    return delay + jitter
  }

  const clearReconnectTimeout = () => {
    if (reconnectTimeout.value) {
      clearTimeout(reconnectTimeout.value)
      reconnectTimeout.value = null
    }
  }

  const scheduleReconnect = () => {
    if (reconnectAttempts.value >= maxReconnectAttempts.value) {
      console.error('Max reconnection attempts reached')
      connectionState.value = 'disconnected'
      error.value = 'Failed to reconnect after maximum attempts'
      return
    }

    const delay = calculateBackoffDelay(reconnectAttempts.value)
    console.log(
      `Scheduling reconnection attempt ${reconnectAttempts.value + 1} in ${Math.round(delay)}ms`
    )

    connectionState.value = 'reconnecting'
    reconnectTimeout.value = setTimeout(() => {
      reconnectAttempts.value++
      if (currentToken.value) {
        connect(currentToken.value)
      }
    }, delay)
  }

  const resetReconnection = () => {
    reconnectAttempts.value = 0
    clearReconnectTimeout()
  }

  // Actions
  const connect = token => {
    const useNative =
      import.meta.env.VITE_USE_NATIVE_WS === 'true' || !import.meta.env.VITE_PUSHER_APP_KEY
    if (echo.value && connected.value) return
    if (connecting.value) return
    connecting.value = true
    connectionState.value = 'connecting'
    error.value = null
    currentToken.value = token
    mode.value = useNative ? 'native' : 'pusher'
    if (useNative) {
      try {
        if (nativeSocket.value) {
          nativeSocket.value.close()
          nativeSocket.value = null
        }
        const apiUrl = import.meta.env.VITE_API_URL
        const u = new URL(apiUrl)
        const protocol = u.protocol === 'https:' ? 'wss:' : 'ws:'
        const wsUrl = `${protocol}//${u.host}/ws?token=${encodeURIComponent(token)}`
        nativeSocket.value = new WebSocket(wsUrl)
        nativeSocket.value.onopen = () => {
          connected.value = true
          connecting.value = false
          connectionState.value = 'connected'
          resetReconnection()
        }
        nativeSocket.value.onclose = () => {
          connected.value = false
          connecting.value = false
          if (connectionState.value === 'connected' && currentToken.value) {
            scheduleReconnect()
          } else {
            connectionState.value = 'disconnected'
          }
        }
        nativeSocket.value.onerror = e => {
          const msg = e?.message || 'WebSocket connection error'
          error.value = msg
          connecting.value = false
          if (currentToken.value && connectionState.value !== 'disconnected') {
            scheduleReconnect()
          } else {
            connectionState.value = 'disconnected'
          }
        }
        nativeSocket.value.onmessage = ev => {
          try {
            const message = JSON.parse(ev.data)
            const type = message.type
            const data = message.data || {}
            const roomStore = useRoomStore()
            const trackStore = useTrackStore()
            if (type === 'connection_established') {
              connected.value = true
              connecting.value = false
              connectionState.value = 'connected'
            } else if (type === 'room_joined') {
              roomStore.updateRoomState(data.room)
            } else if (type === 'user_joined') {
              roomStore.addParticipant(data.user)
            } else if (type === 'user_left') {
              roomStore.removeParticipant(data.user.id)
            } else if (type === 'track_added') {
              trackStore.addTrackToQueue(data.track)
              const currentUserId = roomStore.currentRoom?.user?.id
              if (data.track.uploader?.id !== currentUserId) {
                if (typeof window !== 'undefined' && window.showNotification) {
                  window.showNotification(
                    'info',
                    'New Track Added',
                    `${data.track.uploader?.username || 'Someone'} added "${data.track.original_name}" to the queue`
                  )
                }
              }
            } else if (type === 'track_voted') {
              const currentUserId = roomStore.currentRoom?.user?.id
              trackStore.updateTrackVote(
                data.track.id,
                data.track.vote_score,
                data.voter?.id === currentUserId
              )
            } else if (type === 'playback_started') {
              trackStore.setCurrentTrack(data.track)
              trackStore.updatePlaybackState({
                isPlaying: true,
                startedAt: data.playback_started_at,
                pausedAt: null,
                position: 0,
                duration: data.track?.duration_seconds,
              })
            } else if (type === 'playback_paused') {
              trackStore.updatePlaybackState({
                isPlaying: false,
                pausedAt: data.playback_paused_at,
                position: data.current_position,
              })
            } else if (type === 'playback_resumed') {
              trackStore.updatePlaybackState({
                isPlaying: true,
                startedAt: data.playback_started_at,
                pausedAt: null,
              })
            } else if (type === 'track_skipped') {
              if (data.next_track) {
                trackStore.setCurrentTrack(data.next_track)
                trackStore.updatePlaybackState({
                  isPlaying: true,
                  startedAt: data.server_time,
                  pausedAt: null,
                  position: 0,
                  duration: data.next_track.duration_seconds,
                })
              } else {
                trackStore.setCurrentTrack(null)
                trackStore.updatePlaybackState({
                  isPlaying: false,
                  startedAt: null,
                  pausedAt: null,
                  position: 0,
                  duration: 0,
                })
              }
            } else if (type === 'room_state' || type === 'room_state_updated') {
              roomStore.updateRoomState(data.room)
            } else if (type === 'error') {
              error.value = data.message || 'WebSocket error'
            }
          } catch (e) {
            error.value = e?.message || 'Failed to process WebSocket message'
          }
        }
      } catch (err) {
        const errorMessage = err.message || 'Failed to initialize WebSocket'
        error.value = errorMessage
        connecting.value = false
        connectionState.value = 'disconnected'
        if (currentToken.value) {
          scheduleReconnect()
        }
      }
      return
    }

    try {
      // Disconnect existing connection if any
      if (echo.value) {
        echo.value.disconnect()
        echo.value = null
      }

      echo.value = new Echo({
        broadcaster: 'pusher',
        key: import.meta.env.VITE_PUSHER_APP_KEY,
        wsHost: import.meta.env.VITE_PUSHER_HOST,
        wsPort: import.meta.env.VITE_PUSHER_PORT,
        forceTLS: false,
        cluster: 'mt1',
        encrypted: false,
        disableStats: true,
        enabledTransports: ['ws'],
        activityTimeout: 120000,
        pongTimeout: 30000,
        unavailableTimeout: 10000,
        auth: {
          headers: {
            Authorization: `Bearer ${token}`,
          },
        },
        authEndpoint: `${import.meta.env.VITE_API_URL}/broadcasting/auth`,
      })

      // Connection event handlers
      echo.value.connector.pusher.connection.bind('connected', () => {
        connected.value = true
        connecting.value = false
        connectionState.value = 'connected'
        resetReconnection()
        console.log('WebSocket connected successfully')
      })

      echo.value.connector.pusher.connection.bind('disconnected', () => {
        connected.value = false
        connecting.value = false
        console.log('WebSocket disconnected')

        // Only attempt reconnection if we were previously connected and have a token
        if (connectionState.value === 'connected' && currentToken.value) {
          scheduleReconnect()
        } else {
          connectionState.value = 'disconnected'
        }
      })

      echo.value.connector.pusher.connection.bind('error', err => {
        const errorMessage = err.message || err.error?.message || 'WebSocket connection error'
        error.value = errorMessage
        connecting.value = false
        console.error('WebSocket error:', err)

        // Attempt reconnection on error if we have a token
        if (currentToken.value && connectionState.value !== 'disconnected') {
          scheduleReconnect()
        } else {
          connectionState.value = 'disconnected'
        }
      })

      echo.value.connector.pusher.connection.bind('unavailable', () => {
        console.warn('WebSocket connection unavailable')
        if (currentToken.value) {
          scheduleReconnect()
        }
      })

      echo.value.connector.pusher.connection.bind('failed', () => {
        console.error('WebSocket connection failed')
        connecting.value = false
        connectionState.value = 'disconnected'
        error.value = 'WebSocket connection failed'
      })
    } catch (err) {
      const errorMessage = err.message || 'Failed to initialize WebSocket'
      error.value = errorMessage
      connecting.value = false
      connectionState.value = 'disconnected'
      console.error('WebSocket initialization error:', err)

      // Attempt reconnection if we have a token
      if (currentToken.value) {
        scheduleReconnect()
      }
    }
  }
  const disconnect = () => {
    // Clear any pending reconnection attempts
    clearReconnectTimeout()
    resetReconnection()

    if (roomChannel.value && mode.value === 'pusher') {
      leaveRoom()
    }

    if (echo.value) {
      echo.value.disconnect()
      echo.value = null
    }
    if (nativeSocket.value) {
      try {
        nativeSocket.value.close()
      } finally {
        nativeSocket.value = null
      }
    }

    connected.value = false
    connecting.value = false
    connectionState.value = 'disconnected'
    error.value = null
    currentToken.value = null
    console.log('WebSocket disconnected manually')
  }

  const forceReconnect = () => {
    if (!currentToken.value) {
      console.log('Cannot reconnect: no token available')
      return false
    }

    console.log('Forcing WebSocket reconnection')
    resetReconnection()
    disconnect()
    setTimeout(() => {
      connect(currentToken.value)
    }, 1000)
    return true
  }

  const joinRoom = roomId => {
    if (mode.value === 'pusher') {
      if (!echo.value || !connected.value) {
        console.error('WebSocket not connected - cannot join room')
        error.value = 'WebSocket not connected'
        return false
      }
    } else {
      if (!nativeSocket.value || !connected.value) {
        console.error('WebSocket not connected - cannot join room')
        error.value = 'WebSocket not connected'
        return false
      }
    }

    try {
      // Leave current room if any
      if (roomChannel.value) {
        leaveRoom()
      }

      const roomStore = useRoomStore()
      const trackStore = useTrackStore()

      if (mode.value === 'pusher') {
        roomChannel.value = echo.value.private(`room.${roomId}`)

        // Listen for room events with error handling
        roomChannel.value
          .listen('user.joined', event => {
            console.log('User joined:', event)
            try {
              roomStore.addParticipant(event.user)
            } catch (err) {
              console.error('Error handling UserJoined event:', err)
            }
          })
          .listen('user.left', event => {
            console.log('User left:', event)
            try {
              roomStore.removeParticipant(event.user.id)
            } catch (err) {
              console.error('Error handling UserLeft event:', err)
            }
          })
          .listen('track.added', event => {
            console.log('Track added:', event)
            try {
              // Add track to queue and ensure proper sorting
              trackStore.addTrackToQueue(event.track)

              // Show notification to other users (not the uploader)
              const roomStore = useRoomStore()
              const currentUserId = roomStore.currentRoom?.user?.id
              if (event.track.uploader?.id !== currentUserId) {
                // This is from another user, show notification
                if (typeof window !== 'undefined' && window.showNotification) {
                  window.showNotification(
                    'info',
                    'New Track Added',
                    `${event.track.uploader?.username || 'Someone'} added "${event.track.original_name}" to the queue`
                  )
                }
              }
            } catch (err) {
              console.error('Error handling TrackAdded event:', err)
            }
          })
          .listen('track.voted', event => {
            console.log('Track voted:', event)
            try {
              trackStore.updateTrackVote(
                event.track.id,
                event.track.vote_score,
                event.user.id === roomStore.currentRoom?.user?.id
              )
            } catch (err) {
              console.error('Error handling TrackVoted event:', err)
            }
          })
          .listen('playback.started', event => {
            console.log('Playback started:', event)
            try {
              trackStore.setCurrentTrack(event.track)
              trackStore.updatePlaybackState({
                isPlaying: true,
                startedAt: event.started_at,
                pausedAt: null,
                position: 0,
                duration: event.track.duration_seconds,
              })
            } catch (err) {
              console.error('Error handling PlaybackStarted event:', err)
            }
          })
          .listen('playback.paused', event => {
            console.log('Playback paused:', event)
            try {
              trackStore.updatePlaybackState({
                isPlaying: false,
                pausedAt: event.paused_at,
                position: event.position,
              })
            } catch (err) {
              console.error('Error handling PlaybackPaused event:', err)
            }
          })
          .listen('playback.resumed', event => {
            console.log('Playback resumed:', event)
            try {
              trackStore.updatePlaybackState({
                isPlaying: true,
                startedAt: event.resumed_at,
                pausedAt: null,
              })
            } catch (err) {
              console.error('Error handling PlaybackResumed event:', err)
            }
          })
          .listen('track.skipped', event => {
            console.log('Track skipped:', event)
            try {
              if (event.next_track) {
                trackStore.setCurrentTrack(event.next_track)
                trackStore.updatePlaybackState({
                  isPlaying: true,
                  startedAt: event.timestamp,
                  pausedAt: null,
                  position: 0,
                  duration: event.next_track.duration_seconds,
                })
              } else {
                trackStore.setCurrentTrack(null)
                trackStore.updatePlaybackState({
                  isPlaying: false,
                  startedAt: null,
                  pausedAt: null,
                  position: 0,
                  duration: 0,
                })
              }
            } catch (err) {
              console.error('Error handling TrackSkipped event:', err)
            }
          })
          .listen('TrackRemoved', event => {
            console.log('Track removed:', event)
            try {
              trackStore.removeTrackFromQueue(event.track_id)
            } catch (err) {
              console.error('Error handling TrackRemoved event:', err)
            }
          })
          .listen('RoomUpdated', event => {
            console.log('Room updated:', event)
            try {
              roomStore.updateRoomState(event.room)
            } catch (err) {
              console.error('Error handling RoomUpdated event:', err)
            }
          })
          .error(err => {
            console.error('Room channel error:', err)
            // Handle channel-specific errors
            if (err.type === 'AuthError') {
              console.error('Authentication failed for room channel')
              error.value = 'Authentication failed for room'
            }
          })
        return true
      } else {
        nativeSocket.value.send(JSON.stringify({ type: 'join_room', data: { room_id: roomId } }))
        return true
      }
    } catch (err) {
      console.error('Failed to join room:', err)
      error.value = `Failed to join room: ${err.message}`
      return false
    }
  }

  const leaveRoom = () => {
    if (mode.value === 'pusher') {
      if (roomChannel.value) {
        try {
          if (roomChannel.value.stopListening) {
            roomChannel.value.stopListening()
          }

          const channelName = roomChannel.value.name || roomChannel.value.subscription?.name
          if (channelName && typeof channelName === 'string') {
            echo.value.leave(channelName)
            console.log(`Left room channel ${channelName} successfully`)
          } else {
            console.warn('Could not determine channel name to leave', roomChannel.value)
          }

          roomChannel.value = null
        } catch (err) {
          console.error('Error leaving room channel:', err)
          roomChannel.value = null
        }
      }
    } else {
      if (nativeSocket.value && connected.value) {
        try {
          nativeSocket.value.send(JSON.stringify({ type: 'leave_room', data: {} }))
        } catch (err) { }
      }
    }
  }

  // Utility methods for connection monitoring
  const isConnected = () => connected.value && connectionState.value === 'connected'
  const isConnecting = () => connecting.value || connectionState.value === 'connecting'
  const isReconnecting = () => connectionState.value === 'reconnecting'
  const getConnectionInfo = () => ({
    connected: connected.value,
    connecting: connecting.value,
    connectionState: connectionState.value,
    reconnectAttempts: reconnectAttempts.value,
    maxReconnectAttempts: maxReconnectAttempts.value,
    hasToken: !!currentToken.value,
    error: error.value,
  })

  return {
    // State
    echo,
    connected,
    connecting,
    error,
    roomChannel,
    reconnectAttempts,
    maxReconnectAttempts,
    connectionState,

    // Actions
    connect,
    disconnect,
    forceReconnect,
    joinRoom,
    leaveRoom,

    // Utility methods
    isConnected,
    isConnecting,
    isReconnecting,
    getConnectionInfo,
  }
})
