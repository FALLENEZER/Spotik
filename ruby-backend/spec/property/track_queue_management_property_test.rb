# Property-based test for track queue management
# **Feature: ruby-backend-migration, Property 7: Track Queue Management**
# **Validates: Requirements 4.3, 6.3**

require 'bundler/setup'
require 'rspec'
require 'rantly'
require 'rantly/rspec_extensions'
require 'securerandom'
require 'json'
require 'tempfile'

# Set test environment
ENV['APP_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test_jwt_secret_key_for_testing_purposes_only'
ENV['JWT_TTL'] = '60' # 1 hour for testing

RSpec.describe 'Track Queue Management Property Test', :property do
  before(:all) do
    # Load configuration
    require_relative '../../config/settings'
    
    # Load test database configuration
    require_relative '../../config/test_database'
    
    # Override the DB constant for testing
    Object.send(:remove_const, :DB) if defined?(DB)
    DB = SpotikConfig::TestDatabase.connection
    
    # Load models and services with test database
    require_relative '../../app/models/user'
    require_relative '../../app/models/room'
    require_relative '../../app/models/room_participant'
    require_relative '../../app/models/track'
    require_relative '../../app/models/track_vote'
    require_relative '../../app/controllers/track_controller'
    require_relative '../../app/services/room_manager'
    require_relative '../../app/services/auth_service'
    require_relative '../../app/services/file_service'
    
    # Stub WebSocketConnection for testing
    class WebSocketConnection
      @@broadcasted_events = []
      
      def self.send_to_user(user_id, message)
        # Stub implementation for testing
        true
      end
      
      def self.broadcast_to_room(room_id, message)
        # Capture broadcasted events for testing
        @@broadcasted_events << {
          room_id: room_id,
          message: message,
          timestamp: Time.now.to_f
        }
        true
      end
      
      def self.get_user_connection(user_id)
        # Stub implementation for testing - return nil (no connection)
        nil
      end
      
      def self.get_broadcasted_events
        @@broadcasted_events
      end
      
      def self.clear_broadcasted_events
        @@broadcasted_events.clear
      end
    end
    
    # Stub RoomManager broadcasting to capture events
    class RoomManager
      @@broadcasted_events = []
      
      def self.broadcast_to_room(room_id, event_type, data = {})
        @@broadcasted_events << {
          room_id: room_id,
          event_type: event_type,
          data: data,
          timestamp: Time.now.to_f
        }
        true
      end
      
      def self.get_broadcasted_events
        @@broadcasted_events
      end
      
      def self.clear_broadcasted_events
        @@broadcasted_events.clear
      end
    end
    
    # Mock FileService to avoid actual file operations
    class FileService
      def self.save_uploaded_file(file_data, user_id, room_id)
        {
          success: true,
          file_info: {
            filename: 'test_track_' + SecureRandom.hex(8) + '.mp3',
            original_name: file_data[:filename] || 'test_track.mp3',
            file_path: '/tmp/test_track.mp3',
            duration_seconds: rand(60..300), # Random duration between 1-5 minutes
            file_size_bytes: rand(1_000_000..10_000_000), # Random size 1-10MB
            mime_type: 'audio/mpeg'
          }
        }
      end
      
      def self.validate_audio_file(file_data)
        {
          valid: true,
          errors: [],
          file_info: {
            content_type: file_data[:type] || 'audio/mpeg',
            filename: file_data[:filename] || 'test.mp3',
            file_size: rand(1_000_000..10_000_000)
          }
        }
      end
    end
    
    # Stub logger for testing
    $logger = Class.new do
      def self.info(msg); end
      def self.error(msg); end
      def self.debug(msg); end
      def self.warn(msg); end
    end
    
    # Finalize associations
    Sequel::Model.finalize_associations
  end
  
  before(:each) do
    # Clean database before each test
    DB[:track_votes].delete
    DB[:tracks].delete
    DB[:room_participants].delete
    DB[:rooms].delete
    DB[:users].delete
    
    # Clear broadcasted events
    WebSocketConnection.clear_broadcasted_events
    RoomManager.clear_broadcasted_events
  end

  describe 'Property 7: Track Queue Management' do
    it 'adds any successfully uploaded track to the room queue and maintains proper ordering' do
      test_instance = self
      
      property_of {
        # Generate test scenario with room and multiple tracks
        room_data = test_instance.generate_room_data
        users_data = test_instance.generate_multiple_users(rand(2..5))
        tracks_data = test_instance.generate_multiple_tracks(rand(3..8))
        [room_data, users_data, tracks_data]
      }.check(100) { |room_data, users_data, tracks_data|
        # Create users
        users = users_data.map { |user_data| create_test_user(user_data) }
        admin_user = users.first
        
        # Create room
        room = create_test_room(room_data, admin_user)
        
        # Add all users as participants
        users[1..-1].each { |user| room.add_participant(user) }
        
        # Track the expected queue state
        expected_tracks = []
        
        # Upload tracks one by one and verify queue management
        tracks_data.each_with_index do |track_data, index|
          uploader = users.sample
          token = AuthService.generate_jwt(uploader)
          
          # Clear previous events
          RoomManager.clear_broadcasted_events
          
          # Create mock file data
          mock_file_data = {
            audio_file: {
              filename: track_data[:filename],
              tempfile: StringIO.new('mock audio data'),
              type: 'audio/mpeg'
            }
          }
          
          # Upload track
          result = TrackController.store(room.id, mock_file_data, token)
          
          # **Validates: Requirements 4.3** - Track should be added to queue
          expect(result[:status]).to eq(201)
          expect(result[:body][:track]).to have_key(:id)
          
          track_id = result[:body][:track][:id]
          track = Track[track_id]
          expect(track).not_to be_nil
          expect(track.room_id).to eq(room.id)
          expect(track.uploader_id).to eq(uploader.id)
          
          # Add to expected tracks with initial vote score of 0
          expected_tracks << {
            id: track_id,
            vote_score: 0,
            created_at: track.created_at,
            uploader_id: uploader.id
          }
          
          # Verify track_added event was broadcasted
          events = RoomManager.get_broadcasted_events
          track_added_event = events.find { |e| e[:event_type] == 'track_added' }
          expect(track_added_event).not_to be_nil
          expect(track_added_event[:data][:track][:id]).to eq(track_id)
          expect(track_added_event[:data][:room_id]).to eq(room.id)
          
          # Verify queue ordering after each addition
          room.refresh
          actual_queue = room.track_queue.to_a
          
          # **Validates: Requirements 6.3** - Queue should be ordered by vote score (desc) then upload time (asc)
          expected_order = expected_tracks.sort do |a, b|
            if a[:vote_score] == b[:vote_score]
              a[:created_at] <=> b[:created_at]
            else
              b[:vote_score] <=> a[:vote_score]
            end
          end
          
          expect(actual_queue.length).to eq(expected_tracks.length)
          actual_queue.each_with_index do |track, pos|
            expected_track = expected_order[pos]
            expect(track.id).to eq(expected_track[:id])
            expect(track.vote_score).to eq(expected_track[:vote_score])
          end
        end
        
        # Verify final queue state
        room.refresh
        final_queue = room.track_queue.to_a
        expect(final_queue.length).to eq(tracks_data.length)
        
        # All tracks should have vote_score of 0 initially, so order should be by created_at (upload time)
        final_queue.each_cons(2) do |track1, track2|
          if track1.vote_score == track2.vote_score
            expect(track1.created_at).to be <= track2.created_at
          else
            expect(track1.vote_score).to be >= track2.vote_score
          end
        end
      }
    end

    it 'maintains correct queue ordering when votes are added or removed' do
      test_instance = self
      
      property_of {
        # Generate scenario with tracks and voting operations
        room_data = test_instance.generate_room_data
        users_data = test_instance.generate_multiple_users(rand(3..6))
        tracks_count = rand(4..7)
        voting_operations = test_instance.generate_voting_operations(tracks_count, users_data.length, rand(5..15))
        [room_data, users_data, tracks_count, voting_operations]
      }.check(50) { |room_data, users_data, tracks_count, voting_operations|
        # Create users and room
        users = users_data.map { |user_data| create_test_user(user_data) }
        admin_user = users.first
        room = create_test_room(room_data, admin_user)
        
        # Add all users as participants
        users[1..-1].each { |user| room.add_participant(user) }
        
        # Create tracks with staggered upload times
        tracks = []
        tracks_count.times do |i|
          uploader = users.sample
          track = Track.create(
            id: SecureRandom.uuid,
            room_id: room.id,
            uploader_id: uploader.id,
            filename: "test_track_#{i}.mp3",
            original_name: "Test Track #{i}",
            file_path: "/tmp/test_track_#{i}.mp3",
            duration_seconds: rand(60..300),
            file_size_bytes: rand(1_000_000..10_000_000),
            mime_type: 'audio/mpeg',
            vote_score: 0,
            created_at: Time.now + i, # Stagger creation times
            updated_at: Time.now + i
          )
          tracks << track
          sleep(0.001) # Ensure different timestamps
        end
        
        # Track expected vote scores
        expected_votes = Hash.new(0)
        user_votes = Hash.new { |h, k| h[k] = Set.new }
        
        # Execute voting operations
        voting_operations.each do |operation|
          track_index = operation[:track_index] % tracks.length
          user_index = operation[:user_index] % users.length
          action = operation[:action]
          
          track = tracks[track_index]
          user = users[user_index]
          token = AuthService.generate_jwt(user)
          
          # Clear previous events
          RoomManager.clear_broadcasted_events
          
          case action
          when :vote
            if !user_votes[user.id].include?(track.id)
              # Vote for track
              result = TrackController.vote(track.id, token)
              
              if result[:status] == 200 && result[:body][:message] == 'Vote added successfully'
                expected_votes[track.id] += 1
                user_votes[user.id].add(track.id)
                
                # Verify track_voted event was broadcasted
                events = RoomManager.get_broadcasted_events
                track_voted_event = events.find { |e| e[:event_type] == 'track_voted' }
                expect(track_voted_event).not_to be_nil
                expect(track_voted_event[:data][:track][:id]).to eq(track.id)
                expect(track_voted_event[:data][:new_vote_score]).to eq(expected_votes[track.id])
              end
            end
            
          when :unvote
            if user_votes[user.id].include?(track.id)
              # Remove vote from track
              result = TrackController.unvote(track.id, token)
              
              if result[:status] == 200 && result[:body][:message] == 'Vote removed successfully'
                expected_votes[track.id] -= 1
                user_votes[user.id].delete(track.id)
                
                # Verify track_unvoted event was broadcasted
                events = RoomManager.get_broadcasted_events
                track_unvoted_event = events.find { |e| e[:event_type] == 'track_unvoted' }
                expect(track_unvoted_event).not_to be_nil
                expect(track_unvoted_event[:data][:track][:id]).to eq(track.id)
                expect(track_unvoted_event[:data][:new_vote_score]).to eq(expected_votes[track.id])
              end
            end
          end
          
          # Verify queue ordering after each vote operation
          room.refresh
          actual_queue = room.track_queue.to_a
          
          # **Validates: Requirements 6.3** - Queue should be ordered by vote score (desc) then upload time (asc)
          actual_queue.each_cons(2) do |track1, track2|
            if track1.vote_score == track2.vote_score
              expect(track1.created_at).to be <= track2.created_at
            else
              expect(track1.vote_score).to be >= track2.vote_score
            end
          end
          
          # Verify vote scores match expected values
          actual_queue.each do |track|
            expect(track.vote_score).to eq(expected_votes[track.id])
          end
        end
        
        # Final verification of queue ordering
        room.refresh
        final_queue = room.track_queue.to_a
        
        # Verify the queue is properly ordered
        final_queue.each_cons(2) do |track1, track2|
          if track1.vote_score == track2.vote_score
            # Same vote score - should be ordered by creation time (upload time)
            expect(track1.created_at).to be <= track2.created_at
          else
            # Different vote scores - higher score should come first
            expect(track1.vote_score).to be >= track2.vote_score
          end
        end
        
        # Verify vote scores are accurate
        final_queue.each do |track|
          actual_vote_count = track.votes.count
          expect(track.vote_score).to eq(actual_vote_count)
          expect(track.vote_score).to eq(expected_votes[track.id])
        end
      }
    end

    it 'broadcasts real-time queue updates when tracks are added or votes change' do
      test_instance = self
      
      property_of {
        # Generate scenario for testing real-time updates
        room_data = test_instance.generate_room_data
        users_data = test_instance.generate_multiple_users(rand(2..4))
        operations_count = rand(3..8)
        [room_data, users_data, operations_count]
      }.check(50) { |room_data, users_data, operations_count|
        # Create users and room
        users = users_data.map { |user_data| create_test_user(user_data) }
        admin_user = users.first
        room = create_test_room(room_data, admin_user)
        
        # Add all users as participants
        users[1..-1].each { |user| room.add_participant(user) }
        
        tracks = []
        
        operations_count.times do |i|
          uploader = users.sample
          token = AuthService.generate_jwt(uploader)
          
          # Clear previous events
          RoomManager.clear_broadcasted_events
          
          # Create mock file data
          mock_file_data = {
            audio_file: {
              filename: "test_track_#{i}.mp3",
              tempfile: StringIO.new('mock audio data'),
              type: 'audio/mpeg'
            }
          }
          
          # Upload track
          result = TrackController.store(room.id, mock_file_data, token)
          expect(result[:status]).to eq(201)
          
          track_id = result[:body][:track][:id]
          tracks << Track[track_id]
          
          # Verify track_added event was broadcasted
          events = RoomManager.get_broadcasted_events
          track_added_event = events.find { |e| e[:event_type] == 'track_added' }
          
          expect(track_added_event).not_to be_nil
          expect(track_added_event[:room_id]).to eq(room.id)
          expect(track_added_event[:data][:track][:id]).to eq(track_id)
          expect(track_added_event[:data][:uploader][:id]).to eq(uploader.id)
          expect(track_added_event[:data]).to have_key(:queue_position)
          expect(track_added_event[:data]).to have_key(:total_tracks)
          expect(track_added_event[:data]).to have_key(:updated_queue)
          
          # Verify queue information in the event
          expect(track_added_event[:data][:total_tracks]).to eq(i + 1)
          expect(track_added_event[:data][:updated_queue]).to be_an(Array)
          expect(track_added_event[:data][:updated_queue].length).to eq(i + 1)
        end
        
        # Test voting events
        if tracks.length > 0
          voter = users.sample
          track_to_vote = tracks.sample
          token = AuthService.generate_jwt(voter)
          
          # Clear previous events
          RoomManager.clear_broadcasted_events
          
          # Vote for track
          vote_result = TrackController.vote(track_to_vote.id, token)
          
          if vote_result[:status] == 200 && vote_result[:body][:message] == 'Vote added successfully'
            # Verify track_voted event was broadcasted
            events = RoomManager.get_broadcasted_events
            track_voted_event = events.find { |e| e[:event_type] == 'track_voted' }
            
            expect(track_voted_event).not_to be_nil
            expect(track_voted_event[:room_id]).to eq(room.id)
            expect(track_voted_event[:data][:track][:id]).to eq(track_to_vote.id)
            expect(track_voted_event[:data][:voter][:id]).to eq(voter.id)
            expect(track_voted_event[:data]).to have_key(:new_vote_score)
            expect(track_voted_event[:data]).to have_key(:updated_queue)
            
            # Verify updated queue reflects new ordering
            updated_queue = track_voted_event[:data][:updated_queue]
            expect(updated_queue).to be_an(Array)
            expect(updated_queue.length).to eq(tracks.length)
            
            # Check if queue_reordered event was also broadcasted (if order changed)
            queue_reordered_event = events.find { |e| e[:event_type] == 'queue_reordered' }
            if queue_reordered_event
              expect(queue_reordered_event[:room_id]).to eq(room.id)
              expect(queue_reordered_event[:data]).to have_key(:updated_queue)
              expect(queue_reordered_event[:data]).to have_key(:reorder_reason)
              expect(queue_reordered_event[:data][:reorder_reason]).to eq('vote_added')
            end
          end
        end
      }
    end

    it 'handles concurrent track uploads and maintains queue consistency' do
      test_instance = self
      
      property_of {
        # Generate scenario for concurrent operations
        room_data = test_instance.generate_room_data
        users_data = test_instance.generate_multiple_users(rand(3..5))
        concurrent_tracks = rand(3..6)
        [room_data, users_data, concurrent_tracks]
      }.check(30) { |room_data, users_data, concurrent_tracks|
        # Create users and room
        users = users_data.map { |user_data| create_test_user(user_data) }
        admin_user = users.first
        room = create_test_room(room_data, admin_user)
        
        # Add all users as participants
        users[1..-1].each { |user| room.add_participant(user) }
        
        # Simulate concurrent track uploads
        uploaded_tracks = []
        
        concurrent_tracks.times do |i|
          uploader = users.sample
          token = AuthService.generate_jwt(uploader)
          
          # Create mock file data
          mock_file_data = {
            audio_file: {
              filename: "concurrent_track_#{i}.mp3",
              tempfile: StringIO.new('mock audio data'),
              type: 'audio/mpeg'
            }
          }
          
          # Upload track
          result = TrackController.store(room.id, mock_file_data, token)
          expect(result[:status]).to eq(201)
          
          track_id = result[:body][:track][:id]
          uploaded_tracks << track_id
        end
        
        # Verify all tracks were added to the queue
        room.refresh
        actual_queue = room.track_queue.to_a
        
        expect(actual_queue.length).to eq(concurrent_tracks)
        
        # Verify all uploaded tracks are in the queue
        queue_track_ids = actual_queue.map(&:id)
        uploaded_tracks.each do |track_id|
          expect(queue_track_ids).to include(track_id)
        end
        
        # **Validates: Requirements 6.3** - Queue should be properly ordered
        actual_queue.each_cons(2) do |track1, track2|
          if track1.vote_score == track2.vote_score
            expect(track1.created_at).to be <= track2.created_at
          else
            expect(track1.vote_score).to be >= track2.vote_score
          end
        end
        
        # Verify queue positions are sequential
        queue_with_positions = room.track_queue_with_positions
        queue_with_positions.each_with_index do |track_data, index|
          expect(track_data[:queue_position]).to eq(index + 1)
        end
      }
    end

    it 'maintains queue integrity when tracks have identical vote scores' do
      test_instance = self
      
      property_of {
        # Generate scenario with tracks that will have same vote scores
        room_data = test_instance.generate_room_data
        users_data = test_instance.generate_multiple_users(rand(2..4))
        tracks_count = rand(4..8)
        [room_data, users_data, tracks_count]
      }.check(30) { |room_data, users_data, tracks_count|
        # Create users and room
        users = users_data.map { |user_data| create_test_user(user_data) }
        admin_user = users.first
        room = create_test_room(room_data, admin_user)
        
        # Add all users as participants
        users[1..-1].each { |user| room.add_participant(user) }
        
        # Create tracks with different upload times but same vote scores
        tracks = []
        base_time = Time.now
        
        tracks_count.times do |i|
          uploader = users.sample
          track = Track.create(
            id: SecureRandom.uuid,
            room_id: room.id,
            uploader_id: uploader.id,
            filename: "identical_score_track_#{i}.mp3",
            original_name: "Track #{i}",
            file_path: "/tmp/track_#{i}.mp3",
            duration_seconds: rand(60..300),
            file_size_bytes: rand(1_000_000..10_000_000),
            mime_type: 'audio/mpeg',
            vote_score: 0, # All tracks start with same vote score
            created_at: base_time + i * 10, # Different upload times
            updated_at: base_time + i * 10
          )
          tracks << track
        end
        
        # Verify initial ordering by upload time (created_at)
        room.refresh
        initial_queue = room.track_queue.to_a
        
        expect(initial_queue.length).to eq(tracks_count)
        
        # **Validates: Requirements 6.3** - With same vote scores, should be ordered by upload time
        initial_queue.each_cons(2) do |track1, track2|
          expect(track1.vote_score).to eq(track2.vote_score) # Same vote score
          expect(track1.created_at).to be <= track2.created_at # Ordered by upload time
        end
        
        # Give some tracks the same vote score (but different from 0)
        same_score = rand(1..users.length) # Ensure we don't exceed available users
        tracks_to_vote = tracks.sample(rand(2..tracks.length))
        voter = users.sample
        
        tracks_to_vote.each do |track|
          # Create multiple votes from different users to achieve same score
          vote_users = users.sample([same_score, users.length].min) # Don't exceed available users
          vote_users.each do |vote_user|
            # Create vote directly in database to ensure same score
            TrackVote.create(
              id: SecureRandom.uuid,
              track_id: track.id,
              user_id: vote_user.id,
              created_at: Time.now
            )
          end
          track.update(vote_score: vote_users.length) # Use actual number of votes created
        end
        
        # Verify ordering with identical vote scores
        room.refresh
        final_queue = room.track_queue.to_a
        
        # Group tracks by vote score and verify ordering within each group
        grouped_tracks = final_queue.group_by(&:vote_score)
        
        grouped_tracks.each do |score, tracks_with_score|
          # Within each score group, tracks should be ordered by upload time
          tracks_with_score.each_cons(2) do |track1, track2|
            expect(track1.created_at).to be <= track2.created_at
          end
        end
        
        # Verify overall ordering: higher scores first, then by upload time within same score
        final_queue.each_cons(2) do |track1, track2|
          if track1.vote_score == track2.vote_score
            expect(track1.created_at).to be <= track2.created_at
          else
            expect(track1.vote_score).to be >= track2.vote_score
          end
        end
      }
    end
  end

  # Helper methods for generating test data

  def generate_room_data
    {
      name: generate_room_name
    }
  end

  def generate_user_data
    {
      username: generate_username,
      email: generate_email,
      password: generate_password
    }
  end

  def generate_multiple_users(count)
    count.times.map { generate_user_data }
  end

  def generate_multiple_tracks(count)
    count.times.map do |i|
      {
        filename: "test_track_#{i}_#{SecureRandom.hex(4)}.mp3",
        original_name: "Test Track #{i}",
        duration: rand(60..300)
      }
    end
  end

  def generate_voting_operations(tracks_count, users_count, operations_count)
    operations = []
    
    operations_count.times do
      operations << {
        track_index: rand(0...tracks_count),
        user_index: rand(0...users_count),
        action: [:vote, :unvote].sample
      }
    end
    
    operations
  end

  def generate_room_name
    prefixes = ['Music Room', 'Party Room', 'Study Room', 'Chill Room', 'Dance Room']
    suffixes = ['Alpha', 'Beta', 'Gamma', 'Delta', 'Omega', '2024', 'Pro', 'VIP']
    "#{prefixes.sample} #{suffixes.sample} #{rand(100..999)}"
  end

  def generate_username
    prefixes = ['user', 'test', 'demo', 'member', 'guest']
    "#{prefixes.sample}_#{SecureRandom.hex(6)}"
  end

  def generate_email
    domains = ['example.com', 'test.org', 'demo.net', 'sample.io']
    "#{SecureRandom.hex(6)}@#{domains.sample}"
  end

  def generate_password
    # Generate passwords that meet validation requirements (min 8 chars)
    password_patterns = [
      "password#{rand(100..999)}",
      "Password#{rand(100..999)}!",
      "#{SecureRandom.hex(4)}Pass123",
      "Test#{rand(1000..9999)}$",
      "#{SecureRandom.alphanumeric(8)}123"
    ]
    
    password_patterns.sample
  end

  def create_test_user(user_data)
    User.create(
      id: SecureRandom.uuid,
      username: user_data[:username],
      email: user_data[:email].downcase.strip,
      password_hash: BCrypt::Password.create(user_data[:password]),
      created_at: Time.now,
      updated_at: Time.now
    )
  end

  def create_test_room(room_data, admin_user)
    room = Room.create(
      id: SecureRandom.uuid,
      name: room_data[:name],
      administrator_id: admin_user.id,
      is_playing: false,
      created_at: Time.now,
      updated_at: Time.now
    )
    
    # Add administrator as first participant
    room.add_participant(admin_user)
    room.refresh
    room
  end
end