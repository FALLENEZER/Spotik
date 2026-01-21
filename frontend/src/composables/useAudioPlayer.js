import { ref, computed, onMounted, onUnmounted, watch } from 'vue'
import { useTrackStore } from '@/stores/track'
import { useAuthStore } from '@/stores/auth'

/**
 * Audio playback composable with server timestamp synchronization
 * Provides precise control over HTMLAudioElement for synchronized listening
 */
export function useAudioPlayer() {
  const trackStore = useTrackStore()
  const authStore = useAuthStore()

  // Audio element and state
  const audioElement = ref(null)
  const isLoading = ref(false)
  const isBuffering = ref(false)
  const canPlay = ref(false)
  const volume = ref(0.75)
  const muted = ref(false)
  const error = ref(null)
  const duration = ref(0)
  const currentTime = ref(0)
  const buffered = ref([])

  // Synchronization state
  const lastSyncTime = ref(0)
  const syncTolerance = ref(0.1) // 100ms tolerance for sync corrections
  const syncCheckInterval = ref(null)
  const serverTimeOffset = ref(0) // Difference between server and client time
  const networkLatency = ref(0) // Measured network latency
  const syncFailureCount = ref(0) // Count of consecutive sync failures
  const maxSyncFailures = ref(5) // Maximum allowed sync failures before error
  const adaptiveTolerance = ref(0.1) // Dynamic tolerance based on network conditions
  const syncHistory = ref([]) // History of sync measurements for analysis
  const maxSyncHistory = ref(20) // Increased history for better analysis
  const lastOffsetCalculation = ref(0) // Timestamp of last offset calculation

  // Playback state
  const isPlaying = computed(() => trackStore.playbackState.isPlaying)
  const currentTrack = computed(() => trackStore.currentTrack)

  // Audio loading states
  const loadingStates = {
    HAVE_NOTHING: 0,
    HAVE_METADATA: 1,
    HAVE_CURRENT_DATA: 2,
    HAVE_FUTURE_DATA: 3,
    HAVE_ENOUGH_DATA: 4,
  }

  /**
   * Initialize audio element and event listeners
   */
  const initializeAudio = () => {
    if (typeof window === 'undefined') return

    audioElement.value = new Audio()
    audioElement.value.preload = 'auto'
    audioElement.value.volume = volume.value
    audioElement.value.muted = muted.value

    // Audio event listeners
    audioElement.value.addEventListener('loadstart', handleLoadStart)
    audioElement.value.addEventListener('loadedmetadata', handleLoadedMetadata)
    audioElement.value.addEventListener('loadeddata', handleLoadedData)
    audioElement.value.addEventListener('canplay', handleCanPlay)
    audioElement.value.addEventListener('canplaythrough', handleCanPlayThrough)
    audioElement.value.addEventListener('playing', handlePlaying)
    audioElement.value.addEventListener('pause', handlePause)
    audioElement.value.addEventListener('ended', handleEnded)
    audioElement.value.addEventListener('error', handleError)
    audioElement.value.addEventListener('stalled', handleStalled)
    audioElement.value.addEventListener('waiting', handleWaiting)
    audioElement.value.addEventListener('progress', handleProgress)
    audioElement.value.addEventListener('timeupdate', handleTimeUpdate)
    audioElement.value.addEventListener('volumechange', handleVolumeChange)
    audioElement.value.addEventListener('seeking', handleSeeking)
    audioElement.value.addEventListener('seeked', handleSeeked)

    console.log('Audio player initialized')
  }

  /**
   * Calculate server time offset for synchronization with improved latency compensation
   */
  const calculateServerTimeOffset = async () => {
    try {
      const measurements = []
      const numMeasurements = 5 // Increased measurements for better accuracy

      for (let i = 0; i < numMeasurements; i++) {
        const startTime = performance.now()

        // Make a simple request to get server time
        const response = await fetch(`${import.meta.env.VITE_API_URL}/time`, {
          method: 'GET',
          headers: {
            Accept: 'application/json',
            'Cache-Control': 'no-cache',
          },
        })

        const endTime = performance.now()
        const roundTripTime = endTime - startTime

        if (response.ok) {
          const data = await response.json()
          const serverTime = new Date(data.timestamp).getTime()
          const clientReceiveTime = Date.now()
          const networkDelay = roundTripTime / 2

          // More precise offset calculation accounting for processing time
          const estimatedServerTimeAtReceive = serverTime + networkDelay
          const offset = estimatedServerTimeAtReceive - clientReceiveTime

          measurements.push({
            serverTime,
            clientReceiveTime,
            roundTripTime,
            networkDelay,
            offset,
            quality: 1 / roundTripTime, // Higher quality for lower latency
          })
        }

        // Adaptive delay between measurements based on network conditions
        if (i < numMeasurements - 1) {
          const delay = Math.min(50 + i * 25, 200) // 50ms to 200ms
          await new Promise(resolve => setTimeout(resolve, delay))
        }
      }

      if (measurements.length > 0) {
        // Use weighted average of best measurements for more stability
        const sortedMeasurements = measurements
          .sort((a, b) => a.roundTripTime - b.roundTripTime)
          .slice(0, Math.ceil(measurements.length * 0.6)) // Use best 60% of measurements

        const totalWeight = sortedMeasurements.reduce((sum, m) => sum + m.quality, 0)
        const weightedOffset =
          sortedMeasurements.reduce((sum, m) => sum + m.offset * m.quality, 0) / totalWeight
        const avgLatency =
          sortedMeasurements.reduce((sum, m) => sum + m.networkDelay, 0) / sortedMeasurements.length

        serverTimeOffset.value = Math.round(weightedOffset)
        networkLatency.value = Math.round(avgLatency)

        // Update adaptive tolerance based on network conditions and measurement variance
        const variance =
          sortedMeasurements.reduce((sum, m) => sum + Math.pow(m.offset - weightedOffset, 2), 0) /
          sortedMeasurements.length
        updateAdaptiveTolerance(avgLatency, Math.sqrt(variance))

        console.log(
          `Server time offset calculated: ${serverTimeOffset.value}ms, latency: ${networkLatency.value}ms, variance: ${Math.round(Math.sqrt(variance))}ms`
        )

        // Reset sync failure count on successful measurement
        syncFailureCount.value = 0
      }
    } catch (err) {
      console.warn('Failed to calculate server time offset:', err)
      syncFailureCount.value++

      // Use fallback values if sync fails repeatedly
      if (syncFailureCount.value >= maxSyncFailures.value) {
        console.error('Max sync failures reached, using fallback values')
        serverTimeOffset.value = 0
        networkLatency.value = 100 // Conservative default latency
        adaptiveTolerance.value = 0.3 // Increase tolerance for poor connections
      }
    }
  }

  /**
   * Update adaptive tolerance based on network conditions and measurement variance
   */
  const updateAdaptiveTolerance = (latency, variance = 0) => {
    // Base tolerance of 100ms, increase based on network latency and variance
    const baseTolerance = 0.1
    const latencyFactor = Math.min(latency / 1000, 0.4) // Cap at 400ms additional tolerance
    const varianceFactor = Math.min(variance / 1000, 0.2) // Cap at 200ms for variance

    adaptiveTolerance.value = baseTolerance + latencyFactor + varianceFactor
    syncTolerance.value = adaptiveTolerance.value

    console.log(
      `Adaptive tolerance updated: ${Math.round(adaptiveTolerance.value * 1000)}ms (latency: ${Math.round(latency)}ms, variance: ${Math.round(variance)}ms)`
    )
  }

  /**
   * Get current server time accounting for offset
   */
  const getServerTime = () => {
    return Date.now() + serverTimeOffset.value
  }

  /**
   * Calculate expected playback position based on server timestamps with improved accuracy
   */
  const calculateExpectedPosition = () => {
    const playbackState = trackStore.playbackState

    if (!playbackState.isPlaying || !playbackState.startedAt) {
      return playbackState.position || 0
    }

    const serverTime = getServerTime()
    const startTime = new Date(playbackState.startedAt).getTime()

    // Calculate elapsed time since playback started
    let elapsed = (serverTime - startTime) / 1000 // Convert to seconds

    // Account for any paused time
    if (playbackState.pausedAt) {
      const pausedTime = new Date(playbackState.pausedAt).getTime()
      const pauseDuration = (serverTime - pausedTime) / 1000
      elapsed = elapsed - pauseDuration
    }

    // Enhanced network latency compensation with predictive buffering
    const latencyCompensation = networkLatency.value / 1000
    const bufferCompensation = Math.min(latencyCompensation * 0.5, 0.1) // Up to 100ms buffer
    elapsed += latencyCompensation + bufferCompensation

    // Add base position if resuming from a specific point
    const basePosition = playbackState.position || 0

    // For new tracks starting from 0, use elapsed time directly
    // For resumed tracks, add elapsed time to the stored position
    const calculatedPosition = playbackState.position > 0 ? basePosition + elapsed : elapsed

    return Math.max(0, Math.min(calculatedPosition, duration.value))
  }

  /**
   * Synchronize audio playback with server state with enhanced error handling
   */
  const synchronizePlayback = () => {
    if (!audioElement.value || !currentTrack.value) return

    try {
      // Basic play/pause sync
      const shouldBePlaying = isPlaying.value && canPlay.value
      const isActuallyPlaying = !audioElement.value.paused

      if (shouldBePlaying && !isActuallyPlaying) {
        console.log('Sync: Starting audio playback')
        playAudio()
      } else if (!shouldBePlaying && isActuallyPlaying) {
        console.log('Sync: Pausing audio playback')
        pauseAudio()
      }

      // If we're playing, check for position synchronization
      if (shouldBePlaying && isActuallyPlaying) {
        const expectedPosition = calculateExpectedPosition()
        const actualPosition = audioElement.value.currentTime
        const diff = Math.abs(expectedPosition - actualPosition)

        // Only sync if the difference is greater than the adaptive tolerance
        if (diff > syncTolerance.value) {
          console.log(
            `Sync: Position mismatch detected. Diff: ${Math.round(diff * 1000)}ms, Tolerance: ${Math.round(syncTolerance.value * 1000)}ms`
          )

          // Determine urgency based on difference
          const urgency = diff > 2 ? 'urgent' : 'normal'
          performSync(expectedPosition, urgency)

          // Record measurement for adaptive improvements
          recordSyncMeasurement(expectedPosition, actualPosition, diff)
        }
      }
    } catch (err) {
      console.error('Synchronization error:', err)
      syncFailureCount.value++

      if (syncFailureCount.value >= maxSyncFailures.value) {
        handleSyncFailure()
      }
    }
  }

  /**
   * Perform the actual sync operation with different strategies
   */
  const performSync = (expectedPosition, urgency = 'normal') => {
    try {
      // Validate the expected position is reasonable
      if (expectedPosition < 0 || expectedPosition > duration.value) {
        console.warn(`Invalid expected position: ${expectedPosition}, duration: ${duration.value}`)
        syncFailureCount.value++
        return
      }

      // Different sync strategies based on urgency
      if (urgency === 'urgent') {
        // Immediate sync for large differences
        audioElement.value.currentTime = expectedPosition
        lastSyncTime.value = Date.now()
        syncFailureCount.value = 0
      } else {
        // Gradual sync for smaller differences to avoid jarring jumps
        const currentTime = audioElement.value.currentTime
        const diff = expectedPosition - currentTime

        if (Math.abs(diff) > 0.05) {
          // Only sync if difference > 50ms
          // Smooth sync - move 80% of the way to target
          const targetTime = currentTime + diff * 0.8
          audioElement.value.currentTime = targetTime
          lastSyncTime.value = Date.now()
          syncFailureCount.value = 0
        }
      }
    } catch (seekError) {
      console.warn('Failed to sync audio position:', seekError)
      syncFailureCount.value++

      // If seeking fails repeatedly, try to reload the audio
      if (syncFailureCount.value >= maxSyncFailures.value) {
        console.error('Multiple sync failures, attempting audio reload')
        handleSyncFailure()
      }
    }
  }

  /**
   * Sync play/pause state with enhanced error handling
   */
  const syncPlayPauseState = async () => {
    try {
      const shouldBePlaying = isPlaying.value && canPlay.value
      const isActuallyPlaying = !audioElement.value.paused

      if (shouldBePlaying && !isActuallyPlaying) {
        console.log('Starting audio playback')
        await playAudio()
      } else if (!shouldBePlaying && isActuallyPlaying) {
        console.log('Pausing audio playback')
        pauseAudio()
      }
    } catch (err) {
      console.error('Failed to sync play/pause state:', err)
      syncFailureCount.value++
    }
  }

  /**
   * Record sync measurement for analysis and adaptive improvements
   */
  const recordSyncMeasurement = (expected, actual, diff) => {
    const measurement = {
      timestamp: Date.now(),
      expected,
      actual,
      diff,
      tolerance: syncTolerance.value,
      networkLatency: networkLatency.value,
    }

    syncHistory.value.push(measurement)

    // Keep only recent measurements
    if (syncHistory.value.length > maxSyncHistory.value) {
      syncHistory.value.shift()
    }

    // Analyze sync performance and adjust tolerance if needed
    if (syncHistory.value.length >= 5) {
      analyzeSyncPerformance()
    }
  }

  /**
   * Analyze sync performance and adjust parameters
   */
  const analyzeSyncPerformance = () => {
    const recentMeasurements = syncHistory.value.slice(-5)
    const avgDiff =
      recentMeasurements.reduce((sum, m) => sum + m.diff, 0) / recentMeasurements.length
    const maxDiff = Math.max(...recentMeasurements.map(m => m.diff))

    // If we're consistently having large differences, increase tolerance
    if (avgDiff > syncTolerance.value * 0.8 && maxDiff > syncTolerance.value * 1.5) {
      const newTolerance = Math.min(syncTolerance.value * 1.2, 0.5) // Cap at 500ms
      console.log(
        `Increasing sync tolerance from ${Math.round(syncTolerance.value * 1000)}ms to ${Math.round(newTolerance * 1000)}ms due to poor sync performance`
      )
      syncTolerance.value = newTolerance
    }
    // If we're consistently syncing well, we can tighten tolerance
    else if (avgDiff < syncTolerance.value * 0.3 && maxDiff < syncTolerance.value * 0.6) {
      const newTolerance = Math.max(syncTolerance.value * 0.9, 0.05) // Don't go below 50ms
      console.log(
        `Decreasing sync tolerance from ${Math.round(syncTolerance.value * 1000)}ms to ${Math.round(newTolerance * 1000)}ms due to good sync performance`
      )
      syncTolerance.value = newTolerance
    }
  }

  /**
   * Handle sync failures by attempting recovery with progressive strategies
   */
  const handleSyncFailure = async () => {
    console.warn(
      `Handling sync failure (attempt ${syncFailureCount.value}), attempting recovery...`
    )

    try {
      // Progressive recovery strategies based on failure count
      if (syncFailureCount.value <= 3) {
        // Strategy 1: Recalculate server time offset
        console.log('Recovery strategy 1: Recalculating server time offset')
        await calculateServerTimeOffset()
      } else if (syncFailureCount.value <= 6) {
        // Strategy 2: Reload current track
        console.log('Recovery strategy 2: Reloading current track')
        if (currentTrack.value) {
          const track = currentTrack.value
          await loadTrack(track)

          // Wait for track to load, then try to sync
          setTimeout(() => {
            if (canPlay.value) {
              synchronizePlayback()
            }
          }, 1000)
        }
      } else if (syncFailureCount.value <= 9) {
        // Strategy 3: Reset audio element and reload
        console.log('Recovery strategy 3: Resetting audio element')
        if (audioElement.value) {
          audioElement.value.src = ''
          audioElement.value.load()

          if (currentTrack.value) {
            setTimeout(async () => {
              await loadTrack(currentTrack.value)
            }, 500)
          }
        }
      } else {
        // Strategy 4: Full recovery - reinitialize audio system
        console.log('Recovery strategy 4: Full audio system reset')
        const currentTrackBackup = currentTrack.value
        const currentVolumeBackup = volume.value
        const currentMutedBackup = muted.value

        // Reinitialize audio
        if (audioElement.value) {
          audioElement.value.src = ''
          audioElement.value = null
        }

        initializeAudio()

        // Restore settings
        setTimeout(() => {
          if (audioElement.value) {
            audioElement.value.volume = currentVolumeBackup
            audioElement.value.muted = currentMutedBackup

            if (currentTrackBackup) {
              loadTrack(currentTrackBackup)
            }
          }
        }, 1000)

        // Reset failure count after full recovery
        syncFailureCount.value = 0
        error.value = null
        return
      }

      // Partial reset of failure count on recovery attempt
      syncFailureCount.value = Math.max(0, syncFailureCount.value - 2)
    } catch (err) {
      console.error('Failed to recover from sync failure:', err)

      // If all recovery strategies fail, provide user feedback
      if (syncFailureCount.value >= maxSyncFailures.value * 2) {
        error.value =
          'Audio synchronization failed repeatedly. Please refresh the page or check your network connection.'

        // Stop sync checks to prevent further errors
        stopSyncChecks()
      }
    }
  }

  /**
   * Start periodic synchronization checks with adaptive intervals
   */
  const startSyncChecks = () => {
    if (syncCheckInterval.value) return

    const checkInterval = 1000 // Check every 1 second

    syncCheckInterval.value = setInterval(() => {
      if (isPlaying.value && currentTrack.value) {
        synchronizePlayback()
      }
    }, checkInterval)

    console.log(`Started sync checks with ${checkInterval}ms interval`)
  }

  /**
   * Calculate optimal sync check interval based on network conditions and performance
   */
  const calculateOptimalSyncInterval = () => {
    let baseInterval = 1000 // 1 second base interval

    // Adjust based on network latency
    if (networkLatency.value > 200) {
      baseInterval = 500 // Check more frequently for high-latency connections
    } else if (networkLatency.value > 100) {
      baseInterval = 750 // Moderate frequency for medium latency
    } else if (networkLatency.value < 30) {
      baseInterval = 1500 // Check less frequently for excellent connections
    }

    // Adjust based on sync failure rate
    if (syncFailureCount.value > 3) {
      baseInterval = Math.max(300, baseInterval * 0.5) // Check more frequently if failing
    } else if (syncFailureCount.value === 0 && syncHistory.value.length > 5) {
      // If sync is consistently good, can check less frequently
      const recentDiffs = syncHistory.value.slice(-5).map(h => h.diff)
      const avgDiff = recentDiffs.reduce((sum, diff) => sum + diff, 0) / recentDiffs.length

      if (avgDiff < syncTolerance.value * 0.3) {
        baseInterval = Math.min(2000, baseInterval * 1.5) // Check less frequently if very stable
      }
    }

    return baseInterval
  }

  /**
   * Stop periodic synchronization checks
   */
  const stopSyncChecks = () => {
    if (syncCheckInterval.value) {
      clearInterval(syncCheckInterval.value)
      syncCheckInterval.value = null
      console.log('Stopped sync checks')
    }
  }

  /**
   * Load audio track
   */
  const loadTrack = async track => {
    if (!audioElement.value || !track) return

    try {
      isLoading.value = true
      error.value = null
      canPlay.value = false

      // Construct audio URL
      const token = authStore.token || localStorage.getItem('auth_token') || ''
      const baseUrl = import.meta.env.VITE_API_URL
      const audioUrl = `${baseUrl}/tracks/${track.id}/stream${token ? `?token=${encodeURIComponent(token)}` : ''}`

      console.log(`Loading track: ${track.original_name}`)
      audioElement.value.src = audioUrl
      audioElement.value.load()
    } catch (err) {
      console.error('Failed to load track:', err)
      error.value = err.message || 'Failed to load audio track'
      isLoading.value = false
    }
  }

  /**
   * Play audio
   */
  const playAudio = async () => {
    if (!audioElement.value || !canPlay.value) return

    try {
      await audioElement.value.play()
      startSyncChecks()
    } catch (err) {
      console.error('Failed to play audio:', err)
      error.value = err.message || 'Failed to play audio'
    }
  }

  /**
   * Pause audio
   */
  const pauseAudio = () => {
    if (!audioElement.value) return

    try {
      audioElement.value.pause()
      stopSyncChecks()
    } catch (err) {
      console.error('Failed to pause audio:', err)
    }
  }

  /**
   * Stop audio and reset position
   */
  const stopAudio = () => {
    if (!audioElement.value) return

    try {
      audioElement.value.pause()
      audioElement.value.currentTime = 0
      stopSyncChecks()
    } catch (err) {
      console.error('Failed to stop audio:', err)
    }
  }

  /**
   * Set audio volume (0-1)
   */
  const setVolume = newVolume => {
    if (!audioElement.value) return

    const clampedVolume = Math.max(0, Math.min(1, newVolume))
    volume.value = clampedVolume
    audioElement.value.volume = clampedVolume
  }

  /**
   * Toggle mute state
   */
  const toggleMute = () => {
    if (!audioElement.value) return

    muted.value = !muted.value
    audioElement.value.muted = muted.value
  }

  /**
   * Seek to specific position
   */
  const seekTo = position => {
    if (!audioElement.value || !canPlay.value) return

    try {
      const clampedPosition = Math.max(0, Math.min(duration.value, position))
      audioElement.value.currentTime = clampedPosition
    } catch (err) {
      console.error('Failed to seek:', err)
    }
  }

  // Event handlers
  const handleLoadStart = () => {
    isLoading.value = true
    console.log('Audio load started')
  }

  const handleLoadedMetadata = () => {
    duration.value = audioElement.value.duration || 0
    console.log(`Audio metadata loaded, duration: ${duration.value}s`)
  }

  const handleLoadedData = () => {
    console.log('Audio data loaded')
  }

  const handleCanPlay = () => {
    canPlay.value = true
    isLoading.value = false
    console.log('Audio can play')

    // Start playback if the track store says we should be playing
    if (isPlaying.value) {
      console.log('Track store indicates playing, starting audio')
      playAudio()
    }
  }

  const handleCanPlayThrough = () => {
    isBuffering.value = false
    console.log('Audio can play through')
  }

  const handlePlaying = () => {
    isBuffering.value = false
    console.log('Audio playing')
  }

  const handlePause = () => {
    console.log('Audio paused')
  }

  const handleEnded = () => {
    console.log('Audio ended - track completed')
    stopSyncChecks()

    // Simply update the track store to indicate the track ended
    // The room/playback logic will handle what happens next
    trackStore.updatePlaybackState({
      isPlaying: false,
      position: duration.value,
    })
  }

  const handleError = event => {
    const audioError = audioElement.value.error
    let errorMessage = 'Audio playback error'

    if (audioError) {
      switch (audioError.code) {
        case audioError.MEDIA_ERR_ABORTED:
          errorMessage = 'Audio playback aborted'
          break
        case audioError.MEDIA_ERR_NETWORK:
          errorMessage = 'Network error while loading audio'
          break
        case audioError.MEDIA_ERR_DECODE:
          errorMessage = 'Audio decoding error'
          break
        case audioError.MEDIA_ERR_SRC_NOT_SUPPORTED:
          errorMessage = 'Audio format not supported'
          break
        default:
          errorMessage = 'Unknown audio error'
      }
    }

    console.error('Audio error:', errorMessage, audioError)
    error.value = errorMessage
    isLoading.value = false
    canPlay.value = false

    // Recovery: reload audio with cache-busting and fresh token
    try {
      if (currentTrack.value && audioElement.value) {
        const token = authStore.token || localStorage.getItem('auth_token') || ''
        const baseUrl = import.meta.env.VITE_API_URL
        const ts = Date.now()
        const audioUrl = `${baseUrl}/tracks/${currentTrack.value.id}/stream${token ? `?token=${encodeURIComponent(token)}&ts=${ts}` : `?ts=${ts}`}`
        audioElement.value.src = audioUrl
        audioElement.value.load()
      }
    } catch (e) {
      console.error('Audio recovery failed:', e)
    }
  }

  const handleStalled = () => {
    console.warn('Audio stalled')
    isBuffering.value = true
  }

  const handleWaiting = () => {
    console.log('Audio waiting for data')
    isBuffering.value = true
  }

  const handleProgress = () => {
    if (!audioElement.value) return

    const timeRanges = audioElement.value.buffered
    const bufferRanges = []

    for (let i = 0; i < timeRanges.length; i++) {
      bufferRanges.push({
        start: timeRanges.start(i),
        end: timeRanges.end(i),
      })
    }

    buffered.value = bufferRanges
  }

  const handleTimeUpdate = () => {
    if (!audioElement.value) return
    currentTime.value = audioElement.value.currentTime
  }

  const handleVolumeChange = () => {
    if (!audioElement.value) return
    volume.value = audioElement.value.volume
    muted.value = audioElement.value.muted
  }

  const handleSeeking = () => {
    console.log('Audio seeking')
  }

  const handleSeeked = () => {
    console.log('Audio seeked')
  }

  // Watch for track changes
  watch(currentTrack, async (newTrack, oldTrack) => {
    if (newTrack && newTrack.id !== oldTrack?.id) {
      console.log('Loading new track:', newTrack.original_name)
      await loadTrack(newTrack)
    } else if (!newTrack) {
      console.log('No current track, stopping audio')
      stopAudio()
    }
  })

  // Watch for playback state changes
  watch(
    () => trackStore.playbackState,
    newState => {
      console.log('Playback state changed:', newState)
      if (currentTrack.value && canPlay.value) {
        // Simple sync without complex timing calculations
        const shouldBePlaying = newState.isPlaying
        const isActuallyPlaying = audioElement.value && !audioElement.value.paused

        if (shouldBePlaying && !isActuallyPlaying) {
          console.log('Should be playing, starting audio')
          playAudio()
        } else if (!shouldBePlaying && isActuallyPlaying) {
          console.log('Should be paused, pausing audio')
          pauseAudio()
        }
      }
    },
    { deep: true }
  )

  // Watch for token changes: refresh audio URL and reload
  watch(
    () => authStore.token,
    (newToken, oldToken) => {
      if (newToken && newToken !== oldToken && currentTrack.value && audioElement.value) {
        try {
          const baseUrl = import.meta.env.VITE_API_URL
          const ts = Date.now()
          const audioUrl = `${baseUrl}/tracks/${currentTrack.value.id}/stream?token=${encodeURIComponent(newToken)}&ts=${ts}`
          audioElement.value.src = audioUrl
          audioElement.value.load()
        } catch (e) {
          console.error('Failed to reload audio on token change:', e)
        }
      }
    }
  )

  // Lifecycle
  onMounted(() => {
    initializeAudio()
    // Calculate server time offset on mount
    calculateServerTimeOffset()
    console.log('Audio player mounted')
  })

  onUnmounted(() => {
    stopSyncChecks()

    if (audioElement.value) {
      // Remove all event listeners
      audioElement.value.removeEventListener('loadstart', handleLoadStart)
      audioElement.value.removeEventListener('loadedmetadata', handleLoadedMetadata)
      audioElement.value.removeEventListener('loadeddata', handleLoadedData)
      audioElement.value.removeEventListener('canplay', handleCanPlay)
      audioElement.value.removeEventListener('canplaythrough', handleCanPlayThrough)
      audioElement.value.removeEventListener('playing', handlePlaying)
      audioElement.value.removeEventListener('pause', handlePause)
      audioElement.value.removeEventListener('ended', handleEnded)
      audioElement.value.removeEventListener('error', handleError)
      audioElement.value.removeEventListener('stalled', handleStalled)
      audioElement.value.removeEventListener('waiting', handleWaiting)
      audioElement.value.removeEventListener('progress', handleProgress)
      audioElement.value.removeEventListener('timeupdate', handleTimeUpdate)
      audioElement.value.removeEventListener('volumechange', handleVolumeChange)
      audioElement.value.removeEventListener('seeking', handleSeeking)
      audioElement.value.removeEventListener('seeked', handleSeeked)

      audioElement.value.src = ''
      audioElement.value = null
    }
  })

  return {
    // State
    audioElement,
    isLoading,
    isBuffering,
    canPlay,
    volume,
    muted,
    error,
    duration,
    currentTime,
    buffered,
    syncTolerance,
    serverTimeOffset,
    networkLatency,
    syncFailureCount,
    adaptiveTolerance,
    syncHistory,

    // Computed
    isPlaying,
    currentTrack,

    // Methods
    loadTrack,
    playAudio,
    pauseAudio,
    stopAudio,
    setVolume,
    toggleMute,
    seekTo,
    synchronizePlayback,
    calculateExpectedPosition,
    getServerTime,
    calculateServerTimeOffset,
    handleSyncFailure,

    // Sync control
    startSyncChecks,
    stopSyncChecks,
    calculateOptimalSyncInterval,
    performSync,
    syncPlayPauseState,
  }
}
