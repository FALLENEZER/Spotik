<template>
  <div class="p-6 bg-white rounded-lg shadow-md">
    <h3 class="text-lg font-semibold mb-4">WebSocket Connection Example</h3>

    <!-- Connection Status -->
    <div class="mb-4">
      <ConnectionStatus :show-reconnect-button="true" :show-error="true" />
    </div>

    <!-- Connection Controls -->
    <div class="flex space-x-2 mb-4">
      <button
        @click="handleConnect"
        :disabled="isConnected || isConnecting"
        class="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600 disabled:opacity-50 disabled:cursor-not-allowed"
      >
        Connect
      </button>

      <button
        @click="handleDisconnect"
        :disabled="!isConnected && !isConnecting"
        class="px-4 py-2 bg-red-500 text-white rounded hover:bg-red-600 disabled:opacity-50 disabled:cursor-not-allowed"
      >
        Disconnect
      </button>

      <button
        @click="handleForceReconnect"
        :disabled="!isConnected"
        class="px-4 py-2 bg-yellow-500 text-white rounded hover:bg-yellow-600 disabled:opacity-50 disabled:cursor-not-allowed"
      >
        Force Reconnect
      </button>
    </div>

    <!-- Room Controls -->
    <div class="mb-4">
      <div class="flex space-x-2 mb-2">
        <input
          v-model="roomId"
          type="text"
          placeholder="Enter room ID"
          class="flex-1 px-3 py-2 border border-gray-300 rounded focus:outline-none focus:ring-2 focus:ring-blue-500"
        />
        <button
          @click="handleJoinRoom"
          :disabled="!isConnected || !roomId"
          class="px-4 py-2 bg-green-500 text-white rounded hover:bg-green-600 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          Join Room
        </button>
        <button
          @click="handleLeaveRoom"
          class="px-4 py-2 bg-gray-500 text-white rounded hover:bg-gray-600"
        >
          Leave Room
        </button>
      </div>
    </div>

    <!-- Connection Info -->
    <div class="bg-gray-50 p-4 rounded">
      <h4 class="font-medium mb-2">Connection Information:</h4>
      <pre class="text-sm text-gray-700">{{ JSON.stringify(connectionInfo, null, 2) }}</pre>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useWebSocket } from '@/composables/useWebSocket'
import ConnectionStatus from './ConnectionStatus.vue'

const {
  isConnected,
  isConnecting,
  isReconnecting,
  connectionError,
  connectionInfo,
  connect,
  disconnect,
  forceReconnect,
  joinRoom,
  leaveRoom,
} = useWebSocket()

const roomId = ref('')

const handleConnect = () => {
  connect()
}

const handleDisconnect = () => {
  disconnect()
}

const handleForceReconnect = () => {
  forceReconnect()
}

const handleJoinRoom = () => {
  if (roomId.value) {
    joinRoom(roomId.value)
  }
}

const handleLeaveRoom = () => {
  leaveRoom()
}
</script>
