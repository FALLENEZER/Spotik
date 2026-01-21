<template>
  <div class="bg-white shadow rounded-lg">
    <div class="px-6 py-4 border-b border-gray-200">
      <h3 class="text-lg font-medium text-gray-900 flex items-center">
        <svg
          class="w-5 h-5 text-gray-400 mr-2"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"
          />
        </svg>
        Upload Music
      </h3>
    </div>

    <div class="px-6 py-4">
      <!-- Upload area -->
      <div
        @drop="handleDrop"
        @dragover="handleDragOver"
        @dragenter="handleDragEnter"
        @dragleave="handleDragLeave"
        @click="triggerFileInput"
        class="relative border-2 border-dashed rounded-lg p-6 text-center cursor-pointer transition-colors"
        :class="[
          isDragging ? 'border-blue-400 bg-blue-50' : 'border-gray-300 hover:border-gray-400',
          uploading ? 'pointer-events-none opacity-50' : '',
        ]"
      >
        <!-- Upload icon and text -->
        <div v-if="!uploading">
          <svg
            class="mx-auto h-12 w-12 text-gray-400"
            stroke="currentColor"
            fill="none"
            viewBox="0 0 48 48"
          >
            <path
              d="M28 8H12a4 4 0 00-4 4v20m32-12v8m0 0v8a4 4 0 01-4 4H12a4 4 0 01-4-4v-4m32-4l-3.172-3.172a4 4 0 00-5.656 0L28 28M8 32l9.172-9.172a4 4 0 015.656 0L28 28m0 0l4 4m4-24h8m-4-4v8m-12 4h.02"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            />
          </svg>
          <div class="mt-4">
            <p class="text-lg font-medium text-gray-900">Drop your music files here</p>
            <p class="mt-2 text-sm text-gray-500">
              or <span class="text-blue-600 font-medium">click to browse</span>
            </p>
            <p class="mt-1 text-xs text-gray-400">Supports MP3, WAV, M4A files up to 50MB</p>
          </div>
        </div>

        <!-- Upload progress -->
        <div v-else class="space-y-4">
          <LoadingSpinner size="lg" />
          <div>
            <p class="text-lg font-medium text-gray-900">Uploading {{ uploadingFile?.name }}...</p>
            <div class="mt-2 bg-gray-200 rounded-full h-2">
              <div
                class="bg-blue-600 h-2 rounded-full transition-all duration-300"
                :style="{ width: `${uploadProgress}%` }"
              ></div>
            </div>
            <p class="mt-1 text-sm text-gray-500">{{ uploadProgress }}% complete</p>
          </div>
        </div>

        <!-- Hidden file input -->
        <input
          ref="fileInput"
          type="file"
          multiple
          accept=".mp3,.wav,.m4a,audio/mpeg,audio/wav,audio/mp4,audio/x-m4a"
          @change="handleFileSelect"
          class="hidden"
        />
      </div>

      <!-- Upload queue -->
      <div v-if="uploadQueue.length > 0" class="mt-6">
        <h4 class="text-sm font-medium text-gray-900 mb-3">Upload Queue</h4>
        <div class="space-y-2">
          <div
            v-for="(file, index) in uploadQueue"
            :key="index"
            class="flex items-center justify-between p-3 bg-gray-50 rounded-lg"
          >
            <div class="flex items-center min-w-0 flex-1">
              <svg
                class="w-5 h-5 text-gray-400 mr-3"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3"
                />
              </svg>
              <div class="min-w-0 flex-1">
                <p class="text-sm font-medium text-gray-900 truncate">
                  {{ file.name }}
                </p>
                <p class="text-xs text-gray-500">
                  {{ formatFileSize(file.size) }}
                </p>
              </div>
            </div>

            <div class="flex items-center space-x-2">
              <!-- Status indicator -->
              <span
                v-if="file.status === 'pending'"
                class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800"
              >
                Pending
              </span>
              <span
                v-else-if="file.status === 'uploading'"
                class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800"
              >
                Uploading...
              </span>
              <span
                v-else-if="file.status === 'success'"
                class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-green-100 text-green-800"
              >
                ✓ Uploaded
              </span>
              <span
                v-else-if="file.status === 'error'"
                class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-red-100 text-red-800"
              >
                ✗ Failed
              </span>

              <!-- Remove/Retry button -->
              <button
                v-if="file.status === 'pending' || file.status === 'error'"
                @click="file.status === 'error' ? retryUpload(index) : removeFromQueue(index)"
                class="p-1 transition-colors"
                :class="
                  file.status === 'error'
                    ? 'text-blue-600 hover:text-blue-800'
                    : 'text-gray-400 hover:text-red-600'
                "
                :title="file.status === 'error' ? 'Retry upload' : 'Remove from queue'"
              >
                <svg
                  v-if="file.status === 'error'"
                  class="w-4 h-4"
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
                <svg v-else class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M6 18L18 6M6 6l12 12"
                  />
                </svg>
              </button>
            </div>
          </div>
        </div>

        <!-- Upload controls -->
        <div class="mt-4 flex items-center justify-between">
          <div class="flex items-center space-x-2">
            <button @click="clearQueue" class="btn-sm btn-outline" :disabled="uploading">
              Clear Queue
            </button>
            <button
              v-if="uploadQueue.filter(f => f.status === 'error').length > 0"
              @click="retryAllFailed"
              class="btn-sm btn-outline text-blue-600 border-blue-600 hover:bg-blue-50"
              :disabled="uploading"
            >
              Retry Failed
            </button>
          </div>
          <button
            @click="startUpload"
            class="btn-sm btn-primary"
            :disabled="uploading || uploadQueue.filter(f => f.status === 'pending').length === 0"
          >
            Upload {{ uploadQueue.filter(f => f.status === 'pending').length }} Files
          </button>
        </div>
      </div>

      <!-- Error messages -->
      <div v-if="errors.length > 0" class="mt-4">
        <div class="bg-red-50 border border-red-200 rounded-md p-4">
          <div class="flex">
            <svg class="w-5 h-5 text-red-400" fill="currentColor" viewBox="0 0 20 20">
              <path
                fill-rule="evenodd"
                d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z"
                clip-rule="evenodd"
              />
            </svg>
            <div class="ml-3">
              <h3 class="text-sm font-medium text-red-800">Upload Errors</h3>
              <div class="mt-2 text-sm text-red-700">
                <ul class="list-disc list-inside space-y-1">
                  <li v-for="error in errors" :key="error">{{ error }}</li>
                </ul>
              </div>
              <button
                @click="clearErrors"
                class="mt-2 text-sm text-red-600 hover:text-red-500 underline"
              >
                Dismiss
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, inject } from 'vue'
import { useTrackStore } from '@/stores/track'
import { useRoomStore } from '@/stores/room'
import LoadingSpinner from '@/components/common/LoadingSpinner.vue'

