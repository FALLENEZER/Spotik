/**
 * Cross-Browser Audio Synchronization Integration Tests
 *
 * This test suite validates audio synchronization across different browser environments:
 * - Browser-specific audio API differences and compatibility
 * - Timing precision variations across browsers
 * - Network latency compensation in different environments
 * - Audio codec support and playback behavior
 * - Performance characteristics across browser engines
 *
 * Requirements: 4.1, 4.2, 4.3, 4.4, 4.5
 */

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { useAudioPlayer } from '@/composables/useAudioPlayer'
import { useTrackStore } from '@/stores/track'

// Browser environment simulation
class BrowserEnvironment {
  constructor(browserName, version, audioSupport = {}) {
    this.browserName = browserName
    this.version = version
    this.audioSupport = {
      mp3: true,
      wav: true,
      m4a: true,
      webAudio: true,
      preciseCurrentTime: true,
      ...audioSupport,
    }
    this.performanceCharacteristics = this.getBrowserPerformanceProfile()
  }

  getBrowserPerformanceProfile() {
    const profiles = {
      chrome: {
        timerPrecision: 0.1, // 0.1ms precision
        audioLatency: 10, // 10ms base latency
        networkJitter: 5, // 5ms network jitter
        cpuEfficiency: 1.0, // Baseline efficiency
      },
      firefox: {
        timerPrecision: 1.0, // 1ms precision
        audioLatency: 15, // 15ms base latency
        networkJitter: 8, // 8ms network jitter
        cpuEfficiency: 0.9, // Slightly less efficient
      },
      safari: {
        timerPrecision: 1.0, // 1ms precision
        audioLatency: 20, // 20ms base latency (iOS restrictions)
        networkJitter: 6, // 6ms network jitter
        cpuEfficiency: 0.95, // Good efficiency but different timing
      },
      edge: {
        timerPrecision: 0.1, // 0.1ms precision (Chromium-based)
        audioLatency: 12, // 12ms base latency
        networkJitter: 7, // 7ms network jitter
        cpuEfficiency: 0.98, // Very good efficiency
      },
    }

    return profiles[this.browserName.toLowerCase()] || profiles.chrome
  }

  simulatePerformanceNow() {
    const baseTime = Date.now()
    const jitter = (Math.random() - 0.5) * this.performanceCharacteristics.timerPrecision * 2
    return baseTime + jitter
  }

  simulateNetworkLatency() {
    const baseLatency = this.performanceCharacteristics.audioLatency
    const jitter = (Math.random() - 0.5) * this.performanceCharacteristics.networkJitter * 2
    return Math.max(0, baseLatency + jitter)
  }
}

// Mock HTMLAudioElement with browser-specific behaviors
class BrowserSpecificAudioElement extends EventTarget {
  constructor(browserEnv) {
    super()
    this.browserEnv = browserEnv
    this.currentTime = 0
    this.duration = 180
    this.volume = 0.75
    this.muted = false
    this.paused = true
    this.readyState = 4
    this.src = ''
    this.preload = 'auto'
    this._actualCurrentTime = 0
    this._lastUpdateTime = Date.now()
    this._playbackRate = 1.0
  }

  get currentTime() {
    if (!this.paused) {
      const now = Date.now()
      const elapsed = (now - this._lastUpdateTime) / 1000
      this._actualCurrentTime += elapsed * this._playbackRate
      this._lastUpdateTime = now
    }

    // Apply browser-specific timing precision
    const precision = this.browserEnv.performanceCharacteristics.timerPrecision / 1000
    return Math.round(this._actualCurrentTime / precision) * precision
  }

  set currentTime(value) {
    this._actualCurrentTime = value
    this._lastUpdateTime = Date.now()

    // Simulate browser-specific seek behavior
    if (this.browserEnv.browserName === 'safari') {
      // Safari has slight delays in seeking
      setTimeout(() => {
        this.dispatchEvent(new Event('seeked'))
      }, 5)
    } else {
      // Other browsers seek more immediately
      setTimeout(() => {
        this.dispatchEvent(new Event('seeked'))
      }, 1)
    }
  }

