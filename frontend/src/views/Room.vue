<template>
  <div>
    <!-- Breadcrumbs -->
    <Breadcrumbs :items="breadcrumbItems" />

    <!-- Loading state -->
    <div v-if="loading" class="flex justify-center py-12">
      <LoadingSpinner />
    </div>

    <!-- Error state -->
    <div v-else-if="error" class="text-center py-12">
      <div class="bg-red-50 border border-red-200 rounded-md p-4 max-w-md mx-auto">
        <h3 class="text-lg font-medium text-red-800 mb-2">Room Not Found</h3>
        <p class="text-red-600 mb-4">{{ error }}</p>
        <div class="flex justify-center space-x-3">
          <button type="button" class="btn-outline" @click="fetchRoomDetails">Try Again</button>
          <router-link to="/dashboard" class="btn-primary"> Back to Dashboard </router-link>
        </div>
      </div>
    </div>

    <!-- Room content -->
    <div v-else-if="roomStore.currentRoom">
      <!-- Room header -->
      <div class="bg-white shadow rounded-lg mb-6">
        <div class="px-6 py-4 border-b border-gray-200">
          <div class="flex items-center justify-between">
            <div class="flex items-center">
              <div
                class="w-14 h-14 rounded-md overflow-hidden border border-gray-200 mr-4 flex-shrink-0"
                :style="getRoomCoverStyle(roomStore.currentRoom)"
                aria-hidden="true"
              >
                <img
                  v-if="roomStore.currentRoom.cover_url"
                  :src="roomStore.currentRoom.cover_url"
                  alt=""
                  class="w-full h-full object-cover"
                />
                <div v-else class="w-full h-full grid place-items-center">
                  <span class="text-xs font-semibold text-white drop-shadow">
                    {{ getInitials(roomStore.currentRoom.name) }}
                  </span>
                </div>
              </div>
              <h1 class="text-2xl font-bold text-gray-900">
                {{ roomStore.currentRoom.name }}
              </h1>
              <p v-if="roomStore.currentRoom.description" class="text-gray-600 mt-1">
                {{ roomStore.currentRoom.description }}
              </p>
            </div>
            <div class="flex items-center space-x-3">
              <!-- Connection Status -->
              <ConnectionStatus :compact="true" />

              <!-- Room status -->
              <span
                v-if="roomStore.currentRoom.is_playing"
                class="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-green-100 text-green-800"
              >
                <svg class="w-3 h-3 mr-1" fill="currentColor" viewBox="0 0 8 8">
                  <circle cx="4" cy="4" r="3" />
                </svg>
                Playing
              </span>
              <span
                v-else
                class="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-gray-100 text-gray-800"
              >
                Idle
              </span>

              <!-- Admin badge -->
              <span
                v-if="roomStore.isRoomAdmin"
                class="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-yellow-100 text-yellow-800"
              >
                <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
                Admin
              </span>

              <!-- Room action buttons -->
              <div v-if="roomStore.isRoomAdmin">
                <!-- Admin can delete room -->
                <button
                  type="button"
                  class="btn-outline text-red-600 border-red-300 hover:bg-red-50"
                  @click="handleDeleteRoom"
                  :disabled="roomStore.loading"
                >
                  Delete Room
                </button>
              </div>
              <div v-else>
                <!-- Participants can leave room -->
                <button
                  type="button"
                  class="btn-outline"
                  @click="handleLeaveRoom"
                  :disabled="roomStore.loading"
                >
                  Leave Room
                </button>
              </div>
            </div>
          </div>
        </div>

        <!-- Room stats -->
        <div class="px-6 py-4">
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div class="flex items-center">
              <svg
                class="w-5 h-5 text-gray-400 mr-2"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197m13.5-9a2.5 2.5 0 11-5 0 2.5 2.5 0 015 0z"
                />
              </svg>
              <span class="text-sm text-gray-600">
                {{ roomStore.participantCount }} participant{{
                  roomStore.participantCount !== 1 ? 's' : ''
                }}
              </span>
            </div>
            <div class="flex items-center">
              <svg
                class="w-5 h-5 text-gray-400 mr-2"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3"
                />
              </svg>
              <span class="text-sm text-gray-600">
                {{ trackStore.queueLength }} track{{ trackStore.queueLength !== 1 ? 's' : '' }} in
                queue
              </span>
            </div>
            <div class="flex items-center">
              <svg
                class="w-5 h-5 text-gray-400 mr-2"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
              <span class="text-sm text-gray-600">
                Created {{ formatDate(roomStore.currentRoom.created_at) }}
              </span>
              <div v-if="roomStore.isRoomAdmin">
                <input
                  ref="roomCoverInput"
                  type="file"
                  class="hidden"
                  accept=".jpg,.jpeg,.png,.webp,image/*"
                  @change="handleRoomCoverSelected"
                />
                <button type="button" class="btn-outline btn-sm" @click="triggerRoomCoverInput">
                  Change Cover
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Room interface components -->
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Left column: Track queue and file upload -->
        <div class="lg:col-span-2 space-y-6">
          <!-- Playback controls -->
          <PlaybackControls ref="playbackControls" />

          <!-- Track queue -->
          <TrackQueue
            :loading="trackLoading"
            @play-track="handlePlayTrack"
            @remove-track="handleRemoveTrack"
            @play-next="handlePlayNext"
            @create-playlist="handleCreatePlaylist"
          />

          <!-- File upload -->
          <FileUpload />
        </div>

        <!-- Right column: Participants -->
        <div class="space-y-6">
          <ParticipantList :loading="participantLoading" />
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, inject, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useRoomStore } from '@/stores/room'
import { useTrackStore } from '@/stores/track'
import { useWebSocket } from '@/composables/useWebSocket'
import api from '@/services/api'
import Breadcrumbs from '@/components/common/Breadcrumbs.vue'
import LoadingSpinner from '@/components/common/LoadingSpinner.vue'
import ParticipantList from '@/components/room/ParticipantList.vue'
import TrackQueue from '@/components/room/TrackQueue.vue'
import FileUpload from '@/components/room/FileUpload.vue'
import PlaybackControls from '@/components/room/PlaybackControls.vue'
import ConnectionStatus from '@/components/websocket/ConnectionStatus.vue'

