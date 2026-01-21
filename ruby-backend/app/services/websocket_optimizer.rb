# WebSocket Performance Optimizer
# Implements memory usage optimization, connection pooling, and performance enhancements for WebSocket connections

require_relative '../services/logging_service'
require_relative '../services/performance_monitor'

class WebSocketOptimizer
  # Memory optimization settings
  MEMORY_OPTIMIZATION_SETTINGS = {
    # Connection cleanup intervals
    stale_connection_cleanup_interval: 300, # 5 minutes
    inactive_connection_timeout: 600,       # 10 minutes
    
    # Message buffer settings
    message_buffer_size: 1024,              # 1KB per connection
    max_pending_messages: 100,              # Maximum queued messages per connection
    
    # Connection limits
    max_connections_per_room: 100,
    max_total_connections: 1000,
    
    # Memory thresholds
    memory_warning_threshold_mb: 200,
    memory_critical_threshold_mb: 400,
    
    # Garbage collection settings
    gc_trigger_threshold: 500,              # Trigger GC after 500 new connections
    force_gc_interval: 1800                 # Force GC every 30 minutes
  }.freeze
  
  # Connection state tracking for optimization
  @@connection_metrics = {
    total_connections: 0,
    active_connections: 0,
    peak_connections: 0,
    connections_created: 0,
    connections_destroyed: 0,
    memory_usage_mb: 0,
    peak_memory_usage_mb: 0,
    last_gc_run: Time.now,
    gc_runs: 0,
    message_queue_size: 0,
    dropped_messages: 0
  }
  
  # Connection pools by room for efficient management
  @@room_connection_pools = {}
  @@connection_registry = {}
  @@message_queues = {}
  
  # Performance optimization flags
  @@optimizations_enabled = true
  @@memory_monitoring_enabled = true
  @@connection_pooling_enabled = true
  
  class << self
    # Initialize WebSocket optimizations
    def initialize_optimizations
      LoggingService.log_info(:websocket, "Initializing WebSocket performance optimizations")
      
      begin
        # Setup memory monitoring
        setup_memory_monitoring
        
        # Setup connection cleanup
        setup_connection_cleanup
        
        # Setup message queue optimization
        setup_message_queue_optimization
        
        # Setup periodic garbage collection
        setup_garbage_collection
        
        # Setup connection pooling
        setup_connection_pooling
        
        LoggingService.log_info(:websocket, "WebSocket performance optimizations initialized successfully")
        
      rescue => e
        LoggingService.log_error(:websocket, "Failed to initialize WebSocket optimizations", {}, e)
        raise
      end
    end
    
    # Register a new WebSocket connection for optimization
    def register_connection(connection_id, user_id, room_id = nil)
      return unless @@optimizations_enabled
      
      # Update metrics
      @@connection_metrics[:total_connections] += 1
      @@connection_metrics[:active_connections] += 1
      @@connection_metrics[:connections_created] += 1
      @@connection_metrics[:peak_connections] = [
        @@connection_metrics[:peak_connections],
        @@connection_metrics[:active_connections]
      ].max
      
      # Register connection
      @@connection_registry[connection_id] = {
        user_id: user_id,
        room_id: room_id,
        created_at: Time.now,
        last_activity: Time.now,
        message_count: 0,
        bytes_sent: 0,
        bytes_received: 0
      }
      
      # Add to room pool if room specified
      if room_id && @@connection_pooling_enabled
        @@room_connection_pools[room_id] ||= []
        @@room_connection_pools[room_id] << connection_id
        
        # Check room connection limits
        if @@room_connection_pools[room_id].length > MEMORY_OPTIMIZATION_SETTINGS[:max_connections_per_room]
          LoggingService.log_warn(:websocket, "Room connection limit exceeded", {
            room_id: room_id,
            connections: @@room_connection_pools[room_id].length,
            limit: MEMORY_OPTIMIZATION_SETTINGS[:max_connections_per_room]
          })
        end
      end
      
      # Initialize message queue
      @@message_queues[connection_id] = []
      
      # Check total connection limits
      if @@connection_metrics[:active_connections] > MEMORY_OPTIMIZATION_SETTINGS[:max_total_connections]
        LoggingService.log_warn(:websocket, "Total connection limit exceeded", {
          active_connections: @@connection_metrics[:active_connections],
          limit: MEMORY_OPTIMIZATION_SETTINGS[:max_total_connections]
        })
      end
      
      # Trigger garbage collection if threshold reached
      if @@connection_metrics[:connections_created] % MEMORY_OPTIMIZATION_SETTINGS[:gc_trigger_threshold] == 0
        trigger_garbage_collection("connection_threshold_reached")
      end
      
      LoggingService.log_debug(:websocket, "Connection registered for optimization", {
        connection_id: connection_id,
        user_id: user_id,
        room_id: room_id,
        active_connections: @@connection_metrics[:active_connections]
      })
    end
    
    # Unregister a WebSocket connection
    def unregister_connection(connection_id)
      return unless @@optimizations_enabled
      
      connection_info = @@connection_registry[connection_id]
      return unless connection_info
      
      # Update metrics
      @@connection_metrics[:active_connections] -= 1
      @@connection_metrics[:connections_destroyed] += 1
      
      # Remove from room pool
      if connection_info[:room_id] && @@room_connection_pools[connection_info[:room_id]]
        @@room_connection_pools[connection_info[:room_id]].delete(connection_id)
        
        # Clean up empty room pools
        if @@room_connection_pools[connection_info[:room_id]].empty?
          @@room_connection_pools.delete(connection_info[:room_id])
        end
      end
      
      # Clean up message queue
      @@message_queues.delete(connection_id)
      
      # Remove from registry
      @@connection_registry.delete(connection_id)
      
      LoggingService.log_debug(:websocket, "Connection unregistered", {
        connection_id: connection_id,
        user_id: connection_info[:user_id],
        room_id: connection_info[:room_id],
        active_connections: @@connection_metrics[:active_connections],
        duration_seconds: Time.now - connection_info[:created_at]
      })
    end
    
    # Update connection activity for optimization
    def update_connection_activity(connection_id, activity_type, data_size = 0)
      return unless @@optimizations_enabled
      
      connection_info = @@connection_registry[connection_id]
      return unless connection_info
      
      # Update activity timestamp
      connection_info[:last_activity] = Time.now
      connection_info[:message_count] += 1
      
      case activity_type
      when :message_sent
        connection_info[:bytes_sent] += data_size
      when :message_received
        connection_info[:bytes_received] += data_size
      end
      
      # Update global message queue size
      @@connection_metrics[:message_queue_size] = @@message_queues.values.sum(&:length)
    end
    
    # Optimize message delivery with queuing and batching
    def optimize_message_delivery(connection_id, message)
      return false unless @@optimizations_enabled
      
      message_queue = @@message_queues[connection_id]
      return false unless message_queue
      
      # Check queue size limits
      if message_queue.length >= MEMORY_OPTIMIZATION_SETTINGS[:max_pending_messages]
        # Drop oldest message to make room
        dropped_message = message_queue.shift
        @@connection_metrics[:dropped_messages] += 1
        
        LoggingService.log_warn(:websocket, "Message dropped due to queue overflow", {
          connection_id: connection_id,
          queue_size: message_queue.length,
          dropped_message_type: dropped_message[:type]
        })
      end
      
      # Add message to queue with timestamp
      queued_message = {
        message: message,
        queued_at: Time.now,
        priority: message[:priority] || :normal
      }
      
      # Insert based on priority
      if queued_message[:priority] == :critical
        message_queue.unshift(queued_message)
      else
        message_queue.push(queued_message)
      end
      
      true
    end
    
    # Process message queue for a connection
    def process_message_queue(connection_id, max_messages = 10)
      return [] unless @@optimizations_enabled
      
      message_queue = @@message_queues[connection_id]
      return [] unless message_queue && !message_queue.empty?
      
      # Process up to max_messages from the queue
      messages_to_send = []
      processed_count = 0
      
      while !message_queue.empty? && processed_count < max_messages
        queued_message = message_queue.shift
        messages_to_send << queued_message[:message]
        processed_count += 1
      end
      
      # Update metrics
      update_connection_activity(connection_id, :messages_processed, processed_count)
      
      messages_to_send
    end
    
    # Get optimized room connections
    def get_optimized_room_connections(room_id)
      return [] unless @@connection_pooling_enabled
      
      connection_ids = @@room_connection_pools[room_id] || []
      
      # Filter out stale connections
      active_connections = connection_ids.select do |connection_id|
        connection_info = @@connection_registry[connection_id]
        connection_info && !connection_stale?(connection_info)
      end
      
      # Update pool if connections were filtered out
      if active_connections.length != connection_ids.length
        @@room_connection_pools[room_id] = active_connections
      end
      
      active_connections
    end
    
    # Get WebSocket optimization statistics
    def get_optimization_statistics
      current_memory = get_current_memory_usage
      @@connection_metrics[:memory_usage_mb] = current_memory
      @@connection_metrics[:peak_memory_usage_mb] = [
        @@connection_metrics[:peak_memory_usage_mb],
        current_memory
      ].max
      
      {
        connections: {
          total: @@connection_metrics[:total_connections],
          active: @@connection_metrics[:active_connections],
          peak: @@connection_metrics[:peak_connections],
          created: @@connection_metrics[:connections_created],
          destroyed: @@connection_metrics[:connections_destroyed]
        },
        memory: {
          current_mb: current_memory,
          peak_mb: @@connection_metrics[:peak_memory_usage_mb],
          warning_threshold_mb: MEMORY_OPTIMIZATION_SETTINGS[:memory_warning_threshold_mb],
          critical_threshold_mb: MEMORY_OPTIMIZATION_SETTINGS[:memory_critical_threshold_mb],
          status: get_memory_status(current_memory)
        },
        message_queues: {
          total_queued_messages: @@connection_metrics[:message_queue_size],
          dropped_messages: @@connection_metrics[:dropped_messages],
          average_queue_size: calculate_average_queue_size
        },
        room_pools: {
          active_rooms: @@room_connection_pools.keys.length,
          connections_by_room: @@room_connection_pools.transform_values(&:length)
        },
        garbage_collection: {
          gc_runs: @@connection_metrics[:gc_runs],
          last_gc_run: @@connection_metrics[:last_gc_run],
          time_since_last_gc: Time.now - @@connection_metrics[:last_gc_run]
        },
        optimizations: {
          enabled: @@optimizations_enabled,
          memory_monitoring: @@memory_monitoring_enabled,
          connection_pooling: @@connection_pooling_enabled
        }
      }
    end
    
    # Force cleanup of stale connections
    def cleanup_stale_connections
      return unless @@optimizations_enabled
      
      stale_connections = []
      current_time = Time.now
      
      @@connection_registry.each do |connection_id, connection_info|
        if connection_stale?(connection_info, current_time)
          stale_connections << connection_id
        end
      end
      
      # Clean up stale connections
      stale_connections.each do |connection_id|
        unregister_connection(connection_id)
      end
      
      if stale_connections.any?
        LoggingService.log_info(:websocket, "Cleaned up stale connections", {
          stale_count: stale_connections.length,
          remaining_connections: @@connection_metrics[:active_connections]
        })
      end
      
      stale_connections.length
    end
    
    # Force garbage collection
    def trigger_garbage_collection(reason = "manual")
      return unless @@optimizations_enabled
      
      before_memory = get_current_memory_usage
      
      # Force Ruby garbage collection
      GC.start
      
      after_memory = get_current_memory_usage
      memory_freed = before_memory - after_memory
      
      @@connection_metrics[:gc_runs] += 1
      @@connection_metrics[:last_gc_run] = Time.now
      
      LoggingService.log_info(:websocket, "Garbage collection completed", {
        reason: reason,
        memory_before_mb: before_memory,
        memory_after_mb: after_memory,
        memory_freed_mb: memory_freed,
        gc_runs_total: @@connection_metrics[:gc_runs]
      })
      
      memory_freed
    end
    
    # Enable/disable optimizations
    def set_optimizations_enabled(enabled)
      @@optimizations_enabled = enabled
      LoggingService.log_info(:websocket, "WebSocket optimizations #{enabled ? 'enabled' : 'disabled'}")
    end
    
    def set_memory_monitoring_enabled(enabled)
      @@memory_monitoring_enabled = enabled
      LoggingService.log_info(:websocket, "WebSocket memory monitoring #{enabled ? 'enabled' : 'disabled'}")
    end
    
    def set_connection_pooling_enabled(enabled)
      @@connection_pooling_enabled = enabled
      LoggingService.log_info(:websocket, "WebSocket connection pooling #{enabled ? 'enabled' : 'disabled'}")
    end
    
    private
    
    # Setup methods
    def setup_memory_monitoring
      return unless defined?(Iodine) && @@memory_monitoring_enabled
      
      # Monitor memory usage every 2 minutes
      Iodine.run_every(120_000) do
        monitor_memory_usage
      end
      
      LoggingService.log_info(:websocket, "Memory monitoring setup completed")
    end
    
    def setup_connection_cleanup
      return unless defined?(Iodine)
      
      # Clean up stale connections every 5 minutes
      Iodine.run_every(MEMORY_OPTIMIZATION_SETTINGS[:stale_connection_cleanup_interval] * 1000) do
        cleanup_stale_connections
      end
      
      LoggingService.log_info(:websocket, "Connection cleanup setup completed")
    end
    
    def setup_message_queue_optimization
      return unless defined?(Iodine)
      
      # Process message queues every 30 seconds
      Iodine.run_every(30_000) do
        optimize_message_queues
      end
      
      LoggingService.log_info(:websocket, "Message queue optimization setup completed")
    end
    
    def setup_garbage_collection
      return unless defined?(Iodine)
      
      # Force garbage collection every 30 minutes
      Iodine.run_every(MEMORY_OPTIMIZATION_SETTINGS[:force_gc_interval] * 1000) do
        trigger_garbage_collection("periodic")
      end
      
      LoggingService.log_info(:websocket, "Garbage collection setup completed")
    end
    
    def setup_connection_pooling
      # Connection pooling is enabled by default
      LoggingService.log_info(:websocket, "Connection pooling setup completed")
    end
    
    # Helper methods
    def connection_stale?(connection_info, current_time = Time.now)
      time_since_activity = current_time - connection_info[:last_activity]
      time_since_activity > MEMORY_OPTIMIZATION_SETTINGS[:inactive_connection_timeout]
    end
    
    def get_current_memory_usage
      # Get memory usage in MB (Linux/Unix)
      if File.exist?('/proc/self/status')
        status = File.read('/proc/self/status')
        if match = status.match(/VmRSS:\s+(\d+)\s+kB/)
          return match[1].to_i / 1024.0 # Convert KB to MB
        end
      end
      
      # Fallback for other systems
      begin
        if defined?(ObjectSpace)
          ObjectSpace.count_objects[:TOTAL] / 100000.0
        else
          0
        end
      rescue
        0
      end
    end
    
    def get_memory_status(memory_mb)
      case memory_mb
      when 0..MEMORY_OPTIMIZATION_SETTINGS[:memory_warning_threshold_mb]
        'normal'
      when MEMORY_OPTIMIZATION_SETTINGS[:memory_warning_threshold_mb]..MEMORY_OPTIMIZATION_SETTINGS[:memory_critical_threshold_mb]
        'warning'
      else
        'critical'
      end
    end
    
    def calculate_average_queue_size
      return 0 if @@message_queues.empty?
      
      total_messages = @@message_queues.values.sum(&:length)
      (total_messages.to_f / @@message_queues.length).round(2)
    end
    
    def monitor_memory_usage
      current_memory = get_current_memory_usage
      memory_status = get_memory_status(current_memory)
      
      @@connection_metrics[:memory_usage_mb] = current_memory
      @@connection_metrics[:peak_memory_usage_mb] = [
        @@connection_metrics[:peak_memory_usage_mb],
        current_memory
      ].max
      
      # Log memory warnings
      if memory_status != 'normal'
        LoggingService.log_warn(:websocket, "WebSocket memory usage #{memory_status}", {
          current_memory_mb: current_memory,
          peak_memory_mb: @@connection_metrics[:peak_memory_usage_mb],
          active_connections: @@connection_metrics[:active_connections],
          recommendation: memory_status == 'critical' ? 'Consider reducing connections or triggering GC' : 'Monitor closely'
        })
        
        # Trigger garbage collection for critical memory usage
        if memory_status == 'critical'
          trigger_garbage_collection("critical_memory_usage")
        end
      end
    end
    
    def optimize_message_queues
      total_queued = 0
      processed_queues = 0
      
      @@message_queues.each do |connection_id, queue|
        next if queue.empty?
        
        # Remove old queued messages (older than 5 minutes)
        current_time = Time.now
        queue.reject! do |queued_message|
          age = current_time - queued_message[:queued_at]
          if age > 300 # 5 minutes
            @@connection_metrics[:dropped_messages] += 1
            true
          else
            false
          end
        end
        
        total_queued += queue.length
        processed_queues += 1
      end
      
      @@connection_metrics[:message_queue_size] = total_queued
      
      if processed_queues > 0
        LoggingService.log_debug(:websocket, "Message queue optimization completed", {
          processed_queues: processed_queues,
          total_queued_messages: total_queued,
          average_queue_size: (total_queued.to_f / processed_queues).round(2)
        })
      end
    end
  end
end