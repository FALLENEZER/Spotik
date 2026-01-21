<template>
  <div class="flex items-center space-x-2">
    <!-- Connection Status Indicator -->
    <div class="flex items-center space-x-1">
      <div :class="['w-2 h-2 rounded-full', statusClasses]"></div>
      <span :class="['text-sm font-medium', textClasses]">
        {{ statusText }}
      </span>
    </div>

    <!-- Reconnection Progress -->
    <div v-if="isReconnecting" class="flex items-center space-x-1">
      <div class="animate-spin w-3 h-3 border border-gray-300 border-t-blue-500 rounded-full"></div>
      <span class="text-xs text-gray-500">
        Attempt {{ reconnectAttempts }}/{{ maxReconnectAttempts }}
      </span>
    </div>

    <!-- Manual Reconnect Button -->
    <button
      v-if="showReconnectButton && connectionInfo.connectionState !== 'disabled'"
      @click="handleReconnect"
      :disabled="isConnecting || isReconnecting"
      class="text-xs px-2 py-1 bg-blue-500 text-white rounded hover:bg-blue-600 disabled:opacity-50 disabled:cursor-not-allowed"
    >
      Reconnect
    </button>

    <!-- Error Details (expandable) -->
    <div v-if="connectionError && showError" class="relative">
      <button
        @click="showErrorDetails = !showErrorDetails"
        class="text-xs text-red-600 hover:text-red-800"
      >
        <ExclamationTriangleIcon class="w-4 h-4" />
      </button>

      <div
        v-if="showErrorDetails"
        class="absolute top-6 right-0 z-50 bg-white border border-red-200 rounded-lg shadow-lg p-3 w-64"
      >
        <div class="text-xs text-red-800 font-medium mb-1">Connection Error:</div>
        <div class="text-xs text-gray-700">{{ connectionError }}</div>
        <button
          @click="showErrorDetails = false"
          class="mt-2 text-xs text-gray-500 hover:text-gray-700"
        >
          Close
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, ref } from 'vue'
import { ExclamationTriangleIcon } from '@heroicons/vue/24/outline'
import { useWebSocket } from '@/composables/useWebSocket'

const props = defineProps({
  showReconnectButton: {
    type: Boolean,
    default: true,
  },
  showError: {
    type: Boolean,
    default: true,
  },
  compact: {
    type: Boolean,
    default: false,
  },
})

const {
  isConnected,
  isConnecting,
  isReconnecting,
  connectionError,
  connectionInfo,
  forceReconnect,
} = useWebSocket()

const showErrorDetails = ref(false)

// Computed properties for status display
const statusClasses = computed(() => {
  if (connectionInfo.value.connectionState === 'disabled') return 'bg-gray-400'
  if (isConnected.value) return 'bg-green-500'
  if (isConnecting.value || isReconnecting.value) return 'bg-yellow-500'
  return 'bg-red-500'
})

const textClasses = computed(() => {
  if (connectionInfo.value.connectionState === 'disabled') return 'text-gray-600'
  if (isConnected.value) return 'text-green-700'
  if (isConnecting.value || isReconnecting.value) return 'text-yellow-700'
  return 'text-red-700'
})

const statusText = computed(() => {
  if (connectionInfo.value.connectionState === 'disabled') {
    return props.compact ? 'Disabled' : 'WebSocket Disabled'
  }

  if (props.compact) {
    if (isConnected.value) return 'Online'
    if (isConnecting.value) return 'Connecting'
    if (isReconnecting.value) return 'Reconnecting'
    return 'Offline'
  }

  if (isConnected.value) return 'Connected'
  if (isConnecting.value) return 'Connecting...'
  if (isReconnecting.value) return 'Reconnecting...'
  return 'Disconnected'
})

const reconnectAttempts = computed(() => connectionInfo.value.reconnectAttempts)
const maxReconnectAttempts = computed(() => connectionInfo.value.maxReconnectAttempts)

const handleReconnect = () => {
  showErrorDetails.value = false
  forceReconnect()
}
</script>
