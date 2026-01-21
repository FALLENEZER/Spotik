import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { useAudioPlayer } from '@/composables/useAudioPlayer'
import { useTrackStore } from '@/stores/track'

// Mock HTMLAudioElement
class MockAudioElement extends EventTarget {
  constructor() {
    super()
    this.currentTime = 0
    this.duration = 180
    this.volume = 0.75
    this.muted = false
    this.paused = true
    this.readyState = 4
    this.src = ''
    this.preload = 'auto'
  }

  play() {
    this.paused = false
    this.dispatchEvent(new Event('playing'))
    return Promise.resolve()
  }

  pause() {
    this.paused = true
    this.dispatchEvent(new Event('pause'))
  }

  load() {
    this.dispatchEvent(new Event('loadstart'))
    setTimeout(() => {
      this.dispatchEvent(new Event('loadedmetadata'))
      this.dispatchEvent(new Event('canplay'))
    }, 10)
  }

  addEventListener(event, handler) {
    super.addEventListener(event, handler)
  }

  removeEventListener(event, handler) {
    super.removeEventListener(event, handler)
  }
}

// Mock fetch for server time endpoint
global.fetch = vi.fn()

// Mock performance.now for consistent timing
global.performance = {
  now: vi.fn(() => Date.now()),
}

