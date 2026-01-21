import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import FileUpload from '@/components/room/FileUpload.vue'
import { useTrackStore } from '@/stores/track'
import { useRoomStore } from '@/stores/room'

// Mock API
vi.mock('@/services/api', () => ({
  default: {
    post: vi.fn(),
  },
}))

// Mock notification
const mockShowNotification = vi.fn()

describe('FileUpload Integration', () => {
  let wrapper
  let trackStore
  let roomStore

  beforeEach(() => {
    setActivePinia(createPinia())
    trackStore = useTrackStore()
    roomStore = useRoomStore()

    // Set up room state
    roomStore.currentRoom = {
      id: 'room-123',
      name: 'Test Room',
    }

    wrapper = mount(FileUpload, {
      global: {
        provide: {
          showNotification: mockShowNotification,
        },
      },
    })
  })

  afterEach(() => {
    vi.clearAllMocks()
  })

  describe('Backend Integration', () => {
    it('handles successful upload with proper backend response', async () => {
      const mockTrack = {
        id: 'track-123',
        original_name: 'test-song.mp3',
        duration_seconds: 180,
        vote_score: 0,
        uploader: { id: 'user-1', username: 'testuser' },
        file_url: '/api/tracks/track-123/stream',
      }

      // Mock successful API response
      const mockApi = await import('@/services/api')
      mockApi.default.post.mockResolvedValue({
        data: {
          track: mockTrack,
          message: 'Track uploaded successfully',
        },
      })

      // Create a mock file
      const mockFile = new File(['audio content'], 'test-song.mp3', {
        type: 'audio/mpeg',
      })

      // Add file to queue
      const component = wrapper.vm
      component.addFilesToQueue([mockFile])

      expect(component.uploadQueue).toHaveLength(1)
      expect(component.uploadQueue[0].status).toBe('pending')

      // Start upload
      await component.startUpload()

      // Verify API was called correctly
      expect(mockApi.default.post).toHaveBeenCalledWith(
        '/rooms/room-123/tracks',
        expect.any(FormData),
        {
          headers: {
            'Content-Type': 'multipart/form-data',
          },
        }
      )

      // Verify track was added to store
      expect(trackStore.trackQueue).toContainEqual(mockTrack)

      // Verify success notification
      expect(mockShowNotification).toHaveBeenCalledWith(
        'success',
        'Upload Successful',
        'test-song.mp3 has been added to the queue'
      )

      // Verify upload queue status
      expect(component.uploadQueue[0].status).toBe('success')
    })

    it('handles backend validation errors correctly', async () => {
      // Mock validation error response
      const mockApi = await import('@/services/api')
      mockApi.default.post.mockRejectedValue({
        response: {
          status: 422,
          data: {
            error: 'Validation failed',
            errors: {
              audio_file: ['The audio file must be a file of type: mp3, wav, m4a.'],
            },
          },
        },
      })

      // Create a mock file
      const mockFile = new File(['not audio'], 'test.txt', {
        type: 'text/plain',
      })

      // Add file to queue (should pass frontend validation for this test)
      const component = wrapper.vm
      component.uploadQueue = [
        {
          file: mockFile,
          name: 'test.txt',
          size: mockFile.size,
          status: 'pending',
        },
      ]

      // Start upload
      await component.startUpload()

      // Verify error handling
      expect(component.uploadQueue[0].status).toBe('error')
      expect(component.errors).toContain(
        'test.txt: The audio file must be a file of type: mp3, wav, m4a.'
      )

      // Verify error notification
      expect(mockShowNotification).toHaveBeenCalledWith(
        'error',
        'Upload Failed',
        'test.txt: The audio file must be a file of type: mp3, wav, m4a.'
      )
    })

    it('handles network errors correctly', async () => {
      // Mock network error
      const mockApi = await import('@/services/api')
      mockApi.default.post.mockRejectedValue({
        message: 'Network Error',
      })

      // Create a mock file
      const mockFile = new File(['audio content'], 'test-song.mp3', {
        type: 'audio/mpeg',
      })

      // Add file to queue
      const component = wrapper.vm
      component.uploadQueue = [
        {
          file: mockFile,
          name: 'test-song.mp3',
          size: mockFile.size,
          status: 'pending',
        },
      ]

      // Start upload
      await component.startUpload()

      // Verify error handling
      expect(component.uploadQueue[0].status).toBe('error')
      expect(component.errors).toContain('test-song.mp3: Network Error')
    })

    it('handles file size validation', () => {
      // Create a file that's too large (over 50MB)
      const largeFile = new File(['x'.repeat(51 * 1024 * 1024)], 'large-song.mp3', {
        type: 'audio/mpeg',
      })

      const component = wrapper.vm
      component.addFilesToQueue([largeFile])

      // Should not be added to queue
      expect(component.uploadQueue).toHaveLength(0)
      expect(component.errors).toContain('large-song.mp3: File too large (max 50MB)')
    })

    it('handles empty file validation', () => {
      // Create an empty file
      const emptyFile = new File([], 'empty-song.mp3', {
        type: 'audio/mpeg',
      })

      const component = wrapper.vm
      component.addFilesToQueue([emptyFile])

      // Should not be added to queue
      expect(component.uploadQueue).toHaveLength(0)
      expect(component.errors).toContain('empty-song.mp3: File is empty')
    })

    it('handles unsupported file types', () => {
      // Create an unsupported file
      const unsupportedFile = new File(['content'], 'document.pdf', {
        type: 'application/pdf',
      })

      const component = wrapper.vm
      component.addFilesToQueue([unsupportedFile])

      // Should not be added to queue
      expect(component.uploadQueue).toHaveLength(0)
      expect(component.errors).toContain(
        'document.pdf: Unsupported file type (use MP3, WAV, or M4A)'
      )
    })

    it('supports retry functionality for failed uploads', async () => {
      const component = wrapper.vm

      // Add a failed upload to queue
      component.uploadQueue = [
        {
          file: new File(['audio'], 'test.mp3', { type: 'audio/mpeg' }),
          name: 'test.mp3',
          size: 1000,
          status: 'error',
        },
      ]
      component.errors = ['test.mp3: Upload failed']

      // Retry the upload
      component.retryUpload(0)

      // Verify status changed to pending and error was removed
      expect(component.uploadQueue[0].status).toBe('pending')
      expect(component.errors).not.toContain('test.mp3: Upload failed')
    })

    it('supports retry all failed uploads', () => {
      const component = wrapper.vm

      // Add multiple failed uploads
      component.uploadQueue = [
        {
          file: new File(['audio1'], 'test1.mp3', { type: 'audio/mpeg' }),
          name: 'test1.mp3',
          size: 1000,
          status: 'error',
        },
        {
          file: new File(['audio2'], 'test2.mp3', { type: 'audio/mpeg' }),
          name: 'test2.mp3',
          size: 1000,
          status: 'success',
        },
        {
          file: new File(['audio3'], 'test3.mp3', { type: 'audio/mpeg' }),
          name: 'test3.mp3',
          size: 1000,
          status: 'error',
        },
      ]

      // Retry all failed
      component.retryAllFailed()

      // Verify only failed uploads were retried
      expect(component.uploadQueue[0].status).toBe('pending')
      expect(component.uploadQueue[1].status).toBe('success') // unchanged
      expect(component.uploadQueue[2].status).toBe('pending')
    })
  })

  describe('Room State Integration', () => {
    it('updates track queue after successful upload', async () => {
      const mockTrack = {
        id: 'track-123',
        original_name: 'test-song.mp3',
        duration_seconds: 180,
        vote_score: 0,
      }

      // Mock successful upload
      trackStore.uploadTrack = vi.fn().mockResolvedValue(mockTrack)

      const component = wrapper.vm
      const mockFile = new File(['audio'], 'test-song.mp3', { type: 'audio/mpeg' })

      component.uploadQueue = [
        {
          file: mockFile,
          name: 'test-song.mp3',
          size: 1000,
          status: 'pending',
        },
      ]

      await component.startUpload()

      // Verify track was added to queue
      expect(trackStore.trackQueue).toContainEqual(mockTrack)
    })
  })
})
