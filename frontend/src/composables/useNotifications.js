import { inject } from 'vue'

export function useNotifications() {
  const showNotification = inject('showNotification')

  if (!showNotification) {
    console.warn('useNotifications: showNotification not provided')
    return {
      showSuccess: () => {},
      showError: () => {},
      showWarning: () => {},
      showInfo: () => {},
    }
  }

  const showSuccess = (title, message = '') => {
    showNotification('success', title, message)
  }

  const showError = (title, message = '') => {
    showNotification('error', title, message)
  }

  const showWarning = (title, message = '') => {
    showNotification('warning', title, message)
  }

  const showInfo = (title, message = '') => {
    showNotification('info', title, message)
  }

  return {
    showSuccess,
    showError,
    showWarning,
    showInfo,
  }
}