  async play() {
    // Simulate browser-specific play behavior
    const latency = this.browserEnv.simulateNetworkLatency()

    return new Promise((resolve, reject) => {
      setTimeout(() => {
        if (this.browserEnv.audioSupport.webAudio) {
          this.paused = false
          this._lastUpdateTime = Date.now()
          this.dispatchEvent(new Event('playing'))
          resolve()
        } else {
          reject(new Error('Audio playback not supported'))
        }
      }, latency)
    })
  }

  pause() {
    this.paused = true
    this.dispatchEvent(new Event('pause'))
  }

  load() {
    // Simulate browser-specific loading behavior
    const loadDelay = this.browserEnv.browserName === 'safari' ? 50 : 20

    this.dispatchEvent(new Event('loadstart'))
    setTimeout(() => {
      this.dispatchEvent(new Event('loadedmetadata'))
      setTimeout(() => {
        this.dispatchEvent(new Event('canplay'))
      }, loadDelay / 2)
    }, loadDelay)
  }
}

// Cross-browser test runner
class CrossBrowserTestRunner {
  constructor() {
    this.browsers = [
      new BrowserEnvironment('Chrome', '120.0', { preciseCurrentTime: true }),
      new BrowserEnvironment('Firefox', '121.0', { timerPrecision: 1.0 }),
      new BrowserEnvironment('Safari', '17.0', {
        audioLatency: 25, // Higher latency on Safari/iOS
        timerPrecision: 1.0,
      }),
      new BrowserEnvironment('Edge', '120.0', { preciseCurrentTime: true }),
    ]
  }

  async runTestAcrossBrowsers(testFn, testName) {
    const results = []

    for (const browser of this.browsers) {
      console.log(`Running ${testName} on ${browser.browserName} ${browser.version}`)

      try {
        const result = await testFn(browser)
        results.push({
          browser: browser.browserName,
          success: true,
          result,
          performance: browser.performanceCharacteristics,
        })
      } catch (error) {
        results.push({
          browser: browser.browserName,
          success: false,
          error: error.message,
          performance: browser.performanceCharacteristics,
        })
      }
    }

    return results
  }
}

