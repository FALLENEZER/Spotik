# Property-Based Test for Synchronized Playback Control
# **Feature: ruby-backend-migration, Property 8: Synchronized Playback Control**
# **Validates: Requirements 5.1, 5.2, 5.3, 5.4**

require 'rspec'
require 'securerandom'
require 'json'
require 'time'

# Mock classes for testing without database
class MockUser
  attr_accessor :id, :username, :email, :password_hash, :created_at, :updated_at
  
  def initialize(attributes = {})
    @id = attributes[:id] || SecureRandom.uuid
    @username = attributes[:username] || "user_#{SecureRandom.hex(4)}"
    @email = attributes[:email] || "#{@username}@example.com"
    @password_hash = attributes[:password_hash] || 'mock_hash'
    @created_at = attributes[:created_at] || Time.now
    @updated_at = attributes[:updated_at] || Time.now
  end
  
  def to_hash
    {
      id: @id,
      username: @username,
      email: @email,
      created_at: @created_at.iso8601,
      updated_at: @updated_at.iso8601
    }
  end
end

class MockTrack
  attr_accessor :id, :room_id, :uploader_id, :filename, :original_name, :duration_seconds, :file_size_bytes, :mime_type, :vote_score, :created_at, :updated_at
  
  def initialize(attributes = {})
    @id = attributes[:id] || SecureRandom.uuid
    @room_id = attributes[:room_id]
    @uploader_id = attributes[:uploader_id]
    @filename = attributes[:filename] || "track_#{SecureRandom.hex(4)}.mp3"
    @original_name = attributes[:original_name] || "Track #{SecureRandom.hex(4)}.mp3"
    @duration_seconds = attributes[:duration_seconds] || rand(60..300)
    @file_size_bytes = attributes[:file_size_bytes] || rand(1000000..10000000)
    @mime_type = attributes[:mime_type] || 'audio/mpeg'
    @vote_score = attributes[:vote_score] || 0
    @created_at = attributes[:created_at] || Time.now
    @updated_at = attributes[:updated_at] || Time.now
  end
  
  def to_hash
    {
      id: @id,
      room_id: @room_id,
      uploader_id: @uploader_id,
      filename: @filename,
      original_name: @original_name,
      duration_seconds: @duration_seconds,
      file_size_bytes: @file_size_bytes,
      mime_type: @mime_type,
      vote_score: @vote_score,
      created_at: @created_at.iso8601,
      updated_at: @updated_at.iso8601
    }
  end
end

class MockRoom
  attr_accessor :id, :name, :administrator_id, :current_track_id, :playback_started_at, :playback_paused_at, :is_playing, :created_at, :updated_at
  
  def initialize(attributes = {})
    @id = attributes[:id] || SecureRandom.uuid
    @name = attributes[:name] || "Room #{SecureRandom.hex(4)}"
    @administrator_id = attributes[:administrator_id]
    @current_track_id = attributes[:current_track_id]
    @playback_started_at = attributes[:playback_started_at]
    @playback_paused_at = attributes[:playback_paused_at]
    @is_playing = attributes[:is_playing] || false
    @created_at = attributes[:created_at] || Time.now
    @updated_at = attributes[:updated_at] || Time.now
    @tracks = attributes[:tracks] || []
    @participants = attributes[:participants] || []
  end
  
  def administered_by?(user)
    @administrator_id == user.id
  end
  
  def has_participant?(user)
    @participants.any? { |p| p.id == user.id } || administered_by?(user)
  end
  
  def current_track
    @tracks.find { |t| t.id == @current_track_id }
  end
  
  def next_track
    return nil if @tracks.empty?
    
    current_index = @tracks.find_index { |t| t.id == @current_track_id }
    return @tracks.first if current_index.nil?
    
    next_index = current_index + 1
    next_index < @tracks.length ? @tracks[next_index] : nil
  end
  
  def tracks
    @tracks
  end
  
  def add_track(track)
    @tracks << track
  end
  
  def add_participant(user)
    @participants << user unless @participants.any? { |p| p.id == user.id }
  end
  
  def administrator
    MockUser.new(id: @administrator_id, username: "admin_#{SecureRandom.hex(4)}")
  end
  
  def update(attributes)
    attributes.each do |key, value|
      instance_variable_set("@#{key}", value)
    end
    @updated_at = Time.now
  end
  
  def refresh
    # Mock refresh - in real implementation this would reload from database
    self
  end
  
  def to_hash
    {
      id: @id,
      name: @name,
      administrator_id: @administrator_id,
      current_track_id: @current_track_id,
      playback_started_at: @playback_started_at&.to_f,
      playback_paused_at: @playback_paused_at&.to_f,
      is_playing: @is_playing,
      created_at: @created_at.iso8601,
      updated_at: @updated_at.iso8601
    }
  end
