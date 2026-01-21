#!/usr/bin/env ruby

# Comprehensive Compatibility Test Suite Runner
# **Feature: ruby-backend-migration, Task 16.1: Create comprehensive compatibility test suite**
# **Validates: Requirements 15.1, 15.2, 15.3, 15.4, 15.5**

require 'bundler/setup'
require 'colorize'
require 'json'
require 'fileutils'

puts "🧪 Ruby Backend Migration - Comprehensive Compatibility Test Suite".colorize(:cyan)
puts "=" * 80
puts

# Test configuration
TEST_RESULTS_DIR = 'test_results/compatibility'
TIMESTAMP = Time.now.strftime('%Y%m%d_%H%M%S')

# Create results directory
FileUtils.mkdir_p(TEST_RESULTS_DIR)

# Test suites to run
test_suites = [
  {
    name: 'Comprehensive Compatibility Test Suite',
    file: 'spec/compatibility/comprehensive_compatibility_test_suite.rb',
    description: 'Tests Ruby system vs Legacy_System behavior comparison',
    validates: 'Requirements 15.1, 15.2, 15.3, 15.4, 15.5'
  },
  {
    name: 'WebSocket Event Format Validation',
    file: 'spec/compatibility/websocket_event_format_validation_test.rb',
    description: 'Validates WebSocket event formats match Laravel broadcasting',
    validates: 'Requirements 15.3'
  },
  {
    name: 'API Endpoint Parity Verification',
    file: 'spec/compatibility/api_endpoint_parity_verification_test.rb',
    description: 'Verifies all Laravel API endpoints are implemented identically',
    validates: 'Requirements 15.2'
  },
  {
    name: 'Audio Synchronization Accuracy',
    file: 'spec/compatibility/audio_synchronization_accuracy_test.rb',
    description: 'Tests audio synchronization accuracy and timing precision',
    validates: 'Requirements 15.4'
  },
  {
    name: 'Migration Validation Test',
    file: 'spec/compatibility/migration_validation_test.rb',
    description: 'Validates data compatibility and migration performance',
    validates: 'Requirements 15.5'
  }
]

# Results tracking
results = {
  timestamp: Time.now.iso8601,
  total_suites: test_suites.length,
  passed_suites: 0,
  failed_suites: 0,
  suite_results: []
}

# Run each test suite
test_suites.each_with_index do |suite, index|
  puts "#{index + 1}/#{test_suites.length} Running: #{suite[:name]}".colorize(:yellow)
  puts "   Description: #{suite[:description]}"
  puts "   Validates: #{suite[:validates]}"
  puts

  # Check if test file exists
  unless File.exist?(suite[:file])
    puts "   ❌ Test file not found: #{suite[:file]}".colorize(:red)
    results[:failed_suites] += 1
    results[:suite_results] << {
      name: suite[:name],
      status: 'failed',
      error: 'Test file not found',
      duration: 0
    }
    puts
    next
  end

  # Run the test suite
  start_time = Time.now
  
  begin
    # Execute RSpec with the specific test file
    output_file = "#{TEST_RESULTS_DIR}/#{suite[:name].downcase.gsub(/\s+/, '_')}_#{TIMESTAMP}.txt"
    
    command = "bundle exec rspec #{suite[:file]} --format documentation --format json --out #{output_file}.json 2>&1"
    
    puts "   Executing: #{command}".colorize(:light_black)
    
    output = `#{command}`
    exit_status = $?.exitstatus
    
    duration = Time.now - start_time
    
    # Save output to file
    File.write(output_file, output)
    
    if exit_status == 0
      puts "   ✅ PASSED (#{duration.round(2)}s)".colorize(:green)
      results[:passed_suites] += 1
      results[:suite_results] << {
        name: suite[:name],
        status: 'passed',
        duration: duration.round(2),
        output_file: output_file
      }
    else
      puts "   ❌ FAILED (#{duration.round(2)}s)".colorize(:red)
      results[:failed_suites] += 1
      results[:suite_results] << {
        name: suite[:name],
        status: 'failed',
        duration: duration.round(2),
        output_file: output_file,
        exit_status: exit_status
      }
      
      # Show last few lines of output for quick debugging
      output_lines = output.split("\n")
      if output_lines.length > 5
        puts "   Last few lines of output:".colorize(:light_black)
        output_lines.last(5).each do |line|
          puts "     #{line}".colorize(:light_black)
        end
      end
    end
    
  rescue => e
    duration = Time.now - start_time
    puts "   ❌ ERROR: #{e.message}".colorize(:red)
    results[:failed_suites] += 1
    results[:suite_results] << {
      name: suite[:name],
      status: 'error',
      error: e.message,
      duration: duration.round(2)
    }
  end
  
  puts
