#!/usr/bin/env ruby

# Simple unit test for track controller functionality
# Tests the controller methods directly without requiring a running server

require_relative 'config/settings'
require_relative 'config/test_database'
require_relative 'app/models'
require_relative 'app/services/auth_service'
require_relative 'app/services/file_service'
require_relative 'app/controllers/track_controller'

# Mock file data for testing
class MockFileData
  attr_reader :tempfile, :filename, :type, :size
  
  def initialize(filename, content, type)
    @filename = filename
    @type = type
    @tempfile = StringIO.new(content)
    @size = content.length
  end
end

class TrackControllerTest
  def initialize
    puts "🧪 Testing Track Controller (Unit Tests)"
    puts "=" * 50
    
    # Setup test environment
    ENV['APP_ENV'] = 'test'
    
    # Create test user and room
    setup_test_data
  end
  
  def run_tests
    begin
      test_track_upload_validation
      test_track_queue_retrieval
      test_track_voting_logic
      test_track_unvoting_logic
      
      puts "\n✅ All track controller unit tests passed!"
      
    rescue => e
      puts "\n❌ Test failed: #{e.message}"
      puts e.backtrace.join("\n") if ENV['DEBUG']
      exit 1
    end
  end
  
  private
  
  def setup_test_data
    puts "\n🔧 Setting up test data..."
    
    # Create test user
    @test_user = User.new(
      id: 'test-user-id',
      username: 'testuser',
      email: 'test@example.com',
      password_hash: '$2a$12$test_hash'
    )
    
    # Create test room
    @test_room = Room.new(
      id: 'test-room-id',
      name: 'Test Room',
      administrator_id: @test_user.id,
      is_playing: false
    )
    
    # Mock the database interactions
    allow_room_participant_check
    
    # Generate test JWT token
    @test_token = AuthService.generate_jwt(@test_user.id)
    
    puts "✅ Test data setup complete"
  end
  
  def allow_room_participant_check
    # Mock the room participant check
    def @test_room.has_participant?(user)
      true  # Always return true for testing
    end
    
    def @test_room.track_queue
      []  # Return empty queue initially
    end
  end
  
  def test_track_upload_validation
    puts "\n🔍 Testing track upload validation..."
    
    # Test missing file
    result = TrackController.store(@test_room.id, {}, @test_token)
    
    unless result[:status] == 422
      raise "Expected 422 for missing file, got #{result[:status]}"
    end
    
    unless result[:body][:error] == 'Validation failed'
      raise "Expected validation error message"
    end
    
    puts "✅ Track upload validation works correctly"
  end
  
  def test_track_queue_retrieval
    puts "\n🔍 Testing track queue retrieval..."
    
    # Mock Room.[] method
    def Room.[](id)
      return @test_room if id == 'test-room-id'
      nil
    end
    
    # Mock AuthService.validate_jwt
    def AuthService.validate_jwt(token)
      if token == @test_token
        { success: true, user: @test_user }
      else
        { success: false, status: 401, body: { error: 'Invalid token' } }
      end
    end
    
    result = TrackController.index(@test_room.id, @test_token)
    
    unless result[:status] == 200
      raise "Expected 200 for track queue, got #{result[:status]}"
    end
    
    unless result[:body][:tracks].is_a?(Array)
      raise "Expected tracks array in response"
    end
    
    puts "✅ Track queue retrieval works correctly"
  end
  
  def test_track_voting_logic
    puts "\n🔍 Testing track voting logic..."
    
    # Create mock track
    mock_track = Object.new
    def mock_track.id; 'test-track-id'; end
    def mock_track.room; @test_room; end
    def mock_track.votes_dataset
      mock_dataset = Object.new
      def mock_dataset.where(conditions)
        mock_result = Object.new
        def mock_result.first; nil; end  # No existing vote
        mock_result
      end
      mock_dataset
    end
    def mock_track.votes
      mock_votes = Object.new
      def mock_votes.count; 1; end
      mock_votes
    end
    def mock_track.update(data); true; end
    def mock_track.refresh; self; end
    def mock_track.vote_score; 1; end
    
    # Mock Track.[] method
    def Track.[](id)
      return mock_track if id == 'test-track-id'
      nil
    end
    
    # Mock TrackVote.create
    def TrackVote.create(data)
      Object.new
    end
    
    result = TrackController.vote('test-track-id', @test_token)
    
    unless result[:status] == 200
      raise "Expected 200 for voting, got #{result[:status]}"
    end
    
    unless result[:body][:user_has_voted] == true
      raise "Expected user_has_voted to be true"
    end
    
    puts "✅ Track voting logic works correctly"
  end
  
  def test_track_unvoting_logic
    puts "\n🔍 Testing track unvoting logic..."
    
    # Create mock track with existing vote
    mock_track = Object.new
    def mock_track.id; 'test-track-id'; end
    def mock_track.room; @test_room; end
    def mock_track.votes_dataset
      mock_dataset = Object.new
      def mock_dataset.where(conditions)
        mock_result = Object.new
        mock_vote = Object.new
        def mock_vote.destroy; true; end
        def mock_result.first; mock_vote; end  # Existing vote
        mock_result
      end
      mock_dataset
    end
    def mock_track.votes
      mock_votes = Object.new
      def mock_votes.count; 0; end  # After removal
      mock_votes
    end
    def mock_track.update(data); true; end
    def mock_track.refresh; self; end
    def mock_track.vote_score; 0; end
    
    result = TrackController.unvote('test-track-id', @test_token)
    
    unless result[:status] == 200
      raise "Expected 200 for unvoting, got #{result[:status]}"
    end
    
    unless result[:body][:user_has_voted] == false
      raise "Expected user_has_voted to be false"
    end
    
    puts "✅ Track unvoting logic works correctly"
  end
end

# StringIO class for mock file data
class StringIO
  def initialize(string)
    @string = string
    @pos = 0
  end
  
  def read(length = nil)
    if length
      result = @string[@pos, length]
      @pos += length if result
      result
    else
      result = @string[@pos..-1]
      @pos = @string.length
      result
    end
  end
  
  def rewind
    @pos = 0
  end
  
  def size
    @string.length
  end
end

# Run tests if this file is executed directly
if __FILE__ == $0
  # Set up instance variables for the test
  test = TrackControllerTest.new
  
  # Make instance variables accessible to the controller methods
  @test_user = test.instance_variable_get(:@test_user)
  @test_room = test.instance_variable_get(:@test_room)
  @test_token = test.instance_variable_get(:@test_token)
  
  test.run_tests
end