<template>
  <div v-if="password" class="mt-2">
    <!-- Strength bar -->
    <div class="flex space-x-1 mb-2">
      <div
        v-for="i in 4"
        :key="i"
        class="h-1 flex-1 rounded-full transition-colors duration-200"
        :class="getBarColor(i)"
      ></div>
    </div>

    <!-- Strength text -->
    <div class="flex items-center justify-between text-xs">
      <span :class="getTextColor()">
        {{ strengthText }}
      </span>
      <span class="text-gray-500"> {{ password.length }}/{{ minLength }}+ characters </span>
    </div>

    <!-- Requirements checklist -->
    <div v-if="showRequirements" class="mt-2 space-y-1">
      <div
        v-for="requirement in requirements"
        :key="requirement.key"
        class="flex items-center text-xs"
        :class="requirement.met ? 'text-green-600' : 'text-gray-500'"
      >
        <CheckIcon v-if="requirement.met" class="h-3 w-3 mr-1" />
        <XMarkIcon v-else class="h-3 w-3 mr-1" />
        {{ requirement.text }}
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { CheckIcon, XMarkIcon } from '@heroicons/vue/24/outline'

const props = defineProps({
  password: {
    type: String,
    default: '',
  },
  minLength: {
    type: Number,
    default: 8,
  },
  showRequirements: {
    type: Boolean,
    default: true,
  },
})

// Password strength calculation
const strength = computed(() => {
  if (!props.password) return 0

  let score = 0
  const password = props.password

  // Length check
  if (password.length >= props.minLength) score += 1
  if (password.length >= 12) score += 1

  // Character variety checks
  if (/[a-z]/.test(password)) score += 1
  if (/[A-Z]/.test(password)) score += 1
  if (/[0-9]/.test(password)) score += 1
  if (/[^A-Za-z0-9]/.test(password)) score += 1

  // Bonus for longer passwords
  if (password.length >= 16) score += 1

  return Math.min(score, 4)
})

// Requirements checklist
const requirements = computed(() => [
  {
    key: 'length',
    text: `At least ${props.minLength} characters`,
    met: props.password.length >= props.minLength,
  },
  {
    key: 'lowercase',
    text: 'Contains lowercase letter',
    met: /[a-z]/.test(props.password),
  },
  {
    key: 'uppercase',
    text: 'Contains uppercase letter',
    met: /[A-Z]/.test(props.password),
  },
  {
    key: 'number',
    text: 'Contains number',
    met: /[0-9]/.test(props.password),
  },
  {
    key: 'special',
    text: 'Contains special character',
    met: /[^A-Za-z0-9]/.test(props.password),
  },
])

// Strength text
const strengthText = computed(() => {
  switch (strength.value) {
    case 0:
    case 1:
      return 'Weak'
    case 2:
      return 'Fair'
    case 3:
      return 'Good'
    case 4:
      return 'Strong'
    default:
      return 'Weak'
  }
})

// Bar colors
const getBarColor = index => {
  if (index <= strength.value) {
    switch (strength.value) {
      case 1:
        return 'bg-red-500'
      case 2:
        return 'bg-yellow-500'
      case 3:
        return 'bg-blue-500'
      case 4:
        return 'bg-green-500'
      default:
        return 'bg-gray-200'
    }
  }
  return 'bg-gray-200'
}

// Text colors
const getTextColor = () => {
  switch (strength.value) {
    case 1:
      return 'text-red-600'
    case 2:
      return 'text-yellow-600'
    case 3:
      return 'text-blue-600'
    case 4:
      return 'text-green-600'
    default:
      return 'text-gray-500'
  }
}
</script>
