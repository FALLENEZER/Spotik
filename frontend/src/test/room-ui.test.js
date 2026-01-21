import { describe, it, expect, beforeEach, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { createRouter, createWebHistory } from 'vue-router'
import RoomList from '@/components/room/RoomList.vue'
import CreateRoomModal from '@/components/room/CreateRoomModal.vue'
import Breadcrumbs from '@/components/common/Breadcrumbs.vue'

// Mock router
const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', component: { template: '<div>Home</div>' } },
    { path: '/dashboard', component: { template: '<div>Dashboard</div>' } },
  ],
})

describe('Room UI Components', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  describe('RoomList', () => {
    it('renders empty state when no rooms', () => {
      const wrapper = mount(RoomList, {
        props: {
          rooms: [],
          loading: false,
          error: '',
        },
      })

      expect(wrapper.text()).toContain('No rooms available')
    })

    it('renders loading state', () => {
      const wrapper = mount(RoomList, {
        props: {
          rooms: [],
          loading: true,
          error: '',
        },
      })

      expect(wrapper.find('.spinner')).toBeTruthy()
    })

    it('renders room cards when rooms provided', () => {
      const mockRooms = [
        {
          id: '1',
          name: 'Test Room',
          description: 'A test room',
          is_playing: false,
          participant_count: 2,
          track_count: 5,
          administrator: { username: 'testuser' },
          created_at: '2024-01-01T00:00:00Z',
        },
      ]

      const wrapper = mount(RoomList, {
        props: {
          rooms: mockRooms,
          loading: false,
          error: '',
        },
      })

      expect(wrapper.text()).toContain('Test Room')
      expect(wrapper.text()).toContain('A test room')
      expect(wrapper.text()).toContain('2 participants')
      expect(wrapper.text()).toContain('5 tracks')
    })

    it('emits join event when join button clicked', async () => {
      const mockRooms = [
        {
          id: '1',
          name: 'Test Room',
          description: 'A test room',
          is_playing: false,
          participant_count: 2,
          track_count: 5,
          administrator: { username: 'testuser' },
          created_at: '2024-01-01T00:00:00Z',
        },
      ]

      const wrapper = mount(RoomList, {
        props: {
          rooms: mockRooms,
          loading: false,
          error: '',
        },
      })

      const joinButton = wrapper.find('button')
      await joinButton.trigger('click')

      expect(wrapper.emitted('join')).toBeTruthy()
      expect(wrapper.emitted('join')[0]).toEqual([mockRooms[0]])
    })
  })

  describe('CreateRoomModal', () => {
    it('renders when show prop is true', () => {
      const wrapper = mount(CreateRoomModal, {
        props: {
          show: true,
        },
        global: {
          stubs: {
            LoadingSpinner: true,
          },
        },
      })

      expect(wrapper.text()).toContain('Create New Room')
      expect(wrapper.find('input[type="text"]').exists()).toBe(true)
      expect(wrapper.find('textarea').exists()).toBe(true)
    })

    it('does not render when show prop is false', () => {
      const wrapper = mount(CreateRoomModal, {
        props: {
          show: false,
        },
      })

      expect(wrapper.find('.fixed').exists()).toBe(false)
    })

    it('validates required room name', async () => {
      const wrapper = mount(CreateRoomModal, {
        props: {
          show: true,
        },
        global: {
          stubs: {
            LoadingSpinner: true,
          },
        },
      })

      const form = wrapper.find('form')
      await form.trigger('submit')

      // Should show validation error for empty name
      expect(wrapper.text()).toContain('Room name is required')
    })

    it('emits close event when cancel button clicked', async () => {
      const wrapper = mount(CreateRoomModal, {
        props: {
          show: true,
        },
        global: {
          stubs: {
            LoadingSpinner: true,
          },
        },
      })

      const cancelButton = wrapper.find('button[type="button"]')
      await cancelButton.trigger('click')

      expect(wrapper.emitted('close')).toBeTruthy()
    })
  })

  describe('Breadcrumbs', () => {
    it('renders breadcrumb items', async () => {
      const wrapper = mount(Breadcrumbs, {
        props: {
          items: [{ name: 'Dashboard', to: '/dashboard' }, { name: 'Room 1' }],
        },
        global: {
          plugins: [router],
        },
      })

      expect(wrapper.text()).toContain('Dashboard')
      expect(wrapper.text()).toContain('Room 1')
    })

    it('renders links for items with "to" property', async () => {
      const wrapper = mount(Breadcrumbs, {
        props: {
          items: [{ name: 'Dashboard', to: '/dashboard' }, { name: 'Room 1' }],
        },
        global: {
          plugins: [router],
        },
      })

      const links = wrapper.findAll('a')
      expect(links.length).toBe(1)
      expect(links[0].text()).toBe('Dashboard')
    })

    it('renders last item as plain text', async () => {
      const wrapper = mount(Breadcrumbs, {
        props: {
          items: [{ name: 'Dashboard', to: '/dashboard' }, { name: 'Room 1' }],
        },
        global: {
          plugins: [router],
        },
      })

      const spans = wrapper.findAll('span')
      const lastSpan = spans[spans.length - 1]
      expect(lastSpan.text()).toBe('Room 1')
    })
  })
})
