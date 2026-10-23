import { mount } from '@vue/test-utils'
import HomePage from '@/views/HomePage.vue'
import { describe, expect, test } from 'vitest'

describe('HomePage.vue', () => {
  test('shows the browser notice outside the native app', () => {
    const wrapper = mount(HomePage)
    expect(wrapper.text()).toMatch('Push works only in the Android app')
  })
})
