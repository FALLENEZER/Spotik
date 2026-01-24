import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import api from '@/services/api'

export const useTrackStore = defineStore('track', () => {
  // State
  const trackQueue = ref([])
  const currentTrack = ref(null)
  const userVotes = ref(new Set()) // Track IDs the user has voted for
  const playbackState = ref({
    isPlaying: false,
    startedAt: null,
    pausedAt: null,
    position: 0,
    duration: 0,
  })
  const loading = ref(false)
  const error = ref(null)

  // Getters
  const queueLength = computed(() => trackQueue.value.length)

  const currentTrackIndex = computed(() => {
    if (!currentTrack.value) return -1
    return trackQueue.value.findIndex(track => track.id === currentTrack.value.id)
  })

  const nextTrack = computed(() => {
    const currentIndex = currentTrackIndex.value
    if (currentIndex === -1 || currentIndex >= trackQueue.value.length - 1) {
      return null
    }
    return trackQueue.value[currentIndex + 1]
  })

  const hasUserVoted = trackId => {
    return userVotes.value.has(trackId)
  }

  const sortedQueue = computed(() => {
    return [...trackQueue.value].sort((a, b) => {
      // Sort by score (highest first), then by created_at (oldest first)
      if (a.vote_score !== b.vote_score) {
        return b.vote_score - a.vote_score
      }
      return new Date(a.created_at) - new Date(b.created_at)
    })
  })

  // Actions
  const fetchTrackQueue = async roomId => {
    loading.value = true
    error.value = null

    try {
      const response = await api.get(`/rooms/${roomId}/tracks`)
      const { tracks } = response.data

      trackQueue.value = tracks || []

      // Extract user votes from tracks
      const votedTrackIds =
        tracks?.filter(track => track.user_has_voted).map(track => track.id) || []
      userVotes.value = new Set(votedTrackIds)

      return tracks || []
    } catch (err) {
      error.value =
        err.response?.data?.message || err.response?.data?.error || 'Failed to fetch track queue'
      throw err
    } finally {
      loading.value = false
    }
  }

  const uploadTrack = async (roomId, file, coverFile, genreId) => {
    loading.value = true
    error.value = null

    try {
      const formData = new FormData()
      formData.append('audio_file', file)
      if (coverFile) {
        formData.append('cover_image', coverFile)
      }
      if (genreId) {
        formData.append('genre_id', genreId)
      }

      const response = await api.post(`/rooms/${roomId}/tracks`, formData, {
        headers: {
          'Content-Type': 'multipart/form-data',
        },
      })

      const track = response.data.track

      // Add track to queue if not already present (WebSocket might have already added it)
      const existingTrack = trackQueue.value.find(t => t.id === track.id)
      if (!existingTrack) {
        trackQueue.value.push(track)
      }

      // Update room state after track upload (for auto-playback)
      const { useRoomStore } = await import('./room')
      const roomStore = useRoomStore()
      if (roomStore.currentRoom) {
        try {
          await roomStore.fetchRoomDetails(roomId)
        } catch (roomError) {
          console.warn('Failed to update room state after track upload:', roomError)
        }
      }

      return track
    } catch (err) {
      // Preserve the original error structure for better error handling in components
      const errorMessage =
        err.response?.data?.message || err.response?.data?.error || 'Failed to upload track'

      error.value = errorMessage

      // Re-throw the original error so components can access response details
      throw err
    } finally {
      loading.value = false
    }
  }

  const voteForTrack = async trackId => {
    try {
      // Find the track to get room ID
      const track = trackQueue.value.find(t => t.id === trackId)
      if (!track) {
        throw new Error('Track not found')
      }

      // Determine the room ID from the current room or track
      const roomId =
        track.room_id ||
        (typeof window !== 'undefined' && window.location.pathname.match(/\/room\/([^\/]+)/)?.[1])
      if (!roomId) {
        throw new Error('Room ID not found')
      }

      const isCurrentlyVoted = userVotes.value.has(trackId)
      const endpoint = `/rooms/${roomId}/tracks/${trackId}/vote`

      let response
      if (isCurrentlyVoted) {
        // Remove vote
        response = await api.delete(endpoint)
      } else {
        // Add vote
        response = await api.post(endpoint)
      }

      const { vote_score, user_has_voted } = response.data

      // Update local vote state
      if (user_has_voted) {
        userVotes.value.add(trackId)
      } else {
        userVotes.value.delete(trackId)
      }

      // Update track score in queue
      const trackIndex = trackQueue.value.findIndex(track => track.id === trackId)
      if (trackIndex !== -1) {
        trackQueue.value[trackIndex].vote_score = vote_score
        trackQueue.value[trackIndex].user_has_voted = user_has_voted
      }

      return { voted: user_has_voted, vote_score }
    } catch (err) {
      error.value =
        err.response?.data?.message || err.response?.data?.error || 'Failed to vote for track'
      throw err
    }
  }

  const removeTrack = async trackId => {
    try {
      // Find the track to get room ID
      const track = trackQueue.value.find(t => t.id === trackId)
      if (!track) {
        throw new Error('Track not found')
      }

      const roomId =
        track.room_id ||
        (typeof window !== 'undefined' && window.location.pathname.match(/\/room\/([^\/]+)/)?.[1])
      if (!roomId) {
        throw new Error('Room ID not found')
      }

      await api.delete(`/rooms/${roomId}/tracks/${trackId}`)

      // Remove track from queue
      trackQueue.value = trackQueue.value.filter(track => track.id !== trackId)

      // Clear current track if it was removed
      if (currentTrack.value?.id === trackId) {
        currentTrack.value = null
      }

      // Remove from user votes
      userVotes.value.delete(trackId)

      return true
    } catch (err) {
      error.value =
        err.response?.data?.message || err.response?.data?.error || 'Failed to remove track'
      throw err
    }
  }

  const updateTrackQueue = tracks => {
    trackQueue.value = tracks
  }

  const addTrackToQueue = track => {
    const existingIndex = trackQueue.value.findIndex(t => t.id === track.id)
    if (existingIndex === -1) {
      trackQueue.value.push(track)

      // Re-sort the queue to maintain proper ordering by score and upload time
      trackQueue.value.sort((a, b) => {
        // Sort by score (highest first), then by created_at (oldest first)
        if (a.vote_score !== b.vote_score) {
          return b.vote_score - a.vote_score
        }
        return new Date(a.created_at) - new Date(b.created_at)
      })
    }
  }

  const removeTrackFromQueue = trackId => {
    trackQueue.value = trackQueue.value.filter(track => track.id !== trackId)

    // Clear current track if it was removed
    if (currentTrack.value?.id === trackId) {
      currentTrack.value = null
    }
  }

  const updateTrackVote = (trackId, voteScore, userVoted) => {
    // Update track score in queue
    const trackIndex = trackQueue.value.findIndex(track => track.id === trackId)
    if (trackIndex !== -1) {
      trackQueue.value[trackIndex].vote_score = voteScore
    }

    // Update user vote state if provided
    if (userVoted !== undefined) {
      if (userVoted) {
        userVotes.value.add(trackId)
      } else {
        userVotes.value.delete(trackId)
      }
    }
  }

  const setCurrentTrack = track => {
    currentTrack.value = track
  }

  const updatePlaybackState = state => {
    playbackState.value = { ...playbackState.value, ...state }
  }

  const calculateCurrentPosition = () => {
    if (!playbackState.value.isPlaying || !playbackState.value.startedAt) {
      return playbackState.value.position || 0
    }

    const now = Date.now()
    const startTime = new Date(playbackState.value.startedAt).getTime()
    const elapsed = (now - startTime) / 1000 // Convert to seconds

    return Math.min(elapsed, playbackState.value.duration || 0)
  }

  const clearTracks = () => {
    trackQueue.value = []
    currentTrack.value = null
    userVotes.value.clear()
    playbackState.value = {
      isPlaying: false,
      startedAt: null,
      pausedAt: null,
      position: 0,
      duration: 0,
    }
    error.value = null
  }

  return {
    // State
    trackQueue,
    currentTrack,
    userVotes,
    playbackState,
    loading,
    error,

    // Getters
    queueLength,
    currentTrackIndex,
    nextTrack,
    hasUserVoted,
    sortedQueue,

    // Actions
    fetchTrackQueue,
    uploadTrack,
    voteForTrack,
    removeTrack,
    updateTrackQueue,
    addTrackToQueue,
    removeTrackFromQueue,
    updateTrackVote,
    setCurrentTrack,
    updatePlaybackState,
    calculateCurrentPosition,
    clearTracks,
  }
})
