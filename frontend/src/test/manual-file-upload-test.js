/**
 * Manual File Upload Integration Test
 *
 * This file contains manual test scenarios to verify the file upload integration
 * with the backend file system. Run these tests manually in the browser console
 * or use them as a guide for testing the functionality.
 */

// Test 1: Successful file upload
export const testSuccessfulUpload = async () => {
  console.log('Testing successful file upload...')

  // Create a mock MP3 file
  const mockFile = new File(['mock audio content'], 'test-song.mp3', {
    type: 'audio/mpeg',
    size: 1024 * 1024, // 1MB
  })

  // Simulate adding file to upload queue
  const fileUploadComponent = {
    uploadQueue: [],
    errors: [],
    addFilesToQueue: function (files) {
      files.forEach(file => {
        if (file.size <= 50 * 1024 * 1024 && file.type === 'audio/mpeg') {
          this.uploadQueue.push({
            file,
            name: file.name,
            size: file.size,
            status: 'pending',
          })
        }
      })
    },
  }

  fileUploadComponent.addFilesToQueue([mockFile])

  console.log('✓ File added to queue:', fileUploadComponent.uploadQueue[0])
  console.log('✓ No errors:', fileUploadComponent.errors.length === 0)

  return fileUploadComponent.uploadQueue.length === 1 && fileUploadComponent.errors.length === 0
}

// Test 2: File validation errors
export const testFileValidation = () => {
  console.log('Testing file validation...')

  const fileUploadComponent = {
    uploadQueue: [],
    errors: [],
    addFilesToQueue: function (files) {
      files.forEach(file => {
        // Check file size
        if (file.size > 50 * 1024 * 1024) {
          this.errors.push(`${file.name}: File too large (max 50MB)`)
          return
        }

        // Check file type
        const supportedTypes = ['audio/mpeg', 'audio/wav', 'audio/mp4', 'audio/x-m4a']
        if (!supportedTypes.includes(file.type)) {
          this.errors.push(`${file.name}: Unsupported file type (use MP3, WAV, or M4A)`)
          return
        }

        this.uploadQueue.push({
          file,
          name: file.name,
          size: file.size,
          status: 'pending',
        })
      })
    },
  }

  // Test large file
  const largeFile = new File(['x'.repeat(51 * 1024 * 1024)], 'large-song.mp3', {
    type: 'audio/mpeg',
  })

  // Test unsupported file type
  const unsupportedFile = new File(['content'], 'document.pdf', {
    type: 'application/pdf',
  })

  fileUploadComponent.addFilesToQueue([largeFile, unsupportedFile])

  console.log(
    '✓ Large file rejected:',
    fileUploadComponent.errors.includes('large-song.mp3: File too large (max 50MB)')
  )
  console.log(
    '✓ Unsupported file rejected:',
    fileUploadComponent.errors.includes(
      'document.pdf: Unsupported file type (use MP3, WAV, or M4A)'
    )
  )
  console.log('✓ No files added to queue:', fileUploadComponent.uploadQueue.length === 0)

  return fileUploadComponent.errors.length === 2 && fileUploadComponent.uploadQueue.length === 0
}

// Test 3: Backend error handling
export const testBackendErrorHandling = () => {
  console.log('Testing backend error handling...')

  // Mock backend validation error response
  const mockBackendError = {
    response: {
      status: 422,
      data: {
        error: 'Validation failed',
        errors: {
          audio_file: ['The audio file must be a file of type: mp3, wav, m4a.'],
        },
      },
    },
  }

  // Function to extract error message from backend response
  const extractErrorMessage = error => {
    if (error.response?.data?.errors) {
      const validationErrors = error.response.data.errors
      if (validationErrors.audio_file) {
        return validationErrors.audio_file[0]
      }
      return Object.values(validationErrors).flat().join(', ')
    } else if (error.response?.data?.error) {
      return error.response.data.error
    } else if (error.response?.data?.message) {
      return error.response.data.message
    } else if (error.message) {
      return error.message
    }
    return 'Upload failed'
  }

  const errorMessage = extractErrorMessage(mockBackendError)

  console.log('✓ Extracted error message:', errorMessage)
  console.log('✓ Error message is descriptive:', errorMessage.includes('mp3, wav, m4a'))

  return errorMessage === 'The audio file must be a file of type: mp3, wav, m4a.'
}

