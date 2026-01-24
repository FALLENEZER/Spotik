<template>
  <div>
    <!-- Breadcrumbs -->
    <Breadcrumbs :items="breadcrumbItems" />

    <!-- Header -->
    <div class="md:flex md:items-center md:justify-between">
      <div class="min-w-0 flex-1">
        <h2
          class="text-2xl font-bold leading-7 text-gray-900 sm:truncate sm:text-3xl sm:tracking-tight"
        >
          Dashboard
        </h2>
        <p class="mt-1 text-sm text-gray-500">
          Join an existing room or create your own to start listening together.
        </p>
      </div>
      <div class="mt-4 flex md:ml-4 md:mt-0">
        <button
          type="button"
          class="btn-primary"
          @click="showCreateRoom = true"
          :disabled="roomStore.loading"
        >
          <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 4v16m8-8H4"
            />
          </svg>
          Create Room
        </button>
      </div>
    </div>

    <!-- Room statistics -->
    <div class="mt-6 grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3">
      <div class="bg-white overflow-hidden shadow rounded-lg">
        <div class="p-5">
          <div class="flex items-center">
            <div class="flex-shrink-0">
              <svg
                class="h-6 w-6 text-gray-400"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10"
                />
              </svg>
            </div>
            <div class="ml-5 w-0 flex-1">
              <dl>
                <dt class="text-sm font-medium text-gray-500 truncate">Total Rooms</dt>
                <dd class="text-lg font-medium text-gray-900">{{ rooms.length }}</dd>
              </dl>
            </div>
          </div>
        </div>
      </div>

      <div class="bg-white overflow-hidden shadow rounded-lg">
        <div class="p-5">
          <div class="flex items-center">
            <div class="flex-shrink-0">
              <svg
                class="h-6 w-6 text-gray-400"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M14.828 14.828a4 4 0 01-5.656 0M9 10h1m4 0h1m-6 4h8m-9-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
            </div>
            <div class="ml-5 w-0 flex-1">
              <dl>
                <dt class="text-sm font-medium text-gray-500 truncate">Active Rooms</dt>
                <dd class="text-lg font-medium text-gray-900">{{ activeRoomsCount }}</dd>
              </dl>
            </div>
          </div>
        </div>
      </div>

      <div class="bg-white overflow-hidden shadow rounded-lg">
        <div class="p-5">
          <div class="flex items-center">
            <div class="flex-shrink-0">
              <svg
                class="h-6 w-6 text-gray-400"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197m13.5-9a2.5 2.5 0 11-5 0 2.5 2.5 0 015 0z"
                />
              </svg>
            </div>
            <div class="ml-5 w-0 flex-1">
              <dl>
                <dt class="text-sm font-medium text-gray-500 truncate">Total Participants</dt>
                <dd class="text-lg font-medium text-gray-900">{{ totalParticipants }}</dd>
              </dl>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Room list -->
    <div class="mt-8">
      <div class="mb-6">
        <div class="flex items-center justify-between">
          <h3 class="text-lg font-medium text-gray-900">Available Rooms</h3>
          <button
            type="button"
            class="btn-outline"
            @click="fetchRooms"
            :disabled="roomStore.loading"
            title="Refresh rooms"
          >
            <svg
              class="w-4 h-4 mr-2"
              :class="{ 'animate-spin': roomStore.loading }"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
              />
            </svg>
            Refresh
          </button>
        </div>

        <!-- Search and sort controls -->
        <div class="mt-4 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4">
          <div class="lg:col-span-2">
            <label class="block text-sm font-medium text-gray-700">Search</label>
            <input type="text" v-model="searchQuery" placeholder="By name…" class="mt-1 input" />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700">From date</label>
            <input type="date" v-model="dateFrom" class="mt-1 input" />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700">To date</label>
            <input type="date" v-model="dateTo" class="mt-1 input" />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700">Min participants</label>
            <input type="number" min="0" v-model.number="minParticipants" class="mt-1 input" />
          </div>
          <div>
            <label class="block text-sm font-medium text-gray-700">Sort by</label>
            <select v-model="sortBy" class="mt-1 input">
              <option value="name_asc">Name (A→Z)</option>
              <option value="name_desc">Name (Z→A)</option>
              <option value="date_new">Date (newest)</option>
              <option value="date_old">Date (oldest)</option>
              <option value="participants_desc">Participants (high→low)</option>
              <option value="participants_asc">Participants (low→high)</option>
              <option value="active">Active first</option>
            </select>
          </div>
        </div>
      </div>

      <RoomList
        :rooms="displayedRooms"
        :loading="roomStore.loading"
        :error="roomStore.error"
        @join="handleJoinRoom"
        @retry="fetchRooms"
      />
    </div>

    <!-- Playlist management -->
    <div class="mt-8">
      <PlaylistManager @view-playlist="handleViewPlaylist" />
    </div>

    <!-- Monitoring -->
    <div class="mt-8">
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-medium text-gray-900">Monitoring</h3>
        <button type="button" class="btn-outline" @click="fetchMetrics">
          <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
            />
          </svg>
          Refresh Metrics
        </button>
      </div>
      <div class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-4">
        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <div class="flex items-center">
              <div class="ml-0 w-0 flex-1">
                <dl>
                  <dt class="text-sm font-medium text-gray-500 truncate">Avg response time</dt>
                  <dd class="text-lg font-medium text-gray-900">
                    {{
                      metrics.requests?.avg_response_time
                        ? metrics.requests.avg_response_time.toFixed(1) + ' ms'
                        : '—'
                    }}
                  </dd>
                </dl>
              </div>
            </div>
          </div>
        </div>
        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">Requests (last hour)</dt>
              <dd class="text-lg font-medium text-gray-900">
                {{ metrics.requests?.total ?? '—' }}
              </dd>
            </dl>
          </div>
        </div>
        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">2xx/4xx/5xx</dt>
              <dd class="text-lg font-medium text-gray-900">
                {{ metrics.status_codes?.['200'] || 0 }} /
                {{ metrics.status_codes?.['400'] || 0 }} /
                {{ metrics.status_codes?.['500'] || 0 }}
              </dd>
            </dl>
          </div>
        </div>
        <div class="bg-white overflow-hidden shadow rounded-lg">
          <div class="p-5">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">Top route</dt>
              <dd class="text-sm font-medium text-gray-900 truncate">
                {{ topRouteLabel }}
              </dd>
            </dl>
          </div>
        </div>
      </div>
    </div>

    <!-- Create room modal -->
    <CreateRoomModal
      :show="showCreateRoom"
      @close="showCreateRoom = false"
      @created="handleRoomCreated"
    />
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted, inject } from 'vue'
import { useRouter } from 'vue-router'
import { useRoomStore } from '@/stores/room'
import api from '@/services/api'
import Breadcrumbs from '@/components/common/Breadcrumbs.vue'
import RoomList from '@/components/room/RoomList.vue'
import CreateRoomModal from '@/components/room/CreateRoomModal.vue'
import PlaylistManager from '@/components/playlist/PlaylistManager.vue'

