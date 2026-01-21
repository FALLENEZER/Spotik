import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import api from '@/services/api'
import { useTrackStore } from './track'
import { useRoomStore } from './room'

export const usePlaybackStore = defineStore('playback', () => {
  // State
  const loading = ref(false)
  const error = ref(null)

  // Getters
  const trackStore = useTrackStore()
  const roomStore = useRoomStore()

  const currentTrack = computed(() => trackStore.currentTrack)
  const playbackState = computed(() => trackStore.playbackState)
  const isPlaying = computed(() => playbackState.value.isPlaying)
  const canControl = computed(() => roomStore.isRoomAdmin)

  // Actions
  const startTrack = async (roomId, trackId) => {
    if (!canControl.value) {
      throw new Error('Only room administrators can control playback')
    }

    loading.value = true
    error.value = null

    try {
      const response = await api.post(`/rooms/${roomId}/tracks/${trackId}/play`)
      const payload = response.data?.data || {}
      if (payload.track_id) {
        const track = trackStore.trackQueue.find(t => t.id === payload.track_id)
        if (track) {
          trackStore.setCurrentTrack(track)
          trackStore.updatePlaybackState({ duration: track.duration_seconds || 0 })
        }
      }
      trackStore.updatePlaybackState({
        isPlaying: true,
        startedAt: payload.started_at || new Date().toISOString(),
        pausedAt: null,
        position: 0,
      })
      return response.data
    } catch (err) {
      const errorMessage = err.response?.data?.message || err.message || 'Failed to start track'
      error.value = errorMessage
      throw new Error(errorMessage)
    } finally {
      loading.value = false
    }
  }

  const pausePlayback = async roomId => {
    if (!canControl.value) {
      throw new Error('Only room administrators can control playback')
    }

    if (!currentTrack.value || !isPlaying.value) {
      throw new Error('No track is currently playing')
    }

    loading.value = true
    error.value = null

    try {
      const response = await api.post(`/rooms/${roomId}/playback/pause`)
      const payload = response.data?.data || {}
      trackStore.updatePlaybackState({
        isPlaying: false,
        pausedAt: payload.paused_at || new Date().toISOString(),
        position: payload.position ?? playbackState.value.position,
      })
      return response.data
    } catch (err) {
      const errorMessage = err.response?.data?.message || err.message || 'Failed to pause playback'
      error.value = errorMessage
      throw new Error(errorMessage)
    } finally {
      loading.value = false
    }
  }

  const resumePlayback = async roomId => {
    if (!canControl.value) {
      throw new Error('Only room administrators can control playback')
    }

    if (!currentTrack.value || isPlaying.value) {
      throw new Error('No track is currently paused')
    }

    loading.value = true
    error.value = null

    try {
      const response = await api.post(`/rooms/${roomId}/playback/resume`)
      const payload = response.data?.data || {}
      trackStore.updatePlaybackState({
        isPlaying: true,
        startedAt: payload.resumed_at || new Date().toISOString(),
        pausedAt: null,
        position: payload.position ?? playbackState.value.position,
      })
      return response.data
    } catch (err) {
      const errorMessage = err.response?.data?.message || err.message || 'Failed to resume playback'
      error.value = errorMessage
      throw new Error(errorMessage)
    } finally {
      loading.value = false
    }
  }

  const skipTrack = async roomId => {
    if (!canControl.value) {
      throw new Error('Only room administrators can control playback')
    }

    if (!currentTrack.value) {
      throw new Error('No track is currently playing')
    }

    loading.value = true
    error.value = null

    try {
      const response = await api.post(`/rooms/${roomId}/playback/skip`)
      const payload = response.data?.data || {}
      if (payload.next_track_id) {
        const nextTrack = trackStore.trackQueue.find(t => t.id === payload.next_track_id)
        if (nextTrack) {
          trackStore.setCurrentTrack(nextTrack)
          trackStore.updatePlaybackState({ duration: nextTrack.duration_seconds || 0 })
        }
        trackStore.updatePlaybackState({
          isPlaying: true,
          startedAt: payload.server_time || new Date().toISOString(),
          pausedAt: null,
          position: 0,
        })
      } else {
        trackStore.setCurrentTrack(null)
        trackStore.updatePlaybackState({
          isPlaying: false,
          startedAt: null,
          pausedAt: null,
          position: 0,
        })
      }
      return response.data
    } catch (err) {
      const errorMessage = err.response?.data?.message || err.message || 'Failed to skip track'
      error.value = errorMessage
      throw new Error(errorMessage)
    } finally {
      loading.value = false
    }
  }

  const stopPlayback = async roomId => {
    if (!canControl.value) {
      throw new Error('Only room administrators can control playback')
    }

    if (!currentTrack.value) {
      throw new Error('No track is currently playing')
    }

    loading.value = true
    error.value = null

    try {
      const response = await api.post(`/rooms/${roomId}/playback/stop`)
      const payload = response.data?.data || {}
      trackStore.setCurrentTrack(null)
      trackStore.updatePlaybackState({
        isPlaying: false,
        startedAt: payload?.server_time || null,
        pausedAt: null,
        position: 0,
      })
      return response.data
    } catch (err) {
      const errorMessage = err.response?.data?.message || err.message || 'Failed to stop playback'
      error.value = errorMessage
      throw new Error(errorMessage)
    } finally {
      loading.value = false
    }
  }

  const getPlaybackStatus = async roomId => {
    loading.value = true
    error.value = null

    try {
      const response = await api.get(`/rooms/${roomId}/playback/status`)
      return response.data?.data || response.data
    } catch (err) {
      const errorMessage =
        err.response?.data?.message || err.message || 'Failed to get playback status'
      error.value = errorMessage
      throw new Error(errorMessage)
    } finally {
      loading.value = false
    }
  }

  // Helper methods
  const togglePlayback = async roomId => {
    if (currentTrack.value) {
      // There's a current track - toggle play/pause
      if (isPlaying.value) {
        return await pausePlayback(roomId)
      } else {
        return await resumePlayback(roomId)
      }
    } else {
      // No current track - start playing the first track in queue
      const firstTrack = trackStore.sortedQueue[0]
      if (firstTrack) {
        return await startTrack(roomId, firstTrack.id)
      } else {
        throw new Error('No tracks available in the queue')
      }
    }
  }

  const clearError = () => {
    error.value = null
  }

  const handleTrackEnded = async () => {
    // Only handle automatic progression if user is room admin
    if (!canControl.value) {
      console.log('Track ended but user is not admin - no auto-progression')
      return
    }

    const roomId = roomStore.currentRoom?.id
    if (!roomId) {
      console.error('No room ID available for track progression')
      return
    }

    try {
      console.log('Track ended - attempting to play next track')

      // Get the next track in the queue (sorted by votes)
      const nextTrack = trackStore.sortedQueue.find(track => track.id !== currentTrack.value?.id)

      if (nextTrack) {
        console.log(`Auto-playing next track: ${nextTrack.original_name}`)
        await startTrack(roomId, nextTrack.id)
      } else {
        console.log('No more tracks in queue - stopping playback')
        // No more tracks - stop playback
        trackStore.updatePlaybackState({
          isPlaying: false,
          startedAt: null,
          pausedAt: null,
          position: 0,
        })
        trackStore.setCurrentTrack(null)
      }
    } catch (err) {
      console.error('Failed to auto-play next track:', err)
      // Don't throw error - just log it so playback doesn't get stuck
    }
  }

  return {
    // State
    loading,
    error,

    // Getters
    currentTrack,
    playbackState,
    isPlaying,
    canControl,

    // Actions
    startTrack,
    pausePlayback,
    resumePlayback,
    skipTrack,
    stopPlayback,
    getPlaybackStatus,
    togglePlayback,
    clearError,
    handleTrackEnded,
  }
})
