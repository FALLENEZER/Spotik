<template>
  <Transition
    enter-active-class="transform ease-out duration-300 transition"
    enter-from-class="translate-y-2 opacity-0 sm:translate-y-0 sm:translate-x-2"
    enter-to-class="translate-y-0 opacity-100 sm:translate-x-0"
    leave-active-class="transition ease-in duration-100"
    leave-from-class="opacity-100"
    leave-to-class="opacity-0"
  >
    <div
      v-if="showWarning"
      class="fixed top-4 right-4 max-w-sm w-full bg-yellow-50 border border-yellow-200 shadow-lg rounded-lg pointer-events-auto ring-1 ring-yellow-300 z-50"
    >
      <div class="p-4">
        <div class="flex items-start">
          <div class="flex-shrink-0">
            <ExclamationTriangleIcon class="h-6 w-6 text-yellow-400" />
          </div>
          <div class="ml-3 w-0 flex-1 pt-0.5">
            <p class="text-sm font-medium text-yellow-800">Session Expiring Soon</p>
            <p class="mt-1 text-sm text-yellow-700">
              Your session will expire in {{ timeRemaining }} minutes. Would you like to extend it?
            </p>
            <div class="mt-3 flex space-x-2">
              <button
                @click="extendSession"
                class="bg-yellow-100 text-yellow-800 px-3 py-1 rounded-md text-sm font-medium hover:bg-yellow-200 transition-colors"
              >
                Extend Session
              </button>
              <button
                @click="dismissWarning"
                class="bg-white text-yellow-800 px-3 py-1 rounded-md text-sm font-medium border border-yellow-300 hover:bg-yellow-50 transition-colors"
              >
                Dismiss
              </button>
            </div>
          </div>
          <div class="ml-4 flex-shrink-0 flex">
            <button
              @click="dismissWarning"
              class="bg-yellow-50 rounded-md inline-flex text-yellow-400 hover:text-yellow-500 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-yellow-500"
            >
              <span class="sr-only">Close</span>
              <XMarkIcon class="h-5 w-5" />
            </button>
          </div>
        </div>
      </div>
    </div>
  </Transition>
</template>

<script setup>
import { ref, computed, watch, onUnmounted } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { ExclamationTriangleIcon, XMarkIcon } from '@heroicons/vue/24/outline'

const authStore = useAuthStore()

// State
const showWarning = ref(false)
const dismissed = ref(false)
const warningTimer = ref(null)
const updateTimer = ref(null)

// Clear warning timers
const clearWarning = () => {
  if (warningTimer.value) {
    clearTimeout(warningTimer.value)
    warningTimer.value = null
  }

  if (updateTimer.value) {
    clearInterval(updateTimer.value)
    updateTimer.value = null
  }

  showWarning.value = false
}

// Schedule warning to show 10 minutes before expiration
const scheduleWarning = () => {
  clearWarning()
  dismissed.value = false

  if (!authStore.tokenExpiresAt) return

  const timeUntilWarning = Math.max(0, authStore.tokenExpiresAt - Date.now() - 10 * 60 * 1000) // 10 minutes before expiry

  warningTimer.value = setTimeout(() => {
    if (authStore.isAuthenticated && !dismissed.value) {
      showWarning.value = true

      // Update time remaining every minute
      updateTimer.value = setInterval(() => {
        if (timeRemaining.value <= 0) {
          clearWarning()
        }
      }, 60000) // Update every minute
    }
  }, timeUntilWarning)
}

// Computed
const timeRemaining = computed(() => {
  if (!authStore.tokenExpiresAt) return 0
  const remaining = Math.max(0, authStore.tokenExpiresAt - Date.now())
  return Math.ceil(remaining / (1000 * 60)) // Convert to minutes
})

// Watch for token expiration changes
watch(
  () => authStore.tokenExpiresAt,
  newExpiration => {
    if (newExpiration) {
      scheduleWarning()
    } else {
      clearWarning()
    }
  },
  { immediate: true }
)

// Extend session by refreshing token
const extendSession = async () => {
  try {
    await authStore.refreshToken()
    showWarning.value = false
    dismissed.value = false
  } catch (error) {
    console.error('Failed to extend session:', error)
  }
}

// Dismiss warning
const dismissWarning = () => {
  showWarning.value = false
  dismissed.value = true

  if (updateTimer.value) {
    clearInterval(updateTimer.value)
    updateTimer.value = null
  }
}

// Cleanup on unmount
onUnmounted(() => {
  clearWarning()
})
</script>
