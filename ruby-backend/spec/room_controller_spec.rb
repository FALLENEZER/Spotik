require 'bundler/setup'
require 'rspec'
require 'json'
require 'securerandom'

# Set test environment
ENV['APP_ENV'] = 'test'

# Mock the database models for testing
class MockUser
  attr_accessor :id, :username, :email
  
  def initialize(id: nil, username: nil, email: nil)
    @id = id || SecureRandom.uuid
    @username = username
    @email = email
  end
end

class MockRoom
  attr_accessor :id, :name, :administrator_id, :participants
  
  def initialize(id: nil, name: nil, administrator_id: nil)
    @id = id || SecureRandom.uuid
    @name = name
    @administrator_id = administrator_id
    @participants = []
  end
  
  def has_participant?(user)
    @participants.any? { |p| p.id == user.id }
  end
  
  def add_participant(user)
    @participants << user unless has_participant?(user)
  end
  
  def remove_participant(user)
    initial_count = @participants.length
    @participants.reject! { |p| p.id == user.id }
    @participants.length < initial_count
  end
  
  def administered_by?(user)
    @administrator_id == user.id
  end
  
  def refresh
    # Mock refresh method
    self
  end
  
  def track_queue
    []  # Mock empty track queue
  end
  
  def is_playing
    false
  end
  
  def current_track
    nil
  end
  
  def tracks
    MockTrackCollection.new
  end
  
  def to_hash
    {
      id: @id,
      name: @name,
      administrator_id: @administrator_id,
      administrator: nil,
      current_track_id: nil,
      current_track: nil,
      playback_started_at: nil,
      playback_paused_at: nil,
      is_playing: false,
      participants: @participants.map { |p| { id: p.id, username: p.username } },
      track_count: 0,
      participant_count: @participants.length,
      created_at: Time.now.iso8601,
      updated_at: Time.now.iso8601,
      track_queue: []
    }
  end
end

class MockTrackCollection
  def count
    0
  end
end

# Mock the dependencies
class MockLogger
  def info(msg); end
  def warn(msg); end
  def error(msg); end
  def debug(msg); end
end

$logger = MockLogger.new

# Mock SpotikConfig
module SpotikConfig
  class Settings
    def self.app_debug?
      false
    end
  end
end

# Mock AuthService for testing
class MockAuthService
  def self.validate_jwt(token)
    return { success: false, status: 401, body: { error: 'Authentication required' } } if token.nil?
    return { success: false, status: 401, body: { error: 'Invalid or expired token' } } if token == 'invalid.jwt.token'
    
    # Return different users based on token
    if token == 'valid.jwt.token.other'
      user = MockUser.new(id: 'other-user-id', username: 'otheruser', email: 'other@test.com')
    else
      user = MockUser.new(id: 'test-user-id', username: 'testuser', email: 'test@example.com')
    end
    
    { success: true, user: user }
  end
  
  def self.generate_jwt(user_id)
    "valid.jwt.token.for.#{user_id}"
  end
end

# Mock Sequel for validation errors
module Sequel
  class ValidationFailed < StandardError
    attr_reader :errors
    
    def initialize(errors)
      @errors = errors
      super("Validation failed")
    end
  end
end

# Mock Room model
class MockRoomModel
  @@rooms = {}
  
  def self.create(attributes)
    # Validate required fields
    if attributes[:name].nil? || attributes[:name].strip.empty?
      raise Sequel::ValidationFailed.new({ name: ['is not present'] })
    end
    
    if attributes[:name].length > 100
      raise Sequel::ValidationFailed.new({ name: ['is longer than 100 characters'] })
    end
    
    room = MockRoom.new(
      name: attributes[:name],
      administrator_id: attributes[:administrator_id]
    )
    @@rooms[room.id] = room
    room
  end
  
  def self.[](id)
    @@rooms[id]
  end
  
  def self.all
    @@rooms.values
  end
  
  def self.clear_all
    @@rooms.clear
  end
end

# Load the controller with mocked dependencies
require 'json'
require 'securerandom'

# Mock the dependencies
AuthService = MockAuthService
Room = MockRoomModel

require_relative '../app/controllers/room_controller'

