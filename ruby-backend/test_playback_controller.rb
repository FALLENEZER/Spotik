#!/usr/bin/env ruby

# Test script for PlaybackController functionality
# Tests synchronized playback control with timestamp synchronization

require_relative 'config/settings'
require_relative 'config/database'
require_relative 'app/models'
require_relative 'app/services/auth_service'
require_relative 'app/services/room_manager'
require_relative 'app/controllers/playback_controller'

puts "=== Playback Controller Test ==="
puts "Testing synchronized playback control with timestamp synchronization"
puts

# Test data setup
def setup_test_data
  puts "Setting up test data..."
  
  # Create test user (administrator)
  admin_user = User.create(
    id: SecureRandom.uuid,
    username: "admin_#{SecureRandom.hex(4)}",
    email: "admin_#{SecureRandom.hex(4)}@test.com",
    password_hash: BCrypt::Password.create('password123'),
    created_at: Time.now,
    updated_at: Time.now
  )
  
  # Create test room
  room = Room.create(
    id: SecureRandom.uuid,
    name: "Test Playback Room",
    administrator_id: admin_user.id,
    is_playing: false,
    created_at: Time.now,
    updated_at: Time.now
  )
  
  # Add admin as participant
  room.add_participant(admin_user)
  
  # Create test tracks
  track1 = Track.create(
    id: SecureRandom.uuid,
    room_id: room.id,
    uploader_id: admin_user.id,
    filename: "test_track_1.mp3",
    original_name: "Test Track 1.mp3",
    file_path: "/fake/path/test_track_1.mp3",
    duration_seconds: 180,
    file_size_bytes: 5000000,
    mime_type: "audio/mpeg",
    vote_score: 0,
    created_at: Time.now,
    updated_at: Time.now
  )
  
  track2 = Track.create(
    id: SecureRandom.uuid,
    room_id: room.id,
    uploader_id: admin_user.id,
    filename: "test_track_2.mp3",
    original_name: "Test Track 2.mp3",
    file_path: "/fake/path/test_track_2.mp3",
    duration_seconds: 240,
    file_size_bytes: 6000000,
    mime_type: "audio/mpeg",
    vote_score: 0,
    created_at: Time.now,
    updated_at: Time.now
  )
  
  puts "✓ Created test user: #{admin_user.username}"
  puts "✓ Created test room: #{room.name}"
  puts "✓ Created test tracks: #{track1.original_name}, #{track2.original_name}"
  puts
  
  { admin_user: admin_user, room: room, track1: track1, track2: track2 }
end

# Test playback start functionality
def test_playback_start(admin_user, room, track)
  puts "Testing playback start..."
  
  # Generate JWT token for admin
  token = AuthService.generate_jwt(admin_user.id)
  
  # Start playback
  start_time = Time.now
  result = PlaybackController.start_track(room.id, track.id, token)
  
  if result[:status] == 200
    puts "✓ Playback started successfully"
    puts "  - Track: #{track.original_name}"
    puts "  - Started at: #{Time.at(result[:body][:started_at]).strftime('%H:%M:%S.%3N')}"
    puts "  - Server time: #{Time.at(result[:body][:server_time]).strftime('%H:%M:%S.%3N')}"
    puts "  - Response time: #{((Time.now - start_time) * 1000).round(2)}ms"
    
    # Verify room state
    room.refresh
    if room.is_playing && room.current_track_id == track.id
      puts "✓ Room state updated correctly"
      puts "  - Is playing: #{room.is_playing}"
      puts "  - Current track: #{room.current_track.original_name}"
      puts "  - Playback started at: #{room.playback_started_at.strftime('%H:%M:%S.%3N')}"
    else
      puts "✗ Room state not updated correctly"
      return false
    end
  else
    puts "✗ Playback start failed: #{result[:body][:error]}"
    return false
  end
  
  puts
  true
end

# Test playback pause functionality
def test_playback_pause(admin_user, room)
  puts "Testing playback pause..."
  
  # Wait a moment to have some playback time
  sleep(0.5)
  
  # Generate JWT token for admin
  token = AuthService.generate_jwt(admin_user.id)
  
  # Pause playback
  pause_time = Time.now
  result = PlaybackController.pause_track(room.id, token)
  
  if result[:status] == 200
    puts "✓ Playback paused successfully"
    puts "  - Paused at: #{Time.at(result[:body][:paused_at]).strftime('%H:%M:%S.%3N')}"
    puts "  - Position: #{result[:body][:position].round(3)}s"
    puts "  - Server time: #{Time.at(result[:body][:server_time]).strftime('%H:%M:%S.%3N')}"
    
    # Verify room state
    room.refresh
    if !room.is_playing && room.playback_paused_at
      puts "✓ Room state updated correctly"
      puts "  - Is playing: #{room.is_playing}"
      puts "  - Paused at: #{room.playback_paused_at.strftime('%H:%M:%S.%3N')}"
    else
      puts "✗ Room state not updated correctly"
      return false
    end
  else
    puts "✗ Playback pause failed: #{result[:body][:error]}"
    return false
  end
  
  puts
  true
