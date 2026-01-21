import { describe, it, expect, vi, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import TrackQueue from '@/components/room/TrackQueue.vue'
import { useTrackStore } from '@/stores/track'
import { useRoomStore } from '@/stores/room'

// Mock the API
vi.mock('@/services/api', () => ({
  default: {
    post: vi.fn(),
    delete: vi.fn(),
  },
}))

describe('Track Voting UI', () => {
  let wrapper
  let trackStore
  let roomStore
  let mockShowNotification

  beforeEach(() => {
    setActivePinia(createPinia())
    trackStore = useTrackStore()
    roomStore = useRoomStore()

    mockShowNotification = vi.fn()

    // Mock room state
    roomStore.currentRoom = {
      id: 'test-room',
      user: { id: 'current-user' },
    }
    roomStore.isRoomAdmin = false

    // Mock track queue with voting data
    trackStore.trackQueue = [
      {
        id: 'track-1',
        room_id: 'test-room',
        original_name: 'Test Song 1.mp3',
        duration_seconds: 180,
        file_size_bytes: 5000000,
        vote_score: 5,
        user_has_voted: false,
        uploader: { username: 'user1' },
        created_at: new Date().toISOString(),
      },
      {
        id: 'track-2',
        room_id: 'test-room',
        original_name: 'Test Song 2.mp3',
        duration_seconds: 240,
        file_size_bytes: 7000000,
        vote_score: 3,
        user_has_voted: true,
        uploader: { username: 'user2' },
        created_at: new Date().toISOString(),
      },
    ]

    wrapper = mount(TrackQueue, {
      global: {
        provide: {
          showNotification: mockShowNotification,
        },
      },
    })
  })

  it('displays vote buttons for each track', () => {
    const voteButtons = wrapper.findAll('[data-testid="vote-button"]')
    expect(voteButtons).toHaveLength(2)
  })

  it('shows correct vote counts', () => {
    const trackItems = wrapper.findAll('.flex.items-center.p-4')

    // First track should show 5 votes
    expect(trackItems[0].text()).toContain('5')

    // Second track should show 3 votes
    expect(trackItems[1].text()).toContain('3')
  })

  it('shows different styles for voted and unvoted tracks', () => {
    const voteButtons = wrapper.findAll('button')
    const voteButtonsFiltered = voteButtons.filter(
      btn => btn.text().includes('5') || btn.text().includes('3')
    )

    expect(voteButtonsFiltered).toHaveLength(2)

    // First track (not voted) should have gray styling
    expect(voteButtonsFiltered[0].classes()).toContain('bg-gray-100')

    // Second track (voted) should have red styling
    expect(voteButtonsFiltered[1].classes()).toContain('bg-red-100')
  })

  it('calls voteForTrack when vote button is clicked', async () => {
    const voteForTrackSpy = vi.spyOn(trackStore, 'voteForTrack').mockResolvedValue({
      voted: true,
      vote_score: 6,
    })

    const voteButtons = wrapper.findAll('button')
    const firstVoteButton = voteButtons.find(btn => btn.text().includes('5'))

    await firstVoteButton.trigger('click')

    expect(voteForTrackSpy).toHaveBeenCalledWith('track-1')
  })

  it('displays tracks in correct order by vote score', () => {
    const trackItems = wrapper.findAll('.flex.items-center.p-4')

    // First track should be the one with higher vote score (5)
    expect(trackItems[0].text()).toContain('Test Song 1.mp3')
    expect(trackItems[0].text()).toContain('5')

    // Second track should be the one with lower vote score (3)
    expect(trackItems[1].text()).toContain('Test Song 2.mp3')
    expect(trackItems[1].text()).toContain('3')
  })

  it('shows loading state when voting', async () => {
    const voteForTrackSpy = vi
      .spyOn(trackStore, 'voteForTrack')
      .mockImplementation(() => new Promise(resolve => setTimeout(resolve, 100)))

    const voteButtons = wrapper.findAll('button')
    const firstVoteButton = voteButtons.find(btn => btn.text().includes('5'))

    await firstVoteButton.trigger('click')

    // Button should be disabled during voting
    expect(firstVoteButton.attributes('disabled')).toBeDefined()
  })
})