const trackStore = useTrackStore()
const roomStore = useRoomStore()
const showNotification = inject('showNotification')

// State
const fileInput = ref(null)
const isDragging = ref(false)
const uploading = ref(false)
const uploadingFile = ref(null)
const uploadProgress = ref(0)
const uploadQueue = ref([])
const errors = ref([])

// Constants
const MAX_FILE_SIZE = 50 * 1024 * 1024 // 50MB
const SUPPORTED_TYPES = ['audio/mpeg', 'audio/wav', 'audio/mp4', 'audio/x-m4a']
const SUPPORTED_EXTENSIONS = ['.mp3', '.wav', '.m4a']

// Methods
const triggerFileInput = () => {
  if (!uploading.value) {
    fileInput.value?.click()
  }
}

const handleDragEnter = e => {
  e.preventDefault()
  isDragging.value = true
}

const handleDragOver = e => {
  e.preventDefault()
}

const handleDragLeave = e => {
  e.preventDefault()
  if (!e.currentTarget.contains(e.relatedTarget)) {
    isDragging.value = false
  }
}

const handleDrop = e => {
  e.preventDefault()
  isDragging.value = false

  const files = Array.from(e.dataTransfer.files)
  addFilesToQueue(files)
}

const handleFileSelect = e => {
  const files = Array.from(e.target.files)
  addFilesToQueue(files)

  // Clear the input so the same file can be selected again
  e.target.value = ''
}

