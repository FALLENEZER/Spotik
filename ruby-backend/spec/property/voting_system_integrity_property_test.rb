# Property-based test for voting system integrity
# **Feature: ruby-backend-migration, Property 9: Voting System Integrity**
# **Validates: Requirements 6.1, 6.2**

require 'bundler/setup'
require 'rspec'
require 'rantly'
require 'rantly/rspec_extensions'
require 'securerandom'
require 'json'
require 'set'

# Set test environment
ENV['APP_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test_jwt_secret_key_for_testing_purposes_only'
ENV['JWT_TTL'] = '60' # 1 hour for testing

RSpec.describe 'Voting System Integrity Property Test', :property do
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
    # Clean database before each test - be more thorough
    begin
      DB[:track_votes].delete
      DB[:tracks].delete
      DB[:room_participants].delete
      DB[:rooms].delete
      DB[:users].delete
    rescue => e
      puts "Warning: Database cleanup failed: #{e.message}"
    end
    
    # Clear broadcasted events
    RoomManager.clear_broadcasted_events
  end

  describe 'Property 9: Voting System Integrity' do
    it 'correctly increases track vote count when user votes and decreases when user removes vote' do
      test_instance = self
      
      property_of {
        # Generate test scenario with room, users, and tracks
        room_data = test_instance.generate_room_data
        users_data = test_instance.generate_multiple_users(rand(3..8))
        tracks_count = rand(2..6)
        voting_sequence = test_instance.generate_voting_sequence(tracks_count, users_data.length, rand(10..25))
        [room_data, users_data, tracks_count, voting_sequence]
      }.check(100) { |room_data, users_data, tracks_count, voting_sequence|
        # Create users and room
        users = users_data.map { |user_data| create_test_user(user_data) }
        admin_user = users.first
        room = create_test_room(room_data, admin_user)
        
        # Add all users as participants
        users[1..-1].each { |user| room.add_participant(user) }
        
        # Create tracks
        tracks = []
        tracks_count.times do |i|
          uploader = users.sample
          track = Track.create(
            id: SecureRandom.uuid,
            room_id: room.id,
            uploader_id: uploader.id,
            filename: "integrity_test_track_#{i}.mp3",
            original_name: "Integrity Test Track #{i}",
            file_path: "/tmp/integrity_test_track_#{i}.mp3",
            duration_seconds: rand(60..300),
            file_size_bytes: rand(1_000_000..10_000_000),
            mime_type: 'audio/mpeg',
            vote_score: 0,
            created_at: Time.now + i,
            updated_at: Time.now + i
          )
          tracks << track
          sleep(0.001) # Ensure different timestamps
        end
        
        # Track expected vote counts and user votes
        expected_vote_counts = Hash.new(0)
        user_votes = Hash.new { |h, k| h[k] = Set.new }
        
        # Execute voting sequence and verify integrity at each step
        voting_sequence.each_with_index do |operation, step|
          track_index = operation[:track_index] % tracks.length
          user_index = operation[:user_index] % users.length
          action = operation[:action]
          
          track = tracks[track_index]
          user = users[user_index]
          token = AuthService.generate_jwt(user)
          
          # Clear previous events
          RoomManager.clear_broadcasted_events
          
          # Record state before operation
          initial_vote_count = track.vote_score
          initial_db_vote_count = track.votes.count
          user_had_voted = user_votes[user.id].include?(track.id)
          
          case action
          when :vote
            # Attempt to vote for track
            result = TrackController.vote(track.id, token)
            
            if !user_had_voted
              # **Validates: Requirements 6.1** - System SHALL increase track's vote count
              expect(result[:status]).to eq(200)
              expect(result[:body][:message]).to eq('Vote added successfully')
              
              # Update expected state
              expected_vote_counts[track.id] += 1
              user_votes[user.id].add(track.id)
              
              # Verify vote count increased by exactly 1
              track.refresh
              expect(track.vote_score).to eq(initial_vote_count + 1)
              expect(track.votes.count).to eq(initial_db_vote_count + 1)
              expect(track.vote_score).to eq(expected_vote_counts[track.id])
              
              # Verify response contains correct vote score
              expect(result[:body][:vote_score]).to eq(track.vote_score)
              expect(result[:body][:user_has_voted]).to be true
              
              # Verify track_voted event was broadcasted
              events = RoomManager.get_broadcasted_events
              track_voted_event = events.find { |e| e[:event_type] == 'track_voted' }
              expect(track_voted_event).not_to be_nil
              expect(track_voted_event[:data][:track][:id]).to eq(track.id)
              expect(track_voted_event[:data][:voter][:id]).to eq(user.id)
              expect(track_voted_event[:data][:new_vote_score]).to eq(track.vote_score)
              
            else
              # User already voted - should not change vote count
              expect(result[:status]).to eq(200)
              expect(result[:body][:message]).to eq('Vote already exists')
              
              # Verify vote count unchanged
              track.refresh
              expect(track.vote_score).to eq(initial_vote_count)
              expect(track.votes.count).to eq(initial_db_vote_count)
              expect(track.vote_score).to eq(expected_vote_counts[track.id])
              
              # Verify response contains correct vote score
              expect(result[:body][:vote_score]).to eq(track.vote_score)
              expect(result[:body][:user_has_voted]).to be true
            end
            
          when :unvote
            # Attempt to remove vote from track
            result = TrackController.unvote(track.id, token)
            
            if user_had_voted
              # **Validates: Requirements 6.2** - System SHALL decrease track's vote count
              expect(result[:status]).to eq(200)
              expect(result[:body][:message]).to eq('Vote removed successfully')
              
              # Update expected state
              expected_vote_counts[track.id] -= 1
              user_votes[user.id].delete(track.id)
              
              # Verify vote count decreased by exactly 1
              track.refresh
              expect(track.vote_score).to eq(initial_vote_count - 1)
              expect(track.votes.count).to eq(initial_db_vote_count - 1)
              expect(track.vote_score).to eq(expected_vote_counts[track.id])
              
              # Verify response contains correct vote score
              expect(result[:body][:vote_score]).to eq(track.vote_score)
              expect(result[:body][:user_has_voted]).to be false
              
              # Verify track_unvoted event was broadcasted
              events = RoomManager.get_broadcasted_events
              track_unvoted_event = events.find { |e| e[:event_type] == 'track_unvoted' }
              expect(track_unvoted_event).not_to be_nil
              expect(track_unvoted_event[:data][:track][:id]).to eq(track.id)
              expect(track_unvoted_event[:data][:voter][:id]).to eq(user.id)
              expect(track_unvoted_event[:data][:new_vote_score]).to eq(track.vote_score)
              
            else
              # User had not voted - should not change vote count
              expect(result[:status]).to eq(200)
              expect(result[:body][:message]).to eq('No vote to remove')
              
              # Verify vote count unchanged
              track.refresh
              expect(track.vote_score).to eq(initial_vote_count)
              expect(track.votes.count).to eq(initial_db_vote_count)
              expect(track.vote_score).to eq(expected_vote_counts[track.id])
              
              # Verify response contains correct vote score
              expect(result[:body][:vote_score]).to eq(track.vote_score)
              expect(result[:body][:user_has_voted]).to be false
            end
          end
          
          # Verify vote count consistency across all tracks after each operation
          tracks.each do |t|
            t.refresh
            expect(t.vote_score).to eq(expected_vote_counts[t.id])
            expect(t.vote_score).to eq(t.votes.count)
            expect(t.vote_score).to be >= 0 # Vote count should never be negative
          end
          
          # Verify user vote tracking consistency
          users.each do |u|
            tracks.each do |t|
              has_vote_in_db = t.has_vote_from?(u)
              has_vote_in_tracking = user_votes[u.id].include?(t.id)
              expect(has_vote_in_db).to eq(has_vote_in_tracking)
            end
          end
        end
        
        # Final integrity verification
        tracks.each do |track|
          track.refresh
          
          # Verify vote_score matches actual vote count
          actual_vote_count = track.votes.count
          expect(track.vote_score).to eq(actual_vote_count)
          expect(track.vote_score).to eq(expected_vote_counts[track.id])
          
          # Verify each vote record is valid
          track.votes.each do |vote|
            expect(vote.track_id).to eq(track.id)
            expect(users.map(&:id)).to include(vote.user_id)
            expect(user_votes[vote.user_id]).to include(track.id)
          end
          
          # Verify no duplicate votes from same user
          vote_user_ids = track.votes.map(&:user_id)
          expect(vote_user_ids.uniq.length).to eq(vote_user_ids.length)
        end
        
        # Verify user vote tracking is accurate
        users.each do |user|
          user_track_votes = user_votes[user.id]
          
          user_track_votes.each do |track_id|
            track = tracks.find { |t| t.id == track_id }
            expect(track.has_vote_from?(user)).to be true
          end
          
          # Verify user hasn't voted for tracks not in their tracking
          tracks.each do |track|
            if !user_track_votes.include?(track.id)
              expect(track.has_vote_from?(user)).to be false
            end
          end
        end
      }
    end

    it 'maintains vote count integrity under concurrent voting operations' do
      test_instance = self
      
      property_of {
        # Generate scenario for concurrent voting
        room_data = test_instance.generate_room_data
        users_data = test_instance.generate_multiple_users(rand(4..7))
        tracks_count = rand(3..5)
        concurrent_operations = test_instance.generate_concurrent_voting_operations(tracks_count, users_data.length, rand(8..15))
        [room_data, users_data, tracks_count, concurrent_operations]
      }.check(50) { |room_data, users_data, tracks_count, concurrent_operations|
        # Create users and room
        users = users_data.map { |user_data| create_test_user(user_data) }
        admin_user = users.first
        room = create_test_room(room_data, admin_user)
        
        # Add all users as participants
        users[1..-1].each { |user| room.add_participant(user) }
        
        # Create tracks
        tracks = []
        tracks_count.times do |i|
          uploader = users.sample
          track = Track.create(
            id: SecureRandom.uuid,
            room_id: room.id,
            uploader_id: uploader.id,
            filename: "concurrent_vote_track_#{i}.mp3",
            original_name: "Concurrent Vote Track #{i}",
            file_path: "/tmp/concurrent_vote_track_#{i}.mp3",
            duration_seconds: rand(60..300),
            file_size_bytes: rand(1_000_000..10_000_000),
            mime_type: 'audio/mpeg',
            vote_score: 0,
            created_at: Time.now + i,
            updated_at: Time.now + i
          )
          tracks << track
        end
        
        # Track expected final state
        expected_final_votes = Hash.new { |h, k| h[k] = Set.new }
        
        # Process concurrent operations to determine final expected state
        concurrent_operations.each do |operation|
          track_index = operation[:track_index] % tracks.length
          user_index = operation[:user_index] % users.length
          action = operation[:action]
          
          track_id = tracks[track_index].id
          user_id = users[user_index].id
          
          case action
          when :vote
            expected_final_votes[track_id].add(user_id)
          when :unvote
            expected_final_votes[track_id].delete(user_id)
          end
        end
        
        # Execute all operations (simulating concurrent access)
        concurrent_operations.each do |operation|
          track_index = operation[:track_index] % tracks.length
          user_index = operation[:user_index] % users.length
          action = operation[:action]
          
          track = tracks[track_index]
          user = users[user_index]
          token = AuthService.generate_jwt(user)
          
          case action
          when :vote
            result = TrackController.vote(track.id, token)
            expect([200]).to include(result[:status])
            
          when :unvote
            result = TrackController.unvote(track.id, token)
            expect([200]).to include(result[:status])
          end
        end
        
        # Verify final state integrity
        tracks.each do |track|
          track.refresh
          expected_vote_count = expected_final_votes[track.id].size
          
          # **Validates: Requirements 6.1, 6.2** - Final vote count should match expected state
          expect(track.vote_score).to eq(expected_vote_count)
          expect(track.votes.count).to eq(expected_vote_count)
          
          # Verify each expected voter has a vote record
          expected_final_votes[track.id].each do |user_id|
            user = users.find { |u| u.id == user_id }
            expect(track.has_vote_from?(user)).to be true
          end
          
          # Verify no unexpected votes exist
          track.votes.each do |vote|
            expect(expected_final_votes[track.id]).to include(vote.user_id)
          end
          
          # Verify vote count is non-negative
          expect(track.vote_score).to be >= 0
        end
      }
    end

    it 'preserves vote count accuracy when users vote for multiple tracks' do
      test_instance = self
      
      property_of {
        # Generate scenario with users voting across multiple tracks
        room_data = test_instance.generate_room_data
        users_data = test_instance.generate_multiple_users(rand(3..6))
        tracks_count = rand(4..8)
        multi_track_operations = test_instance.generate_multi_track_voting_operations(tracks_count, users_data.length, rand(12..20))
        [room_data, users_data, tracks_count, multi_track_operations]
      }.check(50) { |room_data, users_data, tracks_count, multi_track_operations|
        # Create users and room
        users = users_data.map { |user_data| create_test_user(user_data) }
        admin_user = users.first
        room = create_test_room(room_data, admin_user)
        
        # Add all users as participants
        users[1..-1].each { |user| room.add_participant(user) }
        
        # Create tracks
        tracks = []
        tracks_count.times do |i|
          uploader = users.sample
          track = Track.create(
            id: SecureRandom.uuid,
            room_id: room.id,
            uploader_id: uploader.id,
            filename: "multi_track_vote_#{i}.mp3",
            original_name: "Multi Track Vote #{i}",
            file_path: "/tmp/multi_track_vote_#{i}.mp3",
            duration_seconds: rand(60..300),
            file_size_bytes: rand(1_000_000..10_000_000),
            mime_type: 'audio/mpeg',
            vote_score: 0,
            created_at: Time.now + i,
            updated_at: Time.now + i
          )
          tracks << track
        end
        
        # Track vote state per user per track
        user_track_votes = Hash.new { |h, k| h[k] = Hash.new(false) }
        expected_track_votes = Hash.new(0)
        
        # Execute multi-track voting operations
        multi_track_operations.each do |operation|
          track_index = operation[:track_index] % tracks.length
          user_index = operation[:user_index] % users.length
          action = operation[:action]
          
          track = tracks[track_index]
          user = users[user_index]
          token = AuthService.generate_jwt(user)
          
          # Record current state
          user_had_voted = user_track_votes[user.id][track.id]
          
          case action
          when :vote
            result = TrackController.vote(track.id, token)
            expect(result[:status]).to eq(200)
            
            if !user_had_voted
              # **Validates: Requirements 6.1** - Vote count should increase
              user_track_votes[user.id][track.id] = true
              expected_track_votes[track.id] += 1
              
              expect(result[:body][:message]).to eq('Vote added successfully')
            else
              # User already voted - no change
              expect(result[:body][:message]).to eq('Vote already exists')
            end
            
          when :unvote
            result = TrackController.unvote(track.id, token)
            expect(result[:status]).to eq(200)
            
            if user_had_voted
              # **Validates: Requirements 6.2** - Vote count should decrease
              user_track_votes[user.id][track.id] = false
              expected_track_votes[track.id] -= 1
              
              expect(result[:body][:message]).to eq('Vote removed successfully')
            else
              # User had not voted - no change
              expect(result[:body][:message]).to eq('No vote to remove')
            end
          end
          
          # Verify immediate consistency
          track.refresh
          expect(track.vote_score).to eq(expected_track_votes[track.id])
          expect(track.votes.count).to eq(expected_track_votes[track.id])
        end
        
        # Final verification across all tracks and users
        tracks.each do |track|
          track.refresh
          
          # Count expected votes for this track
          expected_votes_for_track = users.count { |user| user_track_votes[user.id][track.id] }
          
          # **Validates: Requirements 6.1, 6.2** - Final vote count should be accurate
          expect(track.vote_score).to eq(expected_votes_for_track)
          expect(track.votes.count).to eq(expected_votes_for_track)
          expect(track.vote_score).to eq(expected_track_votes[track.id])
          
          # Verify each user's vote state matches database
          users.each do |user|
            expected_has_vote = user_track_votes[user.id][track.id]
            actual_has_vote = track.has_vote_from?(user)
            expect(actual_has_vote).to eq(expected_has_vote)
          end
        end
        
        # Verify total vote consistency across the system
        total_expected_votes = expected_track_votes.values.sum
        total_actual_votes = tracks.sum { |track| track.votes.count }
        expect(total_actual_votes).to eq(total_expected_votes)
        
        # Verify no orphaned votes exist - only check votes for tracks created in this test
        track_ids = tracks.map(&:id)
        user_ids = users.map(&:id)
        
        all_vote_records = DB[:track_votes].where(track_id: track_ids, user_id: user_ids).all
        all_vote_records.each do |vote_record|
          track = tracks.find { |t| t.id == vote_record[:track_id] }
          user = users.find { |u| u.id == vote_record[:user_id] }
          
          expect(track).not_to be_nil, "Track with ID #{vote_record[:track_id]} not found in tracks list"
          expect(user).not_to be_nil, "User with ID #{vote_record[:user_id]} not found in users list"
          expect(user_track_votes[user.id][track.id]).to be true
        end
      }
    end

    it 'maintains vote count bounds and prevents negative vote scores' do
      test_instance = self
      
      property_of {
        # Generate scenario that might cause edge cases with vote counts
        room_data = test_instance.generate_room_data
        users_data = test_instance.generate_multiple_users(rand(2..4))
        tracks_count = rand(2..4)
        edge_case_operations = test_instance.generate_edge_case_voting_operations(tracks_count, users_data.length, rand(15..25))
        [room_data, users_data, tracks_count, edge_case_operations]
      }.check(30) { |room_data, users_data, tracks_count, edge_case_operations|
        # Create users and room
        users = users_data.map { |user_data| create_test_user(user_data) }
        admin_user = users.first
        room = create_test_room(room_data, admin_user)
        
        # Add all users as participants
        users[1..-1].each { |user| room.add_participant(user) }
        
        # Create tracks
        tracks = []
        tracks_count.times do |i|
          uploader = users.sample
          track = Track.create(
            id: SecureRandom.uuid,
            room_id: room.id,
            uploader_id: uploader.id,
            filename: "edge_case_track_#{i}.mp3",
            original_name: "Edge Case Track #{i}",
            file_path: "/tmp/edge_case_track_#{i}.mp3",
            duration_seconds: rand(60..300),
            file_size_bytes: rand(1_000_000..10_000_000),
            mime_type: 'audio/mpeg',
            vote_score: 0,
            created_at: Time.now + i,
            updated_at: Time.now + i
          )
          tracks << track
        end
        
        # Execute edge case operations (many unvotes, repeated votes, etc.)
        edge_case_operations.each do |operation|
          track_index = operation[:track_index] % tracks.length
          user_index = operation[:user_index] % users.length
          action = operation[:action]
          
          track = tracks[track_index]
          user = users[user_index]
          token = AuthService.generate_jwt(user)
          
          initial_vote_score = track.vote_score
          
          case action
          when :vote
            result = TrackController.vote(track.id, token)
            expect(result[:status]).to eq(200)
            
            track.refresh
            # **Validates: Requirements 6.1** - Vote count should never exceed number of users
            expect(track.vote_score).to be <= users.length
            expect(track.vote_score).to be >= 0
            
          when :unvote
            result = TrackController.unvote(track.id, token)
            expect(result[:status]).to eq(200)
            
            track.refresh
            # **Validates: Requirements 6.2** - Vote count should never go negative
            expect(track.vote_score).to be >= 0
            expect(track.vote_score).to be <= users.length
          end
          
          # Verify vote score consistency
          track.refresh
          expect(track.vote_score).to eq(track.votes.count)
          
          # Verify vote score bounds
          expect(track.vote_score).to be >= 0
          expect(track.vote_score).to be <= users.length
        end
        
        # Final verification of all tracks
        tracks.each do |track|
          track.refresh
          
          # **Validates: Requirements 6.1, 6.2** - Final state should be consistent and within bounds
          expect(track.vote_score).to eq(track.votes.count)
          expect(track.vote_score).to be >= 0
          expect(track.vote_score).to be <= users.length
          
          # Verify no duplicate votes from same user
          vote_user_ids = track.votes.map(&:user_id)
          expect(vote_user_ids.uniq.length).to eq(vote_user_ids.length)
          
          # Verify all voters are valid users
          track.votes.each do |vote|
            expect(users.map(&:id)).to include(vote.user_id)
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

  def generate_voting_sequence(tracks_count, users_count, operations_count)
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

  def generate_concurrent_voting_operations(tracks_count, users_count, operations_count)
    operations = []
    
    # Generate operations that might conflict (same user, same track)
    operations_count.times do
      operations << {
        track_index: rand(0...tracks_count),
        user_index: rand(0...users_count),
        action: [:vote, :unvote].sample
      }
    end
    
    # Shuffle to simulate concurrent execution
    operations.shuffle
  end

  def generate_multi_track_voting_operations(tracks_count, users_count, operations_count)
    operations = []
    
    # Ensure each user votes for multiple tracks
    operations_count.times do
      operations << {
        track_index: rand(tracks_count), # This gives 0 to tracks_count-1, which is correct
        user_index: rand(users_count),   # This gives 0 to users_count-1, which is correct
        action: [:vote, :unvote].sample
      }
    end
    
    operations
  end

  def generate_edge_case_voting_operations(tracks_count, users_count, operations_count)
    operations = []
    
    # Generate operations that might cause edge cases
    operations_count.times do
      # Bias towards unvote operations to test negative vote prevention
      action = rand < 0.6 ? :unvote : :vote
      
      operations << {
        track_index: rand(0...tracks_count),
        user_index: rand(0...users_count),
        action: action
      }
    end
    
    operations
  end

  def generate_room_name
    prefixes = ['Vote Test Room', 'Integrity Room', 'Test Room', 'Voting Room']
    suffixes = ['Alpha', 'Beta', 'Gamma', 'Delta', '2024', 'Test']
    "#{prefixes.sample} #{suffixes.sample} #{rand(100..999)}"
  end

  def generate_username
    prefixes = ['voter', 'user', 'test', 'member']
    "#{prefixes.sample}_#{SecureRandom.hex(6)}"
  end

  def generate_email
    domains = ['example.com', 'test.org', 'demo.net', 'vote.io']
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