const props = defineProps({
  id: {
    type: String,
    required: true,
  },
})

const router = useRouter()
const roomStore = useRoomStore()
const trackStore = useTrackStore()
const websocket = useWebSocket()
const showNotification = inject('showNotification')

const loading = ref(false)
const error = ref('')
const trackLoading = ref(false)
const participantLoading = ref(false)
const playbackControls = ref(null)
const roomCoverInput = ref(null)

// Computed properties
const breadcrumbItems = computed(() => [
  { name: 'Dashboard', to: '/dashboard' },
  { name: roomStore.currentRoom?.name || `Room ${props.id}` },
])

// Methods
const fetchRoomDetails = async () => {
  loading.value = true
  error.value = ''

  try {
    await roomStore.fetchRoomDetails(props.id)

    // Also fetch track queue and connect to WebSocket
    await Promise.all([fetchTrackQueue(), connectToWebSocket()])
  } catch (err) {
    error.value = err.message || 'Failed to load room details'
    console.error('Failed to fetch room details:', err)
  } finally {
    loading.value = false
  }
}

const fetchTrackQueue = async () => {
  if (!roomStore.currentRoom) return

  trackLoading.value = true
  try {
    await trackStore.fetchTrackQueue(roomStore.currentRoom.id)
  } catch (err) {
    console.error('Failed to fetch track queue:', err)
    showNotification('error', 'Error', 'Failed to load track queue')
  } finally {
    trackLoading.value = false
  }
}

const connectToWebSocket = async () => {
  if (!roomStore.currentRoom) return

  try {
    // Check if WebSocket is configured/enabled
    if (websocket.connectionInfo.value.connectionState === 'disabled') {
      console.log('WebSocket is disabled - skipping room channel connection')
      return
    }

    // Ensure WebSocket is connected
    if (!websocket.isConnected.value) {
      websocket.initializeConnection()

      // Wait for connection to be established
      let attempts = 0
      const maxAttempts = 20 // Increased attempts
      while (!websocket.isConnected.value && attempts < maxAttempts) {
        // If we hit an error during connection, stop waiting and report it
        if (websocket.connectionError.value) {
          throw new Error(`WebSocket connection failed: ${websocket.connectionError.value}`)
        }
        await new Promise(resolve => setTimeout(resolve, 500))
        attempts++
      }

      if (!websocket.isConnected.value) {
        throw new Error('Failed to establish WebSocket connection within time limit')
      }
    }

    // Join room channel
    const joined = websocket.joinRoom(roomStore.currentRoom.id)
    if (!joined) {
      throw new Error('Failed to join room channel')
    }

    console.log(`Successfully connected to room ${roomStore.currentRoom.id}`)
  } catch (err) {
    console.error('Failed to connect to WebSocket:', err)
    showNotification(
      'warning',
      'Connection Warning',
      `Real-time updates may not work properly: ${err.message}`
    )
  }
}

