# Database Performance Optimizer
# Implements database query optimization, indexing strategies, and connection pooling enhancements

require_relative '../services/logging_service'
require_relative '../services/performance_monitor'

class DatabaseOptimizer
  # Index definitions for performance optimization
  PERFORMANCE_INDEXES = {
    # User table indexes
    users: [
      { columns: [:username], unique: true, name: 'idx_users_username_unique' },
      { columns: [:email], unique: true, name: 'idx_users_email_unique' },
      { columns: [:created_at], name: 'idx_users_created_at' },
      { columns: [:updated_at], name: 'idx_users_updated_at' }
    ],
    
    # Room table indexes
    rooms: [
      { columns: [:administrator_id], name: 'idx_rooms_administrator_id' },
      { columns: [:current_track_id], name: 'idx_rooms_current_track_id' },
      { columns: [:is_playing], name: 'idx_rooms_is_playing' },
      { columns: [:created_at], name: 'idx_rooms_created_at' },
      { columns: [:updated_at], name: 'idx_rooms_updated_at' },
      { columns: [:administrator_id, :is_playing], name: 'idx_rooms_admin_playing' },
      { columns: [:is_playing, :current_track_id], name: 'idx_rooms_playing_track' }
    ],
    
    # Track table indexes
    tracks: [
      { columns: [:room_id], name: 'idx_tracks_room_id' },
      { columns: [:uploader_id], name: 'idx_tracks_uploader_id' },
      { columns: [:vote_score], name: 'idx_tracks_vote_score' },
      { columns: [:created_at], name: 'idx_tracks_created_at' },
      { columns: [:updated_at], name: 'idx_tracks_updated_at' },
      { columns: [:room_id, :vote_score, :created_at], name: 'idx_tracks_queue_order' },
      { columns: [:room_id, :created_at], name: 'idx_tracks_room_chronological' },
      { columns: [:uploader_id, :created_at], name: 'idx_tracks_uploader_chronological' },
      { columns: [:filename], unique: true, name: 'idx_tracks_filename_unique' }
    ],
    
    # Room participants table indexes
    room_participants: [
      { columns: [:room_id], name: 'idx_room_participants_room_id' },
      { columns: [:user_id], name: 'idx_room_participants_user_id' },
      { columns: [:room_id, :user_id], unique: true, name: 'idx_room_participants_unique' },
      { columns: [:joined_at], name: 'idx_room_participants_joined_at' },
      { columns: [:room_id, :joined_at], name: 'idx_room_participants_room_joined' }
    ],
    
    # Track votes table indexes
    track_votes: [
      { columns: [:track_id], name: 'idx_track_votes_track_id' },
      { columns: [:user_id], name: 'idx_track_votes_user_id' },
      { columns: [:track_id, :user_id], unique: true, name: 'idx_track_votes_unique' },
      { columns: [:created_at], name: 'idx_track_votes_created_at' },
      { columns: [:track_id, :created_at], name: 'idx_track_votes_track_chronological' }
    ]
  }.freeze
  
  # Query optimization patterns
  QUERY_OPTIMIZATIONS = {
    # Room queue optimization - pre-sorted by vote score and creation time
    room_track_queue: {
      base_query: 'SELECT * FROM tracks WHERE room_id = ? ORDER BY vote_score DESC, created_at ASC',
      optimized_query: 'SELECT * FROM tracks WHERE room_id = ? ORDER BY vote_score DESC, created_at ASC LIMIT 100',
      cache_key: 'room_queue',
      cache_ttl: 30
    },
    
    # Room participants with user data
    room_participants_with_users: {
      base_query: 'SELECT rp.*, u.username, u.email FROM room_participants rp JOIN users u ON rp.user_id = u.id WHERE rp.room_id = ?',
      optimized_query: 'SELECT rp.*, u.username, u.email FROM room_participants rp JOIN users u ON rp.user_id = u.id WHERE rp.room_id = ? ORDER BY rp.joined_at ASC',
      cache_key: 'room_participants',
      cache_ttl: 60
    },
    
    # Track votes with user data
    track_votes_with_users: {
      base_query: 'SELECT tv.*, u.username FROM track_votes tv JOIN users u ON tv.user_id = u.id WHERE tv.track_id = ?',
      optimized_query: 'SELECT tv.*, u.username FROM track_votes tv JOIN users u ON tv.user_id = u.id WHERE tv.track_id = ? ORDER BY tv.created_at ASC',
      cache_key: 'track_votes',
      cache_ttl: 30
    },
    
    # Active rooms with current track info
    active_rooms: {
      base_query: 'SELECT r.*, t.original_name as current_track_name FROM rooms r LEFT JOIN tracks t ON r.current_track_id = t.id WHERE r.is_playing = true',
      optimized_query: 'SELECT r.*, t.original_name as current_track_name FROM rooms r LEFT JOIN tracks t ON r.current_track_id = t.id WHERE r.is_playing = true ORDER BY r.updated_at DESC',
      cache_key: 'active_rooms',
      cache_ttl: 15
    }
  }.freeze
  
  # Connection pool optimization settings
  CONNECTION_POOL_SETTINGS = {
    development: {
      max_connections: 10,
      pool_timeout: 5,
      checkout_timeout: 5,
      reap_frequency: 10,
      pool_sleep_time: 0.001
    },
    production: {
      max_connections: 25,
      pool_timeout: 10,
      checkout_timeout: 10,
      reap_frequency: 30,
      pool_sleep_time: 0.001
    },
    test: {
      max_connections: 5,
      pool_timeout: 2,
      checkout_timeout: 2,
      reap_frequency: 5,
      pool_sleep_time: 0.001
    }
  }.freeze
  
  # Query result cache
  @@query_cache = {}
  @@cache_stats = {
    hits: 0,
    misses: 0,
    evictions: 0,
    total_queries: 0
  }
  
  class << self
    # Initialize database optimizations
    def initialize_optimizations
      LoggingService.log_info(:database, "Initializing database performance optimizations")
      
      begin
        # Create performance indexes
        create_performance_indexes
        
        # Optimize connection pool settings
        optimize_connection_pool
        
        # Setup query result caching
        setup_query_caching
        
        # Setup periodic optimization tasks
        setup_periodic_optimizations
        
        LoggingService.log_info(:database, "Database performance optimizations initialized successfully")
        
      rescue => e
        LoggingService.log_error(:database, "Failed to initialize database optimizations", {}, e)
        raise
      end
    end
    
    # Create performance indexes
    def create_performance_indexes
      return unless SpotikConfig::Database.connection
      
      db = SpotikConfig::Database.connection
      created_indexes = []
      skipped_indexes = []
      
      PERFORMANCE_INDEXES.each do |table, indexes|
        next unless db.table_exists?(table)
        
        indexes.each do |index_def|
          index_name = index_def[:name]
          
          begin
            # Check if index already exists
            existing_indexes = db.indexes(table)
            if existing_indexes.key?(index_name.to_sym)
              skipped_indexes << "#{table}.#{index_name}"
              next
            end
            
            # Create the index
            options = {}
            options[:unique] = true if index_def[:unique]
            options[:name] = index_name
            
            db.add_index(table, index_def[:columns], options)
            created_indexes << "#{table}.#{index_name}"
            
            LoggingService.log_info(:database, "Created performance index", {
              table: table,
              index_name: index_name,
              columns: index_def[:columns],
              unique: index_def[:unique] || false
            })
            
          rescue => e
            LoggingService.log_warn(:database, "Failed to create index #{index_name} on #{table}", {
              error: e.message,
              columns: index_def[:columns]
            })
          end
        end
      end
      
      LoggingService.log_info(:database, "Index creation summary", {
        created: created_indexes.length,
        skipped: skipped_indexes.length,
        created_indexes: created_indexes,
        skipped_indexes: skipped_indexes
      })
    end
    
    # Optimize connection pool settings
    def optimize_connection_pool
      return unless SpotikConfig::Database.connection
      
      env = SpotikConfig::Settings.app_env.to_sym
      settings = CONNECTION_POOL_SETTINGS[env] || CONNECTION_POOL_SETTINGS[:development]
      
      db = SpotikConfig::Database.connection
      pool = db.pool
      
      # Apply optimized settings if pool supports them
      begin
        if pool.respond_to?(:max_size=)
          pool.max_size = settings[:max_connections]
        end
        
        if pool.respond_to?(:timeout=)
          pool.timeout = settings[:pool_timeout]
        end
        
        LoggingService.log_info(:database, "Connection pool optimized", {
          environment: env,
          max_connections: settings[:max_connections],
          pool_timeout: settings[:pool_timeout],
          checkout_timeout: settings[:checkout_timeout]
        })
        
      rescue => e
        LoggingService.log_warn(:database, "Failed to optimize connection pool", {
          error: e.message
        })
      end
    end
    
    # Setup query result caching
    def setup_query_caching
      # Initialize cache cleanup timer
      if defined?(Iodine)
        Iodine.run_every(60_000) do # Every minute
          cleanup_expired_cache_entries
        end
      end
      
      LoggingService.log_info(:database, "Query result caching initialized")
    end
    
    # Setup periodic optimization tasks
    def setup_periodic_optimizations
      return unless defined?(Iodine)
      
      # Run database maintenance every 30 minutes
      Iodine.run_every(1_800_000) do # 30 minutes in milliseconds
        perform_periodic_maintenance
      end
      
      # Update query statistics every 5 minutes
      Iodine.run_every(300_000) do # 5 minutes in milliseconds
        update_query_statistics
      end
      
      LoggingService.log_info(:database, "Periodic optimization tasks scheduled")
    end
    
    # Execute optimized query with caching
    def execute_optimized_query(query_type, *params)
      optimization = QUERY_OPTIMIZATIONS[query_type]
      return nil unless optimization
      
      # Generate cache key
      cache_key = "#{optimization[:cache_key]}_#{params.join('_')}"
      
      # Check cache first
      cached_result = get_cached_result(cache_key)
      if cached_result
        @@cache_stats[:hits] += 1
        @@cache_stats[:total_queries] += 1
        return cached_result
      end
      
      # Execute query with performance monitoring
      result = PerformanceMonitor.measure_operation(:database_query, query_type.to_s, {
        query_type: query_type,
        params: params
      }) do
        db = SpotikConfig::Database.connection
        db.fetch(optimization[:optimized_query], *params).all
      end
      
      # Cache the result
      cache_result(cache_key, result, optimization[:cache_ttl])
      
      @@cache_stats[:misses] += 1
      @@cache_stats[:total_queries] += 1
      
      result
    end
    
    # Get room track queue with optimization
    def get_optimized_room_queue(room_id, limit = 100)
      execute_optimized_query(:room_track_queue, room_id)
    end
    
    # Get room participants with user data
    def get_optimized_room_participants(room_id)
      execute_optimized_query(:room_participants_with_users, room_id)
    end
    
    # Get track votes with user data
    def get_optimized_track_votes(track_id)
      execute_optimized_query(:track_votes_with_users, track_id)
    end
    
    # Get active rooms with current track info
    def get_optimized_active_rooms
      execute_optimized_query(:active_rooms)
    end
    
    # Analyze query performance
    def analyze_query_performance(query, params = [])
      return unless SpotikConfig::Settings.development?
      
      db = SpotikConfig::Database.connection
      
      # Use EXPLAIN to analyze query performance
      explain_query = "EXPLAIN (ANALYZE, BUFFERS) #{query}"
      
      begin
        result = db.fetch(explain_query, *params).all
        
        LoggingService.log_info(:database, "Query performance analysis", {
          query: query,
          params: params,
          explain_result: result
        })
        
        result
        
      rescue => e
        LoggingService.log_warn(:database, "Failed to analyze query performance", {
          query: query,
          error: e.message
        })
        nil
      end
    end
    
    # Get database optimization statistics
    def get_optimization_statistics
      db = SpotikConfig::Database.connection
      
      {
        connection_pool: get_connection_pool_stats,
        query_cache: {
          hits: @@cache_stats[:hits],
          misses: @@cache_stats[:misses],
          hit_rate: calculate_cache_hit_rate,
          total_queries: @@cache_stats[:total_queries],
          cached_entries: @@query_cache.length,
          evictions: @@cache_stats[:evictions]
        },
        indexes: get_index_statistics,
        table_sizes: get_table_size_statistics,
        active_connections: get_active_connection_count,
        slow_queries: get_slow_query_statistics
      }
    end
    
    # Invalidate cache for specific patterns
    def invalidate_cache(pattern = nil)
      if pattern
        # Invalidate specific cache entries matching pattern
        keys_to_remove = @@query_cache.keys.select { |key| key.include?(pattern) }
        keys_to_remove.each { |key| @@query_cache.delete(key) }
        
        LoggingService.log_info(:database, "Cache invalidated", {
          pattern: pattern,
          entries_removed: keys_to_remove.length
        })
      else
        # Clear entire cache
        @@query_cache.clear
        LoggingService.log_info(:database, "Entire query cache cleared")
      end
    end
    
    # Force database maintenance
    def perform_maintenance
      perform_periodic_maintenance
    end
    
    private
    
    # Cache management
    def get_cached_result(cache_key)
      cached = @@query_cache[cache_key]
      return nil unless cached
      
      # Check if cache entry is still valid
      if Time.now - cached[:cached_at] < cached[:ttl]
        cached[:data]
      else
        @@query_cache.delete(cache_key)
        nil
      end
    end
    
    def cache_result(cache_key, result, ttl)
      @@query_cache[cache_key] = {
        data: result,
        cached_at: Time.now,
        ttl: ttl
      }
      
      # Limit cache size to prevent memory issues
      if @@query_cache.length > 1000
        # Remove oldest entries
        oldest_keys = @@query_cache.keys.sort_by { |key| @@query_cache[key][:cached_at] }.first(100)
        oldest_keys.each { |key| @@query_cache.delete(key) }
        @@cache_stats[:evictions] += oldest_keys.length
      end
    end
    
    def cleanup_expired_cache_entries
      expired_keys = []
      current_time = Time.now
      
      @@query_cache.each do |key, cached|
        if current_time - cached[:cached_at] >= cached[:ttl]
          expired_keys << key
        end
      end
      
      expired_keys.each { |key| @@query_cache.delete(key) }
      
      if expired_keys.any?
        LoggingService.log_debug(:database, "Cleaned up expired cache entries", {
          expired_count: expired_keys.length,
          remaining_count: @@query_cache.length
        })
      end
    end
    
    # Statistics helpers
    def get_connection_pool_stats
      db = SpotikConfig::Database.connection
      pool = db.pool
      
      {
        size: pool.respond_to?(:size) ? pool.size : 0,
        max_size: pool.respond_to?(:max_size) ? pool.max_size : 0,
        allocated: pool.respond_to?(:allocated) ? pool.allocated : 0,
        available: pool.respond_to?(:available) ? pool.available : 0
      }
    rescue => e
      LoggingService.log_warn(:database, "Failed to get connection pool stats", { error: e.message })
      {}
    end
    
    def calculate_cache_hit_rate
      total = @@cache_stats[:hits] + @@cache_stats[:misses]
      return 0.0 if total == 0
      
      (@@cache_stats[:hits].to_f / total * 100).round(2)
    end
    
    def get_index_statistics
      db = SpotikConfig::Database.connection
      index_stats = {}
      
      PERFORMANCE_INDEXES.each do |table, indexes|
        next unless db.table_exists?(table)
        
        existing_indexes = db.indexes(table)
        index_stats[table] = {
          total_indexes: existing_indexes.length,
          performance_indexes: indexes.length,
          index_names: existing_indexes.keys
        }
      end
      
      index_stats
    rescue => e
      LoggingService.log_warn(:database, "Failed to get index statistics", { error: e.message })
      {}
    end
    
    def get_table_size_statistics
      db = SpotikConfig::Database.connection
      
      # PostgreSQL-specific query for table sizes
      size_query = <<~SQL
        SELECT 
          schemaname,
          tablename,
          attname,
          n_distinct,
          correlation
        FROM pg_stats 
        WHERE schemaname = 'public' 
        AND tablename IN ('users', 'rooms', 'tracks', 'room_participants', 'track_votes')
        ORDER BY tablename, attname
      SQL
      
      db.fetch(size_query).all
    rescue => e
      LoggingService.log_warn(:database, "Failed to get table size statistics", { error: e.message })
      []
    end
    
    def get_active_connection_count
      db = SpotikConfig::Database.connection
      
      # PostgreSQL-specific query for active connections
      connection_query = "SELECT count(*) as active_connections FROM pg_stat_activity WHERE datname = current_database()"
      
      result = db.fetch(connection_query).first
      result[:active_connections]
    rescue => e
      LoggingService.log_warn(:database, "Failed to get active connection count", { error: e.message })
      0
    end
    
    def get_slow_query_statistics
      # This would require pg_stat_statements extension in production
      # For now, return placeholder data
      {
        slow_query_threshold_ms: SpotikConfig::Settings.slow_query_threshold,
        slow_queries_detected: 0,
        average_query_time_ms: 0
      }
    end
    
    def update_query_statistics
      stats = get_optimization_statistics
      
      LoggingService.log_info(:database, "Database optimization statistics", stats)
      
      # Log warnings for performance issues
      if stats[:query_cache][:hit_rate] < 50
        LoggingService.log_warn(:database, "Low cache hit rate detected", {
          hit_rate: stats[:query_cache][:hit_rate],
          recommendation: "Consider increasing cache TTL or optimizing queries"
        })
      end
      
      pool_stats = stats[:connection_pool]
      if pool_stats[:available] && pool_stats[:available] < 2
        LoggingService.log_warn(:database, "Low connection pool availability", {
          available: pool_stats[:available],
          allocated: pool_stats[:allocated],
          recommendation: "Consider increasing max_connections"
        })
      end
    end
    
    def perform_periodic_maintenance
      LoggingService.log_info(:database, "Starting periodic database maintenance")
      
      begin
        # Clean up expired cache entries
        cleanup_expired_cache_entries
        
        # Update table statistics (PostgreSQL)
        update_table_statistics
        
        # Log maintenance completion
        LoggingService.log_info(:database, "Periodic database maintenance completed")
        
      rescue => e
        LoggingService.log_error(:database, "Periodic database maintenance failed", {}, e)
      end
    end
    
    def update_table_statistics
      return unless SpotikConfig::Settings.production?
      
      db = SpotikConfig::Database.connection
      
      # Update PostgreSQL table statistics
      PERFORMANCE_INDEXES.keys.each do |table|
        next unless db.table_exists?(table)
        
        begin
          db.run("ANALYZE #{table}")
          LoggingService.log_debug(:database, "Updated statistics for table #{table}")
        rescue => e
          LoggingService.log_warn(:database, "Failed to update statistics for table #{table}", {
            error: e.message
          })
        end
      end
    end
  end
end