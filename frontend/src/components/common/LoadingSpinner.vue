<template>
  <div class="flex items-center justify-center" :class="containerClass">
    <div class="animate-spin rounded-full border-b-2" :class="[sizeClass, colorClass]"></div>
    <span v-if="text" class="ml-3 text-sm text-gray-600">{{ text }}</span>
  </div>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  size: {
    type: String,
    default: 'md',
    validator: value => ['sm', 'md', 'lg', 'xl'].includes(value),
  },
  color: {
    type: String,
    default: 'indigo',
    validator: value => ['indigo', 'gray', 'white'].includes(value),
  },
  text: {
    type: String,
    default: '',
  },
  center: {
    type: Boolean,
    default: false,
  },
})

const sizeClass = computed(() => {
  const sizes = {
    sm: 'h-4 w-4',
    md: 'h-6 w-6',
    lg: 'h-8 w-8',
    xl: 'h-12 w-12',
  }
  return sizes[props.size]
})

const colorClass = computed(() => {
  const colors = {
    indigo: 'border-indigo-600',
    gray: 'border-gray-600',
    white: 'border-white',
  }
  return colors[props.color]
})

const containerClass = computed(() => {
  return props.center ? 'min-h-[200px]' : ''
})
</script>
