<template>
  <div class="bg-white shadow rounded-lg">
    <div class="px-6 py-4 border-b border-gray-200">
      <div class="flex items-center justify-between">
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
              d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3"
            />
          </svg>
          Track Queue ({{ sortedTracks.length }})
        </h3>

        <!-- Queue controls -->
        <div class="flex items-center space-x-2">
          <button
            v-if="roomStore.isRoomAdmin && sortedTracks.length > 0"
            @click="$emit('play-next')"
            class="btn-sm btn-primary"
            :disabled="loading"
          >
            <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M14.828 14.828a4 4 0 01-5.656 0M9 10h1m4 0h1m-6 4h1m4 0h1m-6-8h1m4 0h1M9 18h6"
              />
            </svg>
            Play Next
          </button>
        </div>
      </div>
    </div>

    <div class="px-6 py-4">
      <!-- Loading state -->
      <div v-if="loading" class="flex justify-center py-8">
        <LoadingSpinner />
      </div>

      <!-- Empty state -->
      <div v-else-if="sortedTracks.length === 0" class="text-center py-12">
        <svg
          class="mx-auto h-12 w-12 text-gray-400"
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
        <h3 class="mt-2 text-lg font-medium text-gray-900">No tracks in queue</h3>
        <p class="mt-1 text-sm text-gray-500">Upload some music to get the party started!</p>
      </div>

      <!-- Track list -->
      <div v-else class="space-y-3">
        <div
          v-for="(track, index) in sortedTracks"
          :key="track.id"
          class="flex items-center p-4 border border-gray-200 rounded-lg hover:bg-gray-50 transition-colors"
          :class="{
            'bg-blue-50 border-blue-200': isCurrentTrack(track),
            'ring-2 ring-blue-500': isCurrentTrack(track),
          }"
        >
          <!-- Track cover -->
          <div
            class="flex-shrink-0 w-12 h-12 rounded-md overflow-hidden border border-gray-200"
            :style="getCoverStyle(track)"
            aria-hidden="true"
          >
            <img
              v-if="track.cover_url"
              :src="track.cover_url"
              alt=""
              class="w-full h-full object-cover"
            />
            <div v-else class="w-full h-full grid place-items-center">
              <span class="text-xs font-semibold text-white drop-shadow">
                {{ getInitials(track.original_name) }}
              </span>
            </div>
          </div>
          <!-- Track position -->
          <div class="flex-shrink-0 w-8 text-center">
            <span
              v-if="isCurrentTrack(track)"
              class="inline-flex items-center justify-center w-6 h-6 bg-blue-500 text-white text-xs font-medium rounded-full"
            >
              <svg class="w-3 h-3" fill="currentColor" viewBox="0 0 8 8">
                <circle cx="4" cy="4" r="3" />
              </svg>
            </span>
            <span v-else class="text-sm text-gray-500 font-medium">
              {{ index + 1 }}
            </span>
          </div>

          <!-- Track info -->
          <div class="flex-1 min-w-0 ml-4">
            <div class="flex items-center justify-between">
              <div class="min-w-0 flex-1">
                <div class="flex items-center space-x-2">
                  <p class="text-sm font-medium text-gray-900 truncate">
                    {{ track.original_name }}
                  </p>
                  <!-- Genre badge -->
                  <span
                    v-if="track.genre"
                    class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium text-white"
                    :style="{ backgroundColor: track.genre.color || '#6B7280' }"
                  >
                    {{ track.genre.name }}
                  </span>
                </div>
                <div class="flex items-center mt-1 text-xs text-gray-500 space-x-4">
                  <span>{{ formatDuration(track.duration_seconds) }}</span>
                  <span>{{ formatFileSize(track.file_size_bytes) }}</span>
                  <span>by {{ track.uploader.username }}</span>
                  <span>{{ formatUploadTime(track.created_at) }}</span>
                </div>
              </div>

              <!-- Track actions -->
              <div class="flex items-center space-x-3 ml-4">
                <!-- Vote button -->
                <button
                  @click="handleVote(track)"
                  :disabled="votingTrackId === track.id"
                  class="flex items-center space-x-1 px-3 py-1 rounded-full text-sm font-medium transition-colors"
                  :class="[
                    track.user_has_voted
                      ? 'bg-red-100 text-red-700 hover:bg-red-200'
                      : 'bg-gray-100 text-gray-700 hover:bg-gray-200',
                  ]"
                >
                  <svg
                    class="w-4 h-4"
                    :class="{ 'animate-pulse': votingTrackId === track.id }"
                    fill="currentColor"
                    viewBox="0 0 20 20"
                  >
                    <path
                      v-if="track.user_has_voted"
                      d="M3.172 5.172a4 4 0 015.656 0L10 6.343l1.172-1.171a4 4 0 115.656 5.656L10 17.657l-6.828-6.829a4 4 0 010-5.656z"
                    />
                    <path
                      v-else
                      fill-rule="evenodd"
                      d="M3.172 5.172a4 4 0 015.656 0L10 6.343l1.172-1.171a4 4 0 115.656 5.656L10 17.657l-6.828-6.829a4 4 0 010-5.656z"
                      clip-rule="evenodd"
                    />
                  </svg>
                  <span>{{ track.vote_score }}</span>
                </button>

                <!-- Add to playlist button -->
                <button
                  @click="showAddToPlaylist(track)"
                  class="p-2 text-gray-400 hover:text-purple-600 transition-colors"
                  title="Add to playlist"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 6v6m0 0v6m0-6h6m-6 0H6"
                    />
                  </svg>
                </button>

                <!-- Admin controls -->
                <div v-if="roomStore.isRoomAdmin" class="flex items-center space-x-2">
                  <!-- Play track button -->
                  <button
                    v-if="!isCurrentTrack(track)"
                    @click="$emit('play-track', track)"
                    class="p-2 text-gray-400 hover:text-green-600 transition-colors"
                    title="Play this track"
                  >
                    <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                      <path
                        fill-rule="evenodd"
                        d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z"
                        clip-rule="evenodd"
                      />
                    </svg>
                  </button>

                  <!-- Remove track button -->
                  <button
                    @click="$emit('remove-track', track)"
                    class="p-2 text-gray-400 hover:text-red-600 transition-colors"
                    title="Remove track"
                  >
                    <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                      />
                    </svg>
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Add to Playlist Modal -->
    <AddToPlaylistModal
      :show="showPlaylistModal"
      :track="selectedTrack"
      @close="closePlaylistModal"
      @create-playlist="handleCreatePlaylist"
    />
  </div>
