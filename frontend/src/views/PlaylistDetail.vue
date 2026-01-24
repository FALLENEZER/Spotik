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
        <h3 class="text-lg font-medium text-red-800 mb-2">Error</h3>
        <p class="text-red-600 mb-4">{{ error }}</p>
        <button class="btn-primary" @click="fetchPlaylist">Try Again</button>
      </div>
    </div>

    <!-- Content -->
    <div v-else-if="playlist">
      <!-- Header -->
      <div class="bg-white shadow rounded-lg mb-6 overflow-hidden">
        <div class="bg-gradient-to-r from-purple-600 to-indigo-600 px-6 py-8 md:flex md:items-center md:justify-between">
          <div class="flex items-center">
            <div class="h-24 w-24 bg-white bg-opacity-20 rounded-lg flex items-center justify-center text-white backdrop-blur-sm shadow-inner">
              <svg class="w-12 h-12" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3" />
              </svg>
            </div>
            <div class="ml-6 text-white">
              <h1 class="text-3xl font-bold">{{ playlist.name }}</h1>
              <p class="mt-1 opacity-90">{{ playlist.description || 'No description' }}</p>
              <div class="mt-2 flex items-center text-sm opacity-75 space-x-4">
                <span>{{ playlist.tracks?.length || 0 }} tracks</span>
                <span>Created by {{ playlist.creator?.username || 'You' }}</span>
                <span v-if="playlist.is_public" class="bg-green-500 bg-opacity-30 px-2 py-0.5 rounded text-xs backdrop-blur-sm">Public</span>
                <span v-else class="bg-gray-500 bg-opacity-30 px-2 py-0.5 rounded text-xs backdrop-blur-sm">Private</span>
              </div>
            </div>
          </div>
          <div class="mt-6 md:mt-0 flex gap-3">
             <!-- Play button (future integration) -->
             <!-- <button class="btn-white text-indigo-600 font-semibold" disabled>
               <svg class="w-5 h-5 mr-2 inline" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z" clip-rule="evenodd" /></svg>
               Play
             </button> -->
          </div>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <!-- Track List -->
        <div class="lg:col-span-2 space-y-6">
          <div class="bg-white shadow rounded-lg overflow-hidden">
            <div class="px-6 py-4 border-b border-gray-200 flex justify-between items-center">
              <h3 class="text-lg font-medium text-gray-900">Tracks</h3>
            </div>
            
            <ul v-if="playlist.tracks && playlist.tracks.length > 0" class="divide-y divide-gray-200">
              <li v-for="(track, index) in playlist.tracks" :key="track.id" class="px-6 py-4 hover:bg-gray-50 flex items-center justify-between group">
                <div class="flex items-center min-w-0 flex-1">
                  <span class="text-gray-400 w-6 text-sm">{{ index + 1 }}</span>
                  <div class="ml-4 min-w-0">
                    <p class="text-sm font-medium text-gray-900 truncate">{{ track.original_name }}</p>
                    <p class="text-xs text-gray-500 truncate">{{ formatDuration(track.duration_seconds) }}</p>
                  </div>
                </div>
                <div class="ml-4 flex items-center">
                  <button 
                    @click="removeTrack(track)" 
                    class="p-2 text-gray-400 hover:text-red-600 opacity-0 group-hover:opacity-100 transition-opacity"
                    title="Remove from playlist"
                  >
                    <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                    </svg>
                  </button>
                </div>
              </li>
            </ul>
            <div v-else class="text-center py-12 text-gray-500">
              No tracks in this playlist yet.
            </div>
          </div>
        </div>

        <!-- Add Track Sidebar -->
        <div class="space-y-6">
          <div class="bg-white shadow rounded-lg p-6">
            <h3 class="text-lg font-medium text-gray-900 mb-4">Add Tracks</h3>
            <p class="text-sm text-gray-500 mb-4">Search for tracks to add to this playlist.</p>
            <TrackSearch @select="addTrack" :exclude-ids="playlist.tracks?.map(t => t.id) || []" />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, inject } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { playlistApi } from '@/services/api'
import Breadcrumbs from '@/components/common/Breadcrumbs.vue'
import LoadingSpinner from '@/components/common/LoadingSpinner.vue'
import TrackSearch from '@/components/common/TrackSearch.vue'

const route = useRoute()
const router = useRouter()
const showNotification = inject('showNotification')

const playlist = ref(null)
const loading = ref(true)
const error = ref(null)

const breadcrumbItems = computed(() => [
  { name: 'Dashboard', to: '/dashboard' },
  { name: playlist.value?.name || 'Playlist', to: `/playlist/${route.params.id}` },
])

const fetchPlaylist = async () => {
  loading.value = true
  error.value = null
  try {
    const { data } = await playlistApi.get(route.params.id)
    playlist.value = data.data // Assuming resource wrapper
  } catch (err) {
    console.error('Failed to load playlist:', err)
    error.value = err.response?.data?.message || 'Failed to load playlist'
  } finally {
    loading.value = false
  }
}

const addTrack = async (track) => {
  try {
    await playlistApi.addTrack(playlist.value.id, track.id)
    showNotification('success', 'Success', `Added "${track.original_name}"`)
    // Refresh playlist to show new track
    await fetchPlaylist()
  } catch (err) {
    console.error('Failed to add track:', err)
    showNotification('error', 'Error', 'Failed to add track to playlist')
  }
}

const removeTrack = async (track) => {
  if (!confirm(`Remove "${track.original_name}" from playlist?`)) return
  
  try {
    await playlistApi.removeTrack(playlist.value.id, track.id)
    showNotification('success', 'Success', 'Track removed')
    // Optimistic update or refresh
    await fetchPlaylist()
  } catch (err) {
    console.error('Failed to remove track:', err)
    showNotification('error', 'Error', 'Failed to remove track')
  }
}

const formatDuration = (seconds) => {
  if (!seconds) return '0:00'
  const minutes = Math.floor(seconds / 60)
  const remainingSeconds = Math.floor(seconds % 60)
  return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`
}

onMounted(() => {
  fetchPlaylist()
})
</script>