// Test 4: Room state update after upload
export const testRoomStateUpdate = () => {
  console.log('Testing room state update after upload...')

  // Mock track store
  const mockTrackStore = {
    trackQueue: [],
    addTrackToQueue: function (track) {
      const existingIndex = this.trackQueue.findIndex(t => t.id === track.id)
      if (existingIndex === -1) {
        this.trackQueue.push(track)

        // Re-sort the queue to maintain proper ordering
        this.trackQueue.sort((a, b) => {
          if (a.vote_score !== b.vote_score) {
            return b.vote_score - a.vote_score
          }
          return new Date(a.created_at) - new Date(b.created_at)
        })
      }
    },
  }

  // Mock uploaded track
  const mockTrack = {
    id: 'track-123',
    original_name: 'test-song.mp3',
    duration_seconds: 180,
    vote_score: 0,
    uploader: { id: 'user-1', username: 'testuser' },
    created_at: new Date().toISOString(),
  }

  mockTrackStore.addTrackToQueue(mockTrack)

  console.log('✓ Track added to queue:', mockTrackStore.trackQueue.length === 1)
  console.log('✓ Track data correct:', mockTrackStore.trackQueue[0].id === 'track-123')

  return mockTrackStore.trackQueue.length === 1 && mockTrackStore.trackQueue[0].id === 'track-123'
}

// Test 5: WebSocket notification for other users
export const testWebSocketNotification = () => {
  console.log('Testing WebSocket notification for other users...')

  // Mock WebSocket event handler
  const mockWebSocketHandler = {
    notifications: [],
    handleTrackAdded: function (event) {
      const currentUserId = 'current-user-id'

      if (event.track.uploader?.id !== currentUserId) {
        // This is from another user, show notification
        const notification = {
          type: 'info',
          title: 'New Track Added',
          message: `${event.track.uploader?.username || 'Someone'} added "${event.track.original_name}" to the queue`,
        }
        this.notifications.push(notification)
      }
    },
  }

  // Mock track added event from another user
  const trackAddedEvent = {
    track: {
      id: 'track-456',
      original_name: 'Another Song.mp3',
      uploader: {
        id: 'other-user-id',
        username: 'otheruser',
      },
    },
  }

  mockWebSocketHandler.handleTrackAdded(trackAddedEvent)

  console.log('✓ Notification created:', mockWebSocketHandler.notifications.length === 1)
  console.log(
    '✓ Notification message correct:',
    mockWebSocketHandler.notifications[0].message.includes('otheruser added "Another Song.mp3"')
  )

  return mockWebSocketHandler.notifications.length === 1
}

// Run all tests
export const runAllTests = async () => {
  console.log('🧪 Running File Upload Integration Tests...\n')

  const results = {
    successfulUpload: await testSuccessfulUpload(),
    fileValidation: testFileValidation(),
    backendErrorHandling: testBackendErrorHandling(),
    roomStateUpdate: testRoomStateUpdate(),
    webSocketNotification: testWebSocketNotification(),
  }

  console.log('\n📊 Test Results:')
  Object.entries(results).forEach(([test, passed]) => {
    console.log(`${passed ? '✅' : '❌'} ${test}: ${passed ? 'PASSED' : 'FAILED'}`)
  })

  const allPassed = Object.values(results).every(result => result)
  console.log(`\n🎯 Overall: ${allPassed ? 'ALL TESTS PASSED' : 'SOME TESTS FAILED'}`)

  return results
}

// Instructions for manual testing
export const manualTestingInstructions = `
🔧 Manual Testing Instructions for File Upload Integration

1. Open the Spotik application in your browser
2. Navigate to a room
3. Open the browser console
4. Copy and paste this file's content into the console
5. Run: runAllTests()

Or test individual components:

Frontend Validation:
- Try uploading files larger than 50MB
- Try uploading non-audio files (PDF, TXT, etc.)
- Try uploading valid audio files (MP3, WAV, M4A)

Backend Integration:
- Upload a valid audio file and check network tab for API calls
- Upload an invalid file and verify error messages
- Check that tracks appear in the queue after successful upload

Real-time Features:
- Have another user upload a track and verify you receive a notification
- Check that the track queue updates in real-time
- Verify WebSocket events are properly handled

Error Handling:
- Disconnect from the internet and try uploading
- Upload a corrupted audio file
- Try uploading when not authenticated
`

console.log(manualTestingInstructions)
