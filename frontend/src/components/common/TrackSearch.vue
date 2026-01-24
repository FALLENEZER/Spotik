<template>
  <div class="relative">
    <div class="relative">
      <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
        <svg class="h-5 w-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
          />
        </svg>
      </div>
      <input
        type="text"
        v-model="query"
        @input="handleInput"
        class="input pl-10 w-full"
        placeholder="Search for tracks..."
        :disabled="loading"
        autocomplete="off"
      />
      <div v-if="loading" class="absolute inset-y-0 right-0 pr-3 flex items-center">
        <svg
          class="animate-spin h-5 w-5 text-gray-400"
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
        >
          <circle
            class="opacity-25"
            cx="12"
            cy="12"
            r="10"
            stroke="currentColor"
            stroke-width="4"
          ></circle>
          <path
            class="opacity-75"
            fill="currentColor"
            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
          ></path>
        </svg>
      </div>
    </div>

    <!-- Search Results Dropdown -->
    <div
      v-if="showResults && results.length > 0"
      class="absolute z-10 mt-1 w-full bg-white shadow-lg max-h-60 rounded-md py-1 text-base ring-1 ring-black ring-opacity-5 overflow-auto focus:outline-none sm:text-sm"
    >
      <div
        v-for="track in results"
        :key="track.id"
        class="cursor-pointer select-none relative py-2 pl-3 pr-9 hover:bg-gray-100"
        @click="handleSelect(track)"
      >
        <div class="flex items-center">
          <div class="ml-3 truncate">
            <span class="block truncate font-medium text-gray-900">
              {{ track.title || track.original_name }}
            </span>
            <span class="block truncate text-xs text-gray-500">
              {{ track.artist || 'Unknown Artist' }} • {{ formatDuration(track.duration_seconds) }}
            </span>
          </div>
        </div>
      </div>
    </div>
    
    <div
      v-if="showResults && query.length >= 2 && results.length === 0 && !loading"
      class="absolute z-10 mt-1 w-full bg-white shadow-lg rounded-md py-2 px-4 text-sm text-gray-500 text-center"
    >
      No tracks found
    </div>
  </div>
</template>

<script setup>
import { ref, watch } from 'vue'
import debounce from 'lodash/debounce' // Assume lodash is available or implement debounce
import api from '@/services/api' // Use api service instead of trackApi directly if needed

const props = defineProps({
  excludeIds: {
    type: Array,
    default: () => [],
  },
})

const emit = defineEmits(['select'])

const query = ref('')
const results = ref([])
const loading = ref(false)
const showResults = ref(false)

// Simple debounce implementation if lodash not available/wanted
const debounceFn = (fn, delay) => {
  let timeoutId
  return (...args) => {
    clearTimeout(timeoutId)
    timeoutId = setTimeout(() => fn(...args), delay)
  }
}

const searchTracks = async () => {
  if (query.value.length < 2) {
    results.value = []
    showResults.value = false
    return
  }

  loading.value = true
  try {
    // Assuming backend has a search endpoint or use index with filter
    const response = await api.get(`/tracks?search=${encodeURIComponent(query.value)}`)
    const tracks = response.data.data || []
    
    // Filter out excluded tracks
    results.value = tracks.filter(t => !props.excludeIds.includes(t.id))
    showResults.value = true
  } catch (error) {
    console.error('Search failed:', error)
    results.value = []
  } finally {
    loading.value = false
  }
}

const handleInput = debounceFn(() => {
  searchTracks()
}, 300)

const handleSelect = (track) => {
  emit('select', track)
  query.value = ''
  results.value = []
  showResults.value = false
}

const formatDuration = (seconds) => {
  if (!seconds) return '0:00'
  const minutes = Math.floor(seconds / 60)
  const remainingSeconds = Math.floor(seconds % 60)
  return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`
}

// Close results when clicking outside (rudimentary)
// In a real app, use @vueuse/core onClickOutside
</script>
