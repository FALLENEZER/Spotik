# Property-based test for room membership management
# **Feature: ruby-backend-migration, Property 5: Room Membership Management**
# **Validates: Requirements 3.1, 3.2, 3.3, 3.4**

require 'bundler/setup'
require 'rspec'
require 'rantly'
require 'rantly/rspec_extensions'
require 'securerandom'

# Set test environment
ENV['APP_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test_jwt_secret_key_for_testing_purposes_only'
ENV['JWT_TTL'] = '60' # 1 hour for testing

RSpec.describe 'Room Membership Management Property Test', :property do
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
    require_relative '../../app/services/room_manager'
    require_relative '../../app/services/auth_service'
    
    # Stub WebSocketConnection for testing
    class WebSocketConnection
      def self.send_to_user(user_id, message)
        # Stub implementation for testing
        true
      end
      
      def self.broadcast_to_room(room_id, message)
        # Stub implementation for testing
        true
      end
      
      def self.get_user_connection(user_id)
        # Stub implementation for testing - return nil (no connection)
        nil
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
    DB[:room_participants].delete
    DB[:tracks].delete
    DB[:rooms].delete
    DB[:users].delete
  end

  describe 'Property 5: Room Membership Management' do
    it 'correctly updates participant list when any user joins a room' do
      test_instance = self
      
      property_of {
        # Generate room and users scenario
        room_data = test_instance.generate_room_data
        users_data = test_instance.generate_multiple_users(rand(1..5))
        [room_data, users_data]
      }.check(100) { |room_data, users_data|
        # Create users
        users = users_data.map { |user_data| create_test_user(user_data) }
        
        # Create room with first user as administrator
        admin_user = users.first
        room = create_test_room(room_data, admin_user)
        
        # Verify initial state - administrator is automatically added as participant
        expect(room.participants.count).to eq(1)
        expect(room.has_participant?(admin_user)).to be true
        expect(room.administered_by?(admin_user)).to be true
        
        # Test joining room with remaining users
        joining_users = users[1..-1] || []
        
        joining_users.each do |user|
          # Record state before joining
          initial_participant_count = room.participants.count
          initial_participants = room.participants.map(&:user_id)
          
          # User joins room
          result = RoomManager.join_room(user, room.id)
          
          # Verify join was successful
          expect(result[:success]).to be true
          expect(result[:room]).not_to be_nil
          expect(result[:participant]).not_to be_nil
          
          # Reload room to get fresh data
          room.refresh
          
          # Verify participant list is correctly updated
          expect(room.participants.count).to eq(initial_participant_count + 1)
          expect(room.has_participant?(user)).to be true
          expect(room.participants.map(&:user_id)).to include(user.id)
          
          # Verify all previous participants are still there
          initial_participants.each do |participant_id|
            expect(room.participants.map(&:user_id)).to include(participant_id)
          end
          
          # Verify room state consistency
          expect(room.participant_count).to eq(room.participants.count)
          
          # Verify user is not administrator (only creator is admin)
          expect(room.administered_by?(user)).to be false
          
          # Verify participant record has correct data
          participant = room.participants.find { |p| p.user_id == user.id }
          expect(participant).not_to be_nil
          expect(participant.room_id).to eq(room.id)
          expect(participant.user_id).to eq(user.id)
          expect(participant.joined_at).to be_within(5).of(Time.now)
        end
        
        # Final verification - all users should be participants
        expect(room.participants.count).to eq(users.length)
        users.each do |user|
          expect(room.has_participant?(user)).to be true
        end
      }
    end

    it 'correctly updates participant list when any user leaves a room' do
      test_instance = self
      
      property_of {
        # Generate room with multiple participants
        room_data = test_instance.generate_room_data
        users_data = test_instance.generate_multiple_users(rand(3..6)) # Need at least 3 users (admin + 2 others)
        [room_data, users_data]
      }.check(100) { |room_data, users_data|
        # Create users
        users = users_data.map { |user_data| create_test_user(user_data) }
        
        # Create room with first user as administrator
        admin_user = users.first
        room = create_test_room(room_data, admin_user)
        
        # Add all other users as participants
        participant_users = users[1..-1]
        participant_users.each do |user|
          result = RoomManager.join_room(user, room.id)
          expect(result[:success]).to be true
        end
        
        # Reload room to get fresh data
        room.refresh
        initial_participant_count = room.participants.count
        
        # Test leaving room with non-administrator users
        leaving_users = participant_users.sample(rand(1..participant_users.length))
        
        leaving_users.each do |user|
          # Record state before leaving
          current_participant_count = room.participants.count
          current_participants = room.participants.map(&:user_id)
          
          # Verify user is currently a participant
          expect(room.has_participant?(user)).to be true
          
          # User leaves room
          result = RoomManager.leave_room(user, room.id)
          
          # Verify leave was successful
          expect(result[:success]).to be true
          expect(result[:room]).not_to be_nil
          
          # Reload room to get fresh data
          room.refresh
          
          # Verify participant list is correctly updated
          expect(room.participants.count).to eq(current_participant_count - 1)
          expect(room.has_participant?(user)).to be false
          expect(room.participants.map(&:user_id)).not_to include(user.id)
          
          # Verify all other participants are still there
          remaining_participants = current_participants - [user.id]
          remaining_participants.each do |participant_id|
            expect(room.participants.map(&:user_id)).to include(participant_id)
          end
          
          # Verify room state consistency
          expect(room.participant_count).to eq(room.participants.count)
          
          # Verify administrator is still there
          expect(room.has_participant?(admin_user)).to be true
          expect(room.administered_by?(admin_user)).to be true
        end
        
        # Final verification - administrator should still be there, others who left should be gone
        expect(room.has_participant?(admin_user)).to be true
        leaving_users.each do |user|
          expect(room.has_participant?(user)).to be false
        end
        
        # Remaining participants should still be there
        remaining_users = participant_users - leaving_users
        remaining_users.each do |user|
          expect(room.has_participant?(user)).to be true
        end
      }
    end

    it 'prevents administrator from leaving their own room' do
      test_instance = self
      
      property_of {
        # Generate room data and administrator
        room_data = test_instance.generate_room_data
        admin_data = test_instance.generate_user_data
        [room_data, admin_data]
      }.check(50) { |room_data, admin_data|
        # Create administrator user and room
        admin_user = create_test_user(admin_data)
        room = create_test_room(room_data, admin_user)
        
        # Verify administrator is a participant
        expect(room.has_participant?(admin_user)).to be true
        expect(room.administered_by?(admin_user)).to be true
        
        # Record initial state
        initial_participant_count = room.participants.count
        
        # Attempt to leave room as administrator
        result = RoomManager.leave_room(admin_user, room.id)
        
        # Verify leave was rejected
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Administrator cannot leave their own room')
        
        # Reload room to verify no changes
        room.refresh
        
        # Verify administrator is still a participant
        expect(room.has_participant?(admin_user)).to be true
        expect(room.administered_by?(admin_user)).to be true
        expect(room.participants.count).to eq(initial_participant_count)
      }
    end

    it 'prevents duplicate room membership for any user' do
      test_instance = self
      
      property_of {
        # Generate room and user data
        room_data = test_instance.generate_room_data
        user_data = test_instance.generate_user_data
        admin_data = test_instance.generate_user_data
        [room_data, user_data, admin_data]
      }.check(50) { |room_data, user_data, admin_data|
        # Create users and room
        user = create_test_user(user_data)
        admin_user = create_test_user(admin_data)
        room = create_test_room(room_data, admin_user)
        
        # First join should succeed
        result1 = RoomManager.join_room(user, room.id)
        expect(result1[:success]).to be true
        
        # Reload room
        room.refresh
        initial_participant_count = room.participants.count
        
        # Verify user is now a participant
        expect(room.has_participant?(user)).to be true
        
        # Second join attempt should fail
        result2 = RoomManager.join_room(user, room.id)
        expect(result2[:success]).to be false
        expect(result2[:error]).to eq('Already a participant in this room')
        
        # Reload room to verify no changes
        room.refresh
        
        # Verify participant count hasn't changed
        expect(room.participants.count).to eq(initial_participant_count)
        expect(room.has_participant?(user)).to be true
        
        # Verify no duplicate participant records
        user_participants = room.participants.select { |p| p.user_id == user.id }
        expect(user_participants.length).to eq(1)
      }
    end

    it 'handles non-participant users attempting to leave rooms' do
      test_instance = self
      
      property_of {
        # Generate room and users
        room_data = test_instance.generate_room_data
        admin_data = test_instance.generate_user_data
        non_participant_data = test_instance.generate_user_data
        [room_data, admin_data, non_participant_data]
      }.check(50) { |room_data, admin_data, non_participant_data|
        # Create users and room
        admin_user = create_test_user(admin_data)
        non_participant = create_test_user(non_participant_data)
        room = create_test_room(room_data, admin_user)
        
        # Verify non-participant is not in room
        expect(room.has_participant?(non_participant)).to be false
        
        # Record initial state
        initial_participant_count = room.participants.count
        
        # Attempt to leave room as non-participant
        result = RoomManager.leave_room(non_participant, room.id)
        
        # Verify leave was rejected
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Not a participant in this room')
        
        # Reload room to verify no changes
        room.refresh
        
        # Verify room state is unchanged
        expect(room.participants.count).to eq(initial_participant_count)
        expect(room.has_participant?(non_participant)).to be false
        expect(room.has_participant?(admin_user)).to be true
      }
    end

    it 'maintains accurate room state across multiple membership operations' do
      test_instance = self
      
      property_of {
        # Generate complex scenario with multiple operations
        room_data = test_instance.generate_room_data
        users_data = test_instance.generate_multiple_users(rand(5..10))
        operations = test_instance.generate_membership_operations(users_data.length)
        [room_data, users_data, operations]
      }.check(50) { |room_data, users_data, operations|
        # Create users and room
        users = users_data.map { |user_data| create_test_user(user_data) }
        admin_user = users.first
        room = create_test_room(room_data, admin_user)
        
        # Track expected state
        expected_participants = Set.new([admin_user.id])
        
        # Execute operations
        operations.each do |operation|
          user_index = operation[:user_index] % users.length
          user = users[user_index]
          action = operation[:action]
          
          case action
          when :join
            if user.id != admin_user.id && !expected_participants.include?(user.id)
              # Should succeed
              result = RoomManager.join_room(user, room.id)
              expect(result[:success]).to be true
              expected_participants.add(user.id)
            else
              # Should fail (already participant or admin trying to join again)
              result = RoomManager.join_room(user, room.id)
              expect(result[:success]).to be false
            end
            
          when :leave
            if user.id != admin_user.id && expected_participants.include?(user.id)
              # Should succeed
              result = RoomManager.leave_room(user, room.id)
              expect(result[:success]).to be true
              expected_participants.delete(user.id)
            else
              # Should fail (not participant or admin trying to leave)
              result = RoomManager.leave_room(user, room.id)
              expect(result[:success]).to be false
            end
          end
          
          # Verify room state matches expectations after each operation
          room.refresh
          actual_participants = Set.new(room.participants.map(&:user_id))
          expect(actual_participants).to eq(expected_participants)
          expect(room.participant_count).to eq(expected_participants.size)
          
          # Verify administrator is always present
          expect(expected_participants).to include(admin_user.id)
          expect(room.has_participant?(admin_user)).to be true
          expect(room.administered_by?(admin_user)).to be true
        end
        
        # Final state verification
        room.refresh
        expect(room.participants.count).to eq(expected_participants.size)
        expected_participants.each do |user_id|
          user = users.find { |u| u.id == user_id }
          expect(room.has_participant?(user)).to be true
        end
      }
    end

    it 'handles room membership with nonexistent rooms gracefully' do
      test_instance = self
      
      property_of {
        # Generate user and nonexistent room ID
        user_data = test_instance.generate_user_data
        nonexistent_room_id = SecureRandom.uuid
        [user_data, nonexistent_room_id]
      }.check(50) { |user_data, nonexistent_room_id|
        # Create user
        user = create_test_user(user_data)
        
        # Attempt to join nonexistent room
        join_result = RoomManager.join_room(user, nonexistent_room_id)
        expect(join_result[:success]).to be false
        expect(join_result[:error]).to eq('Room not found')
        
        # Attempt to leave nonexistent room
        leave_result = RoomManager.leave_room(user, nonexistent_room_id)
        expect(leave_result[:success]).to be false
        expect(leave_result[:error]).to eq('Room not found')
      }
    end

    it 'maintains participant data integrity across membership changes' do
      test_instance = self
      
      property_of {
        # Generate room with participants
        room_data = test_instance.generate_room_data
        users_data = test_instance.generate_multiple_users(rand(3..5))
        [room_data, users_data]
      }.check(50) { |room_data, users_data|
        # Create users and room
        users = users_data.map { |user_data| create_test_user(user_data) }
        admin_user = users.first
        room = create_test_room(room_data, admin_user)
        
        # Add participants and verify data integrity
        participant_users = users[1..-1]
        participant_users.each do |user|
          join_time = Time.now
          result = RoomManager.join_room(user, room.id)
          expect(result[:success]).to be true
          
          # Verify participant record integrity
          room.refresh
          participant = room.participants.find { |p| p.user_id == user.id }
          expect(participant).not_to be_nil
          expect(participant.room_id).to eq(room.id)
          expect(participant.user_id).to eq(user.id)
          expect(participant.joined_at).to be_within(5).of(join_time)
          expect(participant.administrator?).to be false
          
          # Verify participant hash serialization
          participant_hash = participant.to_hash
          expect(participant_hash[:id]).to eq(participant.id)
          expect(participant_hash[:room_id]).to eq(room.id)
          expect(participant_hash[:user_id]).to eq(user.id)
          expect(participant_hash[:user]).to eq(user.to_hash)
          expect(participant_hash[:is_administrator]).to be false
        end
        
        # Verify administrator participant data
        admin_participant = room.participants.find { |p| p.user_id == admin_user.id }
        expect(admin_participant).not_to be_nil
        expect(admin_participant.administrator?).to be true
        expect(admin_participant.to_hash[:is_administrator]).to be true
        
        # Remove participants and verify cleanup
        participant_users.each do |user|
          result = RoomManager.leave_room(user, room.id)
          expect(result[:success]).to be true
          
          # Verify participant record is removed
          room.refresh
          participant = room.participants.find { |p| p.user_id == user.id }
          expect(participant).to be_nil
          
          # Verify database record is removed
          db_participant = RoomParticipant.where(room_id: room.id, user_id: user.id).first
          expect(db_participant).to be_nil
        end
        
        # Verify only administrator remains
        room.refresh
        expect(room.participants.count).to eq(1)
        expect(room.participants.first.user_id).to eq(admin_user.id)
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

  def generate_membership_operations(user_count)
    operations = []
    operation_count = rand(10..20)
    
    operation_count.times do
      operations << {
        user_index: rand(0...user_count),
        action: [:join, :leave].sample
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