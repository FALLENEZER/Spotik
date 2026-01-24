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
          My Playlists
        </h3>
        <button
          @click="showCreateModal = true"
          class="btn-sm btn-primary"
          :disabled="playlistStore.loading"
        >
          <svg class="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 4v16m8-8H4"
            />
          </svg>
          New Playlist
        </button>
      </div>
    </div>

    <div class="px-6 py-4">
      <!-- Loading state -->
      <div v-if="playlistStore.loading && playlists.length === 0" class="flex justify-center py-8">
        <LoadingSpinner />
      </div>

      <!-- Empty state -->
      <div v-else-if="playlists.length === 0" class="text-center py-12">
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
        <p class="mt-1 text-sm text-gray-500">Create your first playlist to organize your music!</p>
      </div>

      <!-- Playlist list -->
      <div v-else class="space-y-3">
        <div
          v-for="playlist in playlists"
          :key="playlist.id"
          class="flex items-center p-4 border border-gray-200 rounded-lg hover:bg-gray-50 transition-colors"
        >
          <!-- Playlist icon -->
          <div class="flex-shrink-0 w-12 h-12 bg-gradient-to-br from-purple-500 to-pink-500 rounded-md flex items-center justify-center">
            <svg class="w-6 h-6 text-white" fill="currentColor" viewBox="0 0 20 20">
              <path d="M18 3a1 1 0 00-1.196-.98l-10 2A1 1 0 006 5v9.114A4.369 4.369 0 005 14c-1.657 0-3 .895-3 2s1.343 2 3 2 3-.895 3-2V7.82l8-1.6v5.894A4.37 4.37 0 0015 12c-1.657 0-3 .895-3 2s1.343 2 3 2 3-.895 3-2V3z"/>
            </svg>
          </div>

          <!-- Playlist info -->
          <div class="flex-1 min-w-0 ml-4">
            <div class="flex items-center justify-between">
              <div class="min-w-0 flex-1">
                <div class="flex items-center space-x-2">
                  <p class="text-sm font-medium text-gray-900 truncate">
                    {{ playlist.name }}
                  </p>
                  <span
                    v-if="playlist.is_public"
                    class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800"
                  >
                    Public
                  </span>
                  <span
                    v-else
                    class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800"
                  >
                    Private
                  </span>
                </div>
                <div class="flex items-center mt-1 text-xs text-gray-500 space-x-4">
                  <span>{{ playlist.tracks_count || 0 }} tracks</span>
                  <span v-if="playlist.total_duration">{{ formatDuration(playlist.total_duration) }}</span>
                  <span>{{ formatDate(playlist.created_at) }}</span>
                </div>
                <p v-if="playlist.description" class="mt-1 text-xs text-gray-600 truncate">
                  {{ playlist.description }}
                </p>
              </div>

              <!-- Playlist actions -->
              <div class="flex items-center space-x-2 ml-4">
                <button
                  @click="viewPlaylist(playlist)"
                  class="p-2 text-gray-400 hover:text-blue-600 transition-colors"
                  title="View playlist"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                    />
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"
                    />
                  </svg>
                </button>

                <button
                  @click="editPlaylist(playlist)"
                  class="p-2 text-gray-400 hover:text-yellow-600 transition-colors"
                  title="Edit playlist"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"
                    />
                  </svg>
                </button>

                <button
                  @click="deletePlaylist(playlist)"
                  class="p-2 text-gray-400 hover:text-red-600 transition-colors"
                  title="Delete playlist"
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

    <!-- Create/Edit Playlist Modal -->
    <div
      v-if="showCreateModal || showEditModal"
      class="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50"
      @click="closeModals"
    >
      <div
        class="relative top-20 mx-auto p-5 border w-96 shadow-lg rounded-md bg-white"
        @click.stop
      >
        <div class="mt-3">
          <h3 class="text-lg font-medium text-gray-900 mb-4">
            {{ showCreateModal ? 'Create New Playlist' : 'Edit Playlist' }}
          </h3>
          
          <form @submit.prevent="savePlaylist">
            <div class="mb-4">
              <label class="block text-sm font-medium text-gray-700 mb-2">
                Name
              </label>
              <input
                v-model="playlistForm.name"
                type="text"
                required
                class="input w-full"
                placeholder="Enter playlist name"
              />
            </div>

            <div class="mb-4">
              <label class="block text-sm font-medium text-gray-700 mb-2">
                Description (optional)
              </label>
              <textarea
                v-model="playlistForm.description"
                rows="3"
                class="input w-full"
                placeholder="Enter playlist description"
              ></textarea>
            </div>

            <div class="mb-6">
              <label class="flex items-center">
                <input
                  v-model="playlistForm.is_public"
                  type="checkbox"
                  class="rounded border-gray-300 text-blue-600 shadow-sm focus:border-blue-300 focus:ring focus:ring-blue-200 focus:ring-opacity-50"
                />
                <span class="ml-2 text-sm text-gray-700">Make this playlist public</span>
              </label>
            </div>

            <div class="flex items-center justify-end space-x-3">
              <button
                type="button"
                @click="closeModals"
                class="btn-outline"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="btn-primary"
                :disabled="playlistStore.loading || !playlistForm.name.trim()"
              >
                {{ showCreateModal ? 'Create' : 'Update' }}
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, inject } from 'vue'
import { usePlaylistStore } from '@/stores/playlist'
import LoadingSpinner from '@/components/common/LoadingSpinner.vue'