end

# Mock database models
class Room
  @@rooms = {}
  
  def self.[](id)
    @@rooms[id]
  end
  
  def self.create(attributes)
    room = MockRoom.new(attributes)
    @@rooms[room.id] = room
    room
  end
  
  def self.clear_all
    @@rooms.clear
  end
end

class Track
  @@tracks = {}
  
  def self.[](id)
    @@tracks[id]
  end
  
  def self.create(attributes)
    track = MockTrack.new(attributes)
    @@tracks[track.id] = track
    track
  end
  
  def self.clear_all
    @@tracks.clear
  end
end

class User
  @@users = {}
  
  def self.[](id)
    @@users[id]
  end
  
  def self.create(attributes)
    user = MockUser.new(attributes)
    @@users[user.id] = user
    user
  end
  
  def self.clear_all
    @@users.clear
  end
end

# Mock services - these will be overridden after loading the real classes

class AuthenticationError < StandardError; end

# Mock logger
$logger = Object.new
def $logger.info(msg); end
def $logger.error(msg); end
def $logger.debug(msg); end
def $logger.warn(msg); end

# Load the actual PlaybackController
require_relative '../../app/controllers/playback_controller'

# Override the real AuthService with our mock after it's loaded
class AuthService
  def self.validate_jwt(token)
    # Mock JWT validation - in real implementation this would validate the token
    user_id = token.split('_').last if token.start_with?('valid_token_')
    if user_id && User[user_id]
      { user: User[user_id] }
    else
      raise AuthenticationError.new('Invalid token')
    end
  end
end

# Override the real RoomManager with our mock after it's loaded
class RoomManager
  @@broadcast_log = []
  
  def self.broadcast_to_room(room_id, event_type, data)
    @@broadcast_log << {
      room_id: room_id,
      event_type: event_type,
      data: data,
      timestamp: Time.now.to_f
    }
  end
  
  def self.last_broadcast
    @@broadcast_log.last
  end
  
  def self.clear_broadcast_log
    @@broadcast_log.clear
  end
  
  def self.broadcast_count
    @@broadcast_log.length
  end
end