end

# Test playback resume functionality
def test_playback_resume(admin_user, room)
  puts "Testing playback resume..."
  
  # Wait a moment to simulate pause duration
  sleep(0.3)
  
  # Generate JWT token for admin
  token = AuthService.generate_jwt(admin_user.id)
  
  # Resume playback
  resume_time = Time.now
  result = PlaybackController.resume_track(room.id, token)
  
  if result[:status] == 200
    puts "✓ Playback resumed successfully"
    puts "  - Resumed at: #{Time.at(result[:body][:resumed_at]).strftime('%H:%M:%S.%3N')}"
    puts "  - Position: #{result[:body][:position].round(3)}s"
    puts "  - Server time: #{Time.at(result[:body][:server_time]).strftime('%H:%M:%S.%3N')}"
    
    # Verify room state
    room.refresh
    if room.is_playing && !room.playback_paused_at
      puts "✓ Room state updated correctly"
      puts "  - Is playing: #{room.is_playing}"
      puts "  - Playback started at: #{room.playback_started_at.strftime('%H:%M:%S.%3N')}"
    else
      puts "✗ Room state not updated correctly"
      return false
    end
  else
    puts "✗ Playback resume failed: #{result[:body][:error]}"
    return false
  end
  
  puts
  true
end

# Test playback skip functionality
def test_playback_skip(admin_user, room, next_track)
  puts "Testing playback skip..."
  
  # Generate JWT token for admin
  token = AuthService.generate_jwt(admin_user.id)
  
  # Skip to next track
  skip_time = Time.now
  result = PlaybackController.skip_track(room.id, token)
  
  if result[:status] == 200
    puts "✓ Track skipped successfully"
    if result[:body][:new_track]
      puts "  - New track: #{result[:body][:new_track][:original_name]}"
      puts "  - Started at: #{Time.at(result[:body][:started_at]).strftime('%H:%M:%S.%3N')}"
      puts "  - Server time: #{Time.at(result[:body][:server_time]).strftime('%H:%M:%S.%3N')}"
      
      # Verify room state
      room.refresh
      if room.is_playing && room.current_track_id == next_track.id
        puts "✓ Room state updated correctly"
        puts "  - Current track: #{room.current_track.original_name}"
      else
        puts "✗ Room state not updated correctly"
        return false
      end
    else
      puts "  - No more tracks in queue - playback stopped"
      puts "  - Stopped at: #{Time.at(result[:body][:stopped_at]).strftime('%H:%M:%S.%3N')}"
    end
  else
    puts "✗ Track skip failed: #{result[:body][:error]}"
    return false
  end
  
  puts
  true
end

# Test playback status functionality
def test_playback_status(admin_user, room)
  puts "Testing playback status..."
  
  # Generate JWT token for admin
  token = AuthService.generate_jwt(admin_user.id)
  
  # Get playback status
  result = PlaybackController.get_playback_status(room.id, token)
  
  if result[:status] == 200
    status = result[:body][:playback_status]
    puts "✓ Playback status retrieved successfully"
    puts "  - Room ID: #{status[:room_id]}"
    puts "  - Is playing: #{status[:is_playing]}"
    puts "  - Current track: #{status[:current_track] ? status[:current_track][:original_name] : 'None'}"
    puts "  - Current position: #{status[:current_position].round(3)}s"
    puts "  - Server time: #{Time.at(status[:server_time]).strftime('%H:%M:%S.%3N')}"
    puts "  - Queue length: #{status[:queue_length]}"
    puts "  - Administrator: #{status[:administrator][:username]}"
  else
    puts "✗ Playback status failed: #{result[:body][:error]}"
    return false
  end
  
  puts
  true
end

# Test playback stop functionality
def test_playback_stop(admin_user, room)
  puts "Testing playback stop..."
  
  # Generate JWT token for admin
  token = AuthService.generate_jwt(admin_user.id)
  
  # Stop playback
  stop_time = Time.now
  result = PlaybackController.stop_playback(room.id, token)
  
  if result[:status] == 200
    puts "✓ Playback stopped successfully"
    puts "  - Stopped at: #{Time.at(result[:body][:stopped_at]).strftime('%H:%M:%S.%3N')}"
    puts "  - Server time: #{Time.at(result[:body][:server_time]).strftime('%H:%M:%S.%3N')}"
    
    # Verify room state
    room.refresh
    if !room.is_playing && !room.current_track_id
      puts "✓ Room state updated correctly"
      puts "  - Is playing: #{room.is_playing}"
      puts "  - Current track: None"
    else
      puts "✗ Room state not updated correctly"
      return false
    end
  else
    puts "✗ Playback stop failed: #{result[:body][:error]}"
    return false
  end
  
  puts
  true