const playlistStore = usePlaylistStore()
const showNotification = inject('showNotification')

// State
const showCreateModal = ref(false)
const showEditModal = ref(false)
const editingPlaylist = ref(null)
const playlistForm = ref({
  name: '',
  description: '',
  is_public: false,
})

// Computed
const playlists = computed(() => playlistStore.userPlaylists)

// Methods
const fetchPlaylists = async () => {
  try {
    await playlistStore.fetchPlaylists()
  } catch (error) {
    console.error('Failed to fetch playlists:', error)
    showNotification('error', 'Error', 'Failed to load playlists')
  }
}

const savePlaylist = async () => {
  try {
    if (showCreateModal.value) {
      await playlistStore.createPlaylist(playlistForm.value)
      showNotification('success', 'Success', 'Playlist created successfully')
    } else {
      await playlistStore.updatePlaylist(editingPlaylist.value.id, playlistForm.value)
      showNotification('success', 'Success', 'Playlist updated successfully')
    }
    closeModals()
  } catch (error) {
    console.error('Failed to save playlist:', error)
    showNotification('error', 'Error', error.message || 'Failed to save playlist')
  }
}

const editPlaylist = (playlist) => {
  editingPlaylist.value = playlist
  playlistForm.value = {
    name: playlist.name,
    description: playlist.description || '',
    is_public: playlist.is_public,
  }
  showEditModal.value = true
}

const deletePlaylist = async (playlist) => {
  if (!confirm(`Are you sure you want to delete "${playlist.name}"?`)) {
    return
  }

  try {
    await playlistStore.deletePlaylist(playlist.id)
    showNotification('success', 'Success', 'Playlist deleted successfully')
  } catch (error) {
    console.error('Failed to delete playlist:', error)
    showNotification('error', 'Error', error.message || 'Failed to delete playlist')
  }
}

const viewPlaylist = (playlist) => {
  // Emit event to parent to show playlist details
  emit('view-playlist', playlist)
}

const closeModals = () => {
  showCreateModal.value = false
  showEditModal.value = false
  editingPlaylist.value = null
  playlistForm.value = {
    name: '',
    description: '',
    is_public: false,
  }
}

const formatDuration = (seconds) => {
  if (!seconds) return '0:00'
  const minutes = Math.floor(seconds / 60)
  const remainingSeconds = seconds % 60
  return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`
}

const formatDate = (dateString) => {
  if (!dateString) return 'Unknown'
  const date = new Date(dateString)
  return date.toLocaleDateString()
}

// Emits
const emit = defineEmits(['view-playlist'])

// Initialize
onMounted(() => {
  fetchPlaylists()
})
</script>