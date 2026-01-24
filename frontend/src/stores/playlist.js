import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { playlistApi } from '@/services/api'

export const usePlaylistStore = defineStore('playlist', () => {
  // State
  const playlists = ref([])
  const currentPlaylist = ref(null)
  const loading = ref(false)
  const error = ref(null)

  // Getters
  const userPlaylists = computed(() => {
    return playlists.value.filter(playlist => playlist.is_owner)
  })

  const publicPlaylists = computed(() => {
    return playlists.value.filter(playlist => playlist.is_public && !playlist.is_owner)
  })

  // Actions
  const fetchPlaylists = async () => {
    loading.value = true
    error.value = null

    try {
      const response = await playlistApi.getAll()
      playlists.value = response.data.data || []
      return playlists.value
    } catch (err) {
      error.value = err.response?.data?.message || err.response?.data?.error || 'Failed to fetch playlists'
      throw err
    } finally {
      loading.value = false
    }
  }

  const fetchPlaylist = async (id) => {
    loading.value = true
    error.value = null

    try {
      const response = await playlistApi.get(id)
      currentPlaylist.value = response.data.data
      return currentPlaylist.value
    } catch (err) {
      error.value = err.response?.data?.message || err.response?.data?.error || 'Failed to fetch playlist'
      throw err
    } finally {
      loading.value = false
    }
  }

  const createPlaylist = async (data) => {
    loading.value = true
    error.value = null

    try {
      const response = await playlistApi.create(data)
      const newPlaylist = response.data.data
      playlists.value.unshift(newPlaylist)
      return newPlaylist
    } catch (err) {
      error.value = err.response?.data?.message || err.response?.data?.error || 'Failed to create playlist'
      throw err
    } finally {
      loading.value = false
    }
  }

  const updatePlaylist = async (id, data) => {
    loading.value = true
    error.value = null

    try {
      const response = await playlistApi.update(id, data)
      const updatedPlaylist = response.data.data
      
      // Update in playlists array
      const index = playlists.value.findIndex(p => p.id === id)
      if (index !== -1) {
        playlists.value[index] = updatedPlaylist
      }

      // Update current playlist if it's the same
      if (currentPlaylist.value?.id === id) {
        currentPlaylist.value = updatedPlaylist
      }

      return updatedPlaylist
    } catch (err) {
      error.value = err.response?.data?.message || err.response?.data?.error || 'Failed to update playlist'
      throw err
    } finally {
      loading.value = false
    }
  }

  const deletePlaylist = async (id) => {
    loading.value = true
    error.value = null

    try {
      await playlistApi.delete(id)
      
      // Remove from playlists array
      playlists.value = playlists.value.filter(p => p.id !== id)

      // Clear current playlist if it was deleted
      if (currentPlaylist.value?.id === id) {
        currentPlaylist.value = null
      }

      return true
    } catch (err) {
      error.value = err.response?.data?.message || err.response?.data?.error || 'Failed to delete playlist'
      throw err
    } finally {
      loading.value = false
    }
  }

  const addTrackToPlaylist = async (playlistId, trackId, position) => {
    try {
      await playlistApi.addTrack(playlistId, trackId, position)
      
      // Refresh the playlist to get updated tracks
      if (currentPlaylist.value?.id === playlistId) {
        await fetchPlaylist(playlistId)
      }

      return true
    } catch (err) {
      error.value = err.response?.data?.message || err.response?.data?.error || 'Failed to add track to playlist'
      throw err
    }
  }

  const removeTrackFromPlaylist = async (playlistId, trackId) => {
    try {
      await playlistApi.removeTrack(playlistId, trackId)
      
      // Refresh the playlist to get updated tracks
      if (currentPlaylist.value?.id === playlistId) {
        await fetchPlaylist(playlistId)
      }

      return true
    } catch (err) {
      error.value = err.response?.data?.message || err.response?.data?.error || 'Failed to remove track from playlist'
      throw err
    }
  }

  const clearPlaylists = () => {
    playlists.value = []
    currentPlaylist.value = null
    error.value = null
  }

  return {
    // State
    playlists,
    currentPlaylist,
    loading,
    error,

    // Getters
    userPlaylists,
    publicPlaylists,

    // Actions
    fetchPlaylists,
    fetchPlaylist,
    createPlaylist,
    updatePlaylist,
    deletePlaylist,
    addTrackToPlaylist,
    removeTrackFromPlaylist,
    clearPlaylists,
  }
})