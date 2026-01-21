#!/usr/bin/env ruby
# Test script to verify Sequel models work with existing Laravel database

require 'dotenv/load'
require_relative 'app/models'

puts "🔍 Testing Sequel models compatibility with Laravel database..."
puts "=" * 60

begin
  # Test database connection
  puts "\n1. Testing database connection..."
  health = ModelLoader.health_check
  puts "   Database status: #{health[:database][:status]}"
  
  if health[:database][:status] == 'healthy'
    puts "   ✓ Database connection successful"
  else
    puts "   ✗ Database connection failed: #{health[:database][:error]}"
    exit 1
  end
  
  # Test model counts
  puts "\n2. Testing model access..."
  health[:models].each do |model, count|
    next if model == :error
    puts "   #{model.to_s.capitalize} records: #{count}"
  end
  
  # Test basic model operations
  puts "\n3. Testing model relationships..."
  
  # Test User model
  user_count = User.count
  puts "   Users in database: #{user_count}"
  
  if user_count > 0
    user = User.first
    puts "   Sample user: #{user.username} (#{user.email})"
    puts "   User rooms: #{user.rooms.count}"
    puts "   User uploaded tracks: #{user.uploaded_tracks.count}"
  end
  
  # Test Room model
  room_count = Room.count
  puts "   Rooms in database: #{room_count}"
  
  if room_count > 0
    room = Room.first
    puts "   Sample room: #{room.name}"
    puts "   Room administrator: #{room.administrator&.username}"
    puts "   Room participants: #{room.participants.count}"
    puts "   Room tracks: #{room.tracks.count}"
    puts "   Current track: #{room.current_track&.original_name || 'None'}"
    puts "   Is playing: #{room.is_playing}"
  end
  
  # Test Track model
  track_count = Track.count
  puts "   Tracks in database: #{track_count}"
  
  if track_count > 0
    track = Track.first
    puts "   Sample track: #{track.original_name}"
    puts "   Track uploader: #{track.uploader&.username}"
    puts "   Track room: #{track.room&.name}"
    puts "   Track votes: #{track.votes.count}"
    puts "   Track vote score: #{track.vote_score}"
    puts "   Track duration: #{track.formatted_duration}"
    puts "   Track file size: #{track.formatted_file_size}"
  end
  
  # Test associations
  puts "\n4. Testing model associations..."
  
  if user_count > 0 && room_count > 0
    user = User.first
    room = Room.first
    
    # Test user-room associations
    puts "   User administered rooms: #{user.administered_rooms.count}"
    puts "   User participating rooms: #{user.rooms.count}"
    puts "   Room participants: #{room.users.count}"
    
    # Test track associations if tracks exist
    if track_count > 0
      track = Track.first
      puts "   Track room association: #{track.room&.name}"
      puts "   Track uploader association: #{track.uploader&.username}"
      puts "   Track voters: #{track.voters.count}"
    end
  end
  
  # Test validation
  puts "\n5. Testing model validation..."
  
  # Test User validation
  user = User.new
  user.valid?
  puts "   User validation errors: #{user.errors.full_messages.join(', ')}" if user.errors.any?
  
  # Test Room validation
  room = Room.new
  room.valid?
  puts "   Room validation errors: #{room.errors.full_messages.join(', ')}" if room.errors.any?
  
  # Test Track validation
  track = Track.new
  track.valid?
  puts "   Track validation errors: #{track.errors.full_messages.join(', ')}" if track.errors.any?
  
  puts "\n✅ All model tests completed successfully!"
  puts "   Sequel models are compatible with the existing Laravel database."
  
rescue => e
  puts "\n❌ Model test failed: #{e.message}"
  puts "   Backtrace:"
  puts e.backtrace.first(5).map { |line| "     #{line}" }
  exit 1
end