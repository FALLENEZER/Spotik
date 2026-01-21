import { describe, it, expect, beforeEach, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import PlaybackControls from '@/components/room/PlaybackControls.vue'
import { useRoomStore } from '@/stores/room'
import { useTrackStore } from '@/stores/track'
import { usePlaybackStore } from '@/stores/playback'

// Mock the API
vi.mock('@/services/api', () => ({
  default: {
    post: vi.fn(),
    get: vi.fn(),
  },
}))

// Mock the AudioPlayer component
vi.mock('@/components/audio/AudioPlayer.vue', () => ({
  default: {
    name: 'AudioPlayer',
    template: '<div data-testid="audio-player">Audio Player Mock</div>',
    props: ['show-debug-info'],
  },
}))

// Mock the LoadingSpinner component
vi.mock('@/components/common/LoadingSpinner.vue', () => ({
  default: {
    name: 'LoadingSpinner',
    template: '<div data-testid="loading-spinner">Loading...</div>',
    props: ['size', 'class'],
  },
}))

describe('PlaybackControls', () => {
  let wrapper
  let roomStore
  let trackStore
  let playbackStore
  let mockShowNotification

  beforeEach(() => {
    setActivePinia(createPinia())

    roomStore = useRoomStore()
    trackStore = useTrackStore()
    playbackStore = usePlaybackStore()

    mockShowNotification = vi.fn()

    // Set up mock room data
    roomStore.currentRoom = {
      id: 'room-1',
      name: 'Test Room',
      administrator_id: 'user-1',
    }

    // Mock user as admin by setting the computed property directly
    Object.defineProperty(roomStore, 'isRoomAdmin', {
      get: () => true,
      configurable: true,
    })

    wrapper = mount(PlaybackControls, {
      global: {
        provide: {
          showNotification: mockShowNotification,
        },
      },
    })
  })

  it('renders correctly', () => {
    expect(wrapper.find('[data-testid="audio-player"]').exists()).toBe(true)
    expect(wrapper.text()).toContain('Playback Controls')
  })

  it('shows admin only badge for non-admin users', async () => {
    // Override the admin status
    Object.defineProperty(roomStore, 'isRoomAdmin', {
      get: () => false,
      configurable: true,
    })

    await wrapper.vm.$nextTick()

    expect(wrapper.text()).toContain('Admin Only')
  })

  it('shows correct playback status', async () => {
    // No track selected
    expect(wrapper.text()).toContain('No track selected')

    // Set current track
    trackStore.currentTrack = {
      id: 'track-1',
      original_name: 'Test Track',
      duration_seconds: 180,
    }

    trackStore.playbackState = {
      isPlaying: false,
      position: 0,
      duration: 180,
    }

    await wrapper.vm.$nextTick()
    expect(wrapper.text()).toContain('Paused')

    // Set playing
    trackStore.playbackState.isPlaying = true
    await wrapper.vm.$nextTick()
    expect(wrapper.text()).toContain('Playing')
  })

  it('displays current track information', async () => {
    trackStore.currentTrack = {
      id: 'track-1',
      original_name: 'Test Track',
      duration_seconds: 180,
    }

    trackStore.playbackState = {
      isPlaying: true,
      position: 60,
      duration: 180,
    }

    await wrapper.vm.$nextTick()

    expect(wrapper.text()).toContain('Now Playing')
    expect(wrapper.text()).toContain('Test Track')
    expect(wrapper.text()).toContain('1:00 / 3:00') // 60s / 180s
  })

  it('formats duration correctly', () => {
    const formatDuration = wrapper.vm.formatDuration

    expect(formatDuration(0)).toBe('0:00')
    expect(formatDuration(30)).toBe('0:30')
    expect(formatDuration(60)).toBe('1:00')
    expect(formatDuration(90)).toBe('1:30')
    expect(formatDuration(3661)).toBe('61:01') // 1 hour 1 minute 1 second
  })

  it('exposes playTrack method', () => {
    expect(typeof wrapper.vm.playTrack).toBe('function')
  })
})
