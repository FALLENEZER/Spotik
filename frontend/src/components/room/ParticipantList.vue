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
            d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197m13.5-9a2.5 2.5 0 11-5 0 2.5 2.5 0 015 0z"
          />
        </svg>
        Participants ({{ participants.length }})
      </h3>
    </div>

    <div class="px-6 py-4">
      <!-- Loading state -->
      <div v-if="loading" class="flex justify-center py-4">
        <LoadingSpinner size="sm" />
      </div>

      <!-- Empty state -->
      <div v-else-if="participants.length === 0" class="text-center py-8">
        <svg
          class="mx-auto h-8 w-8 text-gray-400"
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197m13.5-9a2.5 2.5 0 11-5 0 2.5 2.5 0 015 0z"
          />
        </svg>
        <p class="mt-2 text-sm text-gray-500">No participants in this room</p>
      </div>

      <!-- Participants list -->
      <div v-else class="space-y-3">
        <div
          v-for="participant in participants"
          :key="participant.id"
          class="flex items-center justify-between p-3 bg-gray-50 rounded-lg"
        >
          <div class="flex items-center">
            <!-- Avatar -->
            <div class="flex-shrink-0">
              <div class="w-8 h-8 bg-blue-500 rounded-full flex items-center justify-center">
                <span class="text-sm font-medium text-white">
                  {{ getInitials(participant.user?.username || participant.username) }}
                </span>
              </div>
            </div>

            <!-- User info -->
            <div class="ml-3">
              <p class="text-sm font-medium text-gray-900">
                {{ participant.user?.username || participant.username }}
              </p>
              <p class="text-xs text-gray-500">
                Joined {{ formatJoinTime(participant.joined_at) }}
              </p>
            </div>
          </div>

          <!-- Admin badge -->
          <div class="flex items-center space-x-2">
            <span
              v-if="isAdmin(participant)"
              class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800"
            >
              <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
              Admin
            </span>

            <!-- Online indicator -->
            <div class="flex items-center">
              <div class="w-2 h-2 bg-green-400 rounded-full"></div>
              <span class="ml-1 text-xs text-gray-500">Online</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { useRoomStore } from '@/stores/room'
import LoadingSpinner from '@/components/common/LoadingSpinner.vue'

const roomStore = useRoomStore()

// Props
const props = defineProps({
  loading: {
    type: Boolean,
    default: false,
  },
})

// Computed
const participants = computed(() => roomStore.participants)

// Methods
const getInitials = username => {
  if (!username) return '?'
  return username
    .split(' ')
    .map(word => word.charAt(0).toUpperCase())
    .join('')
    .substring(0, 2)
}

const isAdmin = participant => {
  const userId = participant.user?.id || participant.user_id
  return roomStore.currentRoom?.administrator_id === userId
}

const formatJoinTime = joinTime => {
  if (!joinTime) return 'Unknown'

  const date = new Date(joinTime)
  const now = new Date()
  const diffInMinutes = Math.floor((now - date) / (1000 * 60))

  if (diffInMinutes < 1) {
    return 'just now'
  } else if (diffInMinutes < 60) {
    return `${diffInMinutes} min ago`
  } else if (diffInMinutes < 1440) {
    // 24 hours
    const hours = Math.floor(diffInMinutes / 60)
    return `${hours} hour${hours !== 1 ? 's' : ''} ago`
  } else {
    const days = Math.floor(diffInMinutes / 1440)
    return `${days} day${days !== 1 ? 's' : ''} ago`
  }
}
</script>
