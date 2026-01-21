<template>
  <div
    v-if="show"
    class="fixed inset-0 bg-gray-600 bg-opacity-50 overflow-y-auto h-full w-full z-50"
    @click="handleBackdropClick"
  >
    <div class="relative top-20 mx-auto p-5 border w-96 shadow-lg rounded-md bg-white">
      <div class="mt-3">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-lg font-medium text-gray-900">Create New Room</h3>
          <button type="button" class="text-gray-400 hover:text-gray-600" @click="$emit('close')">
            <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M6 18L18 6M6 6l12 12"
              />
            </svg>
          </button>
        </div>

        <form @submit.prevent="handleSubmit">
          <div class="mb-4">
            <label for="roomName" class="form-label">Room Name</label>
            <input
              id="roomName"
              v-model="form.name"
              type="text"
              class="form-input"
              :class="{ 'border-red-500': errors.name }"
              placeholder="Enter room name"
              required
            />
            <p v-if="errors.name" class="form-error">{{ errors.name }}</p>
          </div>

          <div class="mb-6">
            <label for="roomDescription" class="form-label">Description (Optional)</label>
            <textarea
              id="roomDescription"
              v-model="form.description"
              class="form-input"
              :class="{ 'border-red-500': errors.description }"
              rows="3"
              placeholder="Describe your room..."
            ></textarea>
            <p v-if="errors.description" class="form-error">{{ errors.description }}</p>
          </div>

          <div class="flex justify-end space-x-3">
            <button type="button" class="btn-outline" @click="$emit('close')" :disabled="loading">
              Cancel
            </button>
            <button type="submit" class="btn-primary" :disabled="loading || !form.name.trim()">
              <LoadingSpinner v-if="loading" class="mr-2" />
              {{ loading ? 'Creating...' : 'Create Room' }}
            </button>
          </div>
        </form>

        <div v-if="error" class="mt-4 p-3 bg-red-50 border border-red-200 rounded-md">
          <p class="text-sm text-red-600">{{ error }}</p>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, watch } from 'vue'
import { useRoomStore } from '@/stores/room'
import LoadingSpinner from '@/components/common/LoadingSpinner.vue'

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
})

const emit = defineEmits(['close', 'created'])

const roomStore = useRoomStore()

// Form state
const form = reactive({
  name: '',
  description: '',
})

const errors = reactive({
  name: '',
  description: '',
})

const loading = ref(false)
const error = ref('')

// Reset form when modal opens/closes
watch(
  () => props.show,
  newValue => {
    if (newValue) {
      resetForm()
    }
  }
)

const resetForm = () => {
  form.name = ''
  form.description = ''
  errors.name = ''
  errors.description = ''
  error.value = ''
  loading.value = false
}

const validateForm = () => {
  let isValid = true

  // Reset errors
  errors.name = ''
  errors.description = ''

  // Validate name
  if (!form.name.trim()) {
    errors.name = 'Room name is required'
    isValid = false
  } else if (form.name.trim().length < 3) {
    errors.name = 'Room name must be at least 3 characters'
    isValid = false
  } else if (form.name.trim().length > 50) {
    errors.name = 'Room name must be less than 50 characters'
    isValid = false
  }

  // Validate description (optional)
  if (form.description && form.description.length > 200) {
    errors.description = 'Description must be less than 200 characters'
    isValid = false
  }

  return isValid
}

const handleSubmit = async () => {
  if (!validateForm()) {
    return
  }

  loading.value = true
  error.value = ''

  try {
    const roomData = {
      name: form.name.trim(),
      description: form.description.trim() || null,
    }

    const room = await roomStore.createRoom(roomData)

    emit('created', room)
    emit('close')
  } catch (err) {
    error.value = err.message || 'Failed to create room'
  } finally {
    loading.value = false
  }
}

const handleBackdropClick = event => {
  if (event.target === event.currentTarget) {
    emit('close')
  }
}
</script>
