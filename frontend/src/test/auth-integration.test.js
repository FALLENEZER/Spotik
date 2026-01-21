import { describe, it, expect, beforeEach, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import api from '@/services/api'

// Mock successful API responses
vi.mock('@/services/api', () => ({
  default: {
    post: vi.fn(),
    get: vi.fn(),
    defaults: {
      headers: {
        common: {},
      },
    },
  },
}))

describe('Authentication Integration', () => {
  let authStore

  beforeEach(() => {
    setActivePinia(createPinia())
    authStore = useAuthStore()
    localStorage.clear()
    vi.clearAllMocks()
  })

  describe('Login Flow', () => {
    it('successfully logs in user with valid credentials', async () => {
      // Mock successful login response
      api.post.mockResolvedValueOnce({
        data: {
          success: true,
          data: {
            user: {
              id: '1',
              username: 'testuser',
              email: 'test@example.com',
            },
            token: 'mock-jwt-token',
            expires_in: 3600,
          },
        },
      })

      const result = await authStore.login({
        email: 'test@example.com',
        password: 'password123',
      })

      expect(result.success).toBe(true)
      expect(authStore.user).toEqual({
        id: '1',
        username: 'testuser',
        email: 'test@example.com',
      })
      expect(authStore.token).toBe('mock-jwt-token')
      expect(authStore.isAuthenticated).toBe(true)
      expect(localStorage.getItem('auth_token')).toBe('mock-jwt-token')
    })

    it('handles login failure with invalid credentials', async () => {
      // Mock failed login response
      api.post.mockRejectedValueOnce({
        response: {
          data: {
            message: 'Invalid credentials',
          },
        },
      })

      const result = await authStore.login({
        email: 'test@example.com',
        password: 'wrongpassword',
      })

      expect(result.success).toBe(false)
      expect(result.error).toBe('Invalid credentials')
      expect(authStore.user).toBe(null)
      expect(authStore.token).toBe(null)
      expect(authStore.isAuthenticated).toBe(false)
    })
  })

  describe('Registration Flow', () => {
    it('successfully registers new user', async () => {
      // Mock successful registration response
      api.post.mockResolvedValueOnce({
        data: {
          success: true,
          data: {
            user: {
              id: '2',
              username: 'newuser',
              email: 'new@example.com',
            },
            token: 'new-jwt-token',
            expires_in: 3600,
          },
        },
      })

      const result = await authStore.register({
        username: 'newuser',
        email: 'new@example.com',
        password: 'password123',
        password_confirmation: 'password123',
      })

      expect(result.success).toBe(true)
      expect(authStore.user).toEqual({
        id: '2',
        username: 'newuser',
        email: 'new@example.com',
      })
      expect(authStore.token).toBe('new-jwt-token')
      expect(authStore.isAuthenticated).toBe(true)
    })
  })

  describe('Token Management', () => {
    it('successfully refreshes token', async () => {
      // Set initial token
      authStore.token = 'old-token'
      authStore.user = { id: '1', username: 'testuser' }

      // Mock successful refresh response
      api.post.mockResolvedValueOnce({
        data: {
          success: true,
          data: {
            token: 'new-token',
            expires_in: 3600,
          },
        },
      })

      const result = await authStore.refreshToken()

      expect(result).toBe(true)
      expect(authStore.token).toBe('new-token')
      expect(localStorage.getItem('auth_token')).toBe('new-token')
    })

    it('logs out user when token refresh fails', async () => {
      // Set initial token
      authStore.token = 'expired-token'
      authStore.user = { id: '1', username: 'testuser' }

      // Mock failed refresh response
      api.post.mockRejectedValueOnce({
        response: {
          status: 401,
          data: { message: 'Token expired' },
        },
      })

      const result = await authStore.refreshToken()

      expect(result).toBe(false)
      expect(authStore.token).toBe(null)
      expect(authStore.user).toBe(null)
      expect(authStore.isAuthenticated).toBe(false)
    })
  })

  describe('User Session', () => {
    it('fetches user data with valid token', async () => {
      // Set token
      authStore.token = 'valid-token'

      // Mock successful user fetch response
      api.get.mockResolvedValueOnce({
        data: {
          success: true,
          data: {
            user: {
              id: '1',
              username: 'testuser',
              email: 'test@example.com',
            },
          },
        },
      })

      const result = await authStore.fetchUser()

      expect(result).toBe(true)
      expect(authStore.user).toEqual({
        id: '1',
        username: 'testuser',
        email: 'test@example.com',
      })
    })

    it('logs out user when fetch fails', async () => {
      // Set token
      authStore.token = 'invalid-token'

      // Mock failed user fetch response
      api.get.mockRejectedValueOnce({
        response: {
          status: 401,
          data: { message: 'Unauthorized' },
        },
      })

      const result = await authStore.fetchUser()

      expect(result).toBe(false)
      expect(authStore.user).toBe(null)
      expect(authStore.token).toBe(null)
    })
  })

  describe('Logout', () => {
    it('successfully logs out user', async () => {
      // Set initial state
      authStore.token = 'valid-token'
      authStore.user = { id: '1', username: 'testuser' }
      localStorage.setItem('auth_token', 'valid-token')

      // Mock successful logout response
      api.post.mockResolvedValueOnce({
        data: { success: true },
      })

      await authStore.logout()

      expect(authStore.user).toBe(null)
      expect(authStore.token).toBe(null)
      expect(authStore.isAuthenticated).toBe(false)
      expect(localStorage.getItem('auth_token')).toBe(null)
    })
  })
})