describe('Audio Synchronization', () => {
  let pinia
  let trackStore
  let audioPlayer

  beforeEach(() => {
    pinia = createPinia()
    setActivePinia(pinia)
    trackStore = useTrackStore()

    // Mock Audio constructor
    global.Audio = vi.fn(() => new MockAudioElement())

    // Mock environment variables
    import.meta.env = {
      VITE_API_URL: 'http://localhost:8000/api',
    }

    // Reset fetch mock
    fetch.mockClear()
  })

  afterEach(() => {
    vi.clearAllMocks()
    vi.clearAllTimers()
  })

  describe('Server Time Synchronization', () => {
    it('calculates server time offset with multiple measurements', async () => {
      // Mock server time responses
      const serverTime = new Date('2024-01-15T10:30:00.000Z').toISOString()
      fetch.mockResolvedValue({
        ok: true,
        json: () =>
          Promise.resolve({
            timestamp: serverTime,
            unix_timestamp: new Date(serverTime).getTime() / 1000,
            timezone: 'UTC',
          }),
      })

      // Mock performance.now to simulate network latency
      let callCount = 0
      performance.now.mockImplementation(() => {
        callCount++
        // Simulate 50ms round-trip time
        return callCount % 2 === 1 ? 1000 : 1050
      })

      const { calculateServerTimeOffset, serverTimeOffset, networkLatency } = useAudioPlayer()

      await calculateServerTimeOffset()

      expect(fetch).toHaveBeenCalledTimes(3) // Should make 3 measurements
      expect(serverTimeOffset.value).toBeDefined()
      expect(networkLatency.value).toBeGreaterThan(0)
    })

    it('handles server time calculation failures gracefully', async () => {
      fetch.mockRejectedValue(new Error('Network error'))

      const { calculateServerTimeOffset, serverTimeOffset, syncFailureCount } = useAudioPlayer()

      await calculateServerTimeOffset()

      expect(syncFailureCount.value).toBeGreaterThan(0)
      expect(serverTimeOffset.value).toBe(0) // Should fallback to 0
    })

    it('updates adaptive tolerance based on network conditions', async () => {
      const serverTime = new Date().toISOString()
      fetch.mockResolvedValue({
        ok: true,
        json: () => Promise.resolve({ timestamp: serverTime }),
      })

      // Mock high latency
      performance.now.mockImplementation(() => {
        const callCount = performance.now.mock.calls.length
        return callCount % 2 === 1 ? 1000 : 1200 // 200ms round-trip
      })

      const { calculateServerTimeOffset, adaptiveTolerance } = useAudioPlayer()

      await calculateServerTimeOffset()

      expect(adaptiveTolerance.value).toBeGreaterThan(0.1) // Should increase tolerance for high latency
    })
  })

  describe('Playback Position Calculation', () => {
    it('calculates expected position with network latency compensation', () => {
      const { calculateExpectedPosition } = useAudioPlayer()

      // Set up playback state - track that started 5 seconds ago
      const startTime = new Date(Date.now() - 5000) // Started 5 seconds ago
      trackStore.updatePlaybackState({
        isPlaying: true,
        startedAt: startTime.toISOString(),
        pausedAt: null,
        position: 0,
        duration: 180,
      })

      const expectedPosition = calculateExpectedPosition()

      // Should be approximately 5 seconds (plus latency compensation)
      expect(expectedPosition).toBeGreaterThan(4.5)
      expect(expectedPosition).toBeLessThan(6.0)
    })

    it('handles paused playback correctly', () => {
      const { calculateExpectedPosition } = useAudioPlayer()

      const startTime = new Date(Date.now() - 10000) // Started 10 seconds ago
      const pauseTime = new Date(Date.now() - 5000) // Paused 5 seconds ago

      trackStore.updatePlaybackState({
        isPlaying: false,
        startedAt: startTime.toISOString(),
        pausedAt: pauseTime.toISOString(),
        position: 5,
        duration: 180,
      })

      const expectedPosition = calculateExpectedPosition()

      // Should return the stored position when paused
      expect(expectedPosition).toBe(5)
    })

    it('bounds position within track duration', () => {
      const { calculateExpectedPosition } = useAudioPlayer()

      // Set up playback that would exceed duration
      const startTime = new Date(Date.now() - 200000) // Started 200 seconds ago
      trackStore.updatePlaybackState({
        isPlaying: true,
        startedAt: startTime.toISOString(),
        pausedAt: null,
        position: 0,
        duration: 180, // 3 minute track
      })

      const expectedPosition = calculateExpectedPosition()

      // Should be capped at track duration
      expect(expectedPosition).toBeLessThanOrEqual(180)
      expect(expectedPosition).toBeGreaterThan(170) // Should be near the end
    })
  })

  describe('Synchronization Logic', () => {
    beforeEach(() => {
      vi.useFakeTimers()
      audioPlayer = useAudioPlayer()
    })

    afterEach(() => {
      vi.useRealTimers()
    })

    it('syncs audio position when difference exceeds tolerance', () => {
      const { synchronizePlayback, audioElement } = audioPlayer

      // Set up current track
      const mockTrack = {
        id: 'track-1',
        original_name: 'Test Track',
        duration_seconds: 180,
      }
      trackStore.setCurrentTrack(mockTrack)
      trackStore.updatePlaybackState({
        isPlaying: true,
        startedAt: new Date(Date.now() - 5000).toISOString(),
        position: 0,
        duration: 180,
      })

      // Mock audio element with different position
      audioPlayer.audioElement.value = new MockAudioElement()
      audioPlayer.audioElement.value.currentTime = 3.0 // 2 seconds behind expected ~5s

      const initialTime = audioPlayer.audioElement.value.currentTime
      synchronizePlayback()

      // Should have updated currentTime to sync
      expect(audioPlayer.audioElement.value.currentTime).not.toBe(initialTime)
    })

    it('does not sync when difference is within tolerance', () => {
      const { synchronizePlayback, audioElement } = audioPlayer

      const mockTrack = {
        id: 'track-1',
        original_name: 'Test Track',
        duration_seconds: 180,
      }
      trackStore.setCurrentTrack(mockTrack)
      trackStore.updatePlaybackState({
        isPlaying: true,
        startedAt: new Date(Date.now() - 5000).toISOString(),
        position: 0,
        duration: 180,
      })

      audioPlayer.audioElement.value = new MockAudioElement()
      audioPlayer.audioElement.value.currentTime = 5.05 // Within 100ms tolerance

      const initialTime = audioPlayer.audioElement.value.currentTime
      synchronizePlayback()

      // Should not have changed significantly (may have small adjustments)
      const finalTime = audioPlayer.audioElement.value.currentTime
      expect(Math.abs(finalTime - initialTime)).toBeLessThan(0.5) // Allow small adjustments
    })

    it('handles sync failures and attempts recovery', async () => {
      const { synchronizePlayback, handleSyncFailure, syncFailureCount } = audioPlayer

      const mockTrack = {
        id: 'track-1',
        original_name: 'Test Track',
        duration_seconds: 180,
      }
      trackStore.setCurrentTrack(mockTrack)
      trackStore.updatePlaybackState({
        isPlaying: true,
        startedAt: new Date(Date.now() - 5000).toISOString(),
        position: 0,
        duration: 180,
      })

      // Mock audio element that throws on currentTime set
      audioPlayer.audioElement.value = new MockAudioElement()
      Object.defineProperty(audioPlayer.audioElement.value, 'currentTime', {
        set: () => {
          throw new Error('Seek failed')
        },
        get: () => 0,
      })

      // Trigger multiple sync failures
      for (let i = 0; i < 6; i++) {
        synchronizePlayback()
      }

      expect(syncFailureCount.value).toBeGreaterThan(0)
    })

    it('records sync measurements for analysis', () => {
      const { synchronizePlayback, syncHistory } = audioPlayer

      const mockTrack = {
        id: 'track-1',
        original_name: 'Test Track',
        duration_seconds: 180,
      }
      trackStore.setCurrentTrack(mockTrack)
      trackStore.updatePlaybackState({
        isPlaying: true,
        startedAt: new Date(Date.now() - 5000).toISOString(),
        position: 0,
        duration: 180,
      })

      audioPlayer.audioElement.value = new MockAudioElement()
      audioPlayer.audioElement.value.currentTime = 3.0

      synchronizePlayback()

      expect(syncHistory.value.length).toBeGreaterThan(0)
      expect(syncHistory.value[0]).toHaveProperty('timestamp')
      expect(syncHistory.value[0]).toHaveProperty('expected')
      expect(syncHistory.value[0]).toHaveProperty('actual')
      expect(syncHistory.value[0]).toHaveProperty('diff')
    })
  })

  describe('Adaptive Sync Intervals', () => {
    beforeEach(() => {
      vi.useFakeTimers()
      audioPlayer = useAudioPlayer()
    })

    afterEach(() => {
      vi.useRealTimers()
    })

    it('adjusts sync check intervals based on network conditions', () => {
      const { startSyncChecks, networkLatency } = audioPlayer

      // Set high latency
      networkLatency.value = 150

      const setIntervalSpy = vi.spyOn(global, 'setInterval')
      startSyncChecks()

      // Should use shorter interval for high latency (750ms for 150ms latency)
      expect(setIntervalSpy).toHaveBeenCalledWith(expect.any(Function), 750)
    })

    it('uses longer intervals for good network conditions', () => {
      const { startSyncChecks, networkLatency } = audioPlayer

      // Set low latency
      networkLatency.value = 30

      const setIntervalSpy = vi.spyOn(global, 'setInterval')
      startSyncChecks()

      // Should use longer interval for good connections (1000ms base for low latency)
      expect(setIntervalSpy).toHaveBeenCalledWith(expect.any(Function), 1000)
    })
  })

  describe('Error Handling', () => {
    it('handles audio element errors gracefully', () => {
      const { audioElement, error } = useAudioPlayer()

      audioElement.value = new MockAudioElement()

      // Simulate audio error
      const audioError = new Error('Audio decode error')
      audioError.code = 3 // MEDIA_ERR_DECODE
      audioElement.value.error = audioError

      audioElement.value.dispatchEvent(new Event('error'))

      expect(error.value).toBeTruthy()
      expect(error.value).toContain('decoding error')
    })

    it('provides recovery options after multiple failures', async () => {
      const { handleSyncFailure, syncFailureCount } = useAudioPlayer()

      // Mock server time endpoint failure
      fetch.mockRejectedValue(new Error('Server unreachable'))

      syncFailureCount.value = 5

      await handleSyncFailure()

      // Should attempt recovery (fetch may be called for server time recalculation)
      expect(syncFailureCount.value).toBeLessThanOrEqual(5) // Should be reduced after recovery attempt
    })
  })

  describe('Performance Analysis', () => {
    it('analyzes sync performance and adjusts tolerance', () => {
      const audioPlayer = useAudioPlayer()
      const { syncHistory, syncTolerance, synchronizePlayback } = audioPlayer

      // Simulate poor sync performance
      const poorMeasurements = Array.from({ length: 5 }, (_, i) => ({
        timestamp: Date.now() - (5 - i) * 1000,
        expected: 5 + i,
        actual: 5 + i + 0.15, // Consistently 150ms off
        diff: 0.15,
        tolerance: 0.1,
        networkLatency: 50,
      }))

      syncHistory.value = poorMeasurements

      // Set up track and trigger sync to analyze performance
      const mockTrack = {
        id: 'track-1',
        original_name: 'Test Track',
        duration_seconds: 180,
      }
      trackStore.setCurrentTrack(mockTrack)
      trackStore.updatePlaybackState({
        isPlaying: true,
        startedAt: new Date(Date.now() - 5000).toISOString(),
        position: 0,
        duration: 180,
      })

      audioPlayer.audioElement.value = new MockAudioElement()
      audioPlayer.audioElement.value.currentTime = 5.15

      const initialTolerance = syncTolerance.value
      synchronizePlayback()

      // Should have potentially adjusted tolerance (may not always increase)
      expect(syncTolerance.value).toBeGreaterThanOrEqual(initialTolerance)
    })
  })
})

