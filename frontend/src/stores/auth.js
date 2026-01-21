import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import api from '@/services/api'

export const useAuthStore = defineStore('auth', () => {
  // State
  const user = ref(null)
  const token = ref(localStorage.getItem('auth_token'))
  const loading = ref(false)
  const error = ref(null)
  const tokenExpiresAt = ref(null)
  const refreshTimer = ref(null)

  // Getters
  const isAuthenticated = computed(() => !!token.value && !!user.value)
  const isTokenExpired = computed(() => {
    if (!tokenExpiresAt.value) return false
    return Date.now() >= tokenExpiresAt.value
  })

  // Helper function to set token expiration and schedule refresh
  const setTokenExpiration = expiresIn => {
    if (expiresIn) {
      // Set expiration time (convert seconds to milliseconds)
      tokenExpiresAt.value = Date.now() + expiresIn * 1000

      // Schedule token refresh 5 minutes before expiration
      const refreshTime = Math.max(0, (expiresIn - 300) * 1000) // 5 minutes before expiry

      if (refreshTimer.value) {
        clearTimeout(refreshTimer.value)
      }

      refreshTimer.value = setTimeout(async () => {
        if (isAuthenticated.value && !isTokenExpired.value) {
          await refreshToken()
        }
      }, refreshTime)
    }
  }

  // Actions
  // Actions
  const login = async credentials => {
    loading.value = true
    error.value = null

    try {
      const response = await api.post('/auth/login', credentials)
      const { data } = response.data

      user.value = data.user
      token.value = data.token
      localStorage.setItem('auth_token', data.token)

      // Set default authorization header
      api.defaults.headers.common['Authorization'] = `Bearer ${data.token}`

      // Set token expiration and schedule refresh
      setTokenExpiration(data.expires_in)

      return { success: true }
    } catch (err) {
      error.value = err.response?.data?.message || 'Login failed'
      return { success: false, error: error.value }
    } finally {
      loading.value = false
    }
  }

  const register = async userData => {
    loading.value = true
    error.value = null

    try {
      const response = await api.post('/auth/register', userData)
      const { data } = response.data

      user.value = data.user
      token.value = data.token
      localStorage.setItem('auth_token', data.token)

      // Set default authorization header
      api.defaults.headers.common['Authorization'] = `Bearer ${data.token}`

      // Set token expiration and schedule refresh
      setTokenExpiration(data.expires_in)

      return { success: true }
    } catch (err) {
      error.value = err.response?.data?.message || 'Registration failed'
      return { success: false, error: error.value }
    } finally {
      loading.value = false
    }
  }

  const logout = async () => {
    loading.value = true

    try {
      if (token.value) {
        await api.post('/auth/logout')
      }
    } catch (err) {
      console.error('Logout error:', err)
    } finally {
      // Clear state regardless of API call success
      user.value = null
      token.value = null
      tokenExpiresAt.value = null
      localStorage.removeItem('auth_token')
      delete api.defaults.headers.common['Authorization']

      // Clear refresh timer
      if (refreshTimer.value) {
        clearTimeout(refreshTimer.value)
        refreshTimer.value = null
      }

      loading.value = false
    }
  }

  const refreshToken = async () => {
    if (!token.value) return false

    try {
      const response = await api.post('/auth/refresh')
      const { data } = response.data

      token.value = data.token
      localStorage.setItem('auth_token', data.token)
      api.defaults.headers.common['Authorization'] = `Bearer ${data.token}`

      // Set new token expiration and schedule next refresh
      setTokenExpiration(data.expires_in)

      return true
    } catch (err) {
      console.error('Token refresh failed:', err)
      await logout()
      return false
    }
  }

  const fetchUser = async () => {
    if (!token.value) return false

    try {
      const response = await api.get('/auth/me')
      const { data } = response.data
      user.value = data.user
      return true
    } catch (err) {
      console.error('Fetch user failed:', err)
      await logout()
      return false
    }
  }

  const initializeAuth = async () => {
    if (token.value) {
      api.defaults.headers.common['Authorization'] = `Bearer ${token.value}`
      await fetchUser()
    }
  }

  return {
    // State
    user,
    token,
    loading,
    error,
    tokenExpiresAt,

    // Getters
    isAuthenticated,
    isTokenExpired,

    // Actions
    login,
    register,
    logout,
    refreshToken,
    fetchUser,
    initializeAuth,
  }
})