RSpec.describe "Synchronized Playback Control Property Test" do
  
  before(:all) do
    puts "\n=== Property-Based Test: Synchronized Playback Control ==="
    puts "Testing universal properties of playback control with timestamp synchronization"
    puts "**Validates: Requirements 5.1, 5.2, 5.3, 5.4**"
    puts
  end
  
  before(:each) do
    # Clear all mock data before each test
    Room.clear_all
    Track.clear_all
    User.clear_all
    RoomManager.clear_broadcast_log
  end
  
  # Property 8: Synchronized Playback Control
  # For any playback control action (play, pause, resume, skip) by a room administrator,
  # the system should update the room state and broadcast the change to all participants
  # with accurate timestamps.
  it "maintains synchronized playback state across all control actions" do
    # Run property test with reduced iterations for faster execution
    5.times do |iteration|
      # Clear state for each iteration
      Room.clear_all
      Track.clear_all
      User.clear_all
      RoomManager.clear_broadcast_log
      
      # Generate test data
      admin_user = create_test_user(is_admin: true)
      room = create_test_room(admin_user)
      tracks = create_test_tracks(room, rand(1..3))
      action_sequence = generate_playback_action_sequence
      
      # Execute the sequence of playback actions
      action_sequence.each_with_index do |action, index|
        
        case action[:type]
        when :start
          track = tracks.sample
          result = PlaybackController.start_track(room.id, track.id, "valid_token_#{admin_user.id}")
          
          # Verify playback started correctly (Requirement 5.1)
          expect(result[:status]).to eq(200), "Start track failed on iteration #{iteration}, action #{index}. Result: #{result.inspect}"
          expect(result[:body][:is_playing]).to be true
          expect(result[:body][:track][:id]).to eq(track.id)
          expect(result[:body][:started_at]).to be_within(0.1).of(Time.now.to_f)
          
          # Verify timestamp synchronization and broadcasting
          broadcast = RoomManager.last_broadcast
          expect(broadcast).not_to be_nil
          expect(broadcast[:event_type]).to eq('playback_started')
          expect(broadcast[:data][:started_at]).to be_within(0.01).of(result[:body][:started_at])
          expect(broadcast[:data][:server_time]).to be_within(0.1).of(Time.now.to_f)
          
          # Verify room state updated
          room_state = Room[room.id]
          expect(room_state.is_playing).to be true
          expect(room_state.current_track_id).to eq(track.id)
          
        when :pause
          room_state = Room[room.id]
          next unless room_state && room_state.is_playing
          
          result = PlaybackController.pause_track(room.id, "valid_token_#{admin_user.id}")
          
          # Verify playback paused correctly (Requirement 5.2)
          expect(result[:status]).to eq(200), "Pause track failed on iteration #{iteration}, action #{index}"
          expect(result[:body][:is_playing]).to be false
          expect(result[:body][:paused_at]).to be_within(0.1).of(Time.now.to_f)
          
          # Verify position calculation accuracy
          room_state = Room[room.id]
          expect(room_state.is_playing).to be false
          expect(room_state.playback_paused_at).to be_within(0.1).of(Time.now)
          
          # Verify broadcasting
          broadcast = RoomManager.last_broadcast
          expect(broadcast[:event_type]).to eq('playback_paused')
          expect(broadcast[:data][:position]).to be >= 0
          
        when :resume
          room_state = Room[room.id]
          next unless room_state && !room_state.is_playing && room_state.playback_paused_at
          
          result = PlaybackController.resume_track(room.id, "valid_token_#{admin_user.id}")
          
          # Verify playback resumed correctly (Requirement 5.3)
          expect(result[:status]).to eq(200), "Resume track failed on iteration #{iteration}, action #{index}"
          expect(result[:body][:is_playing]).to be true
          
          # Verify timestamp adjustment for correct position
          room_state = Room[room.id]
          expect(room_state.is_playing).to be true
          expect(room_state.playback_paused_at).to be_nil
          
          # Verify broadcasting
          broadcast = RoomManager.last_broadcast
          expect(broadcast[:event_type]).to eq('playback_resumed')
          expect(broadcast[:data][:position]).to be >= 0
          
        when :skip
          result = PlaybackController.skip_track(room.id, "valid_token_#{admin_user.id}")
          
          # Verify skip behavior
          expect(result[:status]).to eq(200), "Skip track failed on iteration #{iteration}, action #{index}"
          
          # Verify broadcasting - could be either track_skipped or playback_stopped
          broadcast = RoomManager.last_broadcast
          expect(['track_skipped', 'playback_stopped']).to include(broadcast[:event_type])
          
        end
        
        # Verify server-side timestamp calculation (Requirement 5.4)
        if result && result[:status] == 200
          server_time = result[:body][:server_time]
          expect(server_time).to be_within(0.1).of(Time.now.to_f)
          
          # Verify real-time broadcasting occurred
          expect(RoomManager.broadcast_count).to be > 0
          broadcast = RoomManager.last_broadcast
          expect(broadcast[:data][:server_time]).to be_within(0.1).of(server_time)
        end
        
        # Small delay to ensure timestamp differences
        sleep(0.01)
      end
    end
  end
  
  # Property: Playback Position Calculation Accuracy
  # For any playback state, the calculated position should accurately reflect
  # the elapsed time based on server timestamps
  it "calculates playback position accurately using server timestamps" do
    scenarios = [:playing_continuously, :paused_and_resumed, :multiple_pause_resume_cycles]
    
    15.times do |iteration|
      # Clear state for each iteration
      Room.clear_all
      Track.clear_all
      User.clear_all
      RoomManager.clear_broadcast_log
      
      admin_user = create_test_user(is_admin: true)
      room = create_test_room(admin_user)
      track = create_test_track(room)
      
      # Choose random scenario
      scenario = scenarios.sample
      
      case scenario
      when :playing_continuously
        # Start playback and check position after random delay
        start_result = PlaybackController.start_track(room.id, track.id, "valid_token_#{admin_user.id}")
        expect(start_result[:status]).to eq(200)
        
        delay = rand(0.1..2.0)
        sleep(delay)
        
        status_result = PlaybackController.get_playback_status(room.id, "valid_token_#{admin_user.id}")
        expect(status_result[:status]).to eq(200)
        
        expected_position = delay
        actual_position = status_result[:body][:playback_status][:current_position]
        
        expect(actual_position).to be_within(0.2).of(expected_position), 
          "Position calculation failed on iteration #{iteration} (scenario: #{scenario})"
        
      when :paused_and_resumed
        # Start, pause, wait, resume, check position
        start_result = PlaybackController.start_track(room.id, track.id, "valid_token_#{admin_user.id}")
        expect(start_result[:status]).to eq(200)
        
        play_duration = rand(0.1..1.0)
        sleep(play_duration)
        
        pause_result = PlaybackController.pause_track(room.id, "valid_token_#{admin_user.id}")
        expect(pause_result[:status]).to eq(200)
        
        pause_duration = rand(0.1..1.0)
        sleep(pause_duration)
        
        resume_result = PlaybackController.resume_track(room.id, "valid_token_#{admin_user.id}")
        expect(resume_result[:status]).to eq(200)
        
        additional_play_duration = rand(0.1..1.0)
        sleep(additional_play_duration)
        
        status_result = PlaybackController.get_playback_status(room.id, "valid_token_#{admin_user.id}")
        expect(status_result[:status]).to eq(200)
        
        expected_position = play_duration + additional_play_duration
        actual_position = status_result[:body][:playback_status][:current_position]
        
        expect(actual_position).to be_within(0.3).of(expected_position),
          "Position calculation failed on iteration #{iteration} (scenario: #{scenario})"
        
      when :multiple_pause_resume_cycles
        # Multiple pause/resume cycles
        start_result = PlaybackController.start_track(room.id, track.id, "valid_token_#{admin_user.id}")
        expect(start_result[:status]).to eq(200)
        
        total_play_time = 0
        cycles = rand(2..4)
        
        cycles.times do
          play_duration = rand(0.1..0.5)
          sleep(play_duration)
          total_play_time += play_duration
          
          pause_result = PlaybackController.pause_track(room.id, "valid_token_#{admin_user.id}")
          expect(pause_result[:status]).to eq(200)
          
          pause_duration = rand(0.1..0.3)
          sleep(pause_duration)
          
          resume_result = PlaybackController.resume_track(room.id, "valid_token_#{admin_user.id}")
          expect(resume_result[:status]).to eq(200)
        end
        
        final_play_duration = rand(0.1..0.5)
        sleep(final_play_duration)
        total_play_time += final_play_duration
        
        status_result = PlaybackController.get_playback_status(room.id, "valid_token_#{admin_user.id}")
        expect(status_result[:status]).to eq(200)
        
        actual_position = status_result[:body][:playback_status][:current_position]
        
        expect(actual_position).to be_within(0.4).of(total_play_time),
          "Position calculation failed on iteration #{iteration} (scenario: #{scenario})"
      end
    end
  end
  
  # Property: Administrator-Only Control Access
  # For any playback control action, only room administrators should be able
  # to execute the action successfully
  it "restricts playback control to room administrators only" do
    actions = [:start, :pause, :resume, :skip, :stop]
    
    15.times do |iteration|
      # Clear state for each iteration
      Room.clear_all
      Track.clear_all
      User.clear_all
      RoomManager.clear_broadcast_log
      
      admin_user = create_test_user(is_admin: true)
      regular_user = create_test_user(is_admin: false)
      room = create_test_room(admin_user)
      track = create_test_track(room)
      action = actions.sample
      
      # Setup room state for different actions
      case action
      when :pause, :resume, :skip
        # Start playback first so we can test pause/resume/skip
        PlaybackController.start_track(room.id, track.id, "valid_token_#{admin_user.id}")
        if action == :resume
          PlaybackController.pause_track(room.id, "valid_token_#{admin_user.id}")
        end
      end
      
      # Regular user should be denied access
      user_result = execute_playback_action(action, room, track, regular_user)
      expect(user_result[:status]).to eq(403), 
        "Regular user should be denied access on iteration #{iteration} (action: #{action})"
      expect(user_result[:body][:error]).to include('administrator')
      
      # Admin should be able to control playback (reset state first if needed)
      if action == :pause
        # Ensure we're playing
        PlaybackController.start_track(room.id, track.id, "valid_token_#{admin_user.id}")
      elsif action == :resume
        # Ensure we're paused
        PlaybackController.start_track(room.id, track.id, "valid_token_#{admin_user.id}")
        PlaybackController.pause_track(room.id, "valid_token_#{admin_user.id}")
      end
      
      admin_result = execute_playback_action(action, room, track, admin_user)
      expect(admin_result[:status]).to eq(200),
        "Admin should be able to control playback on iteration #{iteration} (action: #{action})"
    end
  end
  
  private
  
  # Test data generators
  def create_test_user(is_admin: false)
    user = User.create({
      username: "user_#{SecureRandom.hex(4)}",
      email: "user_#{SecureRandom.hex(4)}@example.com"
    })
    user
  end
  
  def create_test_room(admin_user)
    room = Room.create({
      name: "Room #{SecureRandom.hex(4)}",
      administrator_id: admin_user.id
    })
    room.add_participant(admin_user)
    room
  end
  
  def create_test_track(room)
    track = Track.create({
      room_id: room.id,
      uploader_id: room.administrator_id,
      original_name: "Track #{SecureRandom.hex(4)}.mp3",
      duration_seconds: rand(60..300)
    })
    room.add_track(track)
    track
  end
  
  def create_test_tracks(room, count)
    count.times.map { create_test_track(room) }
  end
  
  def generate_playback_action_sequence
    actions = []
    
    # Always start with a start action
    actions << { type: :start }
    
    # Add random sequence of other actions
    rand(2..6).times do
      actions << { type: [:pause, :resume, :skip].sample }
    end
    
    actions
  end
  
  def execute_playback_action(action, room, track, user)
    token = "valid_token_#{user.id}"
    
    case action
    when :start
      PlaybackController.start_track(room.id, track.id, token)
    when :pause
      PlaybackController.pause_track(room.id, token)
    when :resume
      PlaybackController.resume_track(room.id, token)
    when :skip
      PlaybackController.skip_track(room.id, token)
    when :stop
      PlaybackController.stop_playback(room.id, token)
    else
      { status: 400, body: { error: 'Unknown action' } }
    end
  end
end