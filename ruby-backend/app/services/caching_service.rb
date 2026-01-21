# Caching Service
# Implements comprehensive caching strategies for performance optimization

require_relative '../services/logging_service'
require_relative '../services/performance_monitor'

class CachingService
  # Cache configuration
  CACHE_SETTINGS = {
    # Default TTL values (in seconds)
    default_ttl: 300,           # 5 minutes
    short_ttl: 60,              # 1 minute
    medium_ttl: 300,            # 5 minutes
    long_ttl: 1800,             # 30 minutes
    
    # Cache size limits
    max_cache_entries: 10000,
    max_memory_mb: 100,
    
    # Cleanup intervals
    cleanup_interval: 300,      # 5 minutes
    stats_interval: 60,         # 1 minute
    
    # Cache strategies
    eviction_strategy: :lru,    # Least Recently Used
    compression_enabled: true,
    serialization_format: :json
  }.freeze
  
  # Cache types with specific configurations
  CACHE_TYPES = {
    room_state: {
      ttl: 30,                  # 30 seconds for room state
      max_entries: 1000,
      compression: false,       # Room state changes frequently
      priority: :high
    },
    track_queue: {
      ttl: 60,                  # 1 minute for track queues
      max_entries: 2000,
      compression: false,
      priority: :high
    },
    user_data: {
      ttl: 600,                 # 10 minutes for user data
      max_entries: 5000,
      compression: true,
      priority: :medium
    },
    file_metadata: {
      ttl: 3600,                # 1 hour for file metadata
      max_entries: 10000,
      compression: true,
      priority: :low
    },
    api_response: {
      ttl: 120,                 # 2 minutes for API responses
      max_entries: 3000,
      compression: true,
      priority: :medium
    },
    database_query: {
      ttl: 180,                 # 3 minutes for database queries
      max_entries: 5000,
      compression: true,
      priority: :high
    }
  }.freeze
  
  # Cache storage
  @@cache_stores = {}
  @@cache_stats = {
    hits: Hash.new(0),
    misses: Hash.new(0),
    sets: Hash.new(0),
    deletes: Hash.new(0),
    evictions: Hash.new(0),
    memory_usage: Hash.new(0),
    total_operations: 0
  }
  
  # Cache metadata
  @@cache_metadata = {}
  
  class << self
    # Initialize caching service
    def initialize_caching
      LoggingService.log_info(:cache, "Initializing caching service")
      
      begin
        # Initialize cache stores for each type
        CACHE_TYPES.each do |cache_type, config|
          @@cache_stores[cache_type] = {}
          @@cache_metadata[cache_type] = {
            config: config,
            created_at: Time.now,
            last_cleanup: Time.now,
            entry_count: 0,
            memory_usage: 0
          }
        end
        
        # Setup periodic cleanup
        setup_periodic_cleanup
        
        # Setup statistics collection
        setup_statistics_collection
        
        LoggingService.log_info(:cache, "Caching service initialized successfully", {
          cache_types: CACHE_TYPES.keys,
          total_max_entries: CACHE_TYPES.values.sum { |config| config[:max_entries] }
        })
        
      rescue => e
        LoggingService.log_error(:cache, "Failed to initialize caching service", {}, e)
        raise
      end
    end
    
    # Get value from cache
    def get(cache_type, key)
      return nil unless cache_enabled? && valid_cache_type?(cache_type)
      
      cache_store = @@cache_stores[cache_type]
      cached_item = cache_store[key]
      
      @@cache_stats[:total_operations] += 1
      
      if cached_item && !expired?(cached_item)
        # Update access time for LRU
        cached_item[:accessed_at] = Time.now
        cached_item[:access_count] += 1
        
        @@cache_stats[:hits][cache_type] += 1
        
        LoggingService.log_debug(:cache, "Cache hit", {
          cache_type: cache_type,
          key: key,
          age_seconds: Time.now - cached_item[:created_at]
        })
        
        deserialize_value(cached_item[:value], cached_item[:compressed])
      else
        # Remove expired item
        if cached_item
          cache_store.delete(key)
          update_cache_metadata(cache_type, -1, -cached_item[:size])
        end
        
        @@cache_stats[:misses][cache_type] += 1
        
        LoggingService.log_debug(:cache, "Cache miss", {
          cache_type: cache_type,
          key: key,
          expired: cached_item ? expired?(cached_item) : false
        })
        
        nil
      end
    end
    
    # Set value in cache
    def set(cache_type, key, value, options = {})
      return false unless cache_enabled? && valid_cache_type?(cache_type)
      
      config = CACHE_TYPES[cache_type]
      cache_store = @@cache_stores[cache_type]
      
      # Serialize and optionally compress the value
      serialized_value, compressed = serialize_value(value, config[:compression])
      value_size = serialized_value.bytesize
      
      # Check if we need to evict entries
      if cache_store.length >= config[:max_entries]
        evict_entries(cache_type, 1)
      end
      
      # Create cache entry
      cache_entry = {
        value: serialized_value,
        compressed: compressed,
        created_at: Time.now,
        accessed_at: Time.now,
        access_count: 0,
        ttl: options[:ttl] || config[:ttl],
        size: value_size,
        priority: config[:priority]
      }
      
      # Store in cache
      cache_store[key] = cache_entry
      update_cache_metadata(cache_type, 1, value_size)
      
      @@cache_stats[:sets][cache_type] += 1
      @@cache_stats[:total_operations] += 1
      
      LoggingService.log_debug(:cache, "Cache set", {
        cache_type: cache_type,
        key: key,
        size_bytes: value_size,
        compressed: compressed,
        ttl: cache_entry[:ttl]
      })
      
      true
    end
    
    # Delete value from cache
    def delete(cache_type, key)
      return false unless cache_enabled? && valid_cache_type?(cache_type)
      
      cache_store = @@cache_stores[cache_type]
      cached_item = cache_store.delete(key)
      
      if cached_item
        update_cache_metadata(cache_type, -1, -cached_item[:size])
        @@cache_stats[:deletes][cache_type] += 1
        @@cache_stats[:total_operations] += 1
        
        LoggingService.log_debug(:cache, "Cache delete", {
          cache_type: cache_type,
          key: key,
          age_seconds: Time.now - cached_item[:created_at]
        })
        
        true
      else
        false
      end
    end
    
    # Clear entire cache type
    def clear(cache_type)
      return false unless cache_enabled? && valid_cache_type?(cache_type)
      
      cache_store = @@cache_stores[cache_type]
      entry_count = cache_store.length
      
      cache_store.clear
      
      @@cache_metadata[cache_type][:entry_count] = 0
      @@cache_metadata[cache_type][:memory_usage] = 0
      
      LoggingService.log_info(:cache, "Cache cleared", {
        cache_type: cache_type,
        entries_cleared: entry_count
      })
      
      true
    end
    
    # Clear all caches
    def clear_all
      return false unless cache_enabled?
      
      total_entries = 0
      
      CACHE_TYPES.keys.each do |cache_type|
        total_entries += @@cache_stores[cache_type].length
        clear(cache_type)
      end
      
      LoggingService.log_info(:cache, "All caches cleared", {
        total_entries_cleared: total_entries
      })
      
      true
    end
    
    # Check if key exists in cache
    def exists?(cache_type, key)
      return false unless cache_enabled? && valid_cache_type?(cache_type)
      
      cache_store = @@cache_stores[cache_type]
      cached_item = cache_store[key]
      
      cached_item && !expired?(cached_item)
    end
    
    # Get cache statistics
    def get_statistics
      total_entries = @@cache_stores.values.sum(&:length)
      total_memory = @@cache_metadata.values.sum { |meta| meta[:memory_usage] }
      
      cache_type_stats = {}
      CACHE_TYPES.keys.each do |cache_type|
        cache_type_stats[cache_type] = {
          entries: @@cache_stores[cache_type].length,
          max_entries: CACHE_TYPES[cache_type][:max_entries],
          memory_usage_bytes: @@cache_metadata[cache_type][:memory_usage],
          hits: @@cache_stats[:hits][cache_type],
          misses: @@cache_stats[:misses][cache_type],
          hit_rate: calculate_hit_rate(cache_type),
          sets: @@cache_stats[:sets][cache_type],
          deletes: @@cache_stats[:deletes][cache_type],
          evictions: @@cache_stats[:evictions][cache_type]
        }
      end
      
      {
        enabled: cache_enabled?,
        total_entries: total_entries,
        total_memory_bytes: total_memory,
        total_memory_mb: (total_memory / 1024.0 / 1024.0).round(2),
        max_memory_mb: CACHE_SETTINGS[:max_memory_mb],
        total_operations: @@cache_stats[:total_operations],
        cache_types: cache_type_stats,
        overall_hit_rate: calculate_overall_hit_rate,
        settings: CACHE_SETTINGS
      }
    end
    
    # Warm up cache with commonly accessed data
    def warm_up_cache
      return unless cache_enabled?
      
      LoggingService.log_info(:cache, "Starting cache warm-up")
      
      begin
        # Warm up room state cache for active rooms
        warm_up_room_states
        
        # Warm up user data cache for recent users
        warm_up_user_data
        
        # Warm up file metadata cache
        warm_up_file_metadata
        
        LoggingService.log_info(:cache, "Cache warm-up completed")
        
      rescue => e
        LoggingService.log_error(:cache, "Cache warm-up failed", {}, e)
      end
    end
    
    # Force cleanup of expired entries
    def cleanup_expired_entries
      return unless cache_enabled?
      
      total_cleaned = 0
      
      CACHE_TYPES.keys.each do |cache_type|
        cleaned = cleanup_cache_type(cache_type)
        total_cleaned += cleaned
      end
      
      if total_cleaned > 0
        LoggingService.log_info(:cache, "Cleaned up expired cache entries", {
          total_cleaned: total_cleaned
        })
      end
      
      total_cleaned
    end
    
    # Get cache health status
    def get_health_status
      stats = get_statistics
      
      health_issues = []
      
      # Check memory usage
      if stats[:total_memory_mb] > CACHE_SETTINGS[:max_memory_mb] * 0.9
        health_issues << "High memory usage: #{stats[:total_memory_mb]}MB"
      end
      
      # Check hit rates
      CACHE_TYPES.keys.each do |cache_type|
        hit_rate = stats[:cache_types][cache_type][:hit_rate]
        if hit_rate < 50 && stats[:cache_types][cache_type][:hits] > 10
          health_issues << "Low hit rate for #{cache_type}: #{hit_rate}%"
        end
      end
      
      # Check for cache overflow
      CACHE_TYPES.keys.each do |cache_type|
        type_stats = stats[:cache_types][cache_type]
        if type_stats[:entries] >= type_stats[:max_entries] * 0.95
          health_issues << "Cache type #{cache_type} near capacity: #{type_stats[:entries]}/#{type_stats[:max_entries]}"
        end
      end
      
      {
        status: health_issues.empty? ? 'healthy' : 'warning',
        issues: health_issues,
        total_entries: stats[:total_entries],
        memory_usage_mb: stats[:total_memory_mb],
        overall_hit_rate: stats[:overall_hit_rate]
      }
    end
    
    private
    
    # Helper methods
    def cache_enabled?
      SpotikConfig::Settings.cache_enabled?
    end
    
    def valid_cache_type?(cache_type)
      CACHE_TYPES.key?(cache_type)
    end
    
    def expired?(cached_item)
      Time.now - cached_item[:created_at] > cached_item[:ttl]
    end
    
    def serialize_value(value, compress = false)
      case CACHE_SETTINGS[:serialization_format]
      when :json
        serialized = value.to_json
      when :marshal
        serialized = Marshal.dump(value)
      else
        serialized = value.to_s
      end
      
      if compress && CACHE_SETTINGS[:compression_enabled]
        begin
          require 'zlib'
          compressed_value = Zlib::Deflate.deflate(serialized)
          [compressed_value, true]
        rescue
          [serialized, false]
        end
      else
        [serialized, false]
      end
    end
    
    def deserialize_value(serialized_value, compressed)
      value = serialized_value
      
      if compressed
        begin
          require 'zlib'
          value = Zlib::Inflate.inflate(serialized_value)
        rescue => e
          LoggingService.log_warn(:cache, "Failed to decompress cached value", { error: e.message })
          return nil
        end
      end
      
      case CACHE_SETTINGS[:serialization_format]
      when :json
        JSON.parse(value)
      when :marshal
        Marshal.load(value)
      else
        value
      end
    rescue => e
      LoggingService.log_warn(:cache, "Failed to deserialize cached value", { error: e.message })
      nil
    end
    
    def update_cache_metadata(cache_type, entry_delta, size_delta)
      metadata = @@cache_metadata[cache_type]
      metadata[:entry_count] += entry_delta
      metadata[:memory_usage] += size_delta
    end
    
    def evict_entries(cache_type, count)
      cache_store = @@cache_stores[cache_type]
      config = CACHE_TYPES[cache_type]
      
      # Get entries sorted by eviction strategy
      entries_to_evict = case CACHE_SETTINGS[:eviction_strategy]
      when :lru
        # Least Recently Used
        cache_store.sort_by { |key, item| item[:accessed_at] }.first(count)
      when :lfu
        # Least Frequently Used
        cache_store.sort_by { |key, item| item[:access_count] }.first(count)
      when :fifo
        # First In, First Out
        cache_store.sort_by { |key, item| item[:created_at] }.first(count)
      else
        # Random eviction
        cache_store.to_a.sample(count)
      end
      
      # Evict the selected entries
      entries_to_evict.each do |key, item|
        cache_store.delete(key)
        update_cache_metadata(cache_type, -1, -item[:size])
        @@cache_stats[:evictions][cache_type] += 1
      end
      
      LoggingService.log_debug(:cache, "Evicted cache entries", {
        cache_type: cache_type,
        evicted_count: entries_to_evict.length,
        strategy: CACHE_SETTINGS[:eviction_strategy]
      })
    end
    
    def cleanup_cache_type(cache_type)
      cache_store = @@cache_stores[cache_type]
      expired_keys = []
      
      cache_store.each do |key, item|
        if expired?(item)
          expired_keys << key
        end
      end
      
      expired_keys.each do |key|
        cached_item = cache_store.delete(key)
        update_cache_metadata(cache_type, -1, -cached_item[:size]) if cached_item
      end
      
      @@cache_metadata[cache_type][:last_cleanup] = Time.now
      
      expired_keys.length
    end
    
    def calculate_hit_rate(cache_type)
      hits = @@cache_stats[:hits][cache_type]
      misses = @@cache_stats[:misses][cache_type]
      total = hits + misses
      
      return 0.0 if total == 0
      (hits.to_f / total * 100).round(2)
    end
    
    def calculate_overall_hit_rate
      total_hits = @@cache_stats[:hits].values.sum
      total_misses = @@cache_stats[:misses].values.sum
      total = total_hits + total_misses
      
      return 0.0 if total == 0
      (total_hits.to_f / total * 100).round(2)
    end
    
    def setup_periodic_cleanup
      return unless defined?(Iodine)
      
      # Clean up expired entries every 5 minutes
      Iodine.run_every(CACHE_SETTINGS[:cleanup_interval] * 1000) do
        cleanup_expired_entries
      end
      
      LoggingService.log_info(:cache, "Periodic cleanup scheduled")
    end
    
    def setup_statistics_collection
      return unless defined?(Iodine)
      
      # Log cache statistics every minute
      Iodine.run_every(CACHE_SETTINGS[:stats_interval] * 1000) do
        stats = get_statistics
        LoggingService.log_info(:cache, "Cache statistics", stats)
      end
      
      LoggingService.log_info(:cache, "Statistics collection scheduled")
    end
    
    # Cache warm-up methods
    def warm_up_room_states
      # Get active rooms and cache their states
      begin
        active_rooms = Room.where(is_playing: true).limit(50).all
        
        active_rooms.each do |room|
          room_state = RoomManager.get_room_state(room.id)
          if room_state
            set(:room_state, "room_#{room.id}", room_state)
          end
        end
        
        LoggingService.log_info(:cache, "Room states warmed up", {
          rooms_cached: active_rooms.length
        })
        
      rescue => e
        LoggingService.log_warn(:cache, "Failed to warm up room states", { error: e.message })
      end
    end
    
    def warm_up_user_data
      # Cache recent user data
      begin
        recent_users = User.order(:updated_at).limit(100).all
        
        recent_users.each do |user|
          set(:user_data, "user_#{user.id}", user.to_hash)
        end
        
        LoggingService.log_info(:cache, "User data warmed up", {
          users_cached: recent_users.length
        })
        
      rescue => e
        LoggingService.log_warn(:cache, "Failed to warm up user data", { error: e.message })
      end
    end
    
    def warm_up_file_metadata
      # Cache file metadata for recent tracks
      begin
        recent_tracks = Track.order(:created_at).limit(200).all
        
        recent_tracks.each do |track|
          if FileService.file_exists?(track.filename)
            metadata = FileService.get_file_metadata(track.filename)
            if metadata[:success]
              set(:file_metadata, "file_#{track.filename}", metadata)
            end
          end
        end
        
        LoggingService.log_info(:cache, "File metadata warmed up", {
          files_cached: recent_tracks.length
        })
        
      rescue => e
        LoggingService.log_warn(:cache, "Failed to warm up file metadata", { error: e.message })
      end
    end
  end
end