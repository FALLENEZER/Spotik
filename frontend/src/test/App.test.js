import { describe, it, expect, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createRouter, createWebHistory } from 'vue-router'
import { createPinia } from 'pinia'
import App from '@/App.vue'

// Create test router
const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', component: { template: '<div>Home</div>' } },
    { path: '/login', component: { template: '<div>Login</div>' } },
  ],
})

describe('App.vue', () => {
  let wrapper

  beforeEach(() => {
    const pinia = createPinia()

    wrapper = mount(App, {
      global: {
        plugins: [router, pinia],
        stubs: {
          'router-link': true,
          'router-view': true,
        },
      },
    })
  })

  it('renders the app', () => {
    expect(wrapper.find('#app').exists()).toBe(true)
  })

  it('displays the Spotik logo', () => {
    expect(wrapper.text()).toContain('Spotik')
  })

  it('has navigation elements', () => {
    expect(wrapper.find('nav').exists()).toBe(true)
  })
})