end

# Generate summary report
puts "=" * 80
puts "📊 COMPATIBILITY TEST SUITE SUMMARY".colorize(:cyan)
puts "=" * 80

puts "Total Test Suites: #{results[:total_suites]}"
puts "Passed: #{results[:passed_suites]}".colorize(:green)
puts "Failed: #{results[:failed_suites]}".colorize(results[:failed_suites] > 0 ? :red : :green)

total_duration = results[:suite_results].sum { |r| r[:duration] || 0 }
puts "Total Duration: #{total_duration.round(2)}s"

puts
puts "Individual Suite Results:".colorize(:yellow)
results[:suite_results].each do |suite_result|
  status_color = case suite_result[:status]
                when 'passed' then :green
                when 'failed' then :red
                when 'error' then :red
                else :yellow
                end
  
  status_icon = case suite_result[:status]
               when 'passed' then '✅'
               when 'failed' then '❌'
               when 'error' then '💥'
               else '❓'
               end
  
  puts "  #{status_icon} #{suite_result[:name]} - #{suite_result[:status].upcase} (#{suite_result[:duration]}s)".colorize(status_color)
  
  if suite_result[:error]
    puts "     Error: #{suite_result[:error]}".colorize(:light_black)
  end
  
  if suite_result[:output_file]
    puts "     Output: #{suite_result[:output_file]}".colorize(:light_black)
  end
end

# Save results to JSON file
results_file = "#{TEST_RESULTS_DIR}/compatibility_test_results_#{TIMESTAMP}.json"
File.write(results_file, JSON.pretty_generate(results))

puts
puts "📄 Detailed results saved to: #{results_file}".colorize(:light_black)

# Generate compatibility report
puts
puts "=" * 80
puts "📋 COMPATIBILITY VALIDATION REPORT".colorize(:cyan)
puts "=" * 80

validation_status = {
  'Requirements 15.1' => 'Ruby system vs Legacy_System behavior comparison',
  'Requirements 15.2' => 'API endpoint parity verification',
  'Requirements 15.3' => 'WebSocket event format validation',
  'Requirements 15.4' => 'Audio synchronization accuracy',
  'Requirements 15.5' => 'Migration validation and performance'
}

validation_status.each do |requirement, description|
  # Find test suites that validate this requirement
  validating_suites = test_suites.select { |suite| suite[:validates].include?(requirement) }
  suite_results = validating_suites.map { |suite| results[:suite_results].find { |r| r[:name] == suite[:name] } }
  
  all_passed = suite_results.all? { |r| r && r[:status] == 'passed' }
  
  status_icon = all_passed ? '✅' : '❌'
  status_color = all_passed ? :green : :red
  
  puts "#{status_icon} #{requirement}: #{description}".colorize(status_color)
  
  validating_suites.each do |suite|
    suite_result = results[:suite_results].find { |r| r[:name] == suite[:name] }
    if suite_result
      puts "   └─ #{suite[:name]}: #{suite_result[:status].upcase}".colorize(status_color)
    end
  end
  puts
end

# Final verdict
if results[:failed_suites] == 0
  puts "🎉 ALL COMPATIBILITY TESTS PASSED!".colorize(:green)
  puts "✅ Ruby backend is fully compatible with Legacy_System".colorize(:green)
  puts "✅ Migration validation successful".colorize(:green)
  exit_code = 0
else
  puts "⚠️  SOME COMPATIBILITY TESTS FAILED".colorize(:red)
  puts "❌ #{results[:failed_suites]} out of #{results[:total_suites]} test suites failed".colorize(:red)
  puts "🔧 Review failed tests and fix compatibility issues before migration".colorize(:yellow)
  exit_code = 1
end

puts
puts "=" * 80
puts "Test execution completed at #{Time.now}".colorize(:light_black)
puts "Results directory: #{TEST_RESULTS_DIR}".colorize(:light_black)

# Exit with appropriate code
exit(exit_code)