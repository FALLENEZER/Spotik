<template>
  <nav class="flex mb-6" aria-label="Breadcrumb">
    <ol class="inline-flex items-center space-x-1 md:space-x-3">
      <li v-for="(item, index) in items" :key="item.name" class="inline-flex items-center">
        <!-- Separator (not for first item) -->
        <svg
          v-if="index > 0"
          class="w-6 h-6 text-gray-400 mx-1"
          fill="currentColor"
          viewBox="0 0 20 20"
        >
          <path
            fill-rule="evenodd"
            d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z"
            clip-rule="evenodd"
          />
        </svg>

        <!-- Home icon for first item -->
        <svg
          v-if="index === 0"
          class="w-4 h-4 mr-2 text-gray-400"
          fill="currentColor"
          viewBox="0 0 20 20"
        >
          <path
            d="M10.707 2.293a1 1 0 00-1.414 0l-7 7a1 1 0 001.414 1.414L4 10.414V17a1 1 0 001 1h2a1 1 0 001-1v-2a1 1 0 011-1h2a1 1 0 011 1v2a1 1 0 001 1h2a1 1 0 001-1v-6.586l.293.293a1 1 0 001.414-1.414l-7-7z"
          />
        </svg>

        <!-- Link or text -->
        <router-link
          v-if="item.to && index < items.length - 1"
          :to="item.to"
          class="text-sm font-medium text-gray-500 hover:text-gray-700 transition-colors"
        >
          {{ item.name }}
        </router-link>
        <span
          v-else
          class="text-sm font-medium"
          :class="index === items.length - 1 ? 'text-gray-900' : 'text-gray-500'"
        >
          {{ item.name }}
        </span>
      </li>
    </ol>
  </nav>
</template>

<script setup>
defineProps({
  items: {
    type: Array,
    required: true,
    validator: items => {
      return items.every(item => typeof item === 'object' && typeof item.name === 'string')
    },
  },
})
</script>