RSpec.describe RoomController do
  let(:test_user) { MockUser.new(id: 'test-user-id', username: 'testuser', email: 'test@example.com') }
  let(:valid_token) { 'valid.jwt.token' }
  let(:invalid_token) { 'invalid.jwt.token' }
  
  before(:each) do
    MockRoomModel.clear_all
  end
  
  describe '.index' do
    context 'without authentication' do
      it 'returns list of rooms' do
        # Create a test room
        room = MockRoomModel.create(
          name: 'Test Room',
          administrator_id: test_user.id
        )
        
        result = RoomController.index
        
        expect(result[:status]).to eq(200)
        expect(result[:body][:rooms]).to be_an(Array)
        expect(result[:body][:total]).to be >= 1
      end
    end
    
    context 'with valid authentication' do
      it 'returns list of rooms with user-specific information' do
        room = MockRoomModel.create(
          name: 'Test Room',
          administrator_id: test_user.id
        )
        room.add_participant(test_user)
        
        result = RoomController.index(valid_token)
        
        expect(result[:status]).to eq(200)
        expect(result[:body][:rooms]).to be_an(Array)
        
        room_data = result[:body][:rooms].find { |r| r[:id] == room.id }
        expect(room_data[:is_user_participant]).to be true
        expect(room_data[:is_user_administrator]).to be true
      end
    end
  end
  
  describe '.create' do
    context 'with valid parameters' do
      let(:valid_params) { { 'name' => 'New Test Room' } }
      
      it 'creates a new room' do
        result = RoomController.create(valid_params, valid_token)
        
        expect(result[:status]).to eq(201)
        expect(result[:body][:room][:name]).to eq('New Test Room')
        expect(result[:body][:room][:administrator_id]).to eq(test_user.id)
        expect(result[:body][:message]).to eq('Room created successfully')
      end
      
      it 'adds creator as participant' do
        result = RoomController.create(valid_params, valid_token)
        
        room_id = result[:body][:room][:id]
        room = MockRoomModel[room_id]
        
        expect(room.has_participant?(test_user)).to be true
      end
    end
    
    context 'with invalid parameters' do
      it 'returns validation error for missing name' do
        result = RoomController.create({}, valid_token)
        
        expect(result[:status]).to eq(422)
        expect(result[:body][:error]).to eq('Validation failed')
        expect(result[:body][:errors][:name]).to include('The name field is required.')
      end
      
      it 'returns validation error for empty name' do
        result = RoomController.create({ 'name' => '   ' }, valid_token)
        
        expect(result[:status]).to eq(422)
        expect(result[:body][:error]).to eq('Validation failed')
        expect(result[:body][:errors][:name]).to include('The name field is required.')
      end
      
      it 'returns validation error for name too long' do
        long_name = 'a' * 101
        result = RoomController.create({ 'name' => long_name }, valid_token)
        
        expect(result[:status]).to eq(422)
        expect(result[:body][:error]).to eq('Validation failed')
        expect(result[:body][:errors][:name]).to include('The name may not be greater than 100 characters.')
      end
    end
    
    context 'without authentication' do
      it 'returns authentication error' do
        result = RoomController.create({ 'name' => 'Test Room' }, nil)
        
        expect(result[:status]).to eq(401)
        expect(result[:body][:error]).to eq('Authentication required')
      end
    end
    
    context 'with invalid token' do
      it 'returns authentication error' do
        result = RoomController.create({ 'name' => 'Test Room' }, invalid_token)
        
        expect(result[:status]).to eq(401)
        expect(result[:body][:error]).to eq('Invalid or expired token')
      end
    end
  end
  
  describe '.show' do
    let(:room) { MockRoomModel.create(name: 'Test Room', administrator_id: test_user.id) }
    
    context 'with existing room' do
      it 'returns room details' do
        result = RoomController.show(room.id)
        
        expect(result[:status]).to eq(200)
        expect(result[:body][:room][:id]).to eq(room.id)
        expect(result[:body][:room][:name]).to eq('Test Room')
      end
    end
    
    context 'with non-existent room' do
      it 'returns not found error' do
        result = RoomController.show('non-existent-id')
        
        expect(result[:status]).to eq(404)
        expect(result[:body][:error]).to eq('Room not found')
      end
    end
    
    context 'with authentication' do
      before { room.add_participant(test_user) }
      
      it 'includes user-specific information' do
        result = RoomController.show(room.id, valid_token)
        
        expect(result[:body][:room][:is_user_participant]).to be true
        expect(result[:body][:room][:is_user_administrator]).to be true
      end
    end
  end
  
  describe '.join' do
    let(:room) { MockRoomModel.create(name: 'Test Room', administrator_id: test_user.id) }
    let(:other_user) { MockUser.new(id: 'other-user-id', username: 'otheruser', email: 'other@test.com') }
    let(:other_token) { 'valid.jwt.token.other' }
    
    context 'with valid room and user' do
      it 'adds user to room participants' do
        result = RoomController.join(room.id, other_token)
        
        expect(result[:status]).to eq(200)
        expect(result[:body][:message]).to eq('Successfully joined room')
        expect(room.has_participant?(other_user)).to be true
      end
    end
    
    context 'when user is already a participant' do
      before { room.add_participant(other_user) }
      
      it 'returns conflict error' do
        result = RoomController.join(room.id, other_token)
        
        expect(result[:status]).to eq(409)
        expect(result[:body][:error]).to eq('Already a participant')
      end
    end
    
    context 'with non-existent room' do
      it 'returns not found error' do
        result = RoomController.join('non-existent-id', other_token)
        
        expect(result[:status]).to eq(404)
        expect(result[:body][:error]).to eq('Room not found')
      end
    end
    
    context 'without authentication' do
      it 'returns authentication error' do
        result = RoomController.join(room.id, nil)
        
        expect(result[:status]).to eq(401)
        expect(result[:body][:error]).to eq('Authentication required')
      end
    end
  end
  
  describe '.leave' do
    let(:room) { MockRoomModel.create(name: 'Test Room', administrator_id: test_user.id) }
    let(:other_user) { MockUser.new(id: 'other-user-id', username: 'otheruser', email: 'other@test.com') }
    let(:other_token) { 'valid.jwt.token.other' }
    
    context 'when user is a regular participant' do
      before { room.add_participant(other_user) }
      
      it 'removes user from room participants' do
        result = RoomController.leave(room.id, other_token)
        
        expect(result[:status]).to eq(200)
        expect(result[:body][:message]).to eq('Successfully left room')
        expect(room.has_participant?(other_user)).to be false
      end
    end
    
    context 'when user is the administrator' do
      before { room.add_participant(test_user) }
      
      it 'prevents administrator from leaving' do
        result = RoomController.leave(room.id, valid_token)
        
        expect(result[:status]).to eq(403)
        expect(result[:body][:error]).to eq('Administrator cannot leave')
      end
    end
    
    context 'when user is not a participant' do
      it 'returns conflict error' do
        result = RoomController.leave(room.id, other_token)
        
        expect(result[:status]).to eq(409)
        expect(result[:body][:error]).to eq('Not a participant')
      end
    end
    
    context 'with non-existent room' do
      it 'returns not found error' do
        result = RoomController.leave('non-existent-id', other_token)
        
        expect(result[:status]).to eq(404)
        expect(result[:body][:error]).to eq('Room not found')
      end
    end
  end
end