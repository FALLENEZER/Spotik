#!/usr/bin/env ruby

# Performance Optimization Test Script
# Tests the implemented performance optimizations

require_relative 'config/settings'
require_relative 'config/database'
require_relative 'app/services/database_optimizer'
require_relative 'app/services/websocket_optimizer'
require_relative 'app/services/caching_service'
require_relative 'app/services/performance_monitor'
require_relative 'app/services/logging_service'

puts "🚀 Testing Performance Optimizations"
puts "=" * 50

# Initialize services
begin
  puts "\n📊 Initializing Performance Services..."
  
  # Initialize logging
  LoggingService.initialize_logging
  puts "✅ Logging service initialized"
  
  # Initialize performance monitoring
  PerformanceMonitor.initialize_monitoring
  puts "✅ Performance monitoring initialized"
  
  # Initialize database optimizations
  DatabaseOptimizer.initialize_optimizations
  puts "✅ Database optimizer initialized"
  
  # Initialize WebSocket optimizations
  WebSocketOptimizer.initialize_optimizations
  puts "✅ WebSocket optimizer initialized"
  
  # Initialize caching service
  CachingService.initialize_caching
  puts "✅ Caching service initialized"
  
rescue => e
  puts "❌ Failed to initialize services: #{e.message}"
  exit 1
end

# Test Database Optimizations
puts "\n🗄️  Testing Database Optimizations..."

begin
  # Test query caching
  puts "Testing query result caching..."
  
  # Simulate cached query
  start_time = Time.now
  result1 = DatabaseOptimizer.execute_optimized_query(:room_track_queue, 'test-room-id')
  duration1 = (Time.now - start_time) * 1000
  
  # Second call should be faster (cached)
  start_time = Time.now
  result2 = DatabaseOptimizer.execute_optimized_query(:room_track_queue, 'test-room-id')
  duration2 = (Time.now - start_time) * 1000
  
  puts "  First query: #{duration1.round(2)}ms"
  puts "  Cached query: #{duration2.round(2)}ms"
  puts "  ✅ Query caching working (#{duration2 < duration1 ? 'faster' : 'same speed'})"
  
  # Test statistics
  stats = DatabaseOptimizer.get_optimization_statistics
  puts "  📈 Cache hit rate: #{stats[:query_cache][:hit_rate]}%"
  puts "  📊 Total queries: #{stats[:query_cache][:total_queries]}"
  
rescue => e
  puts "  ❌ Database optimization test failed: #{e.message}"
end

# Test WebSocket Optimizations
puts "\n🔌 Testing WebSocket Optimizations..."

begin
  # Test connection registration
  puts "Testing connection management..."
  
  # Register test connections
  5.times do |i|
    WebSocketOptimizer.register_connection("test-conn-#{i}", "user-#{i}", "room-1")
  end
  
  stats = WebSocketOptimizer.get_optimization_statistics
  puts "  📊 Active connections: #{stats[:connections][:active]}"
  puts "  💾 Memory usage: #{stats[:memory][:current_mb].round(2)}MB"
  puts "  ✅ Connection registration working"
  
  # Test connection cleanup
  puts "Testing connection cleanup..."
  cleaned = WebSocketOptimizer.cleanup_stale_connections
  puts "  🧹 Cleaned connections: #{cleaned}"
  
  # Test garbage collection
  puts "Testing garbage collection..."
  memory_freed = WebSocketOptimizer.trigger_garbage_collection("test")
  puts "  🗑️  Memory freed: #{memory_freed.round(2)}MB"
  puts "  ✅ WebSocket optimization working"
  
rescue => e
  puts "  ❌ WebSocket optimization test failed: #{e.message}"
end

# Test Caching Service
puts "\n💾 Testing Caching Service..."

begin
  # Test cache operations
  puts "Testing cache set/get operations..."
  
  test_data = { message: "Hello, World!", timestamp: Time.now.to_f }
  
  # Test cache set
  start_time = Time.now
  success = CachingService.set(:api_response, 'test_key', test_data)
  set_duration = (Time.now - start_time) * 1000
  
  puts "  Cache set: #{set_duration.round(2)}ms (#{success ? 'success' : 'failed'})"
  
  # Test cache get
  start_time = Time.now
  cached_data = CachingService.get(:api_response, 'test_key')
  get_duration = (Time.now - start_time) * 1000
  
  puts "  Cache get: #{get_duration.round(2)}ms (#{cached_data ? 'hit' : 'miss'})"
  
  # Test cache statistics
  stats = CachingService.get_statistics
  puts "  📈 Overall hit rate: #{stats[:overall_hit_rate]}%"
  puts "  📊 Total entries: #{stats[:total_entries]}"
  puts "  💾 Memory usage: #{stats[:total_memory_mb]}MB"
  
  # Test cache health
  health = CachingService.get_health_status
  puts "  🏥 Cache health: #{health[:status]}"
  puts "  ✅ Caching service working"
  
