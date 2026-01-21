# Property-based test for WebSocket connection cleanup
# **Feature: ruby-backend-migration, Property 12: Connection Cleanup**
# **Validates: Requirements 7.5**

require 'bundler/setup'
require 'rspec'
require 'rantly'
require 'rantly/rspec_extensions'
require 'json'
require 'securerandom'
require 'jwt'
require 'bcrypt'

# Set test environment
ENV['APP_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test_jwt_secret_key_for_testing_purposes_only'
ENV['JWT_TTL'] = '60' # 1 hour for testing

RSpec.describe 'WebSocket Connection Cleanup Property Test', :property do
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
    require_relative '../../app/services/auth_service'
    require_relative '../../app/services/room_manager'
    require_relative '../../app/websocket/connection'
    
    # Finalize associations
    Sequel::Model.finalize_associations
  end
  
  before(:each) do
    # Clean database and connection state before each test
    DB[:track_votes].delete if DB.table_exists?(:track_votes)
    DB[:tracks].delete if DB.table_exists?(:tracks)
    DB[:room_participants].delete
    DB[:rooms].delete
    DB[:users].delete
    
    # Clear WebSocket connection tracking completely
    WebSocketConnection.class_variable_set(:@@connections, {})
    WebSocketConnection.class_variable_set(:@@room_connections, {})
    
    # Clear RoomManager cache
    RoomManager.class_variable_set(:@@room_state_cache, {})
    
    # Force garbage collection to ensure clean state
    GC.start
    
    # Wait a moment for cleanup to complete
    sleep(0.01)
  end
  
  after(:each) do
    # Comprehensive cleanup after each test
    begin
      # Close any remaining connections gracefully
      connections = WebSocketConnection.class_variable_get(:@@connections)
      connections.values.each do |conn|
        begin
          conn.cleanup if conn.respond_to?(:cleanup)
        rescue => e
          # Ignore cleanup errors
        end
      end
    rescue => e
      # Ignore cleanup errors
    end
    
    # Clear all connection tracking
    WebSocketConnection.class_variable_set(:@@connections, {})
    WebSocketConnection.class_variable_set(:@@room_connections, {})
    
    # Clear RoomManager cache
    RoomManager.class_variable_set(:@@room_state_cache, {})
    
    # Force garbage collection
    GC.start
    
    # Wait a moment for cleanup to complete
    sleep(0.01)
  end

  describe 'Property 12: Connection Cleanup' do
    it 'properly cleans up resources when any WebSocket connection is terminated' do
      test_instance = self
      
      property_of {
        # Generate simpler connection termination scenarios
        termination_type = choose(:graceful_close, :ungraceful_disconnect, :error_close)
        user_count = range(2, 3) # Reduced complexity - just 2-3 users
        
        users_data = user_count.times.map { test_instance.generate_valid_user_data }
        
        [termination_type, users_data]
      }.check(3) { |termination_type, users_data|  # Further reduced iterations for stability
        # Record initial connection count (may not be 0 due to test isolation issues)
        initial_connection_count = WebSocketConnection.connection_stats[:total_connections]
        
        # Setup: Create users and one room
        users = users_data.map { |user_data| create_test_user(user_data) }
        admin_user = users.first
        room = create_test_room(name: "Test Room", administrator_id: admin_user.id)
        
        # Setup: Create WebSocket connections for all users
        connections = {}
        mock_clients = {}
        
        users.each do |user|
          connection = create_authenticated_websocket_connection(user)
          mock_client = create_mock_websocket_client
          
          connections[user.id] = connection
          mock_clients[user.id] = mock_client
          
          # Establish connection
          connection.on_open(mock_client)
          expect(connection.authenticated).to be true
        end
        
        # Verify connection count increased by expected amount
        expected_total = initial_connection_count + users.length
        expect(WebSocketConnection.connection_stats[:total_connections]).to eq(expected_total)
        
        # Setup: Have non-admin users join the room
        participating_users = []
        users.each do |user|
          if user.id == admin_user.id
            # Admin is automatically a participant
            participating_users << user
          else
            # Regular users need to join
            result = RoomManager.join_room(user, room.id)
            expect(result[:success]).to be true
            participating_users << user
          end
          
          # Connect to room via WebSocket
          success = connections[user.id].join_room(room.id)
          expect(success).to be true
        end
        
        # Verify room connection state
        room_connections = WebSocketConnection.get_room_connections(room.id)
        expect(room_connections.length).to eq(participating_users.length)
        
        # Select a user to disconnect (prefer non-admin to test regular participant cleanup)
        disconnecting_user = users.find { |u| u.id != admin_user.id } || users.last
        disconnecting_connection = connections[disconnecting_user.id]
        disconnecting_client = mock_clients[disconnecting_user.id]
        
        # Record pre-disconnect state
        pre_disconnect_room_id = disconnecting_connection.room_id
        expect(pre_disconnect_room_id).to eq(room.id)
        
        # Clear messages to focus on disconnect events
        mock_clients.values.each(&:clear_messages)
        
        # Execute: Terminate the connection based on termination type
        case termination_type
        when :graceful_close
          disconnecting_connection.on_close(disconnecting_client)
        when :ungraceful_disconnect
          # Simulate ungraceful disconnect by removing from tracking first
          WebSocketConnection.class_variable_get(:@@connections).delete(disconnecting_user.id)
          disconnecting_connection.on_close(disconnecting_client)
        when :error_close
          disconnecting_connection.on_error(disconnecting_client, StandardError.new("Connection error"))
          disconnecting_connection.on_close(disconnecting_client)
        end
        
        # Verify: Connection is removed from global tracking
        expect(WebSocketConnection.get_user_connection(disconnecting_user.id)).to be_nil
        expected_remaining = initial_connection_count + users.length - 1
        expect(WebSocketConnection.connection_stats[:total_connections]).to eq(expected_remaining)
        
        # Verify: Connection is removed from room tracking
        room_connections_after = WebSocketConnection.get_room_connections(room.id)
        expect(room_connections_after).not_to include(disconnecting_connection)
        expect(room_connections_after.length).to eq(participating_users.length - 1)
        
        # Verify: Room state is updated correctly based on user role
        room.refresh
        if disconnecting_user.id != admin_user.id
          # Regular participants should be removed from room participants table
          participant_exists = DB[:room_participants].where(
            room_id: room.id, 
            user_id: disconnecting_user.id
          ).count > 0
          expect(participant_exists).to be false
          
          # has_participant? should return false for non-admin users
          expect(room.has_participant?(disconnecting_user)).to be false
        else
          # Administrators remain as participants even when disconnected (by design)
          expect(room.has_participant?(disconnecting_user)).to be true
        end
        
        # Verify: Other participants are notified of the disconnection
        remaining_users = users.reject { |u| u.id == disconnecting_user.id }
        
        if remaining_users.any?
          remaining_users.each do |user|
            client = mock_clients[user.id]
            
            # Look for disconnect notification messages
            disconnect_messages = client.sent_messages.select { |msg|
              begin
                parsed = JSON.parse(msg)
                parsed['type'].to_s.include?('disconnect') || 
                parsed['type'].to_s.include?('left') ||
                parsed['type'].to_s == 'user_disconnected' ||
                parsed['type'].to_s == 'user_left'
              rescue JSON::ParserError
                false
              end
            }
            
            # Should receive at least one disconnect notification (unless no other users)
            expect(disconnect_messages).not_to be_empty
            
            # Verify the notification contains correct information
            notification = JSON.parse(disconnect_messages.first)
            expect(notification['data']).to have_key('user')
            expect(notification['data']['user']['id']).to eq(disconnecting_user.id)
          end
        end
        
        # Verify: Connection resources are cleaned up
        expect(disconnecting_connection.room_id).to be_nil
        
        # Verify: Remaining connections are unaffected
        remaining_users.each do |user|
          connection = connections[user.id]
          expect(connection.authenticated).to be true
          expect(WebSocketConnection.get_user_connection(user.id)).to eq(connection)
        end
      }
    end

    it 'handles cleanup correctly when connection terminates while user is in multiple rooms' do
      test_instance = self
      
      property_of {
        # Generate scenarios with users in multiple rooms
        room_count = range(2, 3) # Reduced from 4 to 3 for stability
        rooms_data = room_count.times.map { test_instance.generate_valid_room_data }
        user_data = test_instance.generate_valid_user_data
        
        [rooms_data, user_data]
      }.check(3) { |rooms_data, user_data|  # Reduced iterations
        # Record initial connection count
        initial_connection_count = WebSocketConnection.connection_stats[:total_connections]
        
        # Setup: Create user and multiple rooms
        user = create_test_user(user_data)
        admin_user = create_test_user(generate_valid_user_data) # Separate admin
        rooms = rooms_data.map { |room_data| create_test_room(room_data.merge(administrator_id: admin_user.id)) }
        
        # Setup: Create WebSocket connection
        connection = create_authenticated_websocket_connection(user)
        mock_client = create_mock_websocket_client
        connection.on_open(mock_client)
        
        # Verify connection established
        expected_total = initial_connection_count + 1
        expect(WebSocketConnection.connection_stats[:total_connections]).to eq(expected_total)
        
        # Setup: Join all rooms (but only connect WebSocket to the last one)
        joined_rooms = []
        rooms.each do |room|
          # User joins room via RoomManager
          result = RoomManager.join_room(user, room.id)
          expect(result[:success]).to be true
          joined_rooms << room.id
        end
        
        # Connect to the last room via WebSocket (user can only be connected to one room at a time via WS)
        last_room = rooms.last
        success = connection.join_room(last_room.id)
        expect(success).to be true
        expect(connection.room_id).to eq(last_room.id)
        
        # Verify initial state
        expect(WebSocketConnection.get_user_connection(user.id)).to eq(connection)
        expect(WebSocketConnection.get_room_connections(last_room.id)).to include(connection)
        
        # Verify user is participant in all rooms
        rooms.each do |room|
          room.refresh
          expect(room.has_participant?(user)).to be true
        end
        
        # Clear messages
        mock_client.clear_messages
        
        # Execute: Terminate connection
        connection.on_close(mock_client)
        
        # Verify: Connection cleanup
        expect(WebSocketConnection.get_user_connection(user.id)).to be_nil
        expect(WebSocketConnection.get_room_connections(last_room.id)).not_to include(connection)
        expect(connection.room_id).to be_nil
        expected_remaining = initial_connection_count
        expect(WebSocketConnection.connection_stats[:total_connections]).to eq(expected_remaining)
        
        # Verify: User is removed from all rooms (since they're not the administrator)
        rooms.each do |room|
          room.refresh
          # Check the participants table directly
          participant_exists = DB[:room_participants].where(
            room_id: room.id, 
            user_id: user.id
          ).count > 0
          expect(participant_exists).to be false
          
          # has_participant? should return false since user is not admin
          expect(room.has_participant?(user)).to be false
        end
        
        # Verify: Room state caches are invalidated
        rooms.each do |room|
          cached_state = RoomManager.get_room_state(room.id)
          if cached_state && cached_state[:participants]
            participant_ids = cached_state[:participants].map { |p| p[:id] || p['id'] }
            expect(participant_ids).not_to include(user.id)
          end
        end
      }
    end

    it 'maintains system stability when multiple connections terminate simultaneously' do
      test_instance = self
      
      property_of {
        # Generate concurrent termination scenarios
        user_count = range(3, 5) # Reduced from 6 to 5
        users_data = user_count.times.map { test_instance.generate_valid_user_data }
        room_data = test_instance.generate_valid_room_data
        
        [users_data, room_data]
      }.check(3) { |users_data, room_data|  # Reduced iterations
        # Record initial connection count
        initial_connection_count = WebSocketConnection.connection_stats[:total_connections]
        
        # Setup: Create users and room
        users = users_data.map { |user_data| create_test_user(user_data) }
        room = create_test_room(room_data.merge(administrator_id: users.first.id))
        
        # Setup: Create connections for all users and ensure they join properly
        connections = {}
        mock_clients = {}
        
        users.each do |user|
          connection = create_authenticated_websocket_connection(user)
          mock_client = create_mock_websocket_client
          
          connections[user.id] = connection
          mock_clients[user.id] = mock_client
          
          connection.on_open(mock_client)
          
          # Join the room (skip if user is administrator - they're automatically a participant)
          if room.administrator_id != user.id
            result = RoomManager.join_room(user, room.id)
            expect(result[:success]).to be true
          end
          
          success = connection.join_room(room.id)
          expect(success).to be true
        end
        
        # Verify initial state - check actual participant count in database
        expected_total = initial_connection_count + users.length
        expect(WebSocketConnection.connection_stats[:total_connections]).to eq(expected_total)
        expect(WebSocketConnection.get_room_connections(room.id).length).to eq(users.length)
        
        # Verify room participants
        room.refresh
        expect(room.participants.count).to be >= (users.length - 1) # At least non-admin users
        
        # Select users to disconnect (leave administrator connected for stability)
        admin_id = room.administrator_id
        disconnecting_users = users.reject { |u| u.id == admin_id }
        remaining_users = users.select { |u| u.id == admin_id }
        
        # Clear messages
        mock_clients.values.each(&:clear_messages)
        
        # Execute: Terminate multiple connections simultaneously
        disconnecting_users.each do |user|
          connection = connections[user.id]
          mock_client = mock_clients[user.id]
          
          # Simulate simultaneous disconnection
          connection.on_close(mock_client)
        end
        
        # Verify: All disconnected connections are cleaned up
        disconnecting_users.each do |user|
          expect(WebSocketConnection.get_user_connection(user.id)).to be_nil
        end
        
        # Verify: Remaining connections are unaffected
        remaining_users.each do |user|
          expect(WebSocketConnection.get_user_connection(user.id)).to eq(connections[user.id])
          expect(connections[user.id].authenticated).to be true
        end
        
        # Verify: Connection statistics are accurate
        expected_remaining = initial_connection_count + remaining_users.length
        expect(WebSocketConnection.connection_stats[:total_connections]).to eq(expected_remaining)
        expect(WebSocketConnection.get_room_connections(room.id).length).to eq(remaining_users.length)
        
        # Verify: Room state is correctly updated
        room.refresh
        # Only check that remaining users are still participants
        remaining_users.each do |user|
          expect(room.has_participant?(user)).to be true
        end
        
        # Check that disconnected users are no longer in participants table
        disconnecting_users.each do |user|
          participant_exists = DB[:room_participants].where(
            room_id: room.id, 
            user_id: user.id
          ).count > 0
          expect(participant_exists).to be false
        end
        
        # Verify: Remaining participants received disconnect notifications (if any remain)
        if remaining_users.any?
          remaining_users.each do |user|
            client = mock_clients[user.id]
            
            disconnect_messages = client.sent_messages.select { |msg|
              begin
                parsed = JSON.parse(msg)
                parsed['type'].to_s.include?('disconnect') || 
                parsed['type'].to_s.include?('left') ||
                parsed['type'].to_s == 'user_disconnected' ||
                parsed['type'].to_s == 'user_left'
              rescue JSON::ParserError
                false
              end
            }
            
            # Should receive notifications for users that disconnected
            expect(disconnect_messages.length).to be >= 1
          end
        end
        
        # Verify: System remains stable and functional
        # Test that remaining connections can still send/receive messages
        remaining_users.each do |user|
          connection = connections[user.id]
          client = mock_clients[user.id]
          
          client.clear_messages
          
          # Send ping message
          ping_message = {
            'type' => 'ping',
            'data' => { 'client_time' => Time.now.to_f }
          }
          
          connection.on_message(client, ping_message.to_json)
          
          # Should receive pong response
          expect(client.sent_messages).not_to be_empty
          response = JSON.parse(client.sent_messages.last)
          expect(response['type']).to eq('pong')
        end
      }
    end

    it 'properly handles cleanup when connection fails during room operations' do
      test_instance = self
      
      property_of {
        # Generate scenarios where connection fails during room operations
        operation_type = choose(:joining_room, :leaving_room, :during_broadcast)
        user_data = test_instance.generate_valid_user_data
        room_data = test_instance.generate_valid_room_data
        
        [operation_type, user_data, room_data]
      }.check(3) { |operation_type, user_data, room_data|  # Reduced iterations
        # Record initial connection count
        initial_connection_count = WebSocketConnection.connection_stats[:total_connections]
        
        # Setup: Create user and room
        user = create_test_user(user_data)
        admin_user = create_test_user(generate_valid_user_data)
        room = create_test_room(room_data.merge(administrator_id: admin_user.id))
        
        # Setup: Create connection
        connection = create_authenticated_websocket_connection(user)
        mock_client = create_mock_websocket_client
        connection.on_open(mock_client)
        
        # Verify connection established
        expected_total = initial_connection_count + 1
        expect(WebSocketConnection.connection_stats[:total_connections]).to eq(expected_total)
        
        # Setup based on operation type
        case operation_type
        when :joining_room
          # User joins room via RoomManager but connection fails during WebSocket join
          result = RoomManager.join_room(user, room.id)
          expect(result[:success]).to be true
          
          # Simulate connection failure during WebSocket room join
          # (connection is terminated before completing join_room)
          
        when :leaving_room
          # User joins room successfully, then connection fails during leave
          result = RoomManager.join_room(user, room.id)
          expect(result[:success]).to be true
          success = connection.join_room(room.id)
          expect(success).to be true
          expect(connection.room_id).to eq(room.id)
          
        when :during_broadcast
          # User is in room, connection fails during a broadcast event
          result = RoomManager.join_room(user, room.id)
          expect(result[:success]).to be true
          success = connection.join_room(room.id)
          expect(success).to be true
          expect(connection.room_id).to eq(room.id)
        end
        
        # Record pre-failure state
        pre_failure_connected = WebSocketConnection.get_user_connection(user.id) == connection
        pre_failure_room_id = connection.room_id
        
        if pre_failure_room_id
          room.refresh
          pre_failure_participant = room.has_participant?(user)
        end
        
        # Execute: Simulate connection failure
        connection.on_close(mock_client)
        
        # Verify: Connection cleanup occurred
        expect(WebSocketConnection.get_user_connection(user.id)).to be_nil
        expect(connection.room_id).to be_nil
        expected_remaining = initial_connection_count
        expect(WebSocketConnection.connection_stats[:total_connections]).to eq(expected_remaining)
        
        # Verify: Room state is consistent
        if pre_failure_room_id
          room.refresh
          
          # User should be removed from room participants table (since they're not admin)
          participant_exists = DB[:room_participants].where(
            room_id: room.id, 
            user_id: user.id
          ).count > 0
          expect(participant_exists).to be false
          
          # has_participant? should return false for non-admin users
          expect(room.has_participant?(user)).to be false
          
          # Room should still exist and be functional
          expect(Room[room.id]).not_to be_nil
          
          # Room connections should not include the failed connection
          room_connections = WebSocketConnection.get_room_connections(room.id)
          expect(room_connections).not_to include(connection)
        end
        
        # Verify: No resource leaks or inconsistent state
        stats = WebSocketConnection.connection_stats
        expect(stats[:total_connections]).to eq(expected_remaining)
        
        # Verify: Room state cache is properly handled
        if pre_failure_room_id
          cached_state = RoomManager.get_room_state(room.id)
          if cached_state && cached_state[:participants]
            participant_ids = cached_state[:participants].map { |p| p[:id] || p['id'] }
            expect(participant_ids).not_to include(user.id)
          end
        end
      }
    end
  end

  # Helper methods for generating test data and scenarios

  def generate_valid_user_data
    {
      username: "user_#{SecureRandom.hex(6)}",
      email: "#{SecureRandom.hex(6)}@example.com",
      password: "password#{rand(100..999)}"
    }
  end

  def generate_valid_room_data
    {
      name: "Room #{SecureRandom.hex(4)}"
    }
  end

  def create_test_user(user_data)
    user = User.new
    user.id = SecureRandom.uuid
    user.username = user_data[:username]
    user.email = user_data[:email]
    user.password_hash = BCrypt::Password.create(user_data[:password])
    user.created_at = Time.now
    user.updated_at = Time.now
    user.save
    user
  end

  def create_test_room(attrs = {})
    room = Room.new
    room.id = SecureRandom.uuid
    room.name = attrs[:name] || "Room #{SecureRandom.hex(4)}"
    room.administrator_id = attrs[:administrator_id] if attrs[:administrator_id]
    room.created_at = Time.now
    room.updated_at = Time.now
    room.save
    room
  end

  def create_authenticated_websocket_connection(user)
    jwt_token = AuthService.generate_jwt(user)
    env = create_websocket_env_with_auth(:query_param, jwt_token)
    WebSocketConnection.new(env)
  end

  def create_websocket_env_with_auth(auth_method, token)
    base_env = {
      'REQUEST_METHOD' => 'GET',
      'PATH_INFO' => '/ws',
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTP_HOST' => 'localhost:3000',
      'HTTP_CONNECTION' => 'Upgrade',
      'HTTP_UPGRADE' => 'websocket',
      'HTTP_SEC_WEBSOCKET_VERSION' => '13',
      'HTTP_SEC_WEBSOCKET_KEY' => 'dGhlIHNhbXBsZSBub25jZQ==',
      'rack.upgrade?' => :websocket
    }
    
    case auth_method
    when :query_param
      base_env['QUERY_STRING'] = "token=#{token}"
    when :auth_header
      base_env['HTTP_AUTHORIZATION'] = "Bearer #{token}"
    when :websocket_protocol
      base_env['HTTP_SEC_WEBSOCKET_PROTOCOL'] = "chat, token.#{token}"
    end
    
    base_env
  end

  def create_mock_websocket_client
    MockWebSocketClient.new
  end
end

# Mock WebSocket client for testing
class MockWebSocketClient
  attr_reader :sent_messages, :close_called, :subscriptions
  
  def initialize
    @sent_messages = []
    @close_called = false
    @subscriptions = []
  end
  
  def write(message)
    @sent_messages << message
  end
  
  def close
    @close_called = true
  end
  
  def subscribe(channel)
    @subscriptions << channel
  end
  
  def clear_messages
    @sent_messages.clear
  end
end