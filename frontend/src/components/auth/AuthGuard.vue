<template>
  <div>
    <!-- Loading state -->
    <div v-if="authStore.loading" class="flex items-center justify-center min-h-64">
      <LoadingSpinner />
      <span class="ml-3 text-gray-600">Authenticating...</span>
    </div>

    <!-- Authenticated content -->
    <div v-else-if="authStore.isAuthenticated">
      <slot />
    </div>

    <!-- Unauthenticated state -->
    <div v-else class="text-center py-12">
      <div class="mx-auto h-12 w-12 flex items-center justify-center rounded-lg bg-red-100">
        <ExclamationTriangleIcon class="h-6 w-6 text-red-600" />
      </div>
      <h3 class="mt-4 text-lg font-medium text-gray-900">Authentication Required</h3>
      <p class="mt-2 text-sm text-gray-500">You need to be logged in to access this content.</p>
      <div class="mt-6 flex justify-center space-x-3">
        <router-link to="/login" class="btn-primary"> Sign In </router-link>
        <router-link to="/register" class="btn-outline"> Create Account </router-link>
      </div>
    </div>
  </div>
</template>

<script setup>
import { onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { ExclamationTriangleIcon } from '@heroicons/vue/24/outline'
import LoadingSpinner from '@/components/common/LoadingSpinner.vue'

const props = defineProps({
  // Whether to redirect to login instead of showing the unauthenticated state
  redirect: {
    type: Boolean,
    default: false,
  },
  // Custom redirect path
  redirectTo: {
    type: String,
    default: '/login',
  },
  // Whether to show loading state
  showLoading: {
    type: Boolean,
    default: true,
  },
})

const router = useRouter()
const authStore = useAuthStore()

onMounted(async () => {
  // Initialize auth if needed
  if (!authStore.user && authStore.token) {
    try {
      await authStore.initializeAuth()
    } catch (error) {
      console.error('Auth initialization failed:', error)
    }
  }

  // Redirect if not authenticated and redirect prop is true
  if (props.redirect && !authStore.isAuthenticated && !authStore.loading) {
    const currentPath = router.currentRoute.value.fullPath
    router.push({
      path: props.redirectTo,
      query: { redirect: currentPath },
    })
  }
})
</script>