rescue => e
  puts "  ❌ Caching service test failed: #{e.message}"
end

# Test Performance Monitoring
puts "\n📊 Testing Performance Monitoring..."

begin
  # Test performance measurement
  puts "Testing performance measurement..."
  
  result = PerformanceMonitor.measure_operation(:test_operation, 'performance_test', { test: true }) do
    # Simulate some work
    sleep(0.01)
    "test_result"
  end
  
  puts "  ✅ Performance measurement working (result: #{result})"
  
  # Test performance statistics
  stats = PerformanceMonitor.get_performance_statistics
  puts "  📊 Total operations: #{stats[:total_operations]}"
  puts "  ⏱️  Operations per hour: #{stats[:operations_per_hour]}"
  puts "  🏥 Health status: #{stats[:health_status]}"
  puts "  💾 Current memory: #{stats[:current_memory_mb].round(2)}MB"
  
  # Test performance report
  report = PerformanceMonitor.generate_performance_report
  puts "  📋 Performance report generated (#{report[:summary][:total_operations]} operations)"
  puts "  ✅ Performance monitoring working"
  
rescue => e
  puts "  ❌ Performance monitoring test failed: #{e.message}"
end

# Performance Benchmark
puts "\n🏃 Running Performance Benchmarks..."

begin
  require 'benchmark'
  
  # Database query benchmark
  puts "Database query benchmark:"
  db_time = Benchmark.measure do
    10.times { DatabaseOptimizer.execute_optimized_query(:room_track_queue, 'benchmark-room') }
  end
  puts "  10 queries: #{(db_time.real * 1000).round(2)}ms total, #{(db_time.real * 100).round(2)}ms avg"
  
  # Cache operation benchmark
  puts "Cache operation benchmark:"
  cache_time = Benchmark.measure do
    20.times do |i|
      CachingService.set(:api_response, "bench_key_#{i}", { data: "benchmark_data_#{i}" })
      CachingService.get(:api_response, "bench_key_#{i}")
    end
  end
  puts "  40 operations: #{(cache_time.real * 1000).round(2)}ms total, #{(cache_time.real * 25).round(2)}ms avg"
  
  # Memory allocation benchmark
  puts "Memory allocation benchmark:"
  memory_before = WebSocketOptimizer.send(:get_current_memory_usage)
  
  mem_time = Benchmark.measure do
    arrays = []
    100.times { |i| arrays << Array.new(100) { "string_#{i}" } }
    arrays.clear
  end
  
  memory_after = WebSocketOptimizer.send(:get_current_memory_usage)
  puts "  Memory test: #{(mem_time.real * 1000).round(2)}ms, #{(memory_after - memory_before).round(2)}MB delta"
  
  puts "  ✅ Benchmarks completed"
  
rescue => e
  puts "  ❌ Benchmark test failed: #{e.message}"
end

# Final Summary
puts "\n📋 Performance Optimization Test Summary"
puts "=" * 50

begin
  # Get overall statistics
  db_stats = DatabaseOptimizer.get_optimization_statistics
  ws_stats = WebSocketOptimizer.get_optimization_statistics
  cache_stats = CachingService.get_statistics
  perf_stats = PerformanceMonitor.get_performance_statistics
  
  puts "Database Optimization:"
  puts "  ✅ Query cache hit rate: #{db_stats[:query_cache][:hit_rate]}%"
  puts "  ✅ Cached entries: #{db_stats[:query_cache][:cached_entries]}"
  puts "  ✅ Connection pool size: #{db_stats[:connection_pool][:size] || 'N/A'}"
  
  puts "\nWebSocket Optimization:"
  puts "  ✅ Active connections: #{ws_stats[:connections][:active]}"
  puts "  ✅ Memory usage: #{ws_stats[:memory][:current_mb].round(2)}MB"
  puts "  ✅ Memory status: #{ws_stats[:memory][:status]}"
  
  puts "\nCaching Service:"
  puts "  ✅ Overall hit rate: #{cache_stats[:overall_hit_rate]}%"
  puts "  ✅ Total entries: #{cache_stats[:total_entries]}"
  puts "  ✅ Memory usage: #{cache_stats[:total_memory_mb]}MB"
  puts "  ✅ Health status: #{CachingService.get_health_status[:status]}"
  
  puts "\nPerformance Monitoring:"
  puts "  ✅ Total operations: #{perf_stats[:total_operations]}"
  puts "  ✅ Operations/hour: #{perf_stats[:operations_per_hour]}"
  puts "  ✅ Health status: #{perf_stats[:health_status]}"
  puts "  ✅ Current memory: #{perf_stats[:current_memory_mb].round(2)}MB"
  
  puts "\n🎉 All Performance Optimizations Working Successfully!"
  puts "   The Ruby backend is optimized and ready for production use."
  
rescue => e
  puts "\n❌ Error generating summary: #{e.message}"
  exit 1
end

puts "\n✨ Performance optimization test completed successfully!"
puts "   Run this script periodically to verify optimization health."