import { describe, it, expect, beforeEach, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createRouter, createWebHistory } from 'vue-router'
import Login from '@/views/auth/Login.vue'
import Register from '@/views/auth/Register.vue'
import { useAuthStore } from '@/stores/auth'

// Mock API
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

// Create router for testing
const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/login', component: Login },
    { path: '/register', component: Register },
    { path: '/dashboard', component: { template: '<div>Dashboard</div>' } },
  ],
})

describe('Authentication UI', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    localStorage.clear()
  })

  describe('Login Form', () => {
    it('renders login form correctly', () => {
      const wrapper = mount(Login, {
        global: {
          plugins: [router],
        },
      })

      expect(wrapper.find('h2').text()).toBe('Sign in to your account')
      expect(wrapper.find('input[type="email"]').exists()).toBe(true)
      expect(wrapper.find('input[type="password"]').exists()).toBe(true)
      expect(wrapper.find('button[type="submit"]').exists()).toBe(true)
    })

    it('validates required fields', async () => {
      const wrapper = mount(Login, {
        global: {
          plugins: [router],
        },
      })

      // Submit form without filling fields
      await wrapper.find('form').trigger('submit.prevent')

      // Check for validation errors
      expect(wrapper.text()).toContain('Email is required')
      expect(wrapper.text()).toContain('Password is required')
    })

    it('validates email format', async () => {
      const wrapper = mount(Login, {
        global: {
          plugins: [router],
        },
      })

      // Fill invalid email
      await wrapper.find('input[type="email"]').setValue('invalid-email')
      await wrapper.find('form').trigger('submit.prevent')

      expect(wrapper.text()).toContain('Email is invalid')
    })

    it('validates password length', async () => {
      const wrapper = mount(Login, {
        global: {
          plugins: [router],
        },
      })

      // Fill short password
      await wrapper.find('input[type="password"]').setValue('123')
      await wrapper.find('form').trigger('submit.prevent')

      expect(wrapper.text()).toContain('Password must be at least 6 characters')
    })
  })

  describe('Register Form', () => {
    it('renders register form correctly', () => {
      const wrapper = mount(Register, {
        global: {
          plugins: [router],
        },
      })

      expect(wrapper.find('h2').text()).toBe('Create your account')
      expect(wrapper.find('input[name="username"]').exists()).toBe(true)
      expect(wrapper.find('input[name="email"]').exists()).toBe(true)
      expect(wrapper.find('input[name="password"]').exists()).toBe(true)
      expect(wrapper.find('input[name="password_confirmation"]').exists()).toBe(true)
    })

    it('validates password confirmation', async () => {
      const wrapper = mount(Register, {
        global: {
          plugins: [router],
        },
      })

      // Fill mismatched passwords
      await wrapper.find('input[name="password"]').setValue('password123')
      await wrapper.find('input[name="password_confirmation"]').setValue('different123')
      await wrapper.find('form').trigger('submit.prevent')

      expect(wrapper.text()).toContain('Passwords do not match')
    })

    it('shows password strength indicator', async () => {
      const wrapper = mount(Register, {
        global: {
          plugins: [router],
        },
      })

      // Fill password field
      await wrapper.find('input[name="password"]').setValue('weak')

      // Check if password strength indicator is shown
      expect(wrapper.text()).toContain('Weak')
    })
  })

  describe('Auth Store', () => {
    it('initializes with correct default state', () => {
      const authStore = useAuthStore()

      expect(authStore.user).toBe(null)
      expect(authStore.loading).toBe(false)
      expect(authStore.error).toBe(null)
      expect(authStore.isAuthenticated).toBe(false)
    })

    it('handles token from localStorage', () => {
      // Set token in localStorage before creating store
      localStorage.setItem('auth_token', 'test-token')

      // Create new pinia instance to ensure fresh store
      const pinia = createPinia()
      setActivePinia(pinia)

      const authStore = useAuthStore()

      expect(authStore.token).toBe('test-token')
    })
  })
})
