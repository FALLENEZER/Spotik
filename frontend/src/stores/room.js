import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import api from '@/services/api'
import { useAuthStore } from './auth'

export const useRoomStore = defineStore('room', () => {
  // State
  const currentRoom = ref(null)
  const participants = ref([])
  const loading = ref(false)
  const error = ref(null)

  // Getters
  const isRoomAdmin = computed(() => {
    // Temporary: make all users admins
    return true
    // const authStore = useAuthStore()
    // return currentRoom.value?.administrator_id === authStore.user?.id
  })

  const isInRoom = computed(() => !!currentRoom.value)

  const participantCount = computed(() => participants.value.length)

  // Actions
  const fetchRooms = async () => {
    loading.value = true
    error.value = null

    try {
      const response = await api.get('/rooms')
      return response.data
    } catch (err) {
      error.value = err.response?.data?.message || 'Failed to fetch rooms'
      throw err
    } finally {
      loading.value = false
    }
  }

  const createRoom = async roomData => {
    loading.value = true
    error.value = null

    try {
      const response = await api.post('/rooms', roomData)
      const room = response.data.data // Extract from data wrapper

      currentRoom.value = room
      participants.value = room.participants || [] // Use participants from response

      return room
    } catch (err) {
      error.value = err.response?.data?.message || 'Failed to create room'
      throw err
    } finally {
      loading.value = false
    }
  }

  const joinRoom = async roomId => {
    loading.value = true
    error.value = null

    try {
      const response = await api.post(`/rooms/${roomId}/join`)
      const { room, participant } = response.data.data

      currentRoom.value = room
      participants.value = room.participants || []

      return room
    } catch (err) {
      // If it's a 409 error (already joined), try to fetch room details instead
      if (err.response?.status === 409) {
        try {
          const roomResponse = await api.get(`/rooms/${roomId}`)
          const roomData = roomResponse.data.data

          currentRoom.value = roomData
          participants.value = roomData.participants || []

          return roomData
        } catch (fetchError) {
          error.value = fetchError.response?.data?.message || 'Failed to access room'
          throw fetchError
        }
      } else {
        error.value = err.response?.data?.message || 'Failed to join room'
        throw err
      }
    } finally {
      loading.value = false
    }
  }

  const leaveRoom = async () => {
    if (!currentRoom.value) return

    loading.value = true
    error.value = null

    try {
      await api.post(`/rooms/${currentRoom.value.id}/leave`)

      // Clear room state
      currentRoom.value = null
      participants.value = []

      return true
    } catch (err) {
      error.value = err.response?.data?.message || 'Failed to leave room'
      throw err
    } finally {
      loading.value = false
    }
  }

  const deleteRoom = async roomId => {
    loading.value = true
    error.value = null

    try {
      await api.delete(`/rooms/${roomId}`)

      // Clear room state
      currentRoom.value = null
      participants.value = []

      return true
    } catch (err) {
      error.value = err.response?.data?.message || 'Failed to delete room'
      throw err
    } finally {
      loading.value = false
    }
  }

  const fetchRoomDetails = async roomId => {
    loading.value = true
    error.value = null

    try {
      const response = await api.get(`/rooms/${roomId}`)
      const roomData = response.data.data

      currentRoom.value = roomData
      participants.value = roomData.participants || []

      // Update track store with current track and playback state from room
      const { useTrackStore } = await import('./track')
      const trackStore = useTrackStore()

      if (roomData.current_track) {
        console.log('Setting current track from room data:', roomData.current_track.original_name)
        trackStore.setCurrentTrack(roomData.current_track)

        // Update playback state
        trackStore.updatePlaybackState({
          isPlaying: roomData.is_playing || false,
          startedAt: roomData.playback_started_at,
          pausedAt: roomData.playback_paused_at,
          position: roomData.current_playback_position || 0,
          duration: roomData.current_track.duration_seconds || 0,
        })

        console.log('Updated playback state:', {
          isPlaying: roomData.is_playing,
          startedAt: roomData.playback_started_at,
          currentTrack: roomData.current_track.original_name,
        })
      } else {
        console.log('No current track in room data')
        trackStore.setCurrentTrack(null)
        trackStore.updatePlaybackState({
          isPlaying: false,
          startedAt: null,
          pausedAt: null,
          position: 0,
          duration: 0,
        })
      }

      // If user is not a participant, automatically join the room
      if (!roomData.is_participant) {
        try {
          const joinResponse = await api.post(`/rooms/${roomId}/join`)
          const { room: updatedRoom, participant } = joinResponse.data.data

          // Update room data with joined state
          currentRoom.value = updatedRoom
          participants.value = updatedRoom.participants || []
        } catch (joinError) {
          // If join fails, still return the room data but log the error
          console.warn('Failed to auto-join room:', joinError)
          // Don't throw the error - user can still view the room
        }
      }

      return currentRoom.value
    } catch (err) {
      error.value = err.response?.data?.message || 'Failed to fetch room details'
      throw err
    } finally {
      loading.value = false
    }
  }

  const updateRoomState = roomData => {
    if (currentRoom.value && currentRoom.value.id === roomData.id) {
      currentRoom.value = { ...currentRoom.value, ...roomData }
    }
  }

  const updateParticipants = newParticipants => {
    participants.value = newParticipants
  }

  const addParticipant = participant => {
    const existingIndex = participants.value.findIndex(p => p.id === participant.id)
    if (existingIndex === -1) {
      participants.value.push(participant)
    }
  }

  const removeParticipant = participantId => {
    participants.value = participants.value.filter(p => p.id !== participantId)
  }

  const clearRoom = () => {
    currentRoom.value = null
    participants.value = []
    error.value = null
  }

  return {
    // State
    currentRoom,
    participants,
    loading,
    error,

    // Getters
    isRoomAdmin,
    isInRoom,
    participantCount,

    // Actions
    fetchRooms,
    createRoom,
    joinRoom,
    leaveRoom,
    deleteRoom,
    fetchRoomDetails,
    updateRoomState,
    updateParticipants,
    addParticipant,
    removeParticipant,
    clearRoom,
  }
})
