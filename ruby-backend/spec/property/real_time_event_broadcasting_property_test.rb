# Property-Based Test for Real-time Event Broadcasting
# **Feature: ruby-backend-migration, Property 10: Real-time Event Broadcasting**
# **Validates: Requirements 3.5, 4.5, 5.5, 6.4, 6.5, 11.1, 11.2, 11.3, 11.4**

require 'bundler/setup'
require 'rspec'
require 'rantly'
require 'rantly/rspec_extensions'
require 'securerandom'
require 'json'
require 'set'
require 'timeout'

# Set test environment
ENV['APP_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test_jwt_secret_key_for_testing_purposes_only'
ENV['JWT_TTL'] = '60' # 1 hour for testing

RSpec.describe 'Real-time Event Broadcasting Property Test', :property do
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
    require_relative '../../app/services/event_broadcaster'
    require_relative '../../app/services/room_manager'
    require_relative '../../app/services/auth_service'
    require_relative '../../app/websocket/connection'
    require_relative '../../app/controllers/track_controller'
    require_relative '../../app/controllers/playback_controller'
    
    # Mock Iodine for testing
    module Iodine
      @@published_messages = []
      
      def self.publish(channel, message)
        @@published_messages << {
          channel: channel,
          message: message,
          timestamp: Time.now.to_f
        }
        true
      end
      
      def self.get_published_messages
        @@published_messages
      end
      
      def self.clear_published_messages
        @@published_messages.clear
      end
      
      def self.run_after(milliseconds, &block)
        # Mock timer - execute immediately for testing
        block.call if block
      end
    end
    
    # Mock WebSocket connections for testing
    class MockWebSocketConnection
      attr_reader :user_id, :room_id, :messages_received
      
      def initialize(user_id, room_id = nil)
        @user_id = user_id
        @room_id = room_id
        @messages_received = []
        @connected_at = Time.now
      end
      
      def send_message(message)
        @messages_received << {
          message: message,
          received_at: Time.now.to_f
        }
      end
      
      def join_room(room_id)
        @room_id = room_id
      end
      
      def leave_room
        @room_id = nil
      end
      
      def get_messages_of_type(event_type)
        @messages_received.select { |msg| msg[:message][:type] == event_type }
      end
      
      def clear_messages
        @messages_received.clear
      end
    end
    
    # Override WebSocketConnection for testing
    class WebSocketConnection
      @@mock_connections = {}
      @@room_connections = {}
      
      def self.create_mock_connection(user_id, room_id = nil)
        connection = MockWebSocketConnection.new(user_id, room_id)
        @@mock_connections[user_id] = connection
        
        if room_id
          @@room_connections[room_id] ||= []
          @@room_connections[room_id] << connection
        end
        
        connection
      end
      
      def self.get_user_connection(user_id)
        @@mock_connections[user_id]
      end
      
      def self.get_room_connections(room_id)
        @@room_connections[room_id] || []
      end
      
      def self.broadcast_to_room(room_id, message)
        connections = get_room_connections(room_id)
        connections.each { |conn| conn.send_message(message) }
        connections.any?
      end
      
      def self.clear_mock_connections
        @@mock_connections.clear
        @@room_connections.clear
      end
      
      def self.connection_stats
        {
          total_connections: @@mock_connections.length,
          room_connections: @@room_connections.transform_values(&:length),
          authenticated_users: @@mock_connections.keys
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
    begin
      DB[:track_votes].delete
      DB[:tracks].delete
      DB[:room_participants].delete
      DB[:rooms].delete
      DB[:users].delete
    rescue => e
      puts "Warning: Database cleanup failed: #{e.message}"
    end
    
    # Clear mock connections and published messages
    WebSocketConnection.clear_mock_connections
    Iodine.clear_published_messages
  end

  describe 'Property 10: Real-time Event Broadcasting' do
    it 'broadcasts user join/leave events to all room participants within reasonable time window' do
      test_instance = self
      
      property_of {
        # Generate test scenario with room and multiple participants
        room_data = test_instance.generate_room_data
        participants_count = rand(3..8)
        participants_data = test_instance.generate_multiple_users(participants_count)
        join_leave_sequence = test_instance.generate_join_leave_sequence(participants_count, rand(5..12))
        [room_data, participants_data, join_leave_sequence]
      }.check(50) { |room_data, participants_data, join_leave_sequence|
        # Create users and room
        users = participants_data.map { |user_data| create_test_user(user_data) }
        admin_user = users.first
        room = create_test_room(room_data, admin_user)
        
        # Create WebSocket connections for all users
        connections = {}
        users.each do |user|
          connections[user.id] = WebSocketConnection.create_mock_connection(user.id, room.id)
        end
        
        # Execute join/leave sequence and verify real-time broadcasting
        join_leave_sequence.each_with_index do |operation, step|
          user_index = operation[:user_index] % users.length
          action = operation[:action]
          user = users[user_index]
          
          # Clear previous messages and published events
          connections.values.each(&:clear_messages)
          Iodine.clear_published_messages
          
          # Record timestamp before operation
          operation_start = Time.now.to_f
          
          case action
          when :join
            # User joins room (if not already joined)
            unless room.has_participant?(user)
              room.add_participant(user)
              
              # **Validates: Requirements 3.5, 11.1** - System SHALL broadcast user join events
              EventBroadcaster.broadcast_user_activity(room.id, :joined, user)
              
              # Verify Iodine pub/sub broadcasting occurred
              published_messages = Iodine.get_published_messages
              user_joined_message = published_messages.find do |msg|
                parsed = JSON.parse(msg[:message])
                parsed['type'] == 'user_joined' && parsed['data']['user']['id'] == user.id
              end
              
              expect(user_joined_message).not_to be_nil, "User join event not published via Iodine for step #{step}"
              expect(user_joined_message[:channel]).to eq("room_#{room.id}")
              
              # Verify WebSocket broadcasting occurred
              room_connections = WebSocketConnection.get_room_connections(room.id)
              room_connections.each do |connection|
                user_joined_messages = connection.get_messages_of_type('user_joined')
                expect(user_joined_messages).not_to be_empty, "User join event not received by connection #{connection.user_id}"
                
                message = user_joined_messages.first
                expect(message[:message][:data][:user][:id]).to eq(user.id)
                expect(message[:message][:data][:room_id]).to eq(room.id)
                
                # **Validates: Requirements 11.2** - Events delivered within reasonable time window
                delivery_time = message[:received_at] - operation_start
                expect(delivery_time).to be < 0.1, "User join event delivery too slow: #{delivery_time}s"
              end
            end
            
          when :leave
            # User leaves room (if currently joined)
            if room.has_participant?(user)
              room.remove_participant(user)
              
              # **Validates: Requirements 3.5, 11.1** - System SHALL broadcast user leave events
              EventBroadcaster.broadcast_user_activity(room.id, :left, user)
              
              # Verify Iodine pub/sub broadcasting occurred
              published_messages = Iodine.get_published_messages
              user_left_message = published_messages.find do |msg|
                parsed = JSON.parse(msg[:message])
                parsed['type'] == 'user_left' && parsed['data']['user']['id'] == user.id
              end
              
              expect(user_left_message).not_to be_nil, "User leave event not published via Iodine for step #{step}"
              expect(user_left_message[:channel]).to eq("room_#{room.id}")
              
              # Verify WebSocket broadcasting occurred
              room_connections = WebSocketConnection.get_room_connections(room.id)
              room_connections.each do |connection|
                user_left_messages = connection.get_messages_of_type('user_left')
                expect(user_left_messages).not_to be_empty, "User leave event not received by connection #{connection.user_id}"
                
                message = user_left_messages.first
                expect(message[:message][:data][:user][:id]).to eq(user.id)
                expect(message[:message][:data][:room_id]).to eq(room.id)
                
                # **Validates: Requirements 11.2** - Events delivered within reasonable time window
                delivery_time = message[:received_at] - operation_start
                expect(delivery_time).to be < 0.1, "User leave event delivery too slow: #{delivery_time}s"
              end
            end
          end
          
          # Verify all participants received the event (except for leave events where user is no longer in room)
          current_participants = room.participants
          current_participants.each do |participant|
            connection = connections[participant.id]
            next unless connection # Skip if connection doesn't exist
            expect(connection.messages_received).not_to be_empty, "Participant #{participant.username} did not receive any events"
          end
        end
      }
    end

    it 'broadcasts track addition events to all room participants within reasonable time window' do
      test_instance = self
      
      property_of {
        # Generate test scenario with room, participants, and track additions
        room_data = test_instance.generate_room_data
        participants_count = rand(3..6)
        participants_data = test_instance.generate_multiple_users(participants_count)
        tracks_count = rand(2..5)
        track_addition_sequence = test_instance.generate_track_addition_sequence(tracks_count, participants_count)
        [room_data, participants_data, track_addition_sequence]
      }.check(40) { |room_data, participants_data, track_addition_sequence|
        # Create users and room
        users = participants_data.map { |user_data| create_test_user(user_data) }
        admin_user = users.first
        room = create_test_room(room_data, admin_user)
        
        # Add all users as participants
        users[1..-1].each { |user| room.add_participant(user) }
        
        # Create WebSocket connections for all users
        connections = {}
        users.each do |user|
          connections[user.id] = WebSocketConnection.create_mock_connection(user.id, room.id)
        end
        
        # Execute track addition sequence and verify real-time broadcasting
        track_addition_sequence.each_with_index do |operation, step|
          uploader_index = operation[:uploader_index] % users.length
          uploader = users[uploader_index]
          
          # Clear previous messages and published events
          connections.values.each(&:clear_messages)
          Iodine.clear_published_messages
          
          # Record timestamp before operation
          operation_start = Time.now.to_f
          
          # Create and add track to room
          track = Track.create(
            id: SecureRandom.uuid,
            room_id: room.id,
            uploader_id: uploader.id,
            filename: "broadcast_test_track_#{step}.mp3",
            original_name: "Broadcast Test Track #{step}",
            file_path: "/tmp/broadcast_test_track_#{step}.mp3",
            duration_seconds: rand(60..300),
            file_size_bytes: rand(1_000_000..10_000_000),
            mime_type: 'audio/mpeg',
            vote_score: 0,
            created_at: Time.now
          )
          
          # **Validates: Requirements 4.5, 11.3** - System SHALL broadcast track addition events
          EventBroadcaster.broadcast_track_activity(room.id, :added, track, uploader)
          
          # Verify Iodine pub/sub broadcasting occurred
          published_messages = Iodine.get_published_messages
          track_added_message = published_messages.find do |msg|
            parsed = JSON.parse(msg[:message])
            parsed['type'] == 'track_added' && parsed['data']['track']['id'] == track.id
          end
          
          expect(track_added_message).not_to be_nil, "Track addition event not published via Iodine for step #{step}"
          expect(track_added_message[:channel]).to eq("room_#{room.id}")
          
          # Verify WebSocket broadcasting occurred to all participants
          room_connections = WebSocketConnection.get_room_connections(room.id)
          expect(room_connections.length).to be > 0, "No WebSocket connections found for room"
          
          room_connections.each do |connection|
            track_added_messages = connection.get_messages_of_type('track_added')
            expect(track_added_messages).not_to be_empty, "Track addition event not received by connection #{connection.user_id}"
            
            message = track_added_messages.first
            expect(message[:message][:data][:track][:id]).to eq(track.id)
            expect(message[:message][:data][:uploader][:id]).to eq(uploader.id)
            expect(message[:message][:data][:room_id]).to eq(room.id)
            
            # **Validates: Requirements 11.2** - Events delivered within reasonable time window
            delivery_time = message[:received_at] - operation_start
            expect(delivery_time).to be < 0.1, "Track addition event delivery too slow: #{delivery_time}s"
          end
          
          # Verify event contains required data
          parsed_message = JSON.parse(track_added_message[:message])
          expect(parsed_message['data']['track']['original_name']).to eq(track.original_name)
          expect(parsed_message['data']['uploader']['id']).to eq(uploader.id)
          expect(parsed_message['data']['room_id']).to eq(room.id)
        end
      }
    end

    it 'broadcasts voting events to all room participants within reasonable time window' do
      test_instance = self
      
      property_of {
        # Generate test scenario with room, participants, tracks, and voting
        room_data = test_instance.generate_room_data
        participants_count = rand(4..7)
        participants_data = test_instance.generate_multiple_users(participants_count)
        tracks_count = rand(3..5)
        voting_sequence = test_instance.generate_voting_sequence(tracks_count, participants_count, rand(8..15))
        [room_data, participants_data, tracks_count, voting_sequence]
      }.check(30) { |room_data, participants_data, tracks_count, voting_sequence|
        # Create users and room
        users = participants_data.map { |user_data| create_test_user(user_data) }
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
            filename: "voting_broadcast_track_#{i}.mp3",
            original_name: "Voting Broadcast Track #{i}",
            file_path: "/tmp/voting_broadcast_track_#{i}.mp3",
            duration_seconds: rand(60..300),
            file_size_bytes: rand(1_000_000..10_000_000),
            mime_type: 'audio/mpeg',
            vote_score: 0,
            created_at: Time.now + i
          )
          tracks << track
        end
        
        # Create WebSocket connections for all users
        connections = {}
        users.each do |user|
          connections[user.id] = WebSocketConnection.create_mock_connection(user.id, room.id)
        end
        
        # Execute voting sequence and verify real-time broadcasting
        voting_sequence.each_with_index do |operation, step|
          track_index = operation[:track_index] % tracks.length
          user_index = operation[:user_index] % users.length
          action = operation[:action]
          
          track = tracks[track_index]
          user = users[user_index]
          
          # Clear previous messages and published events
          connections.values.each(&:clear_messages)
          Iodine.clear_published_messages
          
          # Record timestamp before operation
          operation_start = Time.now.to_f
          
          case action
          when :vote
            # Check if user already voted
            user_had_voted = track.has_vote_from?(user)
            
            # Create vote if user hasn't voted yet
            unless user_had_voted
              TrackVote.create(
                id: SecureRandom.uuid,
                track_id: track.id,
                user_id: user.id,
                created_at: Time.now
              )
              
              # Update track vote score
              track.update(vote_score: track.votes.count)
              
              # **Validates: Requirements 6.4, 11.3** - System SHALL broadcast voting events
              EventBroadcaster.broadcast_track_activity(room.id, :voted, track, user)
              
              # Verify Iodine pub/sub broadcasting occurred
              published_messages = Iodine.get_published_messages
              track_voted_message = published_messages.find do |msg|
                parsed = JSON.parse(msg[:message])
                parsed['type'] == 'track_voted' && parsed['data']['track']['id'] == track.id
              end
              
              expect(track_voted_message).not_to be_nil, "Track voting event not published via Iodine for step #{step}"
              expect(track_voted_message[:channel]).to eq("room_#{room.id}")
              
              # Verify WebSocket broadcasting occurred to all participants
              room_connections = WebSocketConnection.get_room_connections(room.id)
              room_connections.each do |connection|
                track_voted_messages = connection.get_messages_of_type('track_voted')
                expect(track_voted_messages).not_to be_empty, "Track voting event not received by connection #{connection.user_id}"
                
                message = track_voted_messages.first
                expect(message[:message][:data][:track][:id]).to eq(track.id)
                expect(message[:message][:data][:voter][:id]).to eq(user.id)
                expect(message[:message][:data][:room_id]).to eq(room.id)
                
                # **Validates: Requirements 11.2** - Events delivered within reasonable time window
                delivery_time = message[:received_at] - operation_start
                expect(delivery_time).to be < 0.1, "Track voting event delivery too slow: #{delivery_time}s"
              end
            end
            
          when :unvote
            # Check if user has voted
            existing_vote = track.votes.find { |v| v.user_id == user.id }
            
            if existing_vote
              # Remove vote
              existing_vote.delete
              
              # Update track vote score
              track.update(vote_score: track.votes.count)
              
              # **Validates: Requirements 6.4, 11.3** - System SHALL broadcast unvoting events
              EventBroadcaster.broadcast_track_activity(room.id, :unvoted, track, user)
              
              # Verify Iodine pub/sub broadcasting occurred
              published_messages = Iodine.get_published_messages
              track_unvoted_message = published_messages.find do |msg|
                parsed = JSON.parse(msg[:message])
                parsed['type'] == 'track_unvoted' && parsed['data']['track']['id'] == track.id
              end
              
              expect(track_unvoted_message).not_to be_nil, "Track unvoting event not published via Iodine for step #{step}"
              expect(track_unvoted_message[:channel]).to eq("room_#{room.id}")
              
              # Verify WebSocket broadcasting occurred to all participants
              room_connections = WebSocketConnection.get_room_connections(room.id)
              room_connections.each do |connection|
                track_unvoted_messages = connection.get_messages_of_type('track_unvoted')
                expect(track_unvoted_messages).not_to be_empty, "Track unvoting event not received by connection #{connection.user_id}"
                
                message = track_unvoted_messages.first
                expect(message[:message][:data][:track][:id]).to eq(track.id)
                expect(message[:message][:data][:voter][:id]).to eq(user.id)
                expect(message[:message][:data][:room_id]).to eq(room.id)
                
                # **Validates: Requirements 11.2** - Events delivered within reasonable time window
                delivery_time = message[:received_at] - operation_start
                expect(delivery_time).to be < 0.1, "Track unvoting event delivery too slow: #{delivery_time}s"
              end
            end
          end
        end
      }
    end

    it 'broadcasts playback control events to all room participants within reasonable time window' do
      test_instance = self
      
      property_of {
        # Generate test scenario with room, participants, tracks, and playback controls
        room_data = test_instance.generate_room_data
        participants_count = rand(3..6)
        participants_data = test_instance.generate_multiple_users(participants_count)
        tracks_count = rand(2..4)
        playback_sequence = test_instance.generate_playback_control_sequence(tracks_count, rand(5..10))
        [room_data, participants_data, tracks_count, playback_sequence]
      }.check(25) { |room_data, participants_data, tracks_count, playback_sequence|
        # Create users and room
        users = participants_data.map { |user_data| create_test_user(user_data) }
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
            filename: "playback_broadcast_track_#{i}.mp3",
            original_name: "Playback Broadcast Track #{i}",
            file_path: "/tmp/playback_broadcast_track_#{i}.mp3",
            duration_seconds: rand(60..300),
            file_size_bytes: rand(1_000_000..10_000_000),
            mime_type: 'audio/mpeg',
            vote_score: 0,
            created_at: Time.now + i
          )
          tracks << track
        end
        
        # Create WebSocket connections for all users
        connections = {}
        users.each do |user|
          connections[user.id] = WebSocketConnection.create_mock_connection(user.id, room.id)
        end
        
        # Execute playback control sequence and verify real-time broadcasting
        playback_sequence.each_with_index do |operation, step|
          action = operation[:action]
          
          # Clear previous messages and published events
          connections.values.each(&:clear_messages)
          Iodine.clear_published_messages
          
          # Record timestamp before operation
          operation_start = Time.now.to_f
          
          case action
          when :start
            track = tracks.sample
            
            # Update room state for playback start
            room.update(
              current_track_id: track.id,
              playback_started_at: Time.now,
              is_playing: true,
              playback_paused_at: nil
            )
            
            # **Validates: Requirements 5.5, 11.4** - System SHALL broadcast playback start events
            EventBroadcaster.broadcast_playback_activity(room.id, :started, admin_user, {
              track: track,
              started_at: room.playback_started_at.to_f
            })
            
            # Verify Iodine pub/sub broadcasting occurred
            published_messages = Iodine.get_published_messages
            playback_started_message = published_messages.find do |msg|
              parsed = JSON.parse(msg[:message])
              parsed['type'] == 'playback_started'
            end
            
            expect(playback_started_message).not_to be_nil, "Playback start event not published via Iodine for step #{step}"
            expect(playback_started_message[:channel]).to eq("room_#{room.id}")
            
            # Verify WebSocket broadcasting occurred to all participants
            room_connections = WebSocketConnection.get_room_connections(room.id)
            room_connections.each do |connection|
              playback_started_messages = connection.get_messages_of_type('playback_started')
              expect(playback_started_messages).not_to be_empty, "Playback start event not received by connection #{connection.user_id}"
              
              message = playback_started_messages.first
              expect(message[:message][:data][:room_id]).to eq(room.id)
              expect(message[:message][:data][:is_playing]).to be true
              expect(message[:message][:data][:administrator][:id]).to eq(admin_user.id)
              
              # **Validates: Requirements 11.2** - Events delivered within reasonable time window
              delivery_time = message[:received_at] - operation_start
              expect(delivery_time).to be < 0.1, "Playback start event delivery too slow: #{delivery_time}s"
            end
            
          when :pause
            next unless room.is_playing
            
            # Update room state for playback pause
            room.update(
              is_playing: false,
              playback_paused_at: Time.now
            )
            
            # **Validates: Requirements 5.5, 11.4** - System SHALL broadcast playback pause events
            EventBroadcaster.broadcast_playback_activity(room.id, :paused, admin_user, {
              paused_at: room.playback_paused_at.to_f
            })
            
            # Verify Iodine pub/sub broadcasting occurred
            published_messages = Iodine.get_published_messages
            playback_paused_message = published_messages.find do |msg|
              parsed = JSON.parse(msg[:message])
              parsed['type'] == 'playback_paused'
            end
            
            expect(playback_paused_message).not_to be_nil, "Playback pause event not published via Iodine for step #{step}"
            expect(playback_paused_message[:channel]).to eq("room_#{room.id}")
            
            # Verify WebSocket broadcasting occurred to all participants
            room_connections = WebSocketConnection.get_room_connections(room.id)
            room_connections.each do |connection|
              playback_paused_messages = connection.get_messages_of_type('playback_paused')
              expect(playback_paused_messages).not_to be_empty, "Playback pause event not received by connection #{connection.user_id}"
              
              message = playback_paused_messages.first
              expect(message[:message][:data][:room_id]).to eq(room.id)
              expect(message[:message][:data][:is_playing]).to be false
              expect(message[:message][:data][:administrator][:id]).to eq(admin_user.id)
              
              # **Validates: Requirements 11.2** - Events delivered within reasonable time window
              delivery_time = message[:received_at] - operation_start
              expect(delivery_time).to be < 0.1, "Playback pause event delivery too slow: #{delivery_time}s"
            end
            
          when :resume
            next unless !room.is_playing && room.playback_paused_at
            
            # Update room state for playback resume
            room.update(
              is_playing: true,
              playback_paused_at: nil
            )
            
            # **Validates: Requirements 5.5, 11.4** - System SHALL broadcast playback resume events
            EventBroadcaster.broadcast_playback_activity(room.id, :resumed, admin_user, {
              resumed_at: Time.now.to_f
            })
            
            # Verify Iodine pub/sub broadcasting occurred
            published_messages = Iodine.get_published_messages
            playback_resumed_message = published_messages.find do |msg|
              parsed = JSON.parse(msg[:message])
              parsed['type'] == 'playback_resumed'
            end
            
            expect(playback_resumed_message).not_to be_nil, "Playback resume event not published via Iodine for step #{step}"
            expect(playback_resumed_message[:channel]).to eq("room_#{room.id}")
            
            # Verify WebSocket broadcasting occurred to all participants
            room_connections = WebSocketConnection.get_room_connections(room.id)
            room_connections.each do |connection|
              playback_resumed_messages = connection.get_messages_of_type('playback_resumed')
              expect(playback_resumed_messages).not_to be_empty, "Playback resume event not received by connection #{connection.user_id}"
              
              message = playback_resumed_messages.first
              expect(message[:message][:data][:room_id]).to eq(room.id)
              expect(message[:message][:data][:is_playing]).to be true
              expect(message[:message][:data][:administrator][:id]).to eq(admin_user.id)
              
              # **Validates: Requirements 11.2** - Events delivered within reasonable time window
              delivery_time = message[:received_at] - operation_start
              expect(delivery_time).to be < 0.1, "Playback resume event delivery too slow: #{delivery_time}s"
            end
          end
        end
      }
    end

    it 'maintains event delivery consistency under concurrent broadcasting scenarios' do
      test_instance = self
      
      property_of {
        # Generate scenario with concurrent events across multiple rooms
        rooms_count = rand(2..4)
        rooms_data = rooms_count.times.map { test_instance.generate_room_data }
        participants_per_room = rand(3..5)
        concurrent_events = test_instance.generate_concurrent_event_sequence(rooms_count, participants_per_room, rand(10..20))
        [rooms_data, participants_per_room, concurrent_events]
      }.check(20) { |rooms_data, participants_per_room, concurrent_events|
        # Create users and rooms
        all_users = []
        rooms = []
        room_connections = {}
        
        rooms_data.each_with_index do |room_data, room_index|
          # Create users for this room
          users_data = participants_per_room.times.map { generate_user_data }
          users = users_data.map { |user_data| create_test_user(user_data) }
          all_users.concat(users)
          
          # Create room
          admin_user = users.first
          room = create_test_room(room_data, admin_user)
          users[1..-1].each { |user| room.add_participant(user) }
          rooms << room
          
          # Create WebSocket connections for all users in this room
          room_connections[room.id] = {}
          users.each do |user|
            room_connections[room.id][user.id] = WebSocketConnection.create_mock_connection(user.id, room.id)
          end
        end
        
        # Execute concurrent events and verify broadcasting consistency
        concurrent_events.each_with_index do |event_batch, batch_index|
          # Clear all messages and published events
          room_connections.values.each do |connections|
            connections.values.each(&:clear_messages)
          end
          Iodine.clear_published_messages
          
          # Record timestamp before batch execution
          batch_start = Time.now.to_f
          
          # Execute all events in the batch concurrently (simulate concurrent access)
          event_batch.each do |event|
            room_index = event[:room_index] % rooms.length
            room = rooms[room_index]
            event_type = event[:event_type]
            
            case event_type
            when :user_activity
              # Find a user who can perform the activity
              available_users = all_users.select { |u| room.has_participant?(u) || !room.has_participant?(u) }
              next if available_users.empty?
              
              user = available_users.sample
              activity = [:joined, :left].sample
              
              if activity == :joined && !room.has_participant?(user)
                room.add_participant(user)
                EventBroadcaster.broadcast_user_activity(room.id, activity, user)
              elsif activity == :left && room.has_participant?(user) && room.administrator_id != user.id
                room.remove_participant(user)
                EventBroadcaster.broadcast_user_activity(room.id, activity, user)
              end
              
            when :track_activity
              uploader = all_users.sample
              track = Track.create(
                id: SecureRandom.uuid,
                room_id: room.id,
                uploader_id: uploader.id,
                filename: "concurrent_track_#{batch_index}_#{SecureRandom.hex(4)}.mp3",
                original_name: "Concurrent Track #{batch_index}",
                file_path: "/tmp/concurrent_track_#{batch_index}.mp3",
                duration_seconds: rand(60..300),
                file_size_bytes: rand(1_000_000..10_000_000),
                mime_type: 'audio/mpeg',
                vote_score: 0,
                created_at: Time.now
              )
              
              EventBroadcaster.broadcast_track_activity(room.id, :added, track, uploader)
              
            when :playback_activity
              admin_user = User[room.administrator_id]
              next unless admin_user
              
              activity = [:started, :paused, :resumed].sample
              
              case activity
              when :started
                room.update(is_playing: true, playback_started_at: Time.now)
                EventBroadcaster.broadcast_playback_activity(room.id, activity, admin_user)
              when :paused
                if room.is_playing
                  room.update(is_playing: false, playback_paused_at: Time.now)
                  EventBroadcaster.broadcast_playback_activity(room.id, activity, admin_user)
                end
              when :resumed
                if !room.is_playing
                  room.update(is_playing: true, playback_paused_at: nil)
                  EventBroadcaster.broadcast_playback_activity(room.id, activity, admin_user)
                end
              end
            end
          end
          
          # Verify events were broadcasted (allow for some batches to have no events due to conditions)
          published_messages = Iodine.get_published_messages
          
          # If no events were published, it might be due to conditions not being met
          # This is acceptable in concurrent scenarios, so we skip verification for empty batches
          if published_messages.empty?
            next # Skip this batch - no events were generated due to conditions
          end
          
          # Verify each room received appropriate events
          rooms.each do |room|
            room_events = published_messages.select { |msg| msg[:channel] == "room_#{room.id}" }
            
            if room_events.any?
              # Verify WebSocket delivery for this room
              connections = room_connections[room.id]
              connections.each do |user_id, connection|
                expect(connection.messages_received).not_to be_empty, "User #{user_id} in room #{room.id} received no events"
                
                # **Validates: Requirements 11.2** - All events delivered within reasonable time window
                connection.messages_received.each do |msg_data|
                  delivery_time = msg_data[:received_at] - batch_start
                  expect(delivery_time).to be < 0.2, "Event delivery too slow in concurrent scenario: #{delivery_time}s"
                end
              end
            end
          end
          
          # Verify event integrity - no duplicate or corrupted events
          published_messages.each do |published_msg|
            expect { JSON.parse(published_msg[:message]) }.not_to raise_error, "Published message is not valid JSON"
            
            parsed = JSON.parse(published_msg[:message])
            expect(parsed).to have_key('type'), "Published event missing type field"
            expect(parsed).to have_key('data'), "Published event missing data field"
            expect(parsed['data']).to have_key('room_id'), "Published event missing room_id"
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

  def generate_join_leave_sequence(participants_count, operations_count)
    operations = []
    
    operations_count.times do
      operations << {
        user_index: rand(0...participants_count),
        action: [:join, :leave].sample
      }
    end
    
    operations
  end

  def generate_track_addition_sequence(tracks_count, participants_count)
    operations = []
    
    tracks_count.times do |i|
      operations << {
        uploader_index: rand(0...participants_count),
        track_name: "Generated Track #{i}"
      }
    end
    
    operations
  end

  def generate_voting_sequence(tracks_count, participants_count, operations_count)
    operations = []
    
    operations_count.times do
      operations << {
        track_index: rand(0...tracks_count),
        user_index: rand(0...participants_count),
        action: [:vote, :unvote].sample
      }
    end
    
    operations
  end

  def generate_playback_control_sequence(tracks_count, operations_count)
    operations = []
    
    operations_count.times do
      operations << {
        action: [:start, :pause, :resume].sample
      }
    end
    
    operations
  end

  def generate_concurrent_event_sequence(rooms_count, participants_per_room, batches_count)
    batches = []
    
    batches_count.times do |batch_index|
      batch_size = rand(2..5)
      batch = []
      
      batch_size.times do
        batch << {
          room_index: rand(0...rooms_count),
          event_type: [:user_activity, :track_activity, :playback_activity].sample
        }
      end
      
      batches << batch
    end
    
    batches
  end

  def generate_room_name
    prefixes = ['Broadcast Test Room', 'Event Room', 'Real-time Room', 'Broadcasting Room']
    suffixes = ['Alpha', 'Beta', 'Gamma', 'Delta', '2024', 'Test']
    "#{prefixes.sample} #{suffixes.sample} #{rand(100..999)}"
  end

  def generate_username
    prefixes = ['broadcaster', 'user', 'test', 'participant']
    "#{prefixes.sample}_#{SecureRandom.hex(6)}"
  end

  def generate_email
    domains = ['example.com', 'test.org', 'demo.net', 'broadcast.io']
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