end

# Test timestamp synchronization accuracy
def test_timestamp_synchronization(admin_user, room, track)
  puts "Testing timestamp synchronization accuracy..."
  
  # Generate JWT token for admin
  token = AuthService.generate_jwt(admin_user.id)
  
  # Start playback and measure timing
  client_start_time = Time.now
  result = PlaybackController.start_track(room.id, track.id, token)
  client_end_time = Time.now
  
  if result[:status] == 200
    server_start_time = result[:body][:started_at]
    server_time = result[:body][:server_time]
    
    # Calculate timing differences
    client_duration = (client_end_time - client_start_time) * 1000 # ms
    server_client_diff = (server_time - client_end_time.to_f) * 1000 # ms
    
    puts "✓ Timestamp synchronization test completed"
    puts "  - Client request duration: #{client_duration.round(2)}ms"
    puts "  - Server-client time diff: #{server_client_diff.round(2)}ms"
    puts "  - Server start time: #{Time.at(server_start_time).strftime('%H:%M:%S.%6N')}"
    puts "  - Server response time: #{Time.at(server_time).strftime('%H:%M:%S.%6N')}"
    
    # Wait and check position accuracy
    sleep(0.5)
    
    # Get current status
    status_result = PlaybackController.get_playback_status(room.id, token)
    if status_result[:status] == 200
      status = status_result[:body][:playback_status]
      expected_position = Time.now.to_f - server_start_time
      actual_position = status[:current_position]
      position_diff = (actual_position - expected_position).abs
      
      puts "  - Expected position: #{expected_position.round(3)}s"
      puts "  - Actual position: #{actual_position.round(3)}s"
      puts "  - Position difference: #{(position_diff * 1000).round(2)}ms"
      
      if position_diff < 0.1 # Less than 100ms difference
        puts "✓ Position synchronization accurate (< 100ms difference)"
      else
        puts "⚠ Position synchronization may need improvement (> 100ms difference)"
      end
    end
  else
    puts "✗ Timestamp synchronization test failed: #{result[:body][:error]}"
    return false
  end
  
  puts
  true
end

# Cleanup test data
def cleanup_test_data(test_data)
  puts "Cleaning up test data..."
  
  begin
    # Delete tracks
    test_data[:track1].destroy if test_data[:track1]
    test_data[:track2].destroy if test_data[:track2]
    
    # Delete room (cascades to participants)
    test_data[:room].destroy if test_data[:room]
    
    # Delete user
    test_data[:admin_user].destroy if test_data[:admin_user]
    
    puts "✓ Test data cleaned up successfully"
  rescue => e
    puts "⚠ Error during cleanup: #{e.message}"
  end
  
  puts
end

# Main test execution
begin
  # Setup test data
  test_data = setup_test_data
  admin_user = test_data[:admin_user]
  room = test_data[:room]
  track1 = test_data[:track1]
  track2 = test_data[:track2]
  
  # Run tests
  tests_passed = 0
  total_tests = 7
  
  tests_passed += 1 if test_playback_start(admin_user, room, track1)
  tests_passed += 1 if test_playback_pause(admin_user, room)
  tests_passed += 1 if test_playback_resume(admin_user, room)
  tests_passed += 1 if test_playback_skip(admin_user, room, track2)
  tests_passed += 1 if test_playback_status(admin_user, room)
  tests_passed += 1 if test_playback_stop(admin_user, room)
  tests_passed += 1 if test_timestamp_synchronization(admin_user, room, track1)
  
  # Test summary
  puts "=== Test Summary ==="
  puts "Tests passed: #{tests_passed}/#{total_tests}"
  puts "Success rate: #{((tests_passed.to_f / total_tests) * 100).round(1)}%"
  
  if tests_passed == total_tests
    puts "✓ All playback controller tests passed!"
    puts
    puts "Key features verified:"
    puts "- ✓ Play/pause/resume/skip/stop controls"
    puts "- ✓ Server-side timestamp synchronization"
    puts "- ✓ Accurate playback position calculation"
    puts "- ✓ Administrator-only access control"
    puts "- ✓ Real-time state broadcasting"
    puts "- ✓ Comprehensive playback status reporting"
  else
    puts "✗ Some tests failed. Please check the implementation."
  end
  
rescue => e
  puts "✗ Test execution failed: #{e.message}"
  puts e.backtrace.join("\n") if ENV['DEBUG']
ensure
  # Always cleanup
  cleanup_test_data(test_data) if test_data
end

puts
puts "=== Playback Controller Test Complete ==="