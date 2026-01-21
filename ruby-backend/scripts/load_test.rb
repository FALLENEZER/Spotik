#!/usr/bin/env ruby

# Load Testing Script for Ruby Backend Migration
# **Feature: ruby-backend-migration, Task 17.1: Complete system integration and final testing**
# **Validates: Requirements 12.1, 12.2, 12.3, 12.4, 15.5**

require 'bundler/setup'
require 'net/http'
require 'uri'
require 'json'
require 'securerandom'
require 'thread'
require 'timeout'
require 'benchmark'
require 'optparse'

class LoadTester
  attr_reader :base_url, :concurrent_users, :operations_per_user, :test_duration
  
  def initialize(options = {})
    @base_url = options[:base_url] || 'http://localhost:3000'
    @concurrent_users = options[:concurrent_users] || 50
    @operations_per_user = options[:operations_per_user] || 10
    @test_duration = options[:test_duration] || 60 # seconds
    @results = []
    @results_mutex = Mutex.new
    @start_time = nil
    @end_time = nil
  end
  
  def run_load_test
    puts "🚀 Starting Load Test for Ruby Backend Migration"
    puts "=" * 60
    puts "Configuration:"
    puts "  Base URL: #{@base_url}"
    puts "  Concurrent Users: #{@concurrent_users}"
    puts "  Operations per User: #{@operations_per_user}"
    puts "  Test Duration: #{@test_duration}s"
    puts "=" * 60
    
    # Verify server is running
    unless server_available?
      puts "❌ Server not available at #{@base_url}"
      puts "Please start the Ruby backend server first:"
      puts "  cd ruby-backend && ruby server.rb"
      exit 1
    end
    
    puts "✅ Server is available"
    
    # Run the load test
    @start_time = Time.now
    
    begin
      # Phase 1: User Registration Load Test
      puts "\n📝 Phase 1: User Registration Load Test"
      registration_results = test_user_registration
      
      # Phase 2: Authentication Load Test  
      puts "\n🔐 Phase 2: Authentication Load Test"
      auth_results = test_authentication(registration_results[:users])
      
      # Phase 3: Room Operations Load Test
      puts "\n🏠 Phase 3: Room Operations Load Test"
      room_results = test_room_operations(auth_results[:authenticated_users])
      
      # Phase 4: Concurrent WebSocket Simulation
      puts "\n🔌 Phase 4: WebSocket Connection Simulation"
      websocket_results = test_websocket_simulation(auth_results[:authenticated_users])
      
      # Phase 5: Mixed Operations Under Load
      puts "\n⚡ Phase 5: Mixed Operations Under Load"
      mixed_results = test_mixed_operations(auth_results[:authenticated_users], room_results[:rooms])
      
      @end_time = Time.now
      
      # Generate comprehensive report
      generate_load_test_report({
        registration: registration_results,
        authentication: auth_results,
        room_operations: room_results,
        websocket: websocket_results,
        mixed_operations: mixed_results
      })
      
    rescue Interrupt
      puts "\n⚠️  Load test interrupted by user"
      @end_time = Time.now
      generate_partial_report
    rescue => e
      puts "\n❌ Load test failed: #{e.message}"
      puts e.backtrace.first(5)
      exit 1
    end
  end
  
  private
  
  def server_available?
    begin
      uri = URI("#{@base_url}/api/health")
      response = Net::HTTP.get_response(uri)
      response.code == '200'
    rescue
      false
    end
  end
  
  def test_user_registration
    puts "  Creating #{@concurrent_users} users concurrently..."
    
    registration_threads = []
    registration_results = []
    results_mutex = Mutex.new
    
    start_time = Time.now
    
    @concurrent_users.times do |i|
      registration_threads << Thread.new do
        user_data = {
          username: "load_user_#{i}_#{SecureRandom.hex(6)}",
          email: "load#{i}_#{SecureRandom.hex(6)}@example.com",
          password: 'loadtest123',
          password_confirmation: 'loadtest123'
        }
        
        begin
          response_time = Benchmark.realtime do
            uri = URI("#{@base_url}/api/auth/register")
            http = Net::HTTP.new(uri.host, uri.port)
            http.read_timeout = 10
            
            request = Net::HTTP::Post.new(uri)
            request['Content-Type'] = 'application/json'
            request.body = user_data.to_json
            
            response = http.request(request)
            
            results_mutex.synchronize do
              registration_results << {
                thread_id: Thread.current.object_id,
                user_data: user_data,
                status_code: response.code.to_i,
                response_time: response_time,
                success: response.code == '201',
                body: response.code == '201' ? JSON.parse(response.body) : nil,
                error: response.code != '201' ? response.body : nil
              }
            end
          end
        rescue => e
          results_mutex.synchronize do
            registration_results << {
              thread_id: Thread.current.object_id,
              user_data: user_data,
              status_code: 0,
              response_time: 0,
              success: false,
              error: e.message
            }
          end
        end
      end
    end
    
    registration_threads.each(&:join)
    end_time = Time.now
    
    successful_registrations = registration_results.select { |r| r[:success] }
    success_rate = (successful_registrations.length.to_f / @concurrent_users * 100).round(2)
    avg_response_time = successful_registrations.map { |r| r[:response_time] }.sum / successful_registrations.length
    total_time = end_time - start_time
    
    puts "  ✅ Registration Results:"
    puts "     Success Rate: #{success_rate}% (#{successful_registrations.length}/#{@concurrent_users})"
    puts "     Average Response Time: #{(avg_response_time * 1000).round(2)}ms"
    puts "     Total Time: #{total_time.round(2)}s"
    puts "     Registrations/sec: #{(@concurrent_users / total_time).round(2)}"
    
    {
      users: successful_registrations,
      success_rate: success_rate,
      avg_response_time: avg_response_time,
      total_time: total_time,
      throughput: @concurrent_users / total_time
    }
  end
  
  def test_authentication(users)
    puts "  Testing authentication for #{users.length} users..."
    
    auth_threads = []
    auth_results = []
    results_mutex = Mutex.new
    
    start_time = Time.now
    
    users.each do |user|
      auth_threads << Thread.new do
        login_data = {
          email: user[:user_data][:email],
          password: user[:user_data][:password]
        }
        
        begin
          response_time = Benchmark.realtime do
            uri = URI("#{@base_url}/api/auth/login")
            http = Net::HTTP.new(uri.host, uri.port)
            http.read_timeout = 10
            
            request = Net::HTTP::Post.new(uri)
            request['Content-Type'] = 'application/json'
            request.body = login_data.to_json
            
            response = http.request(request)
            
            results_mutex.synchronize do
              auth_results << {
                thread_id: Thread.current.object_id,
                user_id: user[:body]['data']['user']['id'],
                status_code: response.code.to_i,
                response_time: response_time,
                success: response.code == '200',
                token: response.code == '200' ? JSON.parse(response.body)['data']['token'] : nil,
                error: response.code != '200' ? response.body : nil
              }
            end
          end
        rescue => e
          results_mutex.synchronize do
            auth_results << {
              thread_id: Thread.current.object_id,
              user_id: user[:body]['data']['user']['id'],
              status_code: 0,
              response_time: 0,
              success: false,
              error: e.message
            }
          end
        end
      end
    end
    
    auth_threads.each(&:join)
    end_time = Time.now
    
    successful_auths = auth_results.select { |r| r[:success] }
    success_rate = (successful_auths.length.to_f / users.length * 100).round(2)
    avg_response_time = successful_auths.map { |r| r[:response_time] }.sum / successful_auths.length
    total_time = end_time - start_time
    
    puts "  ✅ Authentication Results:"
    puts "     Success Rate: #{success_rate}% (#{successful_auths.length}/#{users.length})"
    puts "     Average Response Time: #{(avg_response_time * 1000).round(2)}ms"
    puts "     Total Time: #{total_time.round(2)}s"
    puts "     Logins/sec: #{(users.length / total_time).round(2)}"
    
    {
      authenticated_users: successful_auths,
      success_rate: success_rate,
      avg_response_time: avg_response_time,
      total_time: total_time,
      throughput: users.length / total_time
    }
  end
  
  def test_room_operations(authenticated_users)
    puts "  Testing room operations with #{authenticated_users.length} users..."
    
    # Phase 1: Room Creation
    room_creation_threads = []
    room_results = []
    results_mutex = Mutex.new
    
    start_time = Time.now
    
    # Create rooms with first 10 users (or all if less than 10)
    room_creators = authenticated_users.first([authenticated_users.length, 10].min)
    
    room_creators.each_with_index do |user, i|
      room_creation_threads << Thread.new do
        room_data = {
          name: "Load Test Room #{i} - #{SecureRandom.hex(4)}"
        }
        
        begin
          response_time = Benchmark.realtime do
            uri = URI("#{@base_url}/api/rooms")
            http = Net::HTTP.new(uri.host, uri.port)
            http.read_timeout = 10
            
            request = Net::HTTP::Post.new(uri)
            request['Content-Type'] = 'application/json'
            request['Authorization'] = "Bearer #{user[:token]}"
            request.body = room_data.to_json
            
            response = http.request(request)
            
            results_mutex.synchronize do
              room_results << {
                thread_id: Thread.current.object_id,
                creator_id: user[:user_id],
                status_code: response.code.to_i,
                response_time: response_time,
                success: response.code == '201',
                room_data: response.code == '201' ? JSON.parse(response.body)['room'] : nil,
                error: response.code != '201' ? response.body : nil
              }
            end
          end
        rescue => e
          results_mutex.synchronize do
            room_results << {
              thread_id: Thread.current.object_id,
              creator_id: user[:user_id],
              status_code: 0,
              response_time: 0,
              success: false,
              error: e.message
            }
          end
        end
      end
    end
    
    room_creation_threads.each(&:join)
    
    successful_rooms = room_results.select { |r| r[:success] }
    
    # Phase 2: Room Joining
    if successful_rooms.any?
      puts "  Testing room joining with remaining users..."
      
      join_threads = []
      join_results = []
      
      # Remaining users join random rooms
      remaining_users = authenticated_users - room_creators
      
      remaining_users.each do |user|
        join_threads << Thread.new do
          room = successful_rooms.sample
          
          begin
            response_time = Benchmark.realtime do
              uri = URI("#{@base_url}/api/rooms/#{room[:room_data]['id']}/join")
              http = Net::HTTP.new(uri.host, uri.port)
              http.read_timeout = 10
              
              request = Net::HTTP::Post.new(uri)
              request['Authorization'] = "Bearer #{user[:token]}"
              
              response = http.request(request)
              
              results_mutex.synchronize do
                join_results << {
                  thread_id: Thread.current.object_id,
                  user_id: user[:user_id],
                  room_id: room[:room_data]['id'],
                  status_code: response.code.to_i,
                  response_time: response_time,
                  success: response.code == '200',
                  error: response.code != '200' ? response.body : nil
                }
              end
            end
          rescue => e
            results_mutex.synchronize do
              join_results << {
                thread_id: Thread.current.object_id,
                user_id: user[:user_id],
                room_id: room[:room_data]['id'],
                status_code: 0,
                response_time: 0,
                success: false,
                error: e.message
              }
            end
          end
        end
      end
      
      join_threads.each(&:join)
      
      successful_joins = join_results.select { |r| r[:success] }
      join_success_rate = remaining_users.any? ? (successful_joins.length.to_f / remaining_users.length * 100).round(2) : 100
      
      puts "  ✅ Room Join Results:"
      puts "     Success Rate: #{join_success_rate}% (#{successful_joins.length}/#{remaining_users.length})"
    end
    
    end_time = Time.now
    total_time = end_time - start_time
    
    room_success_rate = (successful_rooms.length.to_f / room_creators.length * 100).round(2)
    avg_room_response_time = successful_rooms.any? ? successful_rooms.map { |r| r[:response_time] }.sum / successful_rooms.length : 0
    
    puts "  ✅ Room Creation Results:"
    puts "     Success Rate: #{room_success_rate}% (#{successful_rooms.length}/#{room_creators.length})"
    puts "     Average Response Time: #{(avg_room_response_time * 1000).round(2)}ms"
    puts "     Total Time: #{total_time.round(2)}s"
    
    {
      rooms: successful_rooms,
      success_rate: room_success_rate,
      avg_response_time: avg_room_response_time,
      total_time: total_time
    }
  end
  
  def test_websocket_simulation(authenticated_users)
    puts "  Simulating WebSocket connections for #{authenticated_users.length} users..."
    
    # Since we can't easily test actual WebSocket connections in this load test,
    # we'll simulate the HTTP endpoints that would trigger WebSocket events
    
    websocket_threads = []
    websocket_results = []
    results_mutex = Mutex.new
    
    start_time = Time.now
    
    authenticated_users.each do |user|
      websocket_threads << Thread.new do
        # Simulate WebSocket-triggering operations
        operations = [
          { endpoint: '/api/auth/me', method: 'GET' },
          { endpoint: '/api/rooms', method: 'GET' }
        ]
        
        operations.each do |operation|
          begin
            response_time = Benchmark.realtime do
              uri = URI("#{@base_url}#{operation[:endpoint]}")
              http = Net::HTTP.new(uri.host, uri.port)
              http.read_timeout = 5
              
              request = case operation[:method]
                       when 'GET'
                         Net::HTTP::Get.new(uri)
                       when 'POST'
                         Net::HTTP::Post.new(uri)
                       end
              
              request['Authorization'] = "Bearer #{user[:token]}"
              
              response = http.request(request)
              
              results_mutex.synchronize do
                websocket_results << {
                  thread_id: Thread.current.object_id,
                  user_id: user[:user_id],
                  operation: operation[:endpoint],
                  status_code: response.code.to_i,
                  response_time: response_time,
                  success: response.code.to_i < 400
                }
              end
            end
          rescue => e
            results_mutex.synchronize do
              websocket_results << {
                thread_id: Thread.current.object_id,
                user_id: user[:user_id],
                operation: operation[:endpoint],
                status_code: 0,
                response_time: 0,
                success: false,
                error: e.message
              }
            end
          end
          
          # Small delay between operations
          sleep(0.1)
        end
      end
    end
    
    websocket_threads.each(&:join)
    end_time = Time.now
    
    successful_operations = websocket_results.select { |r| r[:success] }
    success_rate = (successful_operations.length.to_f / websocket_results.length * 100).round(2)
    avg_response_time = successful_operations.any? ? successful_operations.map { |r| r[:response_time] }.sum / successful_operations.length : 0
    total_time = end_time - start_time
    
    puts "  ✅ WebSocket Simulation Results:"
    puts "     Success Rate: #{success_rate}% (#{successful_operations.length}/#{websocket_results.length})"
    puts "     Average Response Time: #{(avg_response_time * 1000).round(2)}ms"
    puts "     Total Time: #{total_time.round(2)}s"
    puts "     Operations/sec: #{(websocket_results.length / total_time).round(2)}"
    
    {
      operations: successful_operations,
      success_rate: success_rate,
      avg_response_time: avg_response_time,
      total_time: total_time,
      throughput: websocket_results.length / total_time
    }
  end
  
  def test_mixed_operations(authenticated_users, rooms)
    puts "  Running mixed operations load test..."
    
    mixed_threads = []
    mixed_results = []
    results_mutex = Mutex.new
    
    start_time = Time.now
    test_end_time = start_time + @test_duration
    
    authenticated_users.each do |user|
      mixed_threads << Thread.new do
        operations_count = 0
        
        while Time.now < test_end_time && operations_count < @operations_per_user
          # Random operation selection
          operation_type = [:auth_check, :room_list, :room_join].sample
          
          begin
            response_time = Benchmark.realtime do
              case operation_type
              when :auth_check
                uri = URI("#{@base_url}/api/auth/me")
                http = Net::HTTP.new(uri.host, uri.port)
                http.read_timeout = 5
                
                request = Net::HTTP::Get.new(uri)
                request['Authorization'] = "Bearer #{user[:token]}"
                
                response = http.request(request)
                
              when :room_list
                uri = URI("#{@base_url}/api/rooms")
                http = Net::HTTP.new(uri.host, uri.port)
                http.read_timeout = 5
                
                request = Net::HTTP::Get.new(uri)
                request['Authorization'] = "Bearer #{user[:token]}"
                
                response = http.request(request)
                
              when :room_join
                if rooms[:rooms].any?
                  room = rooms[:rooms].sample
                  uri = URI("#{@base_url}/api/rooms/#{room[:room_data]['id']}/join")
                  http = Net::HTTP.new(uri.host, uri.port)
                  http.read_timeout = 5
                  
                  request = Net::HTTP::Post.new(uri)
                  request['Authorization'] = "Bearer #{user[:token]}"
                  
                  response = http.request(request)
                else
                  # Skip if no rooms available
                  next
                end
              end
              
              results_mutex.synchronize do
                mixed_results << {
                  thread_id: Thread.current.object_id,
                  user_id: user[:user_id],
                  operation: operation_type,
                  status_code: response.code.to_i,
                  response_time: response_time,
                  success: response.code.to_i < 400,
                  timestamp: Time.now.to_f
                }
              end
            end
          rescue => e
            results_mutex.synchronize do
              mixed_results << {
                thread_id: Thread.current.object_id,
                user_id: user[:user_id],
                operation: operation_type,
                status_code: 0,
                response_time: 0,
                success: false,
                error: e.message,
                timestamp: Time.now.to_f
              }
            end
          end
          
          operations_count += 1
          
          # Random delay between operations (0.1 to 1 second)
          sleep(rand(0.1..1.0))
        end
      end
    end
    
    mixed_threads.each(&:join)
    end_time = Time.now
    
    successful_operations = mixed_results.select { |r| r[:success] }
    success_rate = mixed_results.any? ? (successful_operations.length.to_f / mixed_results.length * 100).round(2) : 0
    avg_response_time = successful_operations.any? ? successful_operations.map { |r| r[:response_time] }.sum / successful_operations.length : 0
    total_time = end_time - start_time
    
    puts "  ✅ Mixed Operations Results:"
    puts "     Total Operations: #{mixed_results.length}"
    puts "     Success Rate: #{success_rate}% (#{successful_operations.length}/#{mixed_results.length})"
    puts "     Average Response Time: #{(avg_response_time * 1000).round(2)}ms"
    puts "     Total Time: #{total_time.round(2)}s"
    puts "     Operations/sec: #{(mixed_results.length / total_time).round(2)}"
    
    {
      operations: mixed_results,
      success_rate: success_rate,
      avg_response_time: avg_response_time,
      total_time: total_time,
      throughput: mixed_results.length / total_time
    }
  end
  
  def generate_load_test_report(results)
    puts "\n" + "=" * 60
    puts "🎯 LOAD TEST FINAL REPORT"
    puts "=" * 60
    
    total_test_time = @end_time - @start_time
    
    puts "\n📊 Overall Performance Summary:"
    puts "  Total Test Duration: #{total_test_time.round(2)}s"
    puts "  Concurrent Users: #{@concurrent_users}"
    puts "  Target Operations per User: #{@operations_per_user}"
    
    puts "\n📈 Phase Results:"
    
    # Registration Phase
    reg = results[:registration]
    puts "  1. User Registration:"
    puts "     Success Rate: #{reg[:success_rate]}%"
    puts "     Avg Response Time: #{(reg[:avg_response_time] * 1000).round(2)}ms"
    puts "     Throughput: #{reg[:throughput].round(2)} registrations/sec"
    
    # Authentication Phase
    auth = results[:authentication]
    puts "  2. Authentication:"
    puts "     Success Rate: #{auth[:success_rate]}%"
    puts "     Avg Response Time: #{(auth[:avg_response_time] * 1000).round(2)}ms"
    puts "     Throughput: #{auth[:throughput].round(2)} logins/sec"
    
    # Room Operations Phase
    rooms = results[:room_operations]
    puts "  3. Room Operations:"
    puts "     Success Rate: #{rooms[:success_rate]}%"
    puts "     Avg Response Time: #{(rooms[:avg_response_time] * 1000).round(2)}ms"
    
    # WebSocket Simulation Phase
    ws = results[:websocket]
    puts "  4. WebSocket Simulation:"
    puts "     Success Rate: #{ws[:success_rate]}%"
    puts "     Avg Response Time: #{(ws[:avg_response_time] * 1000).round(2)}ms"
    puts "     Throughput: #{ws[:throughput].round(2)} operations/sec"
    
    # Mixed Operations Phase
    mixed = results[:mixed_operations]
    puts "  5. Mixed Operations:"
    puts "     Total Operations: #{mixed[:operations].length}"
    puts "     Success Rate: #{mixed[:success_rate]}%"
    puts "     Avg Response Time: #{(mixed[:avg_response_time] * 1000).round(2)}ms"
    puts "     Throughput: #{mixed[:throughput].round(2)} operations/sec"
    
    puts "\n🎯 Performance Benchmarks:"
    
    # Calculate overall metrics
    total_operations = reg[:users].length + auth[:authenticated_users].length + 
                      rooms[:rooms].length + ws[:operations].length + mixed[:operations].length
    
    overall_success_rate = [
      reg[:success_rate], auth[:success_rate], rooms[:success_rate], 
      ws[:success_rate], mixed[:success_rate]
    ].sum / 5
    
    puts "  Overall Success Rate: #{overall_success_rate.round(2)}%"
    puts "  Total Operations Completed: #{total_operations}"
    puts "  Overall Throughput: #{(total_operations / total_test_time).round(2)} operations/sec"
    
    # Performance Assessment
    puts "\n✅ Performance Assessment:"
    
    if overall_success_rate >= 95
      puts "  🟢 SUCCESS RATE: Excellent (#{overall_success_rate.round(2)}% >= 95%)"
    elsif overall_success_rate >= 90
      puts "  🟡 SUCCESS RATE: Good (#{overall_success_rate.round(2)}% >= 90%)"
    else
      puts "  🔴 SUCCESS RATE: Needs Improvement (#{overall_success_rate.round(2)}% < 90%)"
    end
    
    avg_response_times = [
      reg[:avg_response_time], auth[:avg_response_time], rooms[:avg_response_time],
      ws[:avg_response_time], mixed[:avg_response_time]
    ]
    overall_avg_response = (avg_response_times.sum / avg_response_times.length) * 1000
    
    if overall_avg_response <= 200
      puts "  🟢 RESPONSE TIME: Excellent (#{overall_avg_response.round(2)}ms <= 200ms)"
    elsif overall_avg_response <= 500
      puts "  🟡 RESPONSE TIME: Good (#{overall_avg_response.round(2)}ms <= 500ms)"
    else
      puts "  🔴 RESPONSE TIME: Needs Improvement (#{overall_avg_response.round(2)}ms > 500ms)"
    end
    
    overall_throughput = total_operations / total_test_time
    if overall_throughput >= 50
      puts "  🟢 THROUGHPUT: Excellent (#{overall_throughput.round(2)} ops/sec >= 50)"
    elsif overall_throughput >= 20
      puts "  🟡 THROUGHPUT: Good (#{overall_throughput.round(2)} ops/sec >= 20)"
    else
      puts "  🔴 THROUGHPUT: Needs Improvement (#{overall_throughput.round(2)} ops/sec < 20)"
    end
    
    puts "\n🏆 Load Test Status: " + 
         (overall_success_rate >= 90 && overall_avg_response <= 500 && overall_throughput >= 20 ? 
          "✅ PASSED" : "⚠️  NEEDS OPTIMIZATION")
    
    puts "\n💡 Recommendations:"
    if overall_success_rate < 95
      puts "  - Investigate failed requests and improve error handling"
    end
    if overall_avg_response > 200
      puts "  - Consider database query optimization and caching"
    end
    if overall_throughput < 50
      puts "  - Consider connection pooling and server optimization"
    end
    if overall_success_rate >= 95 && overall_avg_response <= 200 && overall_throughput >= 50
      puts "  - System performance is excellent for production deployment!"
    end
    
    puts "\n" + "=" * 60
    puts "Load test completed successfully! 🎉"
    puts "=" * 60
  end
  
  def generate_partial_report
    puts "\n⚠️  Partial load test report (interrupted)"
    puts "Test duration: #{(@end_time - @start_time).round(2)}s"
  end
end

# Command line interface
if __FILE__ == $0
  options = {}
  
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby load_test.rb [options]"
    
    opts.on("-u", "--url URL", "Base URL (default: http://localhost:3000)") do |url|
      options[:base_url] = url
    end
    
    opts.on("-c", "--concurrent USERS", Integer, "Concurrent users (default: 50)") do |users|
      options[:concurrent_users] = users
    end
    
    opts.on("-o", "--operations OPS", Integer, "Operations per user (default: 10)") do |ops|
      options[:operations_per_user] = ops
    end
    
    opts.on("-d", "--duration SECONDS", Integer, "Test duration in seconds (default: 60)") do |duration|
      options[:test_duration] = duration
    end
    
    opts.on("-h", "--help", "Show this help message") do
      puts opts
      exit
    end
  end.parse!
  
  load_tester = LoadTester.new(options)
  load_tester.run_load_test
end