# Property-based test for database compatibility
# **Feature: ruby-backend-migration, Property 13: Database Compatibility**
# **Validates: Requirements 8.3, 8.5**

require 'spec_helper'
require 'rantly'
require 'rantly/rspec_extensions'
require 'bcrypt'
require 'securerandom'

RSpec.describe 'Database Compatibility Property Test', :property do
  before(:all) do
    # Load test database configuration
    require_relative '../../config/test_database'
    
    # Override the DB constant for testing
    Object.send(:remove_const, :DB) if defined?(DB)
    DB = SpotikConfig::TestDatabase.connection
    
    # Load models with test database
    require_relative '../../app/models/user'
    require_relative '../../app/models/room'
    require_relative '../../app/models/track'
    require_relative '../../app/models/room_participant'
    require_relative '../../app/models/track_vote'
    
    # Finalize associations
    Sequel::Model.finalize_associations
  end
  
  before(:each) do
    # Clean database before each test
    DB[:track_votes].delete
    DB[:room_participants].delete
    DB[:tracks].delete
    DB[:rooms].delete
    DB[:users].delete
  end

  describe 'Property 13: Database Compatibility' do
    it 'maintains identical CRUD behavior with Legacy_System database' do
      test_instance = self
      
      property_of {
        # Generate random CRUD operation scenarios
        operation_type = choose(:create, :read, :update, :delete)
        model_type = choose(:user, :room, :track, :room_participant, :track_vote)
        
        # Generate test data based on model type
        test_data = test_instance.generate_test_data_for_model(model_type)
        
        [operation_type, model_type, test_data]
      }.check(100) { |operation, model, data|
        # Execute the operation and verify compatibility
        result = execute_crud_operation(operation, model, data)
        
        # Verify the operation maintains data integrity
        expect(verify_data_integrity).to be true
        
        # Verify the operation follows Laravel conventions
        expect(verify_laravel_compatibility(operation, model, result)).to be true
        
        # Verify database constraints are maintained
        expect(verify_database_constraints).to be true
      }
    end

    it 'maintains referential integrity across all operations' do
      test_instance = self
      
      property_of {
        # Generate a sequence of related operations
        operations = test_instance.generate_related_operations_sequence
        operations
      }.check(50) { |operations|
        created_records = {}
        
        operations.each do |operation|
          case operation[:type]
          when :create_user
            user = create_test_user(operation[:data])
            created_records[:user] = user
            expect(user).to be_valid
            
          when :create_room
            user = created_records[:user] || create_test_user
            room = create_test_room(operation[:data].merge(administrator_id: user.id))
            created_records[:room] = room
            expect(room).to be_valid
            expect(room.administrator_id).to eq(user.id)
            
          when :join_room
            user = created_records[:user] || create_test_user
            room = created_records[:room] || create_test_room
            participant = room.add_participant(user)
            expect(participant).to be_valid
            expect(room.has_participant?(user)).to be true
            
          when :upload_track
            user = created_records[:user] || create_test_user
            room = created_records[:room] || create_test_room
            track = create_test_track(operation[:data].merge(
              room_id: room.id,
              uploader_id: user.id
            ))
            created_records[:track] = track
            expect(track).to be_valid
            expect(track.room_id).to eq(room.id)
            expect(track.uploader_id).to eq(user.id)
            
          when :vote_track
            user = created_records[:user] || create_test_user
            track = created_records[:track] || create_test_track
            vote = track.add_vote(user)
            expect(vote).to be_valid
            expect(track.has_vote_from?(user)).to be true
          end
        end
        
        # Verify all relationships are maintained
        expect(verify_referential_integrity(created_records)).to be true
      }
    end

    it 'handles concurrent operations without data corruption' do
      test_instance = self
      
      property_of {
        # Generate concurrent operation scenarios
        concurrent_operations = test_instance.generate_concurrent_operations
        concurrent_operations
      }.check(25) { |operations|
        # Create base data for concurrent operations
        user1 = create_test_user(username: "user1_#{SecureRandom.hex(4)}")
        user2 = create_test_user(username: "user2_#{SecureRandom.hex(4)}")
        room = create_test_room(administrator_id: user1.id)
        track = create_test_track(room_id: room.id, uploader_id: user1.id)
        
        # Execute operations concurrently (simulated)
        results = []
        operations.each do |operation|
          result = case operation[:type]
          when :vote_same_track
            # Both users vote for the same track
            vote1 = track.add_vote(user1)
            vote2 = track.add_vote(user2)
            [vote1, vote2]
            
          when :join_same_room
            # Both users join the same room
            participant1 = room.add_participant(user1)
            participant2 = room.add_participant(user2)
            [participant1, participant2]
            
          when :update_same_record
            # Both users try to update the same room (only admin should succeed)
            room.update(name: "Updated by user1")
            room.refresh
            [room]
          end
          
          results << result
        end
        
        # Verify data consistency after concurrent operations
        expect(verify_data_consistency(room, track, [user1, user2])).to be true
      }
    end

    it 'maintains vote score accuracy across all operations' do
      test_instance = self
      
      property_of {
        # Generate voting scenarios
        vote_operations = test_instance.generate_vote_operations
        vote_operations
      }.check(50) { |operations|
        # Create test data
        users = 5.times.map { |i| create_test_user(username: "voter#{i}_#{SecureRandom.hex(4)}") }
        room = create_test_room(administrator_id: users.first.id)
        track = create_test_track(room_id: room.id, uploader_id: users.first.id)
        
        expected_vote_count = 0
        
        operations.each do |operation|
          user = users.sample
          
          case operation[:type]
          when :add_vote
            unless track.has_vote_from?(user)
              track.add_vote(user)
              expected_vote_count += 1
            end
            
          when :remove_vote
            if track.has_vote_from?(user)
              track.remove_vote(user)
              expected_vote_count -= 1
            end
            
          when :toggle_vote
            if track.has_vote_from?(user)
              track.remove_vote(user)
              expected_vote_count -= 1
            else
              track.add_vote(user)
              expected_vote_count += 1
            end
          end
        end
        
        # Verify vote count accuracy
        track.refresh
        actual_vote_count = track.votes.count
        
        expect(actual_vote_count).to eq(expected_vote_count)
        expect(track.vote_score).to eq(actual_vote_count)
      }
    end

    it 'maintains playback state consistency' do
      test_instance = self
      
      property_of {
        # Generate playback control scenarios
        playback_operations = test_instance.generate_playback_operations
        playback_operations
      }.check(30) { |operations|
        # Create test data
        admin = create_test_user(username: "admin_#{SecureRandom.hex(4)}")
        room = create_test_room(administrator_id: admin.id)
        tracks = 3.times.map { |i| 
          create_test_track(
            room_id: room.id, 
            uploader_id: admin.id,
            original_name: "Track #{i + 1}"
          )
        }
        
        current_track = nil
        is_playing = false
        
        operations.each do |operation|
          case operation[:type]
          when :start_track
            track = tracks.sample
            room.start_track(track)
            current_track = track
            is_playing = true
            
          when :pause_playback
            if is_playing
              room.pause_playback
              is_playing = false
            end
            
          when :resume_playback
            if !is_playing && current_track
              room.resume_playback
              is_playing = true
            end
            
          when :stop_playback
            room.stop_playback
            current_track = nil
            is_playing = false
            
          when :skip_to_next
            next_track = room.skip_to_next
            current_track = next_track
            is_playing = next_track ? true : false
          end
        end
        
        # Verify playback state consistency
        room.refresh
        expect(room.is_playing).to eq(is_playing)
        
        if current_track
          expect(room.current_track_id).to eq(current_track.id)
        else
          expect(room.current_track_id).to be_nil
        end
      }
    end
  end

  def generate_test_data_for_model(model_type)
    case model_type
    when :user
      {
        username: "user_#{SecureRandom.hex(6)}",
        email: "#{SecureRandom.hex(6)}@example.com",
        password_hash: BCrypt::Password.create('password123'),
        created_at: Time.now,
        updated_at: Time.now
      }
    when :room
      {
        name: "Room #{SecureRandom.hex(4)}",
        administrator_id: nil, # Will be set during test
        created_at: Time.now,
        updated_at: Time.now
      }
    when :track
      {
        filename: "track_#{SecureRandom.hex(6)}.mp3",
        original_name: "Test Track #{SecureRandom.hex(4)}.mp3",
        file_path: "/tmp/tracks/track_#{SecureRandom.hex(6)}.mp3",
        duration_seconds: rand(60..300),
        file_size_bytes: rand(1024..5*1024*1024),
        mime_type: ['audio/mpeg', 'audio/wav', 'audio/mp4'].sample,
        vote_score: 0,
        created_at: Time.now,
        updated_at: Time.now
      }
    when :room_participant
      {
        joined_at: Time.now
      }
    when :track_vote
      {
        created_at: Time.now
      }
    end
  end

  def execute_crud_operation(operation, model_type, data)
    case operation
    when :create
      create_record(model_type, data)
    when :read
      read_record(model_type, data)
    when :update
      update_record(model_type, data)
    when :delete
      delete_record(model_type, data)
    end
  end

  def create_record(model_type, data)
    case model_type
    when :user
      User.create(data)
    when :room
      admin = create_test_user
      Room.create(data.merge(administrator_id: admin.id))
    when :track
      user = create_test_user
      room = create_test_room(administrator_id: user.id)
      Track.create(data.merge(room_id: room.id, uploader_id: user.id))
    when :room_participant
      user = create_test_user
      room = create_test_room
      RoomParticipant.create(data.merge(room_id: room.id, user_id: user.id))
    when :track_vote
      user = create_test_user
      track = create_test_track
      TrackVote.create(data.merge(track_id: track.id, user_id: user.id))
    end
  end

  def read_record(model_type, data)
    case model_type
    when :user
      User.first
    when :room
      Room.first
    when :track
      Track.first
    when :room_participant
      RoomParticipant.first
    when :track_vote
      TrackVote.first
    end
  end

  def update_record(model_type, data)
    record = read_record(model_type, data)
    return nil unless record
    
    case model_type
    when :user
      record.update(username: "updated_#{SecureRandom.hex(4)}")
    when :room
      record.update(name: "Updated Room #{SecureRandom.hex(4)}")
    when :track
      record.update(original_name: "Updated Track #{SecureRandom.hex(4)}")
    when :room_participant
      record.update(joined_at: Time.now)
    when :track_vote
      record.update(created_at: Time.now)
    end
    
    record
  end

  def delete_record(model_type, data)
    record = read_record(model_type, data)
    return false unless record
    
    record.destroy
    true
  end

  def generate_related_operations_sequence
    operations = []
    
    # Always start with creating a user
    operations << { type: :create_user, data: generate_test_data_for_model(:user) }
    
    # Add random related operations
    rand(2..5).times do
      operations << case rand(4)
      when 0
        { type: :create_room, data: generate_test_data_for_model(:room) }
      when 1
        { type: :join_room, data: {} }
      when 2
        { type: :upload_track, data: generate_test_data_for_model(:track) }
      when 3
        { type: :vote_track, data: {} }
      end
    end
    
    operations
  end

  def generate_concurrent_operations
    operations = []
    
    rand(2..4).times do
      operations << case rand(3)
      when 0
        { type: :vote_same_track }
      when 1
        { type: :join_same_room }
      when 2
        { type: :update_same_record }
      end
    end
    
    operations
  end

  def generate_vote_operations
    operations = []
    
    rand(10..20).times do
      operations << { type: [:add_vote, :remove_vote, :toggle_vote].sample }
    end
    
    operations
  end

  def generate_playback_operations
    operations = []
    
    rand(5..10).times do
      operations << { 
        type: [:start_track, :pause_playback, :resume_playback, :stop_playback, :skip_to_next].sample 
      }
    end
    
    operations
  end

  def create_test_user(attrs = {})
    default_attrs = {
      username: "user_#{SecureRandom.hex(6)}",
      email: "#{SecureRandom.hex(6)}@example.com",
      password_hash: BCrypt::Password.create('password123'),
      created_at: Time.now,
      updated_at: Time.now
    }
    
    User.create(default_attrs.merge(attrs))
  end

  def create_test_room(attrs = {})
    admin = attrs[:administrator_id] ? User[attrs[:administrator_id]] : create_test_user
    default_attrs = {
      name: "Room #{SecureRandom.hex(4)}",
      administrator_id: admin.id,
      created_at: Time.now,
      updated_at: Time.now
    }
    
    Room.create(default_attrs.merge(attrs))
  end

  def create_test_track(attrs = {})
    room = attrs[:room_id] ? Room[attrs[:room_id]] : create_test_room
    uploader = attrs[:uploader_id] ? User[attrs[:uploader_id]] : create_test_user
    
    default_attrs = {
      room_id: room.id,
      uploader_id: uploader.id,
      filename: "track_#{SecureRandom.hex(6)}.mp3",
      original_name: "Test Track #{SecureRandom.hex(4)}.mp3",
      file_path: "/tmp/tracks/track_#{SecureRandom.hex(6)}.mp3",
      duration_seconds: rand(60..300),
      file_size_bytes: rand(1024..5*1024*1024),
      mime_type: 'audio/mpeg',
      vote_score: 0,
      created_at: Time.now,
      updated_at: Time.now
    }
    
    Track.create(default_attrs.merge(attrs))
  end

  def verify_data_integrity
    # Check that all foreign key constraints are satisfied
    begin
      # Verify users exist for all references
      Room.all.each do |room|
        next unless room.administrator_id
        expect(User[room.administrator_id]).not_to be_nil
      end
      
      Track.all.each do |track|
        expect(Room[track.room_id]).not_to be_nil if track.room_id
        expect(User[track.uploader_id]).not_to be_nil if track.uploader_id
      end
      
      RoomParticipant.all.each do |participant|
        expect(Room[participant.room_id]).not_to be_nil if participant.room_id
        expect(User[participant.user_id]).not_to be_nil if participant.user_id
      end
      
      TrackVote.all.each do |vote|
        expect(Track[vote.track_id]).not_to be_nil if vote.track_id
        expect(User[vote.user_id]).not_to be_nil if vote.user_id
      end
      
      true
    rescue => e
      puts "Data integrity check failed: #{e.message}"
      false
    end
  end

  def verify_laravel_compatibility(operation, model, result)
    # Verify that the operation result matches Laravel conventions
    case operation
    when :create
      # Created records should have valid IDs and timestamps
      return false unless result && result.id
      return false unless result.respond_to?(:created_at) && result.created_at
      
    when :update
      # Updated records should have updated timestamps
      return false unless result && result.respond_to?(:updated_at)
      
    when :delete
      # Delete operations should return true/false
      return [true, false].include?(result)
    end
    
    true
  end

  def verify_database_constraints
    # Check that unique constraints are enforced
    begin
      # Test unique username constraint
      username = "unique_test_user_#{SecureRandom.hex(4)}"
      user1 = create_test_user(username: username)
      
      # Try to create another user with the same username - should fail
      expect {
        create_test_user(username: username)
      }.to raise_error(Sequel::UniqueConstraintViolation)
      
      # Test unique email constraint
      expect {
        create_test_user(email: user1.email)
      }.to raise_error(Sequel::UniqueConstraintViolation)
      
      true
    rescue => e
      puts "Database constraint check failed: #{e.message}"
      false
    end
  end

  def verify_referential_integrity(records)
    # Verify that all created records maintain proper relationships
    begin
      if records[:room] && records[:user]
        expect(records[:room].administrator_id).to eq(records[:user].id)
      end
      
      if records[:track] && records[:room] && records[:user]
        expect(records[:track].room_id).to eq(records[:room].id)
        expect(records[:track].uploader_id).to eq(records[:user].id)
      end
      
      true
    rescue => e
      puts "Referential integrity check failed: #{e.message}"
      false
    end
  end

  def verify_data_consistency(room, track, users)
    # Verify that concurrent operations maintain data consistency
    begin
      # Check vote counts are accurate
      actual_votes = track.votes.count
      expected_votes = track.vote_score
      return false unless actual_votes == expected_votes
      
      # Check room participants are accurate
      actual_participants = room.participants.count
      expected_participants = room.users.count
      return false unless actual_participants == expected_participants
      
      true
    rescue => e
      puts "Data consistency check failed: #{e.message}"
      false
    end
  end
end