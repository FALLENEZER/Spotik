<template>
  <div class="audio-player">
    <!-- Hidden audio element - controlled programmatically -->
    <audio ref="audioRef" preload="auto" :volume="volume" :muted="muted" style="display: none" />

    <!-- Audio player UI -->
    <div v-if="currentTrack" class="bg-white rounded-lg shadow-sm border">
      <!-- Loading overlay -->
      <div
        v-if="isLoading"
        class="absolute inset-0 bg-white bg-opacity-75 flex items-center justify-center rounded-lg z-10"
      >
        <div class="flex items-center space-x-2">
          <LoadingSpinner size="sm" />
          <span class="text-sm text-gray-600">Loading audio...</span>
        </div>
      </div>

      <!-- Buffering indicator -->
      <div v-if="isBuffering && !isLoading" class="absolute top-2 right-2 z-10">
        <div
          class="flex items-center space-x-1 bg-yellow-100 text-yellow-800 px-2 py-1 rounded-full text-xs"
        >
          <LoadingSpinner size="xs" />
          <span>Buffering</span>
        </div>
      </div>

      <!-- Error indicator -->
      <div v-if="error" class="absolute top-2 right-2 z-10">
        <div
          class="flex items-center space-x-1 bg-red-100 text-red-800 px-2 py-1 rounded-full text-xs"
        >
          <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 20 20">
            <path
              fill-rule="evenodd"
              d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z"
              clip-rule="evenodd"
            />
          </svg>
          <span>Error</span>
        </div>
      </div>

      <div class="p-4 relative">
        <!-- Track info -->
        <div class="flex items-center space-x-3 mb-3">
          <!-- Album art placeholder -->
          <div
            class="flex-shrink-0 w-12 h-12 bg-gradient-to-br from-blue-400 to-purple-500 rounded-lg flex items-center justify-center"
          >
            <svg class="w-6 h-6 text-white" fill="currentColor" viewBox="0 0 20 20">
              <path
                fill-rule="evenodd"
                d="M18 3a1 1 0 00-1.447-.894L8.763 6H5a3 3 0 000 6h.28l1.771 5.316A1 1 0 008 18h1a1 1 0 001-1v-4.382l6.553 3.276A1 1 0 0018 15V3z"
                clip-rule="evenodd"
              />
            </svg>
          </div>

          <!-- Track details -->
          <div class="flex-1 min-w-0">
            <p class="text-sm font-medium text-gray-900 truncate">
              {{ currentTrack.original_name }}
            </p>
            <p class="text-xs text-gray-500">
              by {{ currentTrack.uploader?.username || 'Unknown' }}
            </p>
          </div>

          <!-- Sync status -->
          <div class="flex-shrink-0">
            <div
              v-if="syncStatus === 'synced'"
              class="flex items-center space-x-1 text-green-600"
              title="Audio synchronized"
            >
              <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                <path
                  fill-rule="evenodd"
                  d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                  clip-rule="evenodd"
                />
              </svg>
            </div>
            <div
              v-else-if="syncStatus === 'syncing'"
              class="flex items-center space-x-1 text-yellow-600"
              title="Synchronizing audio"
            >
              <LoadingSpinner size="xs" />
            </div>
            <div
              v-else-if="syncStatus === 'out_of_sync'"
              class="flex items-center space-x-1 text-red-600"
              title="Audio out of sync"
            >
              <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                <path
                  fill-rule="evenodd"
                  d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"
                  clip-rule="evenodd"
                />
              </svg>
            </div>
          </div>
        </div>

        <!-- Progress bar -->
        <div class="mb-3">
          <div class="flex items-center justify-between text-xs text-gray-500 mb-1">
            <span>{{ formatTime(currentTime) }}</span>
            <span>{{ formatTime(duration) }}</span>
          </div>

          <!-- Progress bar with buffer indicator -->
          <div class="relative">
            <!-- Background -->
            <div class="bg-gray-200 rounded-full h-2">
              <!-- Buffer progress -->
              <div
                v-for="(range, index) in buffered"
                :key="index"
                class="absolute bg-gray-300 h-2 rounded-full"
                :style="{
                  left: `${(range.start / duration) * 100}%`,
                  width: `${((range.end - range.start) / duration) * 100}%`,
                }"
              />

              <!-- Playback progress -->
              <div
                class="bg-blue-600 h-2 rounded-full transition-all duration-300"
                :style="{ width: `${progressPercentage}%` }"
              />
            </div>

            <!-- Clickable overlay for seeking -->
            <div class="absolute inset-0 cursor-pointer" @click="handleSeek" />
          </div>
        </div>

        <!-- Volume control -->
        <div class="flex items-center space-x-3">
          <!-- Mute button -->
          <button
            @click="toggleMute"
            class="p-1 rounded hover:bg-gray-100 transition-colors"
            :title="muted ? 'Unmute' : 'Mute'"
          >
            <svg
              v-if="muted || volume === 0"
              class="w-4 h-4 text-gray-600"
              fill="currentColor"
              viewBox="0 0 20 20"
            >
              <path
                fill-rule="evenodd"
                d="M9.383 3.076A1 1 0 0110 4v12a1 1 0 01-1.617.793L4.828 13H2a1 1 0 01-1-1V8a1 1 0 011-1h2.828l3.555-3.793A1 1 0 019.383 3.076zM8 5.04L5.707 7.293A1 1 0 005 8H3v4h2a1 1 0 01.707.293L8 14.96V5.04zm9.707 1.293a1 1 0 00-1.414-1.414L14.586 6.586l-1.293-1.293a1 1 0 00-1.414 1.414L13.586 8l-1.707 1.707a1 1 0 101.414 1.414L15 9.414l1.293 1.293a1 1 0 001.414-1.414L16 8l1.707-1.707z"
                clip-rule="evenodd"
              />
            </svg>
            <svg
              v-else-if="volume < 0.5"
              class="w-4 h-4 text-gray-600"
              fill="currentColor"
              viewBox="0 0 20 20"
            >
              <path
                fill-rule="evenodd"
                d="M9.383 3.076A1 1 0 0110 4v12a1 1 0 01-1.617.793L4.828 13H2a1 1 0 01-1-1V8a1 1 0 011-1h2.828l3.555-3.793A1 1 0 019.383 3.076zM8 5.04L5.707 7.293A1 1 0 005 8H3v4h2a1 1 0 01.707.293L8 14.96V5.04z"
                clip-rule="evenodd"
              />
              <path
                d="M11.025 7.05a2.5 2.5 0 010 3.536l-.707-.707a1.5 1.5 0 000-2.122l.707-.707z"
              />
            </svg>
            <svg v-else class="w-4 h-4 text-gray-600" fill="currentColor" viewBox="0 0 20 20">
              <path
                fill-rule="evenodd"
                d="M9.383 3.076A1 1 0 0110 4v12a1 1 0 01-1.617.793L4.828 13H2a1 1 0 01-1-1V8a1 1 0 011-1h2.828l3.555-3.793A1 1 0 019.383 3.076zM8 5.04L5.707 7.293A1 1 0 005 8H3v4h2a1 1 0 01.707.293L8 14.96V5.04z"
                clip-rule="evenodd"
              />
              <path
                d="M11.025 7.05a2.5 2.5 0 010 3.536l-.707-.707a1.5 1.5 0 000-2.122l.707-.707z"
              />
              <path
                d="M13.061 5.014a4.5 4.5 0 010 6.364l-.707-.707a3.5 3.5 0 000-4.95l.707-.707z"
              />
            </svg>
          </button>

          <!-- Volume slider -->
          <div class="flex-1 max-w-24">
            <input
              type="range"
              min="0"
              max="1"
              step="0.01"
              :value="volume"
              @input="handleVolumeChange"
              class="w-full h-1 bg-gray-200 rounded-lg appearance-none cursor-pointer slider"
            />
          </div>

          <!-- Volume percentage -->
          <span class="text-xs text-gray-500 w-8"> {{ Math.round(volume * 100) }}% </span>
        </div>

        <!-- Debug info (only in development) -->
        <div v-if="showDebugInfo" class="mt-3 p-2 bg-gray-50 rounded text-xs text-gray-600">
          <div class="grid grid-cols-2 gap-2">
            <div>Server Offset: {{ serverTimeOffset }}ms</div>
            <div>Network Latency: {{ Math.round(networkLatency) }}ms</div>
            <div>Sync Tolerance: {{ Math.round(syncTolerance * 1000) }}ms</div>
            <div>Adaptive Tolerance: {{ Math.round(adaptiveTolerance * 1000) }}ms</div>
            <div>Expected Position: {{ formatTime(expectedPosition) }}</div>
            <div>Actual Position: {{ formatTime(currentTime) }}</div>
            <div>
              Position Diff: {{ Math.round(Math.abs(expectedPosition - currentTime) * 1000) }}ms
            </div>
            <div>Sync Failures: {{ syncFailureCount }}</div>
            <div>Can Play: {{ canPlay ? 'Yes' : 'No' }}</div>
            <div>Sync History: {{ syncHistory.length }} entries</div>
          </div>

          <!-- Sync failure recovery button -->
          <div v-if="syncFailureCount >= 3" class="mt-2">
            <button
              @click="handleSyncFailure"
              class="px-2 py-1 bg-red-100 text-red-800 rounded text-xs hover:bg-red-200 transition-colors"
            >
              Force Sync Recovery
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- No track message -->
    <div v-else class="bg-gray-50 rounded-lg p-8 text-center">
      <svg
        class="mx-auto h-12 w-12 text-gray-400 mb-4"
        fill="none"
        viewBox="0 0 24 24"
        stroke="currentColor"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3"
        />
      </svg>
      <h3 class="text-lg font-medium text-gray-900 mb-2">No track playing</h3>
      <p class="text-gray-500">Select a track from the queue to start listening</p>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { useAudioPlayer } from '@/composables/useAudioPlayer'
import LoadingSpinner from '@/components/common/LoadingSpinner.vue'

const props = defineProps({
  showDebugInfo: {
    type: Boolean,
    default: false,
  },
})

// Use the audio player composable
const audioPlayer = useAudioPlayer()

// Destructure reactive properties and methods
const {
  audioElement,
  isLoading,
  isBuffering,
  canPlay,
  volume,
  muted,
  error,
  duration,
  currentTime,
  buffered,
  syncTolerance,
  serverTimeOffset,
  networkLatency,
  syncFailureCount,
  adaptiveTolerance,
  syncHistory,
  isPlaying,
  currentTrack,
  setVolume,
  toggleMute,
  seekTo,
  calculateExpectedPosition,
  handleSyncFailure,
} = audioPlayer

// Local refs
const audioRef = ref(null)
const syncStatus = ref('synced') // 'synced', 'syncing', 'out_of_sync'

// Computed properties
const progressPercentage = computed(() => {
  if (!duration.value) return 0
  return Math.min((currentTime.value / duration.value) * 100, 100)
})

const expectedPosition = computed(() => {
  return calculateExpectedPosition()
})

// Methods
const formatTime = seconds => {
  if (!seconds || isNaN(seconds)) return '0:00'

  const minutes = Math.floor(seconds / 60)
  const remainingSeconds = Math.floor(seconds % 60)
  return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`
}

const handleSeek = event => {
  if (!duration.value || !canPlay.value) return

  const rect = event.currentTarget.getBoundingClientRect()
  const clickX = event.clientX - rect.left
  const percentage = clickX / rect.width
  const newPosition = percentage * duration.value

  seekTo(newPosition)
}

const handleVolumeChange = event => {
  const newVolume = parseFloat(event.target.value)
  setVolume(newVolume)
}

// Watch for sync status changes with enhanced logic
watch([currentTime, expectedPosition, syncFailureCount], ([actualTime, expectedTime, failures]) => {
  if (!isPlaying.value || !canPlay.value) {
    syncStatus.value = 'synced'
    return
  }

  const diff = Math.abs(expectedTime - actualTime)

  // Consider sync failures in status determination
  if (failures >= 3) {
    syncStatus.value = 'out_of_sync'
  } else if (diff > syncTolerance.value * 2) {
    syncStatus.value = 'out_of_sync'
  } else if (diff > syncTolerance.value) {
    syncStatus.value = 'syncing'
  } else {
    syncStatus.value = 'synced'
  }
})

// Set up audio element reference
onMounted(() => {
  if (audioRef.value && audioElement.value) {
    // The composable already handles the audio element
    // This is just for potential future direct access
  }
})
</script>

<style scoped>
/* Custom slider styles */
.slider::-webkit-slider-thumb {
  appearance: none;
  height: 12px;
  width: 12px;
  border-radius: 50%;
  background: #3b82f6;
  cursor: pointer;
  border: none;
}

.slider::-moz-range-thumb {
  height: 12px;
  width: 12px;
  border-radius: 50%;
  background: #3b82f6;
  cursor: pointer;
  border: none;
}

.slider::-webkit-slider-track {
  height: 4px;
  border-radius: 2px;
  background: #e5e7eb;
}

.slider::-moz-range-track {
  height: 4px;
  border-radius: 2px;
  background: #e5e7eb;
  border: none;
}
</style>
