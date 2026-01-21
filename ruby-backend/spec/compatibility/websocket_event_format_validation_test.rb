#!/usr/bin/env ruby

# WebSocket Event Format Validation Test
# **Feature: ruby-backend-migration, Task 16.1: WebSocket event format validation tests**
# **Validates: Requirements 15.3** - System SHALL support same WebSocket events and formats

require 'bundler/setup'
require 'rspec'
require 'json'
require 'securerandom'
require 'time'

# Set test environment
ENV['APP_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test_jwt_secret_key_for_testing_purposes_only'

# Load configuration and database
require_relative '../../config/settings'
require_relative '../../config/test_database'

# Set up the DB constant for testing
Object.send(:remove_const, :DB) if defined?(DB)
DB = SpotikConfig::TestDatabase.connection

# Load models
require_relative '../../app/models/user'
require_relative '../../app/models/room'
require_relative '../../app/models/track'
require_relative '../../app/models/room_participant'
require_relative '../../app/models/track_vote'

# Override the database connection for models
[User, Room, Track, RoomParticipant, TrackVote].each do |model|
  model.dataset = DB[model.table_name]
end

# Finalize associations
Sequel::Model.finalize_associations

# Mock WebSocket system for event capture
class WebSocketEventCapture
  @@captured_events = []
  
  def self.capture_event(channel, message)
    @@captured_events << {
      channel: channel,
      message: message,
      timestamp: Time.now.to_f,
      raw_message: message.is_a?(String) ? message : message.to_json
    }
  end
  
  def self.get_captured_events
    @@captured_events
  end
  
  def self.clear_captured_events
    @@captured_events.clear
  end
  
  def self.find_event_by_type(event_type)
    @@captured_events.find do |event|
      parsed = JSON.parse(event[:raw_message])
      parsed['type'] == event_type
    end
  end
  
  def self.find_events_by_channel(channel)
    @@captured_events.select { |event| event[:channel] == channel }
  end
end

# Mock Iodine for event capture
module Iodine
  def self.publish(channel, message)
    WebSocketEventCapture.capture_event(channel, message)
    true
  end
end

# Load services
require_relative '../../app/services/event_broadcaster'
require_relative '../../app/services/room_manager'

RSpec.describe 'WebSocket Event Format Validation', :websocket_compatibility do
  
  before(:each) do
    # Clean database and event capture
    DB[:track_votes].delete
    DB[:room_participants].delete
    DB[:tracks].delete
    DB[:rooms].delete
    DB[:users].delete
    
    WebSocketEventCapture.clear_captured_events
  end

  describe 'Laravel-Compatible Event Structure' do
    
    it 'validates user activity event format matches Laravel broadcasting' do
      # Create test data
      user = create_test_user(username: 'eventuser', email: 'event@example.com')
      room = create_test_room(user, name: 'Event Test Room')
      
      # Generate user joined event
      EventBroadcaster.broadcast_user_activity(room.id, :joined, user)
      
      # Capture and validate event
      event = WebSocketEventCapture.find_event_by_type('user_joined')
      expect(event).not_to be_nil, "User joined event not captured"
      
      # Parse event message
      message = JSON.parse(event[:raw_message])
      
      # Validate Laravel-compatible structure
      expect(message).to have_key('type')
      expect(message).to have_key('data')
      expect(message).to have_key('timestamp')
      expect(message).to have_key('priority')
      
      expect(message['type']).to eq('user_joined')
      
      # Validate data structure
      data = message['data']
      expect(data).to have_key('room_id')
      expect(data).to have_key('user')
      expect(data).to have_key('participants_count')
      expect(data).to have_key('server_time')
      
      expect(data['room_id']).to eq(room.id)
      expect(data['user']['id']).to eq(user.id)
      expect(data['user']['username']).to eq(user.username)
      
      # Validate timestamp precision (Laravel uses millisecond precision)
      expect(data['server_time']).to be_within(0.1).of(Time.now.to_f)
      
      # Validate channel format
      expect(event[:channel]).to eq("room_#{room.id}")
    end

    it 'validates user left event format matches Laravel broadcasting' do
      user = create_test_user(username: 'leaveuser', email: 'leave@example.com')
      room = create_test_room(user, name: 'Leave Test Room')
      
      # Add another user to leave
      leaving_user = create_test_user(username: 'leavinguser', email: 'leaving@example.com')
      room.add_participant(leaving_user)
      
      # Generate user left event
      EventBroadcaster.broadcast_user_activity(room.id, :left, leaving_user)
      
      event = WebSocketEventCapture.find_event_by_type('user_left')
      expect(event).not_to be_nil
      
      message = JSON.parse(event[:raw_message])
      
      # Validate structure
      expect(message['type']).to eq('user_left')
      
      data = message['data']
      expect(data).to have_key('room_id')
      expect(data).to have_key('user')
      expect(data).to have_key('participants_count')
      expect(data).to have_key('server_time')
      
      expect(data['room_id']).to eq(room.id)
      expect(data['user']['id']).to eq(leaving_user.id)
      expect(data['user']['username']).to eq(leaving_user.username)
    end

    it 'validates track activity event formats match Laravel broadcasting' do
      user = create_test_user(username: 'trackuser', email: 'track@example.com')
      room = create_test_room(user, name: 'Track Test Room')
      track = create_test_track(user, room)
      
      # Test track added event
      EventBroadcaster.broadcast_track_activity(room.id, :added, track, user)
      
      event = WebSocketEventCapture.find_event_by_type('track_added')
      expect(event).not_to be_nil
      
      message = JSON.parse(event[:raw_message])
      
      # Validate structure
      expect(message['type']).to eq('track_added')
      
      data = message['data']
      expect(data).to have_key('room_id')
      expect(data).to have_key('track')
      expect(data).to have_key('uploader')
      expect(data).to have_key('queue_position')
      expect(data).to have_key('server_time')
      
      # Validate track data structure
      track_data = data['track']
      expect(track_data).to have_key('id')
      expect(track_data).to have_key('filename')
      expect(track_data).to have_key('original_name')
      expect(track_data).to have_key('duration_seconds')
      expect(track_data).to have_key('file_size_bytes')
      expect(track_data).to have_key('mime_type')
      expect(track_data).to have_key('vote_score')
      expect(track_data).to have_key('created_at')
      
      expect(track_data['id']).to eq(track.id)
      expect(track_data['original_name']).to eq(track.original_name)
      expect(track_data['duration_seconds']).to eq(track.duration_seconds)
      
      # Validate uploader data
      uploader_data = data['uploader']
      expect(uploader_data).to have_key('id')
      expect(uploader_data).to have_key('username')
      expect(uploader_data['id']).to eq(user.id)
      expect(uploader_data['username']).to eq(user.username)
    end

    it 'validates voting event formats match Laravel broadcasting' do
      user = create_test_user(username: 'voteuser', email: 'vote@example.com')
      room = create_test_room(user, name: 'Vote Test Room')
      track = create_test_track(user, room)
      voter = create_test_user(username: 'voter', email: 'voter@example.com')
      
      # Test track voted event
      EventBroadcaster.broadcast_track_activity(room.id, :voted, track, voter)
      
      event = WebSocketEventCapture.find_event_by_type('track_voted')
      expect(event).not_to be_nil
      
      message = JSON.parse(event[:raw_message])
      
      # Validate structure
      expect(message['type']).to eq('track_voted')
      
      data = message['data']
      expect(data).to have_key('room_id')
      expect(data).to have_key('track')
      expect(data).to have_key('voter')
      expect(data).to have_key('new_vote_score')
      expect(data).to have_key('queue_updated')
      expect(data).to have_key('server_time')
      
      expect(data['room_id']).to eq(room.id)
      expect(data['track']['id']).to eq(track.id)
      expect(data['voter']['id']).to eq(voter.id)
      expect(data['voter']['username']).to eq(voter.username)
      
      # Test track unvoted event
      WebSocketEventCapture.clear_captured_events
      EventBroadcaster.broadcast_track_activity(room.id, :unvoted, track, voter)
      
      unvote_event = WebSocketEventCapture.find_event_by_type('track_unvoted')
      expect(unvote_event).not_to be_nil
      
      unvote_message = JSON.parse(unvote_event[:raw_message])
      expect(unvote_message['type']).to eq('track_unvoted')
      
      unvote_data = unvote_message['data']
      expect(unvote_data).to have_key('room_id')
      expect(unvote_data).to have_key('track')
      expect(unvote_data).to have_key('voter')
      expect(unvote_data).to have_key('new_vote_score')
    end

    it 'validates playback control event formats match Laravel broadcasting' do
      user = create_test_user(username: 'playbackuser', email: 'playback@example.com')
      room = create_test_room(user, name: 'Playback Test Room')
      track = create_test_track(user, room)
      
      # Test playback started event
      EventBroadcaster.broadcast_playback_activity(room.id, :started, user, {
        track: track,
        started_at: Time.now.to_f
      })
      
      event = WebSocketEventCapture.find_event_by_type('playback_started')
      expect(event).not_to be_nil
      
      message = JSON.parse(event[:raw_message])
      
      # Validate structure
      expect(message['type']).to eq('playback_started')
      
      data = message['data']
      expect(data).to have_key('room_id')
      expect(data).to have_key('track')
      expect(data).to have_key('administrator')
      expect(data).to have_key('is_playing')
      expect(data).to have_key('started_at')
      expect(data).to have_key('position')
      expect(data).to have_key('server_time')
      
      expect(data['room_id']).to eq(room.id)
      expect(data['is_playing']).to be true
      expect(data['administrator']['id']).to eq(user.id)
      expect(data['track']['id']).to eq(track.id)
      
      # Validate timestamp precision for synchronization
      expect(data['started_at']).to be_within(0.1).of(Time.now.to_f)
      expect(data['server_time']).to be_within(0.1).of(Time.now.to_f)
      
      # Test playback paused event
      WebSocketEventCapture.clear_captured_events
      EventBroadcaster.broadcast_playback_activity(room.id, :paused, user, {
        paused_at: Time.now.to_f,
        position: 45.5
      })
      
      pause_event = WebSocketEventCapture.find_event_by_type('playback_paused')
      expect(pause_event).not_to be_nil
      
      pause_message = JSON.parse(pause_event[:raw_message])
      expect(pause_message['type']).to eq('playback_paused')
      
      pause_data = pause_message['data']
      expect(pause_data).to have_key('room_id')
      expect(pause_data).to have_key('administrator')
      expect(pause_data).to have_key('is_playing')
      expect(pause_data).to have_key('paused_at')
      expect(pause_data).to have_key('position')
      expect(pause_data).to have_key('server_time')
      
      expect(pause_data['is_playing']).to be false
      expect(pause_data['position']).to eq(45.5)
    end
  end

  describe 'Event Message Serialization' do
    
    it 'ensures all event messages are valid JSON' do
      user = create_test_user(username: 'jsonuser', email: 'json@example.com')
      room = create_test_room(user, name: 'JSON Test Room')
      track = create_test_track(user, room)
      
      # Generate various events
      EventBroadcaster.broadcast_user_activity(room.id, :joined, user)
      EventBroadcaster.broadcast_track_activity(room.id, :added, track, user)
      EventBroadcaster.broadcast_playback_activity(room.id, :started, user, { track: track })
      
      events = WebSocketEventCapture.get_captured_events
      expect(events.length).to be >= 3
      
      events.each do |event|
        # Verify each message is valid JSON
        expect { JSON.parse(event[:raw_message]) }.not_to raise_error, 
          "Invalid JSON in event: #{event[:raw_message]}"
        
        # Verify parsed JSON has required structure
        parsed = JSON.parse(event[:raw_message])
        expect(parsed).to have_key('type')
        expect(parsed).to have_key('data')
        expect(parsed).to have_key('timestamp')
        
        # Verify timestamp is a valid number
        expect(parsed['timestamp']).to be_a(Numeric)
        expect(parsed['timestamp']).to be > 0
      end
    end

    it 'validates event data types match Laravel expectations' do
      user = create_test_user(username: 'typeuser', email: 'type@example.com')
      room = create_test_room(user, name: 'Type Test Room')
      track = create_test_track(user, room)
      
      EventBroadcaster.broadcast_track_activity(room.id, :added, track, user)
      
      event = WebSocketEventCapture.find_event_by_type('track_added')
      message = JSON.parse(event[:raw_message])
      data = message['data']
      
      # Validate data types
      expect(data['room_id']).to be_a(String)
      expect(data['server_time']).to be_a(Numeric)
      expect(data['queue_position']).to be_a(Integer)
      
      track_data = data['track']
      expect(track_data['id']).to be_a(String)
      expect(track_data['filename']).to be_a(String)
      expect(track_data['original_name']).to be_a(String)
      expect(track_data['duration_seconds']).to be_a(Integer)
      expect(track_data['file_size_bytes']).to be_a(Integer)
      expect(track_data['vote_score']).to be_a(Integer)
      expect(track_data['created_at']).to be_a(String)
      
      # Validate date format (ISO 8601)
      expect(track_data['created_at']).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      
      uploader_data = data['uploader']
      expect(uploader_data['id']).to be_a(String)
      expect(uploader_data['username']).to be_a(String)
    end

    it 'validates special characters and unicode handling in event messages' do
      # Create user with special characters
      user = create_test_user(username: 'üñíçødé_user', email: 'unicode@example.com')
      room = create_test_room(user, name: 'Röøm wîth spéçiål çhårs! 🎵')
      
      EventBroadcaster.broadcast_user_activity(room.id, :joined, user)
      
      event = WebSocketEventCapture.find_event_by_type('user_joined')
      expect(event).not_to be_nil
      
      # Verify JSON parsing handles unicode correctly
      message = JSON.parse(event[:raw_message])
      data = message['data']
      
      expect(data['user']['username']).to eq('üñíçødé_user')
      
      # Verify room name with special characters
      # Note: Room name might be in room data if included in event
      expect(event[:raw_message]).to include('🎵') # Emoji should be preserved
    end
  end

  describe 'Event Timing and Ordering' do
    
    it 'validates event timestamps are in correct chronological order' do
      user = create_test_user(username: 'timinguser', email: 'timing@example.com')
      room = create_test_room(user, name: 'Timing Test Room')
      
      # Generate sequence of events with small delays
      start_time = Time.now.to_f
      
      EventBroadcaster.broadcast_user_activity(room.id, :joined, user)
      sleep(0.01)
      
      track = create_test_track(user, room)
      EventBroadcaster.broadcast_track_activity(room.id, :added, track, user)
      sleep(0.01)
      
      EventBroadcaster.broadcast_playback_activity(room.id, :started, user, { track: track })
      
      events = WebSocketEventCapture.get_captured_events
      expect(events.length).to be >= 3
      
      # Verify timestamps are in chronological order
      timestamps = events.map { |e| e[:timestamp] }
      expect(timestamps).to eq(timestamps.sort), "Events not in chronological order"
      
      # Verify all timestamps are after start time
      timestamps.each do |timestamp|
        expect(timestamp).to be >= start_time
      end
      
      # Verify message timestamps match capture timestamps (within tolerance)
      events.each do |event|
        message = JSON.parse(event[:raw_message])
        message_timestamp = message['timestamp']
        capture_timestamp = event[:timestamp]
        
        expect(message_timestamp).to be_within(0.1).of(capture_timestamp)
      end
    end

    it 'validates event delivery within acceptable time windows' do
      user = create_test_user(username: 'deliveryuser', email: 'delivery@example.com')
      room = create_test_room(user, name: 'Delivery Test Room')
      
      # Measure event generation and delivery time
      generation_start = Time.now.to_f
      EventBroadcaster.broadcast_user_activity(room.id, :joined, user)
      generation_end = Time.now.to_f
      
      event = WebSocketEventCapture.find_event_by_type('user_joined')
      expect(event).not_to be_nil
      
      # Verify event was captured quickly (within 10ms)
      delivery_time = event[:timestamp] - generation_start
      expect(delivery_time).to be < 0.01, "Event delivery too slow: #{delivery_time * 1000}ms"
      
      # Verify event timestamp is within generation window
      message = JSON.parse(event[:raw_message])
      event_timestamp = message['timestamp']
      
      expect(event_timestamp).to be_between(generation_start, generation_end)
    end
  end

  describe 'Channel and Routing Validation' do
    
    it 'validates events are published to correct channels' do
      user1 = create_test_user(username: 'channeluser1', email: 'channel1@example.com')
      user2 = create_test_user(username: 'channeluser2', email: 'channel2@example.com')
      
      room1 = create_test_room(user1, name: 'Channel Test Room 1')
      room2 = create_test_room(user2, name: 'Channel Test Room 2')
      
      # Generate events for different rooms
      EventBroadcaster.broadcast_user_activity(room1.id, :joined, user1)
      EventBroadcaster.broadcast_user_activity(room2.id, :joined, user2)
      
      events = WebSocketEventCapture.get_captured_events
      expect(events.length).to be >= 2
      
      # Verify events are published to correct room channels
      room1_events = WebSocketEventCapture.find_events_by_channel("room_#{room1.id}")
      room2_events = WebSocketEventCapture.find_events_by_channel("room_#{room2.id}")
      
      expect(room1_events.length).to be >= 1
      expect(room2_events.length).to be >= 1
      
      # Verify room1 events contain room1 data
      room1_event = room1_events.first
      room1_message = JSON.parse(room1_event[:raw_message])
      expect(room1_message['data']['room_id']).to eq(room1.id)
      expect(room1_message['data']['user']['id']).to eq(user1.id)
      
      # Verify room2 events contain room2 data
      room2_event = room2_events.first
      room2_message = JSON.parse(room2_event[:raw_message])
      expect(room2_message['data']['room_id']).to eq(room2.id)
      expect(room2_message['data']['user']['id']).to eq(user2.id)
    end

    it 'validates channel naming convention matches Laravel broadcasting' do
      user = create_test_user(username: 'conventionuser', email: 'convention@example.com')
      room = create_test_room(user, name: 'Convention Test Room')
      
      EventBroadcaster.broadcast_user_activity(room.id, :joined, user)
      
      events = WebSocketEventCapture.get_captured_events
      expect(events.length).to be >= 1
      
      event = events.first
      
      # Verify channel follows Laravel convention: "room_{room_id}"
      expected_channel = "room_#{room.id}"
      expect(event[:channel]).to eq(expected_channel)
      
      # Verify room ID format (should be UUID)
      expect(room.id).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
    end
  end

  describe 'Error Handling in Event Broadcasting' do
    
    it 'handles malformed event data gracefully' do
      user = create_test_user(username: 'erroruser', email: 'error@example.com')
      room = create_test_room(user, name: 'Error Test Room')
      
      # Test with nil user (should not crash)
      expect {
        EventBroadcaster.broadcast_user_activity(room.id, :joined, nil)
      }.not_to raise_error
      
      # Test with invalid room ID (should not crash)
      expect {
        EventBroadcaster.broadcast_user_activity('invalid-room-id', :joined, user)
      }.not_to raise_error
      
      # Test with invalid event type (should not crash)
      expect {
        EventBroadcaster.broadcast_user_activity(room.id, :invalid_event, user)
      }.not_to raise_error
    end

    it 'validates event broadcasting continues after individual failures' do
      user = create_test_user(username: 'resilientuser', email: 'resilient@example.com')
      room = create_test_room(user, name: 'Resilient Test Room')
      
      # Mock a failure in the middle of event generation
      original_publish = Iodine.method(:publish)
      call_count = 0
      
      allow(Iodine).to receive(:publish) do |channel, message|
        call_count += 1
        if call_count == 2
          raise StandardError.new("Simulated broadcast failure")
        else
          original_publish.call(channel, message)
        end
      end
      
      # Generate multiple events
      expect {
        EventBroadcaster.broadcast_user_activity(room.id, :joined, user)
        EventBroadcaster.broadcast_user_activity(room.id, :left, user)  # This should fail
        EventBroadcaster.broadcast_user_activity(room.id, :joined, user)
      }.not_to raise_error
      
      # Verify some events were still captured (the ones that didn't fail)
      events = WebSocketEventCapture.get_captured_events
      expect(events.length).to be >= 1  # At least one event should have succeeded
    end
  end

  # Helper methods

  def create_test_user(username: nil, email: nil, password: 'password123')
    username ||= "user_#{SecureRandom.hex(6)}"
    email ||= "#{username}@example.com"
    
    User.create(
      id: SecureRandom.uuid,
      username: username,
      email: email.downcase.strip,
      password_hash: BCrypt::Password.create(password),
      created_at: Time.now,
      updated_at: Time.now
    )
  end

  def create_test_room(user, name: nil)
    name ||= "Room #{SecureRandom.hex(4)}"
    
    room = Room.create(
      id: SecureRandom.uuid,
      name: name,
      administrator_id: user.id,
      is_playing: false,
      created_at: Time.now,
      updated_at: Time.now
    )
    
    room.add_participant(user)
    room
  end

  def create_test_track(user, room)
    Track.create(
      id: SecureRandom.uuid,
      room_id: room.id,
      uploader_id: user.id,
      filename: "track_#{SecureRandom.hex(8)}.mp3",
      original_name: "Test Track #{SecureRandom.hex(4)}.mp3",
      file_path: "/tmp/test_track.mp3",
      duration_seconds: rand(120..300),
      file_size_bytes: rand(1000000..5000000),
      mime_type: 'audio/mpeg',
      vote_score: 0,
      created_at: Time.now,
      updated_at: Time.now
    )
  end
end