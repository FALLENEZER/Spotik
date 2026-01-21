<template>
  <div id="app" class="min-h-screen bg-gray-50">
    <!-- Navigation -->
    <Navigation />

    <!-- Main content -->
    <main class="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
      <router-view />
    </main>

    <!-- Global notifications -->
    <NotificationToast
      :show="notification.show"
      :type="notification.type"
      :title="notification.title"
      :message="notification.message"
      @close="hideNotification"
    />

    <!-- Session timeout warning -->
    <SessionTimeoutWarning v-if="authStore.isAuthenticated" />
  </div>
</template>

<script setup>
import { reactive, provide } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useWebSocketStore } from '@/stores/websocket'
import Navigation from '@/components/layout/Navigation.vue'
import NotificationToast from '@/components/common/NotificationToast.vue'
import SessionTimeoutWarning from '@/components/auth/SessionTimeoutWarning.vue'

const authStore = useAuthStore()
const webSocketStore = useWebSocketStore()

// Global notification state
const notification = reactive({
  show: false,
  type: 'success',
  title: '',
  message: '',
})

// Show notification helper
const showNotification = (type, title, message) => {
  notification.type = type
  notification.title = title
  notification.message = message
  notification.show = true

  // Auto-hide after 5 seconds
  setTimeout(() => {
    notification.show = false
  }, 5000)
}

// Hide notification
const hideNotification = () => {
  notification.show = false
}

// Provide notification function to child components
provide('showNotification', showNotification)

// Initialize auth state and WebSocket connection
const initializeApp = async () => {
  await authStore.initializeAuth()

  // Connect WebSocket if user is authenticated
  if (authStore.isAuthenticated && authStore.token) {
    webSocketStore.connect(authStore.token)
  }
}

// Initialize app
initializeApp()
</script>