const router = useRouter()
const roomStore = useRoomStore()
const showNotification = inject('showNotification')

const showCreateRoom = ref(false)
const rooms = ref([])
const searchQuery = ref('')
const dateFrom = ref('')
const dateTo = ref('')
const minParticipants = ref(0)
const sortBy = ref('active')
const metrics = ref({})

// Breadcrumb items
const breadcrumbItems = [{ name: 'Dashboard', to: '/dashboard' }]

// Computed properties
const activeRoomsCount = computed(() => {
  return rooms.value.filter(room => room.is_playing || room.participant_count > 0).length
})

const totalParticipants = computed(() => {
  return rooms.value.reduce((total, room) => total + (room.participant_count || 0), 0)
})

const displayedRooms = computed(() => {
  const query = searchQuery.value.trim().toLowerCase()
  const from = dateFrom.value ? new Date(dateFrom.value) : null
  const to = dateTo.value ? new Date(dateTo.value) : null
  const minP = Number(minParticipants.value) || 0

  let list = rooms.value.filter(room => {
    const nameMatch = !query || room.name?.toLowerCase().includes(query)
    const created = room.created_at ? new Date(room.created_at) : null
    const dateMatch = (!from || (created && created >= from)) && (!to || (created && created <= to))
    const participantsMatch = (room.participant_count || 0) >= minP
    return nameMatch && dateMatch && participantsMatch
  })

  switch (sortBy.value) {
    case 'name_asc':
      list.sort((a, b) => (a.name || '').localeCompare(b.name || ''))
      break
    case 'name_desc':
      list.sort((a, b) => (b.name || '').localeCompare(a.name || ''))
      break
    case 'date_new':
      list.sort((a, b) => new Date(b.created_at) - new Date(a.created_at))
      break
    case 'date_old':
      list.sort((a, b) => new Date(a.created_at) - new Date(b.created_at))
      break
    case 'participants_desc':
      list.sort((a, b) => (b.participant_count || 0) - (a.participant_count || 0))
      break
    case 'participants_asc':
      list.sort((a, b) => (a.participant_count || 0) - (b.participant_count || 0))
      break
    case 'active':
    default:
      list.sort((a, b) => {
        const aActive = (a.is_playing ? 1 : 0) + (a.participant_count || 0)
        const bActive = (b.is_playing ? 1 : 0) + (b.participant_count || 0)
        if (bActive !== aActive) return bActive - aActive
        return new Date(b.created_at) - new Date(a.created_at)
      })
  }

  return list
})

const topRouteLabel = computed(() => {
  const routes = metrics.value.routes || {}
  const entries = Object.entries(routes).map(([route, data]) => ({
    route,
    count: data.count ?? 0,
  }))
  if (!entries.length) return '—'
  entries.sort((a, b) => b.count - a.count)
  return `${entries[0].route} (${entries[0].count})`
})

// Methods
const fetchRooms = async () => {
  try {
    const roomsData = await roomStore.fetchRooms()
    rooms.value = roomsData.data || roomsData || []
  } catch (error) {
    console.error('Failed to fetch rooms:', error)
    showNotification('error', 'Error', 'Failed to load rooms')
  }
}

const fetchMetrics = async () => {
  try {
    const { data } = await api.get('/metrics')
    metrics.value = data.metrics || {}
  } catch (error) {
    console.warn('Failed to fetch metrics:', error)
  }
}

const handleJoinRoom = async room => {
  try {
    await roomStore.joinRoom(room.id)
    showNotification('success', 'Success', `Joined room "${room.name}"`)
    router.push(`/room/${room.id}`)
  } catch (error) {
    console.error('Failed to join room:', error)
    showNotification('error', 'Error', error.message || 'Failed to join room')
  }
}

const handleRoomCreated = room => {
  showNotification('success', 'Success', `Room "${room.name}" created successfully`)
  // Add the new room to the list
  rooms.value.unshift(room)
  // Navigate to the new room
  router.push(`/room/${room.id}`)
}

const handleViewPlaylist = (playlist) => {
  router.push(`/playlist/${playlist.id}`)
}

// Initialize
onMounted(() => {
  fetchRooms()
  fetchMetrics()
  metricsInterval = setInterval(fetchMetrics, 30000)
})

let metricsInterval
onUnmounted(() => {
  if (metricsInterval) {
    clearInterval(metricsInterval)
    metricsInterval = null
  }
})
</script>
