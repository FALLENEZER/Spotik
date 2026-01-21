<template>
  <div class="min-h-screen bg-gray-50">
    <!-- Navigation -->
    <nav class="bg-white shadow-sm border-b border-gray-200">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex justify-between h-16">
          <div class="flex items-center">
            <router-link to="/" class="flex items-center space-x-2">
              <div class="w-8 h-8 bg-indigo-600 rounded-lg flex items-center justify-center">
                <span class="text-white font-bold text-lg">S</span>
              </div>
              <span class="text-xl font-semibold text-gray-900">Spotik</span>
            </router-link>
          </div>

          <div class="flex items-center space-x-4">
            <template v-if="authStore.isAuthenticated">
              <span class="text-sm text-gray-700"> Welcome, {{ authStore.user?.username }} </span>
              <button @click="handleLogout" class="text-sm text-gray-500 hover:text-gray-700">
                Logout
              </button>
            </template>
            <template v-else>
              <router-link to="/login" class="text-sm text-gray-500 hover:text-gray-700">
                Login
              </router-link>
              <router-link
                to="/register"
                class="bg-indigo-600 text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-indigo-700"
              >
                Sign Up
              </router-link>
            </template>
          </div>
        </div>
      </div>
    </nav>

    <!-- Main content -->
    <main class="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
      <slot />
    </main>
  </div>
</template>

<script setup>
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useWebSocketStore } from '@/stores/websocket'

const router = useRouter()
const authStore = useAuthStore()
const webSocketStore = useWebSocketStore()

// Handle logout
const handleLogout = async () => {
  try {
    // Disconnect WebSocket
    webSocketStore.disconnect()

    // Logout user
    await authStore.logout()

    // Redirect to login
    router.push('/login')
  } catch (error) {
    console.error('Logout error:', error)
  }
}
</script>
