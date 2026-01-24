import axios from 'axios'

// Create axios instance
const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL || 'http://localhost:8000/api',
  timeout: 10000,
  headers: {
    Accept: 'application/json',
  },
})

// Request interceptor
api.interceptors.request.use(
  config => {
    // Add auth token if available
    const token = localStorage.getItem('auth_token')
    if (token) {
      config.headers.Authorization = `Bearer ${token}`
    }

    // If sending FormData, let the browser set Content-Type with boundary
    if (typeof FormData !== 'undefined' && config.data instanceof FormData) {
      if (config.headers && 'Content-Type' in config.headers) {
        delete config.headers['Content-Type']
      }
      // Ensure axios does not serialize FormData
      config.transformRequest = [(data) => data]
    }

    return config
  },
  error => {
    return Promise.reject(error)
  }
)

// Response interceptor
api.interceptors.response.use(
  response => {
    return response
  },
  async error => {
    const originalRequest = error.config

    // Handle 401 errors (unauthorized)
    if (error.response?.status === 401 && !originalRequest._retry) {
      // Prevent infinite loop: if the failing request was already a refresh attempt, don't retry
      if (originalRequest.url.includes('/auth/refresh')) {
        localStorage.removeItem('auth_token')
        delete api.defaults.headers.common['Authorization']
        window.location.href = '/login'
        return Promise.reject(error)
      }

      originalRequest._retry = true

      try {
        // Try to refresh token
        const refreshResponse = await api.post('/auth/refresh')
        const { data } = refreshResponse.data // Access nested data correctly
        const { token } = data

        if (!token) {
           throw new Error('No token in refresh response')
        }

        // Update token in localStorage and headers
        localStorage.setItem('auth_token', token)
        api.defaults.headers.common['Authorization'] = `Bearer ${token}`
        originalRequest.headers['Authorization'] = `Bearer ${token}`

        // Retry original request
        return api(originalRequest)
      } catch (refreshError) {
        // Refresh failed, redirect to login
        localStorage.removeItem('auth_token')
        delete api.defaults.headers.common['Authorization']
        window.location.href = '/login'
        return Promise.reject(refreshError)
      }
    }

    return Promise.reject(error)
  }
)

export default api

// Genre API functions
export const genreApi = {
  getAll: () => api.get('/genres'),
  getPopular: (limit = 10) => api.get(`/genres/popular?limit=${limit}`),
  create: (data) => api.post('/genres', data),
  update: (id, data) => api.put(`/genres/${id}`, data),
  delete: (id) => api.delete(`/genres/${id}`),
}

// Playlist API functions
export const playlistApi = {
  getAll: () => api.get('/playlists'),
  get: (id) => api.get(`/playlists/${id}`),
  create: (data) => api.post('/playlists', data),
  update: (id, data) => api.put(`/playlists/${id}`, data),
  delete: (id) => api.delete(`/playlists/${id}`),
  addTrack: (id, trackId, position) => api.post(`/playlists/${id}/tracks`, { track_id: trackId, position }),
  removeTrack: (id, trackId) => api.delete(`/playlists/${id}/tracks/${trackId}`),
}
