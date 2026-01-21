import { describe, it, expect, beforeEach, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import ParticipantList from '@/components/room/ParticipantList.vue'
import TrackQueue from '@/components/room/TrackQueue.vue'
import FileUpload from '@/components/room/FileUpload.vue'
import PlaybackControls from '@/components/room/PlaybackControls.vue'
import { useRoomStore } from '@/stores/room'
import { useTrackStore } from '@/stores/track'

// Mock the API service
vi.mock('@/services/api', () => ({
  default: {
    get: vi.fn(),
    post: vi.fn(),
    delete: vi.fn(),
  },
}))

// Mock the notification injection
const mockShowNotification = vi.fn()

describe('Room Interface Components', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    vi.clearAllMocks()
  })

  describe('ParticipantList', () => {
    it('renders participant list correctly', () => {
      const roomStore = useRoomStore()

      // Mock participants data
      roomStore.participants = [
        {
          id: '1',
          user: { id: '1', username: 'testuser1' },
          joined_at: new Date().toISOString(),
        },
        {
          id: '2',
          user: { id: '2', username: 'testuser2' },
          joined_at: new Date().toISOString(),
        },
      ]

      roomStore.currentRoom = {
        id: 'room1',
        administrator_id: '1',
      }

      const wrapper = mount(ParticipantList, {
        global: {
          provide: {
            showNotification: mockShowNotification,
          },
        },
      })

      expect(wrapper.text()).toContain('Participants (2)')
      expect(wrapper.text()).toContain('testuser1')
      expect(wrapper.text()).toContain('testuser2')
      expect(wrapper.text()).toContain('Admin')
    })

    it('shows empty state when no participants', () => {
      const roomStore = useRoomStore()
      roomStore.participants = []

      const wrapper = mount(ParticipantList, {
        global: {
          provide: {
            showNotification: mockShowNotification,
          },
        },
      })

      expect(wrapper.text()).toContain('Participants (0)')
      expect(wrapper.text()).toContain('No participants in this room')
    })
  })

  describe('TrackQueue', () => {
    it('renders track queue correctly', () => {
      const trackStore = useTrackStore()

      // Mock track queue data
      trackStore.trackQueue = [
        {
          id: 'track1',
          original_name: 'Test Song 1.mp3',
          duration_seconds: 180,
          file_size_bytes: 5000000,
          vote_score: 5,
          user_has_voted: false,
          uploader: { username: 'uploader1' },
          created_at: new Date().toISOString(),
        },
        {
          id: 'track2',
          original_name: 'Test Song 2.mp3',
          duration_seconds: 240,
          file_size_bytes: 7000000,
          vote_score: 3,
          user_has_voted: true,
          uploader: { username: 'uploader2' },
          created_at: new Date().toISOString(),
        },
      ]

      const wrapper = mount(TrackQueue, {
        global: {
          provide: {
            showNotification: mockShowNotification,
          },
        },
      })

      expect(wrapper.text()).toContain('Track Queue (2)')
      expect(wrapper.text()).toContain('Test Song 1.mp3')
      expect(wrapper.text()).toContain('Test Song 2.mp3')
      expect(wrapper.text()).toContain('3:00') // 180 seconds formatted
      expect(wrapper.text()).toContain('4:00') // 240 seconds formatted
    })

    it('shows empty state when no tracks', () => {
      const trackStore = useTrackStore()
      trackStore.trackQueue = []

      const wrapper = mount(TrackQueue, {
        global: {
          provide: {
            showNotification: mockShowNotification,
          },
        },
      })

      expect(wrapper.text()).toContain('Track Queue (0)')
      expect(wrapper.text()).toContain('No tracks in queue')
      expect(wrapper.text()).toContain('Upload some music to get the party started!')
    })
  })

  describe('FileUpload', () => {
    it('renders file upload interface correctly', () => {
      const wrapper = mount(FileUpload, {
        global: {
          provide: {
            showNotification: mockShowNotification,
          },
        },
      })

      expect(wrapper.text()).toContain('Upload Music')
      expect(wrapper.text()).toContain('Drop your music files here')
      expect(wrapper.text()).toContain('click to browse')
      expect(wrapper.text()).toContain('Supports MP3, WAV, M4A files up to 50MB')
    })

    it('shows upload queue when files are added', async () => {
      const wrapper = mount(FileUpload, {
        global: {
          provide: {
            showNotification: mockShowNotification,
          },
        },
      })

      // Simulate adding files to queue
      const component = wrapper.vm
      component.uploadQueue = [
        {
          name: 'test-song.mp3',
          size: 5000000,
          status: 'pending',
        },
      ]

      await wrapper.vm.$nextTick()

      expect(wrapper.text()).toContain('Upload Queue')
      expect(wrapper.text()).toContain('test-song.mp3')
      expect(wrapper.text()).toContain('Pending')
    })
  })

  describe('PlaybackControls', () => {
    it('renders playback controls correctly', () => {
      const roomStore = useRoomStore()
      const trackStore = useTrackStore()

      roomStore.currentRoom = {
        id: 'room1',
        administrator_id: 'user1',
      }

      roomStore.isRoomAdmin = true

      trackStore.currentTrack = {
        id: 'track1',
        original_name: 'Test Song.mp3',
        duration_seconds: 180,
        file_size_bytes: 5000000,
        uploader: { username: 'testuser' },
      }

      trackStore.playbackState = {
        isPlaying: false,
        startedAt: null,
        pausedAt: null,
        position: 0,
        duration: 180,
      }

      const wrapper = mount(PlaybackControls, {
        global: {
          provide: {
            showNotification: mockShowNotification,
          },
        },
      })

      expect(wrapper.text()).toContain('Playback Controls')
      expect(wrapper.text()).toContain('Test Song.mp3')
      expect(wrapper.text()).toContain('by testuser')
      expect(wrapper.text()).toContain('Paused')
    })

    it('shows no track selected state', () => {
      const roomStore = useRoomStore()
      const trackStore = useTrackStore()

      roomStore.currentRoom = {
        id: 'room1',
        administrator_id: 'user1',
      }

      roomStore.isRoomAdmin = true
      trackStore.currentTrack = null

      const wrapper = mount(PlaybackControls, {
        global: {
          provide: {
            showNotification: mockShowNotification,
          },
        },
      })

      expect(wrapper.text()).toContain('No track selected')
      expect(wrapper.text()).toContain('Select a track from the queue to start playing')
    })

    it('disables controls for non-admin users', () => {
      const roomStore = useRoomStore()
      const trackStore = useTrackStore()

      roomStore.currentRoom = {
        id: 'room1',
        administrator_id: 'admin1',
      }

      roomStore.isRoomAdmin = false
      trackStore.currentTrack = null

      const wrapper = mount(PlaybackControls, {
        global: {
          provide: {
            showNotification: mockShowNotification,
          },
        },
      })

      expect(wrapper.text()).toContain('Admin Only')
      expect(wrapper.text()).toContain('Only room administrators can control playback')
    })
  })
})