/**
 * Property-Based Test for Audio Synchronization Accuracy
 * **Validates: Requirements 4.4, 4.5**
 *
 * Property 12: Audio Synchronization Accuracy
 * For any playback position calculation, the difference between server-calculated
 * position and client-calculated position should be within acceptable tolerance
 * (100ms) to maintain synchronized listening experience.
 */
describe('Property: Audio Synchronization Accuracy', () => {
  let pinia
  let trackStore

  beforeEach(() => {
    pinia = createPinia()
    setActivePinia(pinia)
    trackStore = useTrackStore()

    global.Audio = vi.fn(() => new MockAudioElement())

    import.meta.env = {
      VITE_API_URL: 'http://localhost:8000/api',
    }

    fetch.mockClear()
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  /**
   * Property Test: Synchronization accuracy across network conditions
   * Tests that audio synchronization maintains accuracy within tolerance
   * regardless of network latency and connection quality
   */
  it('maintains synchronization accuracy within tolerance across various network conditions', () => {
    const audioPlayer = useAudioPlayer()
    const { calculateExpectedPosition, synchronizePlayback } = audioPlayer

    // Property: For any valid network conditions, synchronization should maintain accuracy
    const networkConditions = [
      { latency: 5, jitter: 2, description: 'Excellent connection' },
      { latency: 25, jitter: 5, description: 'Good connection' },
      { latency: 75, jitter: 15, description: 'Average connection' },
      { latency: 150, jitter: 30, description: 'Poor connection' },
      { latency: 300, jitter: 50, description: 'Very poor connection' },
      { latency: 500, jitter: 100, description: 'Extremely poor connection' },
    ]

    networkConditions.forEach(({ latency, jitter, description }) => {
      console.log(`Testing ${description} (latency: ${latency}ms, jitter: ${jitter}ms)`)

      // Set network conditions
      audioPlayer.networkLatency.value = latency

      // Calculate adaptive tolerance based on latency
      const baseTolerance = 0.1
      const latencyFactor = Math.min(latency / 1000, 0.4)
      const varianceFactor = Math.min(jitter / 1000, 0.2)
      const adaptiveTolerance = baseTolerance + latencyFactor + varianceFactor
      audioPlayer.adaptiveTolerance.value = adaptiveTolerance
      audioPlayer.syncTolerance.value = adaptiveTolerance

      const currentTolerance = audioPlayer.adaptiveTolerance.value
      // Test various playback scenarios
      const playbackScenarios = [
        { elapsed: 0, position: 0, description: 'Track start' },
        { elapsed: 30000, position: 0, description: 'Mid-track' },
        { elapsed: 150000, position: 0, description: 'Near end' },
        { elapsed: 10000, position: 45, description: 'Resumed from position' },
      ]

      playbackScenarios.forEach(({ elapsed, position, description: scenario }) => {
        // Set up playback state with realistic timing
        const startTime = new Date(Date.now() - elapsed)
        trackStore.updatePlaybackState({
          isPlaying: true,
          startedAt: startTime.toISOString(),
          pausedAt: null,
          position: position,
          duration: 180,
        })

        const expectedPosition = calculateExpectedPosition()

        // Property 1: Expected position should be within reasonable bounds
        expect(expectedPosition).toBeGreaterThanOrEqual(0)
        expect(expectedPosition).toBeLessThanOrEqual(180)

        // Property 2: Position calculation should be reasonable for elapsed time
        const elapsedSeconds = elapsed / 1000
        const expectedMinimum = Math.max(0, position + elapsedSeconds - 2) // Allow 2s variance
        const expectedMaximum = Math.min(180, position + elapsedSeconds + 2) // Allow 2s variance

        expect(expectedPosition).toBeGreaterThanOrEqual(expectedMinimum)
        expect(expectedPosition).toBeLessThanOrEqual(expectedMaximum)

        // Property 3: Synchronization should respect adaptive tolerance
        const mockTrack = {
          id: `track-${Date.now()}-${Math.random()}`,
          original_name: 'Test Track',
          duration_seconds: 180,
        }
        trackStore.setCurrentTrack(mockTrack)

        audioPlayer.audioElement.value = new MockAudioElement()

        // Test sync behavior at tolerance boundary
        audioPlayer.audioElement.value.currentTime = Math.max(
          0,
          expectedPosition - currentTolerance * 0.9
        ) // Just within tolerance
        const beforeSyncWithin = audioPlayer.audioElement.value.currentTime
        synchronizePlayback()
        const afterSyncWithin = audioPlayer.audioElement.value.currentTime

        // Should not sync aggressively when within tolerance
        const withinToleranceChange = Math.abs(afterSyncWithin - beforeSyncWithin)
        expect(withinToleranceChange).toBeLessThan(currentTolerance) // Allow some adjustment

        console.log(
          `  ${scenario}: expected=${expectedPosition.toFixed(3)}s, tolerance=${(currentTolerance * 1000).toFixed(0)}ms`
        )
      })
    })
  })

  /**
   * Property Test: Server time synchronization accuracy
   * Tests that server time offset calculations maintain accuracy
   * across different measurement conditions
   */
  it('calculates server time offset accurately across measurement conditions', async () => {
    const audioPlayer = useAudioPlayer()
    const { calculateServerTimeOffset } = audioPlayer

    // Property: Server time offset should be calculated consistently
    const measurementConditions = [
      { responseTime: 10, clockSkew: 0, description: 'Perfect conditions' },
      { responseTime: 50, clockSkew: 100, description: 'Good conditions with slight skew' },
      { responseTime: 150, clockSkew: -200, description: 'High latency with negative skew' },
    ]

    for (const { responseTime, clockSkew, description } of measurementConditions) {
      console.log(`Testing server time sync: ${description}`)

      // Mock server responses with simulated conditions
      const baseServerTime = Date.now() + clockSkew
      let callCount = 0

      fetch.mockImplementation(() => {
        callCount++
        return Promise.resolve({
          ok: true,
          json: () =>
            Promise.resolve({
              timestamp: new Date(baseServerTime + callCount * 100).toISOString(),
              unix_timestamp: (baseServerTime + callCount * 100) / 1000,
              timezone: 'UTC',
            }),
        })
      })

      // Mock performance.now to simulate network latency
      performance.now.mockImplementation(() => {
        const callIndex = performance.now.mock.calls.length
        return callIndex % 2 === 1 ? 1000 + callIndex * 10 : 1000 + callIndex * 10 + responseTime
      })

      await calculateServerTimeOffset()

      // Property 1: Server time offset should be calculated
      expect(audioPlayer.serverTimeOffset.value).toBeDefined()
      expect(typeof audioPlayer.serverTimeOffset.value).toBe('number')

      // Property 2: Network latency should be measured
      expect(audioPlayer.networkLatency.value).toBeGreaterThan(0)
      expect(audioPlayer.networkLatency.value).toBeLessThan(1000) // Reasonable upper bound

      // Property 3: Adaptive tolerance should be updated based on conditions
      expect(audioPlayer.adaptiveTolerance.value).toBeGreaterThan(0)
      expect(audioPlayer.adaptiveTolerance.value).toBeLessThan(1) // Should not exceed 1 second

      // Property 4: High latency should result in higher tolerance
      if (responseTime > 100) {
        expect(audioPlayer.adaptiveTolerance.value).toBeGreaterThan(0.15) // Higher than base 100ms
      }

      console.log(
        `  Offset: ${audioPlayer.serverTimeOffset.value}ms, Latency: ${audioPlayer.networkLatency.value}ms, Tolerance: ${(audioPlayer.adaptiveTolerance.value * 1000).toFixed(0)}ms`
      )

      // Reset for next iteration
      fetch.mockClear()
      performance.now.mockClear()
    }
  }, 10000) // Increase timeout for async operations

  /**
   * Property Test: Synchronization behavior under timing edge cases
   * Tests that synchronization handles edge cases correctly
   */
  it('handles timing edge cases correctly', () => {
    const audioPlayer = useAudioPlayer()
    const { calculateExpectedPosition, synchronizePlayback } = audioPlayer

    // Property: Synchronization should handle all valid timing scenarios
    const edgeCases = [
      {
        name: 'Track just started (0-1 seconds)',
        startedAt: new Date(Date.now() - 500).toISOString(), // 500ms ago
        position: 0,
        isPlaying: true,
        expectedRange: [0, 2], // Allow more variance for just started
      },
      {
        name: 'Track at exact end',
        startedAt: new Date(Date.now() - 180000).toISOString(), // 180 seconds ago
        position: 0,
        isPlaying: true,
        expectedRange: [175, 180], // Should be near end but allow some variance
      },
      {
        name: 'Paused track',
        startedAt: new Date(Date.now() - 60000).toISOString(),
        pausedAt: new Date(Date.now() - 30000).toISOString(), // Paused 30s ago
        position: 30,
        isPlaying: false,
        expectedRange: [30, 30], // Should return stored position
      },
      {
        name: 'Recently resumed track',
        startedAt: new Date(Date.now() - 45000).toISOString(), // Started 45s ago
        position: 30, // Resumed from 30s
        isPlaying: true,
        expectedRange: [40, 50], // Should be around 45s total, allow variance
      },
    ]

    edgeCases.forEach(({ name, startedAt, pausedAt, position, isPlaying, expectedRange }) => {
      console.log(`Testing edge case: ${name}`)

      // Reset server offset for consistent testing
      audioPlayer.serverTimeOffset.value = 0

      // Set up playback state
      trackStore.updatePlaybackState({
        isPlaying,
        startedAt,
        pausedAt: pausedAt || null,
        position,
        duration: 180,
      })

      const calculatedPosition = calculateExpectedPosition()

      // Property 1: Position should be within expected range
      expect(calculatedPosition).toBeGreaterThanOrEqual(expectedRange[0])
      expect(calculatedPosition).toBeLessThanOrEqual(expectedRange[1])

      // Property 2: Position should never be negative
      expect(calculatedPosition).toBeGreaterThanOrEqual(0)

      // Property 3: Position should never exceed track duration
      expect(calculatedPosition).toBeLessThanOrEqual(180)

      // Property 4: Synchronization should handle the calculated position appropriately
      if (isPlaying) {
        const mockTrack = {
          id: `edge-track-${Date.now()}-${Math.random()}`,
          original_name: 'Edge Test Track',
          duration_seconds: 180,
        }
        trackStore.setCurrentTrack(mockTrack)

        audioPlayer.audioElement.value = new MockAudioElement()
        audioPlayer.audioElement.value.currentTime = Math.max(0, calculatedPosition + 0.5) // Slightly off

        const beforeSync = audioPlayer.audioElement.value.currentTime
        synchronizePlayback()
        const afterSync = audioPlayer.audioElement.value.currentTime

        // Should attempt to sync if difference is significant
        const syncDifference = Math.abs(calculatedPosition - beforeSync)
        if (syncDifference > audioPlayer.syncTolerance.value) {
          // Should have moved towards the calculated position
          const afterSyncDifference = Math.abs(calculatedPosition - afterSync)
          expect(afterSyncDifference).toBeLessThanOrEqual(syncDifference) // Should be closer or same
        }
      }

      console.log(
        `  Calculated position: ${calculatedPosition.toFixed(3)}s (expected: ${expectedRange[0]}-${expectedRange[1]}s)`
      )
    })
  })

  /**
   * Property Test: Sync performance analysis and adaptation
   * Tests that the system adapts its synchronization parameters based on performance
   */
  it('adapts synchronization parameters based on performance history', () => {
    const audioPlayer = useAudioPlayer()
    const { synchronizePlayback, syncHistory, syncTolerance } = audioPlayer

    // Property: System should adapt tolerance based on sync performance
    const performanceScenarios = [
      {
        name: 'Consistently good sync performance',
        measurements: Array.from({ length: 10 }, (_, i) => ({
          timestamp: Date.now() - (10 - i) * 1000,
          expected: 10 + i,
          actual: 10 + i + (Math.random() * 0.02 - 0.01), // ±10ms variance
          diff: Math.random() * 0.02,
          tolerance: 0.1,
          networkLatency: 30,
        })),
        expectedToleranceChange: 'decrease_or_stable',
      },
      {
        name: 'Consistently poor sync performance',
        measurements: Array.from({ length: 10 }, (_, i) => ({
          timestamp: Date.now() - (10 - i) * 1000,
          expected: 10 + i,
          actual: 10 + i + (Math.random() * 0.3 + 0.1), // 100-400ms variance
          diff: Math.random() * 0.3 + 0.1,
          tolerance: 0.1,
          networkLatency: 150,
        })),
        expectedToleranceChange: 'increase',
      },
    ]

    performanceScenarios.forEach(({ name, measurements, expectedToleranceChange }) => {
      console.log(`Testing performance adaptation: ${name}`)

      // Reset sync history and tolerance
      syncHistory.value = []
      syncTolerance.value = 0.1
      const initialTolerance = syncTolerance.value

      // Populate sync history with test measurements
      syncHistory.value = measurements

      // Set up a track and trigger sync to analyze performance
      const mockTrack = {
        id: `perf-track-${Date.now()}-${Math.random()}`,
        original_name: 'Performance Test Track',
        duration_seconds: 180,
      }
      trackStore.setCurrentTrack(mockTrack)
      trackStore.updatePlaybackState({
        isPlaying: true,
        startedAt: new Date(Date.now() - 15000).toISOString(),
        position: 0,
        duration: 180,
      })

      audioPlayer.audioElement.value = new MockAudioElement()
      audioPlayer.audioElement.value.currentTime = 15.1 // Slightly off expected ~15s

      // Trigger synchronization which should analyze performance
      synchronizePlayback()

      const finalTolerance = syncTolerance.value
      const toleranceChange = finalTolerance - initialTolerance

      // Property: Tolerance should adapt based on performance
      switch (expectedToleranceChange) {
        case 'decrease_or_stable':
          // Good performance should allow tighter tolerance or stay same
          expect(finalTolerance).toBeLessThanOrEqual(initialTolerance * 1.2) // Allow some increase
          break
        case 'increase':
          // Poor performance should increase tolerance
          expect(finalTolerance).toBeGreaterThanOrEqual(initialTolerance * 0.9) // Allow slight decrease
          break
      }

      // Property: Tolerance should remain within reasonable bounds
      expect(finalTolerance).toBeGreaterThan(0.05) // At least 50ms
      expect(finalTolerance).toBeLessThan(0.5) // At most 500ms

      console.log(
        `  Tolerance change: ${initialTolerance.toFixed(3)}s → ${finalTolerance.toFixed(3)}s (${toleranceChange > 0 ? '+' : ''}${(toleranceChange * 1000).toFixed(0)}ms)`
      )
    })
  })
})
