<template>
  <div class="text-center">
    <!-- Hero section -->
    <div class="max-w-4xl mx-auto">
      <h1 class="text-4xl font-bold text-gray-900 sm:text-6xl">
        Listen to Music
        <span class="text-indigo-600">Together</span>
      </h1>
      <p class="mt-6 text-lg leading-8 text-gray-600">
        Create rooms, upload your favorite tracks, and enjoy synchronized music listening with
        friends from anywhere in the world.
      </p>
      <div class="mt-10 flex items-center justify-center gap-x-6">
        <router-link
          to="/register"
          class="rounded-md bg-indigo-600 px-3.5 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
        >
          Get Started
        </router-link>
        <router-link to="/login" class="text-sm font-semibold leading-6 text-gray-900">
          Sign In <span aria-hidden="true">→</span>
        </router-link>
      </div>
    </div>

    <!-- Features section -->
    <div class="mt-20">
      <div class="grid grid-cols-1 gap-8 sm:grid-cols-2 lg:grid-cols-3">
        <div class="text-center">
          <div class="mx-auto h-12 w-12 flex items-center justify-center rounded-lg bg-indigo-600">
            <svg
              class="h-6 w-6 text-white"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636"
              />
            </svg>
          </div>
          <h3 class="mt-4 text-lg font-semibold text-gray-900">Real-time Sync</h3>
          <p class="mt-2 text-gray-600">
            Everyone hears the same music at exactly the same time, no matter where they are.
          </p>
        </div>

        <div class="text-center">
          <div class="mx-auto h-12 w-12 flex items-center justify-center rounded-lg bg-indigo-600">
            <svg
              class="h-6 w-6 text-white"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5M16.5 12L12 16.5m0 0L7.5 12m4.5 4.5V3"
              />
            </svg>
          </div>
          <h3 class="mt-4 text-lg font-semibold text-gray-900">Upload & Share</h3>
          <p class="mt-2 text-gray-600">
            Upload your favorite tracks and share them with friends in your room.
          </p>
        </div>

        <div class="text-center">
          <div class="mx-auto h-12 w-12 flex items-center justify-center rounded-lg bg-indigo-600">
            <svg
              class="h-6 w-6 text-white"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M6.633 10.5c.806 0 1.533-.446 2.031-1.08a9.041 9.041 0 012.861-2.4c.723-.384 1.35-.956 1.653-1.715a4.498 4.498 0 00.322-1.672V3a.75.75 0 01.75-.75A2.25 2.25 0 0116.5 4.5c0 1.152-.26 2.243-.723 3.218-.266.558.107 1.282.725 1.282h3.126c1.026 0 1.945.694 2.054 1.715.045.422.068.85.068 1.285a11.95 11.95 0 01-2.649 7.521c-.388.482-.987.729-1.605.729H13.48c-.483 0-.964-.078-1.423-.23l-3.114-.971a6.043 6.043 0 01-4.276-5.795 6.052 6.052 0 011.966-4.484z"
              />
            </svg>
          </div>
          <h3 class="mt-4 text-lg font-semibold text-gray-900">Vote & Queue</h3>
          <p class="mt-2 text-gray-600">
            Vote for your favorite tracks to move them up in the queue.
          </p>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
// Home page component - no additional logic needed for now
</script>
