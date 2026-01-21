import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useWebSocketStore } from '@/stores/websocket'

// Import views
import Home from '@/views/Home.vue'
import Login from '@/views/auth/Login.vue'
import Register from '@/views/auth/Register.vue'
import Dashboard from '@/views/Dashboard.vue'
import Room from '@/views/Room.vue'

const routes = [
  {
    path: '/',
    name: 'Home',
    component: Home,
    meta: { requiresAuth: false },
  },
  {
    path: '/login',
    name: 'Login',
    component: Login,
    meta: { requiresAuth: false, redirectIfAuth: true },
  },
  {
    path: '/register',
    name: 'Register',
    component: Register,
    meta: { requiresAuth: false, redirectIfAuth: true },
  },
  {
    path: '/dashboard',
    name: 'Dashboard',
    component: Dashboard,
    meta: { requiresAuth: true },
  },
  {
    path: '/room/:id',
    name: 'Room',
    component: Room,
    meta: { requiresAuth: true },
    props: true,
  },
  {
    path: '/:pathMatch(.*)*',
    name: 'NotFound',
    component: () => import('@/views/NotFound.vue'),
  },
]

const router = createRouter({
  history: createWebHistory(),
  routes,
})

// Navigation guards
router.beforeEach(async (to, from, next) => {
  const authStore = useAuthStore()
  const webSocketStore = useWebSocketStore()

  // Initialize auth if not already done
  if (!authStore.user && authStore.token) {
    try {
      await authStore.initializeAuth()
    } catch (error) {
      console.error('Auth initialization failed:', error)
      // Clear invalid token
      await authStore.logout()
    }
  }

  // Check if route requires authentication
  if (to.meta.requiresAuth && !authStore.isAuthenticated) {
    // Store the intended route for redirect after login
    const redirectPath = to.fullPath !== '/login' ? to.fullPath : '/dashboard'
    next({
      path: '/login',
      query: { redirect: redirectPath },
    })
    return
  }

  // Redirect authenticated users away from auth pages
  if (to.meta.redirectIfAuth && authStore.isAuthenticated) {
    // Check if there's a redirect query parameter
    const redirectPath = to.query.redirect || '/dashboard'
    next(redirectPath)
    return
  }

  // Connect WebSocket if user is authenticated and not connected
  if (authStore.isAuthenticated && authStore.token && !webSocketStore.connected) {
    try {
      webSocketStore.connect(authStore.token)
    } catch (error) {
      console.error('WebSocket connection failed:', error)
    }
  }

  next()
})

export default router
