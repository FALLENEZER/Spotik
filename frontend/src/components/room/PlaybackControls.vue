<template>
  <div class="bg-white shadow rounded-lg">
    <div class="px-6 py-4 border-b border-gray-200">
      <h3 class="text-lg font-medium text-gray-900 flex items-center">
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
            d="M14.828 14.828a4 4 0 01-5.656 0M9 10h1m4 0h1m-6 4h1m4 0h1m-6-8h1m4 0h1M9 18h6"
          />
        </svg>
        Playback Controls
        <span
          v-if="!roomStore.isRoomAdmin"
          class="ml-2 inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-gray-100 text-gray-600"
        >
          Admin Only
        </span>
      </h3>
    </div>

    <div class="px-6 py-4">
      <!-- Audio Player Component -->
      <div class="mb-6">
        <AudioPlayer :show-debug-info="showDebugInfo" />
      </div>

      <!-- Current track info -->
      <div v-if="currentTrack" class="mb-4 text-center">
        <p class="text-sm text-gray-600 mb-1">Now Playing</p>
        <p class="font-medium text-gray-900 truncate">{{ currentTrack.original_name }}</p>
        <p class="text-xs text-gray-500">
          {{ formatDuration(playbackState.position) }} /
          {{ formatDuration(currentTrack.duration_seconds) }}
        </p>
      </div>

      <!-- Control buttons -->
      <div class="flex items-center justify-center space-x-4">
        <!-- Previous track (disabled for now) -->
        <button
          disabled
          class="p-3 rounded-full bg-gray-100 text-gray-400 cursor-not-allowed"
          title="Previous track (coming soon)"
        >
          <svg class="w-6 h-6" fill="currentColor" viewBox="0 0 20 20">
            <path
              d="M8.445 14.832A1 1 0 0010 14v-2.798l5.445 3.63A1 1 0 0017 14V6a1 1 0 00-1.555-.832L10 8.798V6a1 1 0 00-1.555-.832l-6 4a1 1 0 000 1.664l6 4z"
            />
          </svg>
        </button>

        <!-- Play/Pause/Resume button -->
        <button
          v-if="roomStore.isRoomAdmin"
          @click="togglePlayback"
          :disabled="loading || !hasTracksInQueue"
          class="p-4 rounded-full transition-colors"
          :class="[
            hasTracksInQueue && !loading
              ? 'bg-blue-600 hover:bg-blue-700 text-white'
              : 'bg-gray-100 text-gray-400 cursor-not-allowed',
          ]"
          :title="getPlayButtonTitle()"
        >
          <LoadingSpinner v-if="loading" size="sm" class="text-white" />
          <svg
            v-else-if="playbackState.isPlaying"
            class="w-8 h-8"
            fill="currentColor"
            viewBox="0 0 20 20"
          >
            <path
              fill-rule="evenodd"
              d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zM7 8a1 1 0 012 0v4a1 1 0 11-2 0V8zm5-1a1 1 0 00-1 1v4a1 1 0 102 0V8a1 1 0 00-1-1z"
              clip-rule="evenodd"
            />
          </svg>
          <svg v-else class="w-8 h-8" fill="currentColor" viewBox="0 0 20 20">
            <path
              fill-rule="evenodd"
              d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z"
              clip-rule="evenodd"
            />
          </svg>
        </button>

        <!-- Non-admin play button (disabled) -->
        <button
          v-else
          disabled
          class="p-4 rounded-full bg-gray-100 text-gray-400 cursor-not-allowed"
          title="Only room administrators can control playback"
        >
          <svg class="w-8 h-8" fill="currentColor" viewBox="0 0 20 20">
            <path
              fill-rule="evenodd"
              d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z"
              clip-rule="evenodd"
            />
          </svg>
        </button>

        <!-- Skip button -->
        <button
          v-if="roomStore.isRoomAdmin"
          @click="skipTrack"
          :disabled="loading || !currentTrack"
          class="p-3 rounded-full transition-colors"
          :class="[
            currentTrack && !loading
              ? 'bg-gray-100 hover:bg-gray-200 text-gray-700'
              : 'bg-gray-100 text-gray-400 cursor-not-allowed',
          ]"
          title="Skip to next track"
        >
          <svg class="w-6 h-6" fill="currentColor" viewBox="0 0 20 20">
            <path
              d="M4.555 5.168A1 1 0 003 6v8a1 1 0 001.555.832L10 11.202V14a1 1 0 001.555.832l6-4a1 1 0 000-1.664l-6-4A1 1 0 0010 6v2.798l-5.445-3.63z"
            />
          </svg>
        </button>

        <!-- Non-admin skip button (disabled) -->
        <button
          v-else
          disabled
          class="p-3 rounded-full bg-gray-100 text-gray-400 cursor-not-allowed"
          title="Only room administrators can control playback"
        >
          <svg class="w-6 h-6" fill="currentColor" viewBox="0 0 20 20">
            <path
              d="M4.555 5.168A1 1 0 003 6v8a1 1 0 001.555.832L10 11.202V14a1 1 0 001.555.832l6-4a1 1 0 000-1.664l-6-4A1 1 0 0010 6v2.798l-5.445-3.63z"
            />
          </svg>
        </button>
      </div>

      <!-- Additional controls -->
      <div v-if="roomStore.isRoomAdmin" class="mt-6 flex items-center justify-center space-x-3">
        <button
          @click="stopPlayback"
          :disabled="loading || !currentTrack"
          class="btn-sm btn-outline"
          title="Stop playback and clear current track"
        >
          <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            />
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M9 10h6v4H9z"
            />
          </svg>
          Stop
        </button>

        <!-- Debug toggle (development only) -->
        <button
          v-if="isDevelopment"
          @click="showDebugInfo = !showDebugInfo"
          class="btn-sm btn-outline"
          :class="{ 'bg-blue-50 border-blue-200': showDebugInfo }"
        >
          <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
            />
          </svg>
          Debug
        </button>
      </div>

      <!-- Playback status indicator -->
      <div class="mt-4 text-center">
        <div class="flex items-center justify-center space-x-2 text-sm text-gray-500">
          <div
            class="w-2 h-2 rounded-full"
            :class="{
              'bg-green-500': playbackState.isPlaying,
              'bg-yellow-500': currentTrack && !playbackState.isPlaying,
              'bg-gray-400': !currentTrack,
            }"
          ></div>
          <span>
            {{ getPlaybackStatusText() }}
          </span>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, inject, watch } from 'vue'
