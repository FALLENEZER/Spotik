<template>
  <div
    v-if="show"
    class="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50"
    @click="$emit('close')"
  >
    <div
      class="relative top-20 mx-auto p-5 border w-96 shadow-lg rounded-md bg-white"
      @click.stop
    >
      <div class="mt-3">
        <h3 class="text-lg font-medium text-gray-900 mb-4">
          Add "{{ track?.original_name }}" to Playlist
        </h3>
        
        <!-- Loading state -->
        <div v-if="playlistStore.loading" class="flex justify-center py-8">
          <LoadingSpinner />
        </div>

        <!-- Playlist selection -->
        <div v-else-if="userPlaylists.length > 0" class="space-y-2 max-h-64 overflow-y-auto">
          <button
            v-for="playlist in userPlaylists"
            :key="playlist.id"
            @click="addToPlaylist(playlist)"
            class="w-full text-left p-3 border border-gray-200 rounded-lg hover:bg-gray-50 transition-colors"
            :disabled="adding"
          >
            <div class="flex items-center justify-between">
              <div class="min-w-0 flex-1">
                <p class="text-sm font-medium text-gray-900 truncate">
                  {{ playlist.name }}
                </p>
                <p class="text-xs text-gray-500">
                  {{ playlist.tracks_count || 0 }} tracks
                </p>
              </div>
              <div class="flex items-center space-x-2">
                <span
                  v-if="playlist.is_public"
                  class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800"
                >
                  Public
                </span>
                <svg
                  v-if="adding === playlist.id"
                  class="w-4 h-4 text-blue-600 animate-spin"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <circle
                    class="opacity-25"
                    cx="12"
                    cy="12"
                    r="10"
                    stroke="currentColor"
                    stroke-width="4"
                  ></circle>
                  <path
                    class="opacity-75"
                    fill="currentColor"
                    d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                  ></path>
                </svg>
                <svg v-else class="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 4v16m8-8H4"
                  />
                </svg>
              </div>
            </div>
          </button>
        </div>

        <!-- Empty state -->
        <div v-else class="text-center py-8">
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
          <h3 class="mt-2 text-lg font-medium text-gray-900">No playlists yet</h3>
          <p class="mt-1 text-sm text-gray-500">Create a playlist first to add tracks to it.</p>
        </div>

        <!-- Actions -->
        <div class="flex items-center justify-end space-x-3 mt-6">
          <button
            type="button"
            @click="$emit('close')"
            class="btn-outline"
            :disabled="adding"
          >
            Cancel
          </button>
          <button
            v-if="userPlaylists.length === 0"
            type="button"
            @click="$emit('create-playlist')"
            class="btn-primary"
          >
            Create Playlist
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch, inject } from 'vue'
import { usePlaylistStore } from '@/stores/playlist'
import LoadingSpinner from '@/components/common/LoadingSpinner.vue'

const playlistStore = usePlaylistStore()
const showNotification = inject('showNotification')

// Props
const { show, track } = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
  track: {
    type: Object,
    default: null,
  },
})

// Emits
defineEmits(['close', 'create-playlist'])

// State
const adding = ref(null)

// Computed
const userPlaylists = computed(() => playlistStore.userPlaylists)

// Methods
const addToPlaylist = async (playlist) => {
  if (!track) return

  adding.value = playlist.id

  try {
    await playlistStore.addTrackToPlaylist(playlist.id, track.id)
    showNotification('success', 'Success', `Added "${track.original_name}" to "${playlist.name}"`)
    emit('close')
  } catch (error) {
    console.error('Failed to add track to playlist:', error)
    showNotification('error', 'Error', error.message || 'Failed to add track to playlist')
  } finally {
    adding.value = null
  }
}

// Watch for modal opening to fetch playlists
watch(() => show, (newShow) => {
  if (newShow && userPlaylists.value.length === 0) {
    playlistStore.fetchPlaylists().catch(error => {
      console.error('Failed to fetch playlists:', error)
    })
  }
})
</script>