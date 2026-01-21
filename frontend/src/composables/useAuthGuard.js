import { computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

/**
 * Composable for authentication guards and session management
 */
export function useAuthGuard() {
  const router = useRouter()
  const authStore = useAuthStore()

  // Computed properties
  const isAuthenticated = computed(() => authStore.isAuthenticated)
  const user = computed(() => authStore.user)
  const isLoading = computed(() => authStore.loading)

  /**
   * Require authentication for the current route
   * Redirects to login if not authenticated
   */
  const requireAuth = (redirectTo = '/login') => {
    if (!isAuthenticated.value) {
      const currentPath = router.currentRoute.value.fullPath
      router.push({
        path: redirectTo,
        query: { redirect: currentPath },
      })
      return false
    }
    return true
  }

  /**
   * Require guest (non-authenticated) for the current route
   * Redirects to dashboard if authenticated
   */
  const requireGuest = (redirectTo = '/dashboard') => {
    if (isAuthenticated.value) {
      router.push(redirectTo)
      return false
    }
    return true
  }

  /**
   * Check if user has specific role or permission
   * This can be extended based on your role system
   */
  const hasRole = role => {
    return user.value?.role === role
  }

  /**
   * Watch for authentication changes and redirect if needed
   */
  const watchAuthChanges = (options = {}) => {
    const { onLogin = null, onLogout = null, redirectOnLogout = '/login' } = options

    return watch(isAuthenticated, (newValue, oldValue) => {
      if (newValue && !oldValue) {
        // User just logged in
        if (onLogin) onLogin()
      } else if (!newValue && oldValue) {
        // User just logged out
        if (onLogout) onLogout()
        if (redirectOnLogout) {
          router.push(redirectOnLogout)
        }
      }
    })
  }

  /**
   * Check if token is about to expire
   */
  const isTokenExpiringSoon = computed(() => {
    if (!authStore.tokenExpiresAt) return false
    const timeUntilExpiry = authStore.tokenExpiresAt - Date.now()
    return timeUntilExpiry <= 10 * 60 * 1000 // 10 minutes
  })

  /**
   * Get time until token expires (in minutes)
   */
  const timeUntilExpiry = computed(() => {
    if (!authStore.tokenExpiresAt) return 0
    const remaining = Math.max(0, authStore.tokenExpiresAt - Date.now())
    return Math.ceil(remaining / (1000 * 60))
  })

  return {
    // State
    isAuthenticated,
    user,
    isLoading,
    isTokenExpiringSoon,
    timeUntilExpiry,

    // Methods
    requireAuth,
    requireGuest,
    hasRole,
    watchAuthChanges,

    // Auth store methods
    login: authStore.login,
    register: authStore.register,
    logout: authStore.logout,
    refreshToken: authStore.refreshToken,
  }
}