import { useRoomStore } from '@/stores/room'
import { useTrackStore } from '@/stores/track'
import { usePlaybackStore } from '@/stores/playback'
import LoadingSpinner from '@/components/common/LoadingSpinner.vue'
import AudioPlayer from '@/components/audio/AudioPlayer.vue'

const roomStore = useRoomStore()
const trackStore = useTrackStore()
const playbackStore = usePlaybackStore()
const showNotification = inject('showNotification')

// State
const showDebugInfo = ref(false)

// Computed
const currentTrack = computed(() => playbackStore.currentTrack)
const playbackState = computed(() => playbackStore.playbackState)
const loading = computed(() => playbackStore.loading)
const isDevelopment = computed(() => import.meta.env.DEV)
const hasTracksInQueue = computed(() => trackStore.queueLength > 0)

// Helper methods
const formatDuration = seconds => {
  if (!seconds || seconds < 0) return '0:00'
  const mins = Math.floor(seconds / 60)
  const secs = Math.floor(seconds % 60)
  return `${mins}:${secs.toString().padStart(2, '0')}`
}

const getPlayButtonTitle = () => {
  if (!hasTracksInQueue.value) return 'No tracks in queue'
  if (!roomStore.isRoomAdmin) return 'Only room administrators can control playback'

  if (currentTrack.value) {
    return playbackState.value.isPlaying ? 'Pause current track' : 'Resume current track'
  } else {
    return 'Start playing first track in queue'
  }
}

const getPlaybackStatusText = () => {
  if (!currentTrack.value) return 'No track selected'
  if (playbackState.value.isPlaying) return 'Playing'
  return 'Paused'
}

// Main playback control methods
const togglePlayback = async () => {
  if (loading.value) return

  try {
    const roomId = roomStore.currentRoom.id
    await playbackStore.togglePlayback(roomId)

    // Show appropriate notification
    if (currentTrack.value) {
      const action = playbackState.value.isPlaying ? 'resumed' : 'paused'
      showNotification(
        'success',
        `Playback ${action.charAt(0).toUpperCase() + action.slice(1)}`,
        `Track ${action} successfully`
      )
    } else {
      const firstTrack = trackStore.sortedQueue[0]
      if (firstTrack) {
        showNotification('success', 'Playback Started', `Now playing: ${firstTrack.original_name}`)
      }
    }
  } catch (error) {
    console.error('Failed to toggle playback:', error)
    showNotification('error', 'Playback Error', error.message)
  }
}

const skipTrack = async () => {
  if (!currentTrack.value || loading.value) return

  try {
    const roomId = roomStore.currentRoom.id
    await playbackStore.skipTrack(roomId)
    showNotification('success', 'Track Skipped', 'Moved to next track')
  } catch (error) {
    console.error('Failed to skip track:', error)
    showNotification('error', 'Skip Error', error.message)
  }
}

const stopPlayback = async () => {
  if (!currentTrack.value || loading.value) return

  try {
    const roomId = roomStore.currentRoom.id
    await playbackStore.stopPlayback(roomId)
    showNotification('success', 'Playback Stopped', 'Playback stopped successfully')
  } catch (error) {
    console.error('Failed to stop playback:', error)
    showNotification('error', 'Stop Error', error.message)
  }
}

// Method for external track playing (called from TrackQueue component)
const playTrack = async track => {
  if (loading.value) return

  try {
    const roomId = roomStore.currentRoom.id
    await playbackStore.startTrack(roomId, track.id)
    showNotification('success', 'Track Started', `Now playing: ${track.original_name}`)
  } catch (error) {
    console.error('Failed to play track:', error)
    showNotification('error', 'Play Error', error.message)
    throw error // Re-throw so parent component can handle it
  }
}

// Watch for playback state changes to update position
watch(
  () => playbackState.value,
  (newState, oldState) => {
    // Update position calculation when playback state changes
    if (newState.isPlaying !== oldState?.isPlaying) {
      console.log('Playback state changed:', {
        isPlaying: newState.isPlaying,
        track: currentTrack.value?.original_name,
        position: newState.position,
      })
    }
  },
  { deep: true }
)

// Watch for current track changes
watch(
  () => currentTrack.value,
  (newTrack, oldTrack) => {
    if (newTrack?.id !== oldTrack?.id) {
      console.log('Current track changed:', {
        from: oldTrack?.original_name || 'None',
        to: newTrack?.original_name || 'None',
      })
    }
  }
)

// Watch for playback errors
watch(
  () => playbackStore.error,
  error => {
    if (error) {
      console.error('Playback store error:', error)
      // Clear the error after showing notification
      setTimeout(() => {
        playbackStore.clearError()
      }, 100)
    }
  }
)

// Expose playTrack method for parent component
defineExpose({
  playTrack,
})
</script>
