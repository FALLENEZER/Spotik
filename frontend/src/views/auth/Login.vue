<template>
  <div class="min-h-full flex flex-col justify-center py-12 sm:px-6 lg:px-8">
    <div class="sm:mx-auto sm:w-full sm:max-w-md">
      <div class="mx-auto h-12 w-12 flex items-center justify-center rounded-lg bg-indigo-600">
        <span class="text-white font-bold text-xl">S</span>
      </div>
      <h2 class="mt-6 text-center text-3xl font-bold tracking-tight text-gray-900">
        Sign in to your account
      </h2>
      <p class="mt-2 text-center text-sm text-gray-600">
        Or
        <router-link to="/register" class="font-medium text-indigo-600 hover:text-indigo-500">
          create a new account
        </router-link>
      </p>
    </div>

    <div class="mt-8 sm:mx-auto sm:w-full sm:max-w-md">
      <div class="bg-white py-8 px-4 shadow sm:rounded-lg sm:px-10">
        <form @submit.prevent="handleLogin" class="space-y-6">
          <div>
            <label for="email" class="form-label"> Email address </label>
            <div class="mt-1">
              <input
                id="email"
                v-model="form.email"
                name="email"
                type="email"
                autocomplete="email"
                required
                class="form-input"
                :class="{ 'border-red-300': errors.email }"
              />
              <p v-if="errors.email" class="form-error">
                {{ errors.email }}
              </p>
            </div>
          </div>

          <div>
            <label for="password" class="form-label"> Password </label>
            <div class="mt-1">
              <input
                id="password"
                v-model="form.password"
                name="password"
                type="password"
                autocomplete="current-password"
                required
                class="form-input"
                :class="{ 'border-red-300': errors.password }"
              />
              <p v-if="errors.password" class="form-error">
                {{ errors.password }}
              </p>
            </div>
          </div>

          <div v-if="authStore.error" class="rounded-md bg-red-50 p-4">
            <div class="flex">
              <div class="flex-shrink-0">
                <XCircleIcon class="h-5 w-5 text-red-400" />
              </div>
              <div class="ml-3">
                <h3 class="text-sm font-medium text-red-800">Login failed</h3>
                <div class="mt-2 text-sm text-red-700">
                  {{ authStore.error }}
                </div>
              </div>
            </div>
          </div>

          <div>
            <button type="submit" :disabled="authStore.loading" class="btn-primary w-full">
              <div v-if="authStore.loading" class="spinner mr-2"></div>
              Sign in
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<script setup>
import { reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { XCircleIcon } from '@heroicons/vue/24/outline'

const router = useRouter()
const authStore = useAuthStore()

// Form data
const form = reactive({
  email: '',
  password: '',
})

// Form validation errors
const errors = ref({})

// Validate form
const validateForm = () => {
  errors.value = {}

  if (!form.email) {
    errors.value.email = 'Email is required'
  } else if (!/\S+@\S+\.\S+/.test(form.email)) {
    errors.value.email = 'Email is invalid'
  }

  if (!form.password) {
    errors.value.password = 'Password is required'
  } else if (form.password.length < 6) {
    errors.value.password = 'Password must be at least 6 characters'
  }

  return Object.keys(errors.value).length === 0
}

// Handle login
const handleLogin = async () => {
  if (!validateForm()) return

  const result = await authStore.login({
    email: form.email,
    password: form.password,
  })

  if (result.success) {
    // Check for redirect query parameter
    const redirectPath = router.currentRoute.value.query.redirect || '/dashboard'
    router.push(redirectPath)
  }
}
</script>