</template>

<script setup>
import { ref, computed, inject } from 'vue'
import { useRoomStore } from '@/stores/room'
import { useTrackStore } from '@/stores/track'
import LoadingSpinner from '@/components/common/LoadingSpinner.vue'
import AddToPlaylistModal from '@/components/playlist/AddToPlaylistModal.vue'

const roomStore = useRoomStore()
const trackStore = useTrackStore()
const showNotification = inject('showNotification')

// Props
const { loading } = defineProps({
  loading: {
    type: Boolean,
    default: false,
  },
})

// Emits
const emit = defineEmits(['play-track', 'remove-track', 'play-next', 'create-playlist'])

// State
const votingTrackId = ref(null)
const showPlaylistModal = ref(false)
const selectedTrack = ref(null)

// Computed
const sortedTracks = computed(() => trackStore.sortedQueue)

// Methods
const isCurrentTrack = track => {
  return trackStore.currentTrack?.id === track.id
}

const handleVote = async track => {
  if (votingTrackId.value === track.id) return

  votingTrackId.value = track.id

  try {
    await trackStore.voteForTrack(track.id)

    const message = track.user_has_voted ? 'Vote removed successfully' : 'Vote added successfully'

    showNotification('success', 'Success', message)
  } catch (error) {
    console.error('Failed to vote for track:', error)
    showNotification('error', 'Error', error.message || 'Failed to vote for track')
  } finally {
    votingTrackId.value = null
  }
}

const getInitials = name => {
  if (!name) return 'A'
  const parts = name
    .replace(/\.[^/.]+$/, '')
    .split(/\s+/)
    .filter(Boolean)
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

const getCoverStyle = track => {
  if (track.cover_url) return {}
  const hue = stringToHue(track.original_name || String(track.id))
  const start = `hsl(${hue}, 70%, 55%)`
  const end = `hsl(${(hue + 40) % 360}, 70%, 45%)`
  return { background: `linear-gradient(135deg, ${start}, ${end})` }
}

const formatDuration = seconds => {
  if (!seconds) return '0:00'

  const minutes = Math.floor(seconds / 60)
  const remainingSeconds = seconds % 60
  return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`
}

const formatFileSize = bytes => {
  if (!bytes) return '0 B'

  const sizes = ['B', 'KB', 'MB', 'GB']
  const i = Math.floor(Math.log(bytes) / Math.log(1024))
  return `${(bytes / Math.pow(1024, i)).toFixed(1)} ${sizes[i]}`
}

const formatUploadTime = dateString => {
  if (!dateString) return 'Unknown'

  const date = new Date(dateString)
  const now = new Date()
  const diffInMinutes = Math.floor((now - date) / (1000 * 60))

  if (diffInMinutes < 1) {
    return 'just now'
  } else if (diffInMinutes < 60) {
    return `${diffInMinutes} min ago`
  } else if (diffInMinutes < 1440) {
    // 24 hours
    const hours = Math.floor(diffInMinutes / 60)
    return `${hours}h ago`
  } else {
    const days = Math.floor(diffInMinutes / 1440)
    return `${days}d ago`
  }
}

const showAddToPlaylist = (track) => {
  selectedTrack.value = track
  showPlaylistModal.value = true
}

const closePlaylistModal = () => {
  showPlaylistModal.value = false
  selectedTrack.value = null
}

const handleCreatePlaylist = () => {
  closePlaylistModal()
  emit('create-playlist')
}
</script>