const handleLeaveRoom = async () => {
  try {
    // Leave WebSocket room first
    websocket.leaveRoom()

    await roomStore.leaveRoom()
    showNotification('success', 'Success', 'Left room successfully')
    router.push('/dashboard')
  } catch (err) {
    console.error('Failed to leave room:', err)

    // Handle specific error cases
    if (err.response?.status === 403) {
      showNotification(
        'warning',
        'Cannot Leave Room',
        'Room administrators cannot leave the room. You can delete the room instead.'
      )
    } else {
      showNotification(
        'error',
        'Error',
        err.response?.data?.message || err.message || 'Failed to leave room'
      )
    }
  }
}

const handleDeleteRoom = async () => {
  if (!confirm('Are you sure you want to delete this room? This action cannot be undone.')) {
    return
  }

  try {
    // Leave WebSocket room first
    websocket.leaveRoom()

    await roomStore.deleteRoom(props.id)
    showNotification('success', 'Success', 'Room deleted successfully')
    router.push('/dashboard')
  } catch (err) {
    console.error('Failed to delete room:', err)
    showNotification(
      'error',
      'Error',
      err.response?.data?.message || err.message || 'Failed to delete room'
    )
  }
}

const handlePlayTrack = async track => {
  if (!roomStore.isRoomAdmin) {
    showNotification(
      'warning',
      'Permission Denied',
      'Only room administrators can control playback'
    )
    return
  }

  try {
    await playbackControls.value?.playTrack(track)
  } catch (err) {
    console.error('Failed to play track:', err)
    showNotification('error', 'Playback Error', err.message || 'Failed to play track')
  }
}

const handleRemoveTrack = async track => {
  if (!roomStore.isRoomAdmin) {
    showNotification('warning', 'Permission Denied', 'Only room administrators can remove tracks')
    return
  }

  try {
    await trackStore.removeTrack(track.id)
    showNotification('success', 'Success', 'Track removed successfully')
  } catch (err) {
    console.error('Failed to remove track:', err)
    showNotification('error', 'Error', err.message || 'Failed to remove track')
  }
}

const handlePlayNext = async () => {
  if (!roomStore.isRoomAdmin) {
    showNotification(
      'warning',
      'Permission Denied',
      'Only room administrators can control playback'
    )
    return
  }

  const nextTrack = trackStore.sortedQueue[0]
  if (nextTrack) {
    await handlePlayTrack(nextTrack)
  } else {
    showNotification('info', 'No Tracks', 'No tracks available in the queue')
  }
}

const handleCreatePlaylist = () => {
  // Navigate to dashboard with a focus on playlist creation
  router.push('/dashboard')
  showNotification('info', 'Create Playlist', 'Navigate to the dashboard to create a new playlist')
}

const formatDate = dateString => {
  if (!dateString) return 'Unknown'

  const date = new Date(dateString)
  const now = new Date()
  const diffInHours = Math.floor((now - date) / (1000 * 60 * 60))

  if (diffInHours < 1) {
    return 'just now'
  } else if (diffInHours < 24) {
    return `${diffInHours} hour${diffInHours !== 1 ? 's' : ''} ago`
  } else if (diffInHours < 168) {
    // 7 days
    const days = Math.floor(diffInHours / 24)
    return `${days} day${days !== 1 ? 's' : ''} ago`
  } else {
    return date.toLocaleDateString()
  }
}

const getInitials = name => {
  if (!name) return 'A'
  const parts = name.split(/\s+/).filter(Boolean)
  const first = parts[0]?.[0] || 'A'
  const second = parts.length > 1 ? parts[1]?.[0] : ''
  return (first + second).toUpperCase()
}

const stringToHue = str => {
  let hash = 0
  for (let i = 0; i < str.length; i++) {
    hash = str.charCodeAt(i) + ((hash << 5) - hash)
  }
  return Math.abs(hash) % 360
}

const getRoomCoverStyle = room => {
  if (room?.cover_url) return {}
  const hue = stringToHue(room?.name || String(room?.id))
  const start = `hsl(${hue}, 70%, 55%)`
  const end = `hsl(${(hue + 40) % 360}, 70%, 45%)`
  return { background: `linear-gradient(135deg, ${start}, ${end})` }
}

const triggerRoomCoverInput = () => {
  roomCoverInput.value?.click()
}