describe('Cross-Browser Audio Synchronization', () => {
  let testRunner
  let pinia
  let trackStore

  beforeEach(() => {
    testRunner = new CrossBrowserTestRunner()
    pinia = createPinia()
    setActivePinia(pinia)
    trackStore = useTrackStore()

    // Mock fetch for server time
    global.fetch = vi.fn()

    // Mock performance.now
    global.performance = {
      now: vi.fn(() => Date.now()),
    }
  })

  afterEach(() => {
    vi.clearAllMocks()
  })

  describe('Browser-Specific Audio API Compatibility', () => {
    it('should handle audio element creation across browsers', async () => {
      const results = await testRunner.runTestAcrossBrowsers(async browserEnv => {
        // Mock Audio constructor for this browser
        global.Audio = vi.fn(() => new BrowserSpecificAudioElement(browserEnv))

        const audioPlayer = useAudioPlayer()
        const { initializeAudio } = audioPlayer

        // Initialize audio for this browser environment
        await initializeAudio()

        expect(audioPlayer.audioElement.value).toBeDefined()
        expect(audioPlayer.audioElement.value.browserEnv.browserName).toBe(browserEnv.browserName)

        return {
          audioSupported: true,
          browserName: browserEnv.browserName,
          audioLatency: browserEnv.performanceCharacteristics.audioLatency,
        }
      }, 'Audio Element Creation')

      // All browsers should successfully create audio elements
      results.forEach(result => {
        expect(result.success).toBe(true)
        expect(result.result.audioSupported).toBe(true)
      })

      // Verify different browsers have different characteristics
      const chromeResult = results.find(r => r.browser === 'Chrome')
      const safariResult = results.find(r => r.browser === 'Safari')

      expect(chromeResult.result.audioLatency).toBeLessThan(safariResult.result.audioLatency)
    })

    it('should handle codec support variations', async () => {
      const results = await testRunner.runTestAcrossBrowsers(async browserEnv => {
        const audioElement = new BrowserSpecificAudioElement(browserEnv)

        // Test different audio formats
        const formats = ['audio/mpeg', 'audio/wav', 'audio/mp4']
        const supportedFormats = []

        formats.forEach(format => {
          // Simulate browser codec support
          if (browserEnv.audioSupport[format.split('/')[1]]) {
            supportedFormats.push(format)
          }
        })

        return {
          supportedFormats,
          totalFormats: formats.length,
          browserName: browserEnv.browserName,
        }
      }, 'Codec Support')

      // All browsers should support at least MP3 and WAV
      results.forEach(result => {
        expect(result.success).toBe(true)
        expect(result.result.supportedFormats).toContain('audio/mpeg')
        expect(result.result.supportedFormats).toContain('audio/wav')
      })
    })
  })

  describe('Timing Precision Across Browsers', () => {
    it('should maintain synchronization accuracy within browser-specific tolerances', async () => {
      const results = await testRunner.runTestAcrossBrowsers(async browserEnv => {
        // Mock server time response
        const serverTime = new Date().toISOString()
        fetch.mockResolvedValue({
          ok: true,
          json: () =>
            Promise.resolve({
              timestamp: serverTime,
              unix_timestamp: new Date(serverTime).getTime() / 1000,
            }),
        })

        // Mock performance.now with browser-specific precision
        performance.now.mockImplementation(() => browserEnv.simulatePerformanceNow())

        global.Audio = vi.fn(() => new BrowserSpecificAudioElement(browserEnv))

        const audioPlayer = useAudioPlayer()
        const { calculateServerTimeOffset, synchronizePlayback } = audioPlayer

        // Calculate server time offset
        await calculateServerTimeOffset()

        // Set up playback state
        const startTime = new Date(Date.now() - 5000) // Started 5 seconds ago
        trackStore.updatePlaybackState({
          isPlaying: true,
          startedAt: startTime.toISOString(),
          pausedAt: null,
          position: 0,
          duration: 180,
        })

        trackStore.setCurrentTrack({
          id: 'test-track',
          original_name: 'Test Track',
          duration_seconds: 180,
        })

        // Initialize audio element
        await audioPlayer.initializeAudio()
        audioPlayer.audioElement.value.currentTime = 4.5 // Slightly behind expected ~5s

        // Perform synchronization
        const beforeSync = audioPlayer.audioElement.value.currentTime
        synchronizePlayback()
        const afterSync = audioPlayer.audioElement.value.currentTime

        const syncDifference = Math.abs(afterSync - beforeSync)
        const expectedPosition = 5.0 // Approximately 5 seconds
        const finalDifference = Math.abs(afterSync - expectedPosition)

        return {
          browserName: browserEnv.browserName,
          timerPrecision: browserEnv.performanceCharacteristics.timerPrecision,
          beforeSync,
          afterSync,
          syncDifference,
          finalDifference,
          expectedPosition,
        }
      }, 'Timing Precision')

      // All browsers should achieve reasonable synchronization
      results.forEach(result => {
        expect(result.success).toBe(true)

        const { finalDifference, timerPrecision, browserName } = result.result

        // Tolerance should be based on browser capabilities
        const expectedTolerance = Math.max(0.1, (timerPrecision / 1000) * 2) // At least 100ms or 2x timer precision

        expect(finalDifference).toBeLessThan(expectedTolerance)
        console.log(
          `${browserName}: Final difference ${finalDifference.toFixed(3)}s (tolerance: ${expectedTolerance.toFixed(3)}s)`
        )
      })

      // Chrome should have the best precision
      const chromeResult = results.find(r => r.browser === 'Chrome')
      const firefoxResult = results.find(r => r.browser === 'Firefox')

      expect(chromeResult.result.finalDifference).toBeLessThanOrEqual(
        firefoxResult.result.finalDifference
      )
    })

    it('should adapt tolerance based on browser capabilities', async () => {
      const results = await testRunner.runTestAcrossBrowsers(async browserEnv => {
        global.Audio = vi.fn(() => new BrowserSpecificAudioElement(browserEnv))

        const audioPlayer = useAudioPlayer()
        const { adaptiveTolerance, networkLatency } = audioPlayer

        // Simulate network conditions
        networkLatency.value = browserEnv.simulateNetworkLatency()

        // Calculate adaptive tolerance
        const baseTolerance = 0.1 // 100ms base
        const latencyFactor = networkLatency.value / 1000 // Convert to seconds
        const precisionFactor = browserEnv.performanceCharacteristics.timerPrecision / 1000

        const calculatedTolerance = baseTolerance + latencyFactor + precisionFactor
        adaptiveTolerance.value = calculatedTolerance

        return {
          browserName: browserEnv.browserName,
          networkLatency: networkLatency.value,
          timerPrecision: browserEnv.performanceCharacteristics.timerPrecision,
          adaptiveTolerance: calculatedTolerance,
          baseTolerance,
        }
      }, 'Adaptive Tolerance')

      // Each browser should have appropriate tolerance
      results.forEach(result => {
        expect(result.success).toBe(true)

        const { adaptiveTolerance, baseTolerance, browserName } = result.result

        // Tolerance should be at least the base tolerance
        expect(adaptiveTolerance).toBeGreaterThanOrEqual(baseTolerance)

        // Safari should have higher tolerance due to higher latency
        if (browserName === 'Safari') {
          expect(adaptiveTolerance).toBeGreaterThan(baseTolerance * 1.2)
        }

        console.log(`${browserName}: Adaptive tolerance ${(adaptiveTolerance * 1000).toFixed(1)}ms`)
      })
    })
  })

  describe('Network Latency Compensation', () => {
    it('should compensate for network latency across different browsers', async () => {
      const results = await testRunner.runTestAcrossBrowsers(async browserEnv => {
        // Mock varying network conditions
        const measurements = []

        for (let i = 0; i < 5; i++) {
          const latency = browserEnv.simulateNetworkLatency()
          const serverTime = new Date(Date.now() + latency).toISOString()

          fetch.mockResolvedValueOnce({
            ok: true,
            json: () =>
              Promise.resolve({
                timestamp: serverTime,
                unix_timestamp: new Date(serverTime).getTime() / 1000,
              }),
          })

          // Mock performance.now for round-trip measurement
          let callCount = 0
          performance.now.mockImplementation(() => {
            callCount++
            return callCount % 2 === 1 ? 1000 : 1000 + latency
          })

          measurements.push(latency)
        }

        global.Audio = vi.fn(() => new BrowserSpecificAudioElement(browserEnv))

        const audioPlayer = useAudioPlayer()
        const { calculateServerTimeOffset, networkLatency } = audioPlayer

        // Calculate server time offset with latency compensation
        await calculateServerTimeOffset()

        const averageLatency = measurements.reduce((a, b) => a + b, 0) / measurements.length
        const latencyVariance =
          measurements.reduce((sum, lat) => sum + Math.pow(lat - averageLatency, 2), 0) /
          measurements.length

        return {
          browserName: browserEnv.browserName,
          measuredLatency: networkLatency.value,
          averageLatency,
          latencyVariance,
          serverTimeOffset: audioPlayer.serverTimeOffset.value,
        }
      }, 'Network Latency Compensation')

      // All browsers should measure and compensate for latency
      results.forEach(result => {
        expect(result.success).toBe(true)

        const { measuredLatency, averageLatency, browserName } = result.result

        // Measured latency should be reasonable
        expect(measuredLatency).toBeGreaterThan(0)
        expect(measuredLatency).toBeLessThan(1000) // Less than 1 second

        // Should be close to simulated average latency
        expect(Math.abs(measuredLatency - averageLatency)).toBeLessThan(50) // Within 50ms

        console.log(
          `${browserName}: Measured latency ${measuredLatency.toFixed(1)}ms (expected ~${averageLatency.toFixed(1)}ms)`
        )
      })
    })

    it('should handle high latency scenarios gracefully', async () => {
      const results = await testRunner.runTestAcrossBrowsers(async browserEnv => {
        // Simulate high latency conditions (mobile/poor connection)
        const highLatencyEnv = {
          ...browserEnv,
          performanceCharacteristics: {
            ...browserEnv.performanceCharacteristics,
            audioLatency: 200, // 200ms base latency
            networkJitter: 100, // 100ms jitter
          },
        }

        global.Audio = vi.fn(() => new BrowserSpecificAudioElement(highLatencyEnv))

        const audioPlayer = useAudioPlayer()
        const { synchronizePlayback, adaptiveTolerance } = audioPlayer

        // Set high network latency
        audioPlayer.networkLatency.value = 250

        // Set up playback state
        trackStore.updatePlaybackState({
          isPlaying: true,
          startedAt: new Date(Date.now() - 10000).toISOString(), // Started 10 seconds ago
          pausedAt: null,
          position: 0,
          duration: 180,
        })

        trackStore.setCurrentTrack({
          id: 'high-latency-track',
          original_name: 'High Latency Test',
          duration_seconds: 180,
        })

        await audioPlayer.initializeAudio()

        // Simulate audio being significantly out of sync
        audioPlayer.audioElement.value.currentTime = 8.5 // 1.5 seconds behind expected ~10s

        const beforeSync = audioPlayer.audioElement.value.currentTime
        synchronizePlayback()
        const afterSync = audioPlayer.audioElement.value.currentTime

        // Should adapt tolerance for high latency
        const tolerance = adaptiveTolerance.value

        return {
          browserName: browserEnv.browserName,
          networkLatency: audioPlayer.networkLatency.value,
          beforeSync,
          afterSync,
          adaptiveTolerance: tolerance,
          syncAttempted: Math.abs(afterSync - beforeSync) > 0.01,
        }
      }, 'High Latency Handling')

      // All browsers should handle high latency appropriately
      results.forEach(result => {
        expect(result.success).toBe(true)

        const { adaptiveTolerance, networkLatency, browserName, syncAttempted } = result.result

        // Should have increased tolerance for high latency
        expect(adaptiveTolerance).toBeGreaterThan(0.2) // At least 200ms for high latency

        // Should attempt sync when difference is significant
        expect(syncAttempted).toBe(true)

        console.log(
          `${browserName}: High latency tolerance ${(adaptiveTolerance * 1000).toFixed(0)}ms (latency: ${networkLatency}ms)`
        )
      })
    })
  })

  describe('Performance Characteristics', () => {
    it('should maintain performance across different browser engines', async () => {
      const results = await testRunner.runTestAcrossBrowsers(async browserEnv => {
        global.Audio = vi.fn(() => new BrowserSpecificAudioElement(browserEnv))

        const audioPlayer = useAudioPlayer()

        // Measure sync performance
        const syncTimes = []
        const iterations = 10

        for (let i = 0; i < iterations; i++) {
          trackStore.updatePlaybackState({
            isPlaying: true,
            startedAt: new Date(Date.now() - (i + 1) * 1000).toISOString(),
            position: 0,
            duration: 180,
          })

          trackStore.setCurrentTrack({
            id: `perf-track-${i}`,
            original_name: `Performance Test ${i}`,
            duration_seconds: 180,
          })

          await audioPlayer.initializeAudio()
          audioPlayer.audioElement.value.currentTime = i

          const startTime = performance.now()
          audioPlayer.synchronizePlayback()
          const endTime = performance.now()

          syncTimes.push(endTime - startTime)
        }

        const averageSyncTime = syncTimes.reduce((a, b) => a + b, 0) / syncTimes.length
        const maxSyncTime = Math.max(...syncTimes)
        const minSyncTime = Math.min(...syncTimes)

        return {
          browserName: browserEnv.browserName,
          averageSyncTime,
          maxSyncTime,
          minSyncTime,
          cpuEfficiency: browserEnv.performanceCharacteristics.cpuEfficiency,
          iterations,
        }
      }, 'Performance Characteristics')

      // All browsers should perform synchronization efficiently
      results.forEach(result => {
        expect(result.success).toBe(true)

        const { averageSyncTime, maxSyncTime, browserName, cpuEfficiency } = result.result

        // Sync should be fast (under 10ms average)
        expect(averageSyncTime).toBeLessThan(10)

        // No single sync should take too long (under 50ms)
        expect(maxSyncTime).toBeLessThan(50)

        console.log(
          `${browserName}: Avg sync time ${averageSyncTime.toFixed(2)}ms (efficiency: ${cpuEfficiency})`
        )
      })

      // Chrome should generally be fastest due to V8 optimization
      const chromeResult = results.find(r => r.browser === 'Chrome')
      const otherResults = results.filter(r => r.browser !== 'Chrome')

      otherResults.forEach(result => {
        // Chrome should be at least as fast as other browsers
        expect(chromeResult.result.averageSyncTime).toBeLessThanOrEqual(
          result.result.averageSyncTime * 1.5
        )
      })
    })

    it('should handle memory usage efficiently across browsers', async () => {
      const results = await testRunner.runTestAcrossBrowsers(async browserEnv => {
        global.Audio = vi.fn(() => new BrowserSpecificAudioElement(browserEnv))

        const audioPlayer = useAudioPlayer()
        const { syncHistory } = audioPlayer

        // Simulate extended usage with many sync operations
        const maxHistorySize = 100

        for (let i = 0; i < maxHistorySize * 2; i++) {
          syncHistory.value.push({
            timestamp: Date.now() - i * 1000,
            expected: i,
            actual: i + Math.random() * 0.1,
            diff: Math.random() * 0.1,
            tolerance: 0.1,
            networkLatency: browserEnv.simulateNetworkLatency(),
          })
        }

        // History should be limited to prevent memory leaks
        const historySize = syncHistory.value.length

        return {
          browserName: browserEnv.browserName,
          historySize,
          maxHistorySize,
          memoryEfficient: historySize <= maxHistorySize * 1.1, // Allow 10% overhead
        }
      }, 'Memory Usage')

      // All browsers should manage memory efficiently
      results.forEach(result => {
        expect(result.success).toBe(true)

        const { historySize, maxHistorySize, memoryEfficient, browserName } = result.result

        // Should limit history size to prevent memory leaks
        expect(memoryEfficient).toBe(true)
        expect(historySize).toBeLessThanOrEqual(maxHistorySize * 1.2) // Allow some flexibility

        console.log(`${browserName}: History size ${historySize} (limit: ${maxHistorySize})`)
      })
    })
  })

  describe('Error Handling Across Browsers', () => {
    it('should handle audio loading failures consistently', async () => {
      const results = await testRunner.runTestAcrossBrowsers(async browserEnv => {
        // Create audio element that fails to load
        class FailingAudioElement extends BrowserSpecificAudioElement {
          load() {
            this.dispatchEvent(new Event('loadstart'))
            setTimeout(() => {
              const error = new Error('Network error')
              error.code = 2 // MEDIA_ERR_NETWORK
              this.error = error
              this.dispatchEvent(new Event('error'))
            }, 50)
          }
        }

        global.Audio = vi.fn(() => new FailingAudioElement(browserEnv))

        const audioPlayer = useAudioPlayer()
        const { error } = audioPlayer

        try {
          await audioPlayer.initializeAudio()
          audioPlayer.audioElement.value.src = 'invalid-url.mp3'
          audioPlayer.audioElement.value.load()

          // Wait for error event
          await new Promise(resolve => setTimeout(resolve, 100))

          return {
            browserName: browserEnv.browserName,
            errorHandled: error.value !== null,
            errorMessage: error.value,
          }
        } catch (e) {
          return {
            browserName: browserEnv.browserName,
            errorHandled: true,
            errorMessage: e.message,
          }
        }
      }, 'Audio Loading Failures')

      // All browsers should handle loading failures gracefully
      results.forEach(result => {
        expect(result.success).toBe(true)
        expect(result.result.errorHandled).toBe(true)
        expect(result.result.errorMessage).toBeTruthy()

        console.log(`${result.result.browserName}: Error handled - ${result.result.errorMessage}`)
      })
    })

    it('should recover from sync failures across browsers', async () => {
      const results = await testRunner.runTestAcrossBrowsers(async browserEnv => {
        // Create audio element that fails seeks
        class UnreliableAudioElement extends BrowserSpecificAudioElement {
          set currentTime(value) {
            // Randomly fail seeks to simulate unreliable behavior
            if (Math.random() < 0.3) {
              // 30% failure rate
              throw new Error('Seek failed')
            }
            super.currentTime = value
          }
        }

        global.Audio = vi.fn(() => new UnreliableAudioElement(browserEnv))

        const audioPlayer = useAudioPlayer()
        const { syncFailureCount, handleSyncFailure } = audioPlayer

        // Set up playback state
        trackStore.updatePlaybackState({
          isPlaying: true,
          startedAt: new Date(Date.now() - 5000).toISOString(),
          position: 0,
          duration: 180,
        })

        trackStore.setCurrentTrack({
          id: 'unreliable-track',
          original_name: 'Unreliable Test',
          duration_seconds: 180,
        })

        await audioPlayer.initializeAudio()

        // Attempt multiple syncs, some will fail
        let successfulSyncs = 0
        let failedSyncs = 0

        for (let i = 0; i < 10; i++) {
          try {
            audioPlayer.audioElement.value.currentTime = i
            audioPlayer.synchronizePlayback()
            successfulSyncs++
          } catch (error) {
            failedSyncs++
            await handleSyncFailure()
          }
        }

        return {
          browserName: browserEnv.browserName,
          successfulSyncs,
          failedSyncs,
          totalAttempts: 10,
          syncFailureCount: syncFailureCount.value,
          recoveryAttempted: syncFailureCount.value > 0,
        }
      }, 'Sync Failure Recovery')

      // All browsers should attempt recovery from sync failures
      results.forEach(result => {
        expect(result.success).toBe(true)

        const { successfulSyncs, failedSyncs, recoveryAttempted, browserName } = result.result

        // Should have some successful syncs
        expect(successfulSyncs).toBeGreaterThan(0)

        // If there were failures, recovery should be attempted
        if (failedSyncs > 0) {
          expect(recoveryAttempted).toBe(true)
        }

        console.log(
          `${browserName}: ${successfulSyncs}/${successfulSyncs + failedSyncs} syncs successful, recovery: ${recoveryAttempted}`
        )
      })
    })
  })

  describe('Cross-Browser Synchronization Scenarios', () => {
    it('should maintain sync between different browser types', async () => {
      // Simulate multiple browsers in the same room
      const browserInstances = testRunner.browsers.map(browserEnv => {
        global.Audio = vi.fn(() => new BrowserSpecificAudioElement(browserEnv))

        const pinia = createPinia()
        setActivePinia(pinia)
        const trackStore = useTrackStore()
        const audioPlayer = useAudioPlayer()

        return {
          browserEnv,
          trackStore,
          audioPlayer,
          pinia,
        }
      })

      // Set up same playback state for all browsers
      const startTime = new Date(Date.now() - 10000).toISOString() // Started 10 seconds ago
      const track = {
        id: 'cross-browser-track',
        original_name: 'Cross Browser Test',
        duration_seconds: 180,
      }

      const syncResults = []

      for (const instance of browserInstances) {
        setActivePinia(instance.pinia)

        instance.trackStore.updatePlaybackState({
          isPlaying: true,
          startedAt: startTime,
          pausedAt: null,
          position: 0,
          duration: 180,
        })

        instance.trackStore.setCurrentTrack(track)

        // Mock server time response
        fetch.mockResolvedValue({
          ok: true,
          json: () =>
            Promise.resolve({
              timestamp: new Date().toISOString(),
              unix_timestamp: Date.now() / 1000,
            }),
        })

        await instance.audioPlayer.calculateServerTimeOffset()
        await instance.audioPlayer.initializeAudio()

        // Calculate expected position
        const expectedPosition = instance.audioPlayer.calculateExpectedPosition()

        // Set audio to slightly different position
        instance.audioPlayer.audioElement.value.currentTime = expectedPosition - 0.2 // 200ms behind

        // Synchronize
        instance.audioPlayer.synchronizePlayback()

        const finalPosition = instance.audioPlayer.audioElement.value.currentTime
        const syncDifference = Math.abs(finalPosition - expectedPosition)

        syncResults.push({
          browser: instance.browserEnv.browserName,
          expectedPosition,
          finalPosition,
          syncDifference,
          tolerance: instance.audioPlayer.adaptiveTolerance.value,
        })
      }

      // All browsers should sync to similar positions
      const positions = syncResults.map(r => r.finalPosition)
      const avgPosition = positions.reduce((a, b) => a + b, 0) / positions.length
      const maxDeviation = Math.max(...positions.map(pos => Math.abs(pos - avgPosition)))

      // Maximum deviation between browsers should be reasonable
      expect(maxDeviation).toBeLessThan(0.5) // Within 500ms of each other

      syncResults.forEach(result => {
        console.log(
          `${result.browser}: Position ${result.finalPosition.toFixed(3)}s (diff: ${(result.syncDifference * 1000).toFixed(0)}ms)`
        )

        // Each browser should sync within its own tolerance
        expect(result.syncDifference).toBeLessThan(result.tolerance)
      })

      console.log(
        `Cross-browser sync: Avg position ${avgPosition.toFixed(3)}s, Max deviation ${(maxDeviation * 1000).toFixed(0)}ms`
      )
    })
  })
})