const addFilesToQueue = files => {
  const validFiles = []
  const newErrors = []

  files.forEach(file => {
    // Check file size
    if (file.size > MAX_FILE_SIZE) {
      newErrors.push(`${file.name}: File too large (max 50MB)`)
      return
    }

    // Check for empty files
    if (file.size === 0) {
      newErrors.push(`${file.name}: File is empty`)
      return
    }

    // Check file type - be more strict to match backend validation
    const isValidType =
      SUPPORTED_TYPES.includes(file.type) ||
      SUPPORTED_EXTENSIONS.some(ext => file.name.toLowerCase().endsWith(ext))

    if (!isValidType) {
      newErrors.push(`${file.name}: Unsupported file type (use MP3, WAV, or M4A)`)
      return
    }

    // Additional validation for common non-audio files that might have wrong extensions
    const fileName = file.name.toLowerCase()
    const suspiciousExtensions = [
      '.txt',
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.pdf',
      '.doc',
      '.docx',
      '.zip',
      '.exe',
    ]
    const hasSuspiciousExtension = suspiciousExtensions.some(ext => fileName.includes(ext))

    if (hasSuspiciousExtension) {
      newErrors.push(`${file.name}: Invalid file type detected`)
      return
    }

    // Check if file already in queue
    if (
      uploadQueue.value.some(
        queuedFile => queuedFile.name === file.name && queuedFile.size === file.size
      )
    ) {
      newErrors.push(`${file.name}: File already in queue`)
      return
    }

    validFiles.push({
      file,
      name: file.name,
      size: file.size,
      status: 'pending',
    })
  })

  // Add valid files to queue
  uploadQueue.value.push(...validFiles)

  // Show errors if any
  if (newErrors.length > 0) {
    errors.value.push(...newErrors)
  }

  // Auto-upload if only one file and no errors
  if (validFiles.length === 1 && newErrors.length === 0 && uploadQueue.value.length === 1) {
    startUpload()
  }
}

const removeFromQueue = index => {
  uploadQueue.value.splice(index, 1)
}

const retryUpload = index => {
  const file = uploadQueue.value[index]
  if (file && file.status === 'error') {
    file.status = 'pending'
    // Remove the error message for this file
    errors.value = errors.value.filter(error => !error.startsWith(`${file.name}:`))
  }
}

const retryAllFailed = () => {
  uploadQueue.value.forEach((file, index) => {
    if (file.status === 'error') {
      retryUpload(index)
    }
  })
}

const clearQueue = () => {
  uploadQueue.value = uploadQueue.value.filter(file => file.status === 'uploading')
}

const clearErrors = () => {
  errors.value = []
}

const startUpload = async () => {
  const pendingFiles = uploadQueue.value.filter(file => file.status === 'pending')

  if (pendingFiles.length === 0) return

  uploading.value = true

  for (const queuedFile of pendingFiles) {
    try {
      queuedFile.status = 'uploading'
      uploadingFile.value = queuedFile
      uploadProgress.value = 0

      // Simulate progress updates
      const progressInterval = setInterval(() => {
        if (uploadProgress.value < 90) {
          uploadProgress.value += Math.random() * 10
        }
      }, 200)

      // Upload track to backend
      const uploadedTrack = await trackStore.uploadTrack(roomStore.currentRoom.id, queuedFile.file)

      clearInterval(progressInterval)
      uploadProgress.value = 100

      queuedFile.status = 'success'

      // Show success notification with track details
      showNotification(
        'success',
        'Upload Successful',
        `${queuedFile.name} has been added to the queue`
      )

      // Update room state - the track should already be added via WebSocket events
      // but we can ensure it's in the queue locally as well
      if (uploadedTrack && !trackStore.trackQueue.find(t => t.id === uploadedTrack.id)) {
        trackStore.addTrackToQueue(uploadedTrack)
      }
    } catch (error) {
      queuedFile.status = 'error'

      // Handle different types of backend errors
      let errorMessage = 'Upload failed'

      if (error.response?.data?.errors) {
        // Laravel validation errors
        const validationErrors = error.response.data.errors
        if (validationErrors.audio_file) {
          errorMessage = validationErrors.audio_file[0]
        } else {
          errorMessage = Object.values(validationErrors).flat().join(', ')
        }
      } else if (error.response?.data?.error) {
        // General error message from backend
        errorMessage = error.response.data.error
      } else if (error.response?.data?.message) {
        // Laravel exception message
        errorMessage = error.response.data.message
      } else if (error.message) {
        // Network or other errors
        errorMessage = error.message
      }

      errors.value.push(`${queuedFile.name}: ${errorMessage}`)
      showNotification('error', 'Upload Failed', `${queuedFile.name}: ${errorMessage}`)
    }
  }

  uploading.value = false
  uploadingFile.value = null
  uploadProgress.value = 0

  // Remove successful uploads from queue after a delay
  setTimeout(() => {
    uploadQueue.value = uploadQueue.value.filter(file => file.status !== 'success')
  }, 3000)
}

const formatFileSize = bytes => {
  if (!bytes) return '0 B'

  const sizes = ['B', 'KB', 'MB', 'GB']
  const i = Math.floor(Math.log(bytes) / Math.log(1024))
  return `${(bytes / Math.pow(1024, i)).toFixed(1)} ${sizes[i]}`
}
</script>