const handleRoomCoverSelected = async e => {
  const file = e.target.files?.[0]
  if (!file) return

  try {
    const formData = new FormData()
    formData.append('cover_image', file)

    // Create a custom config that doesn't override Content-Type
    const config = {
      headers: {
        // Don't set Content-Type - let browser set it with boundary
        Accept: 'application/json',
      },
    }

    // Get auth token manually to ensure it's included
    const token = localStorage.getItem('auth_token')
    if (token) {
      config.headers.Authorization = `Bearer ${token}`
    }

    const { data } = await api.post(`/rooms/${roomStore.currentRoom.id}/cover`, formData, config)
    roomStore.updateRoomState({ cover_url: data.cover_url })
    showNotification('success', 'Success', 'Room cover updated')
  } catch (err) {
    console.error('Failed to upload room cover:', err)
    
    // Detailed error handling
    const isValidationError = err.response?.status === 422
    const validationErrors = err.response?.data?.errors || {}
    
    // Check for specific file errors (size, type)
    const hasImageError = 
      !!validationErrors.cover_image || 
      /must be an image/i.test(validationErrors.cover_image?.[0] || '') ||
      /file/i.test(validationErrors.cover_image?.[0] || '')

    // If it's a validation error related to the file, or if the server rejected the upload
    // try the base64 fallback method which can sometimes bypass strict server-side file checks
    // or issues with multipart/form-data parsing
    if (isValidationError || err.response?.status === 413) {
      console.log('Attempting fallback base64 upload...')
      try {
        const toDataUrl = file =>
          new Promise((resolve, reject) => {
            const reader = new FileReader()
            reader.onload = () => resolve(reader.result)
            reader.onerror = reject
            reader.readAsDataURL(file)
          })
          
        // Check file size before fallback - 10MB limit (approx)
        if (file.size > 10 * 1024 * 1024) {
           throw new Error('Image is too large. Please choose an image under 10MB.')
        }

        const dataUrl = await toDataUrl(file)
        const fallbackPayload = { cover_data: dataUrl }
        
        const { data } = await api.post(
          `/rooms/${roomStore.currentRoom.id}/cover`,
          fallbackPayload,
          { headers: { Accept: 'application/json' } }
        )
        
        roomStore.updateRoomState({ cover_url: data.cover_url })
        showNotification('success', 'Success', 'Room cover updated (fallback)')
        return // Exit successfully
      } catch (fallbackErr) {
        console.error('Fallback base64 upload failed:', fallbackErr)
        // If fallback fails, show the original error if it was size related, or the fallback error
        const msg = fallbackErr.message || 
          fallbackErr.response?.data?.error ||
          fallbackErr.response?.data?.message ||
          'Failed to upload cover'
          
        showNotification('error', 'Error', msg)
        return
      }
    }

    // Generic error handling
    const errorMessage =
      err.response?.data?.error || 
      err.response?.data?.message || 
      'Failed to upload cover'
      
    showNotification('error', 'Error', errorMessage)
  } finally {
    roomCoverInput.value.value = ''
  }
}

// Lifecycle
onMounted(() => {
  // Check if we already have room data (from joining via dashboard)
  if (!roomStore.currentRoom || roomStore.currentRoom.id !== props.id) {
    fetchRoomDetails()
  } else {
    // Still fetch track queue and connect WebSocket
    fetchTrackQueue()
    connectToWebSocket()
  }
})

onUnmounted(() => {
  // Leave WebSocket room
  websocket.leaveRoom()

  // Clear room and track state when leaving the component
  roomStore.clearRoom()
  trackStore.clearTracks()
})

// Watch for WebSocket connection changes
watch(
  () => websocket.isConnected.value,
  (connected, wasConnected) => {
    if (connected && !wasConnected && roomStore.currentRoom) {
      // Reconnected - rejoin room
      console.log('WebSocket reconnected, rejoining room')
      websocket.joinRoom(roomStore.currentRoom.id)
      showNotification('success', 'Reconnected', 'Real-time updates restored')
    } else if (!connected && wasConnected) {
      // Disconnected
      console.log('WebSocket disconnected')
      if (websocket.isReconnecting.value) {
        showNotification('warning', 'Connection Lost', 'Attempting to reconnect...')
      }
    }
  }
)

// Watch for WebSocket errors
watch(
  () => websocket.connectionError.value,
  error => {
    if (error) {
      console.error('WebSocket error:', error)
      showNotification('error', 'Connection Error', error)
    }
  }
)
</script>
