<template>
  <nav class="bg-white shadow-sm border-b border-gray-200">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
      <div class="flex justify-between h-16">
        <!-- Logo and brand -->
        <div class="flex items-center">
          <router-link to="/" class="flex items-center space-x-2">
            <div class="w-8 h-8 bg-indigo-600 rounded-lg flex items-center justify-center">
              <span class="text-white font-bold text-lg">S</span>
            </div>
            <span class="text-xl font-semibold text-gray-900">Spotik</span>
          </router-link>

          <!-- Navigation links for authenticated users -->
          <div v-if="authStore.isAuthenticated" class="ml-10 flex items-baseline space-x-4">
            <router-link
              to="/dashboard"
              class="text-gray-500 hover:text-gray-700 px-3 py-2 rounded-md text-sm font-medium"
              :class="{ 'text-indigo-600': $route.name === 'Dashboard' }"
            >
              Dashboard
            </router-link>

            <router-link
              v-if="roomStore.isInRoom"
              :to="`/room/${roomStore.currentRoom.id}`"
              class="text-gray-500 hover:text-gray-700 px-3 py-2 rounded-md text-sm font-medium"
              :class="{ 'text-indigo-600': $route.name === 'Room' }"
            >
              Current Room
            </router-link>
          </div>
        </div>

        <!-- User menu -->
        <div class="flex items-center space-x-4">
          <template v-if="authStore.isAuthenticated">
            <!-- Room indicator -->
            <div
              v-if="roomStore.isInRoom"
              class="flex items-center space-x-2 text-sm text-gray-600"
            >
              <div class="w-2 h-2 bg-green-500 rounded-full"></div>
              <span>In {{ roomStore.currentRoom.name }}</span>
            </div>

            <!-- User info -->
            <div class="flex items-center space-x-3">
              <span class="text-sm text-gray-700">
                {{ authStore.user?.username }}
              </span>

              <!-- Admin badge -->
              <span
                v-if="roomStore.isRoomAdmin"
                class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800"
              >
                Admin
              </span>

              <button
                @click="handleLogout"
                class="text-sm text-gray-500 hover:text-gray-700 transition-colors"
              >
                Logout
              </button>
            </div>
          </template>

          <template v-else>
            <router-link
              to="/login"
              class="text-sm text-gray-500 hover:text-gray-700 transition-colors"
            >
              Login
            </router-link>
            <router-link
              to="/register"
              class="bg-indigo-600 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-indigo-700 transition-colors"
            >
              Sign Up
            </router-link>
          </template>
        </div>
      </div>
    </div>
  </nav>
</template>

<script setup>
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useRoomStore } from '@/stores/room'
import { useWebSocketStore } from '@/stores/websocket'

const router = useRouter()
const authStore = useAuthStore()
const roomStore = useRoomStore()
const webSocketStore = useWebSocketStore()

// Handle logout
const handleLogout = async () => {
  try {
    // Disconnect WebSocket
    webSocketStore.disconnect()

    // Clear room state
    roomStore.clearRoom()

    // Logout user
    await authStore.logout()

    // Redirect to login
    router.push('/login')
  } catch (error) {
    console.error('Logout error:', error)
  }
}
</script>
