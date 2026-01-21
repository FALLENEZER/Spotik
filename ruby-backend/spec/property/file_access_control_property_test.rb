# Property-based test for file access control
# **Feature: ruby-backend-migration, Property 15: File Access Control**
# **Validates: Requirements 10.4**

# Set test environment variables BEFORE loading any application code
ENV['APP_ENV'] = 'test'
ENV['DATABASE_URL'] = 'postgres://postgres:password@localhost:5432/spotik_test'
ENV['JWT_SECRET'] = 'test_secret_key_for_jwt_tokens_in_test_environment_only'
ENV['JWT_TTL'] = '3600' # 1 hour for testing

require 'bundler/setup'
require 'rspec'
require 'rantly'
require 'rantly/rspec_extensions'
require 'json'
require 'tempfile'
require 'fileutils'
require 'securerandom'
require 'mime/types'
require 'digest'

# Load application components
require_relative '../../app/models'
require_relative '../../app/services/auth_service'
require_relative '../../app/services/file_service'
require_relative '../../app/controllers/track_controller'
require_relative '../../config/database'
require_relative '../../config/settings'

RSpec.describe 'File Access Control Property Test', :property do
  
  before(:all) do
    # Initialize file storage
    FileService.initialize_storage
    
    # Set up test directories
    setup_test_directories
    
    # Clean up any existing test data
    cleanup_test_files
    cleanup_test_database
  end
  
  after(:each) do
    # Clean up test files and database after each test
    cleanup_test_files
    cleanup_test_database
  end
  
  after(:all) do
    # Clean up test directories
    cleanup_test_directories
  end
  
  describe 'Property 15: File Access Control' do
    it 'verifies user permissions before serving files and denies access to unauthorized users' do
      test_instance = self
      
      property_of {
        # Generate test data
        room_count = range(1, 3)
        user_count = range(2, 5)
        tracks_per_room = range(1, 3)
        
        # Create users
        users = user_count.times.map do |i|
          {
            username: "testuser#{i}_#{SecureRandom.hex(4)}",
            email: "test#{i}_#{SecureRandom.hex(4)}@example.com",
            password: "password123"
          }
        end
        
        # Create rooms with participants and tracks
        rooms = room_count.times.map do |i|
          room_data = {
            name: "Test Room #{i}_#{SecureRandom.hex(4)}",
            administrator: users.sample,
            participants: users.sample(range(1, user_count))
          }
          
          # Add tracks to room
          room_data[:tracks] = tracks_per_room.times.map do |j|
            {
              filename: "track#{i}_#{j}_#{SecureRandom.hex(4)}.mp3",
              original_name: "Test Track #{i}_#{j}.mp3",
              uploader: room_data[:participants].sample
            }
          end
          
          room_data
        end
        
        # Select test scenario
        test_room = rooms.sample
        test_track = test_room[:tracks].sample
        participant = test_room[:participants].sample
        non_participant = users.find { |u| !test_room[:participants].include?(u) }
        
        {
          users: users,
          rooms: rooms,
          test_room: test_room,
          test_track: test_track,
          participant: participant,
          non_participant: non_participant
        }
      }.check(10) { |data|  # Reduced iterations for faster execution
        begin
          # Create users in database
          created_users = {}
          data[:users].each do |user_data|
            user = User.create(
              username: user_data[:username],
              email: user_data[:email],
              password_hash: BCrypt::Password.create(user_data[:password])
            )
            expect(user).to be_valid
            created_users[user_data[:username]] = user
          end
          
          # Create rooms in database
          created_rooms = {}
          data[:rooms].each do |room_data|
            admin_user = created_users[room_data[:administrator][:username]]
            room = Room.create(
              name: room_data[:name],
              administrator_id: admin_user.id
            )
            expect(room).to be_valid
            created_rooms[room_data[:name]] = room
            
            # Add participants to room (including administrator)
            room_data[:participants].each do |participant_data|
              participant_user = created_users[participant_data[:username]]
              room.add_participant(participant_user)
            end
            
            # Ensure administrator is always a participant
            room.add_participant(admin_user) unless room.has_participant?(admin_user)
            
            # Create tracks for room
            room_data[:tracks].each do |track_data|
              uploader_user = created_users[track_data[:uploader][:username]]
              
              # Create test audio file
              test_file_path = create_test_audio_file(track_data[:filename])
              
              track = Track.create(
                filename: track_data[:filename],
                original_name: track_data[:original_name],
                file_path: "tracks/#{track_data[:filename]}",
                room_id: room.id,
                uploader_id: uploader_user.id,
                duration_seconds: 180,
                file_size_bytes: File.size(test_file_path),
                mime_type: 'audio/mpeg',
                vote_score: 0
              )
              expect(track).to be_valid
            end
          end
          
          # Get test objects
          test_room_obj = created_rooms[data[:test_room][:name]]
          test_track_obj = test_room_obj.tracks.find { |t| t.filename == data[:test_track][:filename] }
          participant_user = created_users[data[:participant][:username]]
          non_participant_user = data[:non_participant] ? created_users[data[:non_participant][:username]] : nil
          
          # Generate JWT tokens
          participant_token = AuthService.generate_jwt(participant_user)
          non_participant_token = non_participant_user ? AuthService.generate_jwt(non_participant_user) : nil
          
          # **Test 1: Room participant should have access to track files**
          # **Validates: Requirements 10.4** - System SHALL verify user permissions before serving files
          result = TrackController.stream(test_track_obj.id, participant_token)
          
          # Debug output
          puts "DEBUG: Participant access result: #{result.inspect}" if result[:status] != 200
          
          expect(result[:status]).to eq(200), "Room participant should have access to track files"
          expect(result[:file_info]).not_to be_nil
          expect(result[:file_info][:success]).to be(true)
          expect(result[:track]).to eq(test_track_obj)
          
          # **Test 2: Non-participant should be denied access**
          # **Validates: Requirements 10.4** - System SHALL deny access to unauthorized users
          if non_participant_user && non_participant_user.id != test_room_obj.administrator_id
            result = TrackController.stream(test_track_obj.id, non_participant_token)
            
            expect(result[:status]).to eq(403), "Non-participant should be denied access"
            expect(result[:body][:error]).to eq('You must be a participant of this room to stream tracks')
          end
          
          # **Test 3: Unauthenticated requests should be denied**
          # **Validates: Requirements 10.4** - System SHALL verify user permissions (authentication required)
          result = TrackController.stream(test_track_obj.id, nil)
          
          expect(result[:status]).to eq(401), "Unauthenticated requests should be denied"
          expect(result[:body][:message]).to eq('Authentication failed')
          
          # **Test 4: Invalid JWT token should be denied**
          # **Validates: Requirements 10.4** - System SHALL verify user permissions (valid authentication required)
          invalid_token = "invalid.jwt.token"
          result = TrackController.stream(test_track_obj.id, invalid_token)
          
          expect(result[:status]).to eq(401), "Invalid JWT token should be denied"
          expect(result[:body][:message]).to eq('Authentication failed')
          
          # **Test 5: Access to non-existent track should return 404**
          # **Validates: Requirements 10.4** - System SHALL verify file exists before checking permissions
          non_existent_track_id = SecureRandom.uuid
          result = TrackController.stream(non_existent_track_id, participant_token)
          
          expect(result[:status]).to eq(404), "Non-existent track should return 404"
          expect(result[:body][:error]).to eq('Track not found')
          
          # **Test 6: Room administrator should have access to all room tracks**
          # **Validates: Requirements 10.4** - Room administrators are participants with access
          admin_user = created_users[data[:test_room][:administrator][:username]]
          admin_token = AuthService.generate_jwt(admin_user)
          
          result = TrackController.stream(test_track_obj.id, admin_token)
          
          expect(result[:status]).to eq(200), "Room administrator should have access to room tracks"
          expect(result[:file_info][:success]).to be(true)
          
          # **Test 7: File serving should work correctly for authorized users**
          # **Validates: Requirements 10.4** - After permission check, file should be served properly
          file_result = FileService.serve_file(test_track_obj.filename)
          
          expect(file_result[:success]).to be(true), "File should be servable after permission check"
          expect(file_result[:file_path]).not_to be_nil
          expect(File.exist?(file_result[:file_path])).to be(true)
          
          # **Test 8: Range requests should work for authorized users**
          # **Validates: Requirements 10.4** - Permission check should not interfere with range requests
          result = TrackController.stream(test_track_obj.id, participant_token, "bytes=0-499")
          
          expect(result[:status]).to eq(206), "Range requests should work for authorized users"
          expect(result[:file_info][:range_request]).to be(true)
          expect(result[:file_info][:start_byte]).to eq(0)
          expect(result[:file_info][:end_byte]).to eq(499)
          
        rescue => e
          raise "Property test failed with error: #{e.message}\nBacktrace: #{e.backtrace.join("\n")}"
        end
      }
    end
    
    it 'maintains consistent access control across different file operations' do
      test_instance = self
      
      property_of {
        # Generate test scenario with multiple operations
        user_data = {
          username: "testuser_#{SecureRandom.hex(4)}",
          email: "test_#{SecureRandom.hex(4)}@example.com",
          password: "password123"
        }
        
        other_user_data = {
          username: "otheruser_#{SecureRandom.hex(4)}",
          email: "other_#{SecureRandom.hex(4)}@example.com",
          password: "password123"
        }
        
        room_data = {
          name: "Test Room #{SecureRandom.hex(4)}"
        }
        
        track_data = {
          filename: "track_#{SecureRandom.hex(4)}.mp3",
          original_name: "Test Track.mp3"
        }
        
        # Choose operation type
        operation_type = choose(:stream, :metadata, :range_request)
        
        {
          user_data: user_data,
          other_user_data: other_user_data,
          room_data: room_data,
          track_data: track_data,
          operation_type: operation_type
        }
      }.check(10) { |data|  # Reduced iterations for faster execution
        begin
          # Create users
          user = User.create(
            username: data[:user_data][:username],
            email: data[:user_data][:email],
            password_hash: BCrypt::Password.create(data[:user_data][:password])
          )
          expect(user).to be_valid
          
          other_user = User.create(
            username: data[:other_user_data][:username],
            email: data[:other_user_data][:email],
            password_hash: BCrypt::Password.create(data[:other_user_data][:password])
          )
          expect(other_user).to be_valid
          
          # Create room with user as participant
          room = Room.create(
            name: data[:room_data][:name],
            administrator_id: user.id
          )
          expect(room).to be_valid
          room.add_participant(user)
          
          # Ensure administrator is always a participant
          room.add_participant(user) unless room.has_participant?(user)
          
          # Create track file
          test_file_path = create_test_audio_file(data[:track_data][:filename])
          
          # Create track
          track = Track.create(
            filename: data[:track_data][:filename],
            original_name: data[:track_data][:original_name],
            file_path: "tracks/#{data[:track_data][:filename]}",
            room_id: room.id,
            uploader_id: user.id,
            duration_seconds: 180,
            file_size_bytes: File.size(test_file_path),
            mime_type: 'audio/mpeg',
            vote_score: 0
          )
          expect(track).to be_valid
          
          # Generate tokens
          user_token = AuthService.generate_jwt(user)
          other_user_token = AuthService.generate_jwt(other_user)
          
          # Test different operations with consistent access control
          case data[:operation_type]
          when :stream
            # **Test streaming access control**
            # **Validates: Requirements 10.4** - Consistent access control for streaming
            
            # Participant should have access
            result = TrackController.stream(track.id, user_token)
            expect(result[:status]).to eq(200), "Participant should have streaming access"
            
            # Non-participant should be denied
            result = TrackController.stream(track.id, other_user_token)
            expect(result[:status]).to eq(403), "Non-participant should be denied streaming access"
            
          when :metadata
            # **Test metadata access through streaming endpoint**
            # **Validates: Requirements 10.4** - Consistent access control for metadata
            
            # Participant should get metadata
            result = TrackController.stream(track.id, user_token)
            expect(result[:status]).to eq(200), "Participant should have metadata access"
            expect(result[:file_info]).not_to be_nil
            
            # Non-participant should be denied metadata
            result = TrackController.stream(track.id, other_user_token)
            expect(result[:status]).to eq(403), "Non-participant should be denied metadata access"
            
          when :range_request
            # **Test range request access control**
            # **Validates: Requirements 10.4** - Consistent access control for range requests
            
            # Participant should have range access
            result = TrackController.stream(track.id, user_token, "bytes=0-1023")
            expect(result[:status]).to eq(206), "Participant should have range request access"
            
            # Non-participant should be denied range access
            result = TrackController.stream(track.id, other_user_token, "bytes=0-1023")
            expect(result[:status]).to eq(403), "Non-participant should be denied range request access"
          end
          
        rescue => e
          raise "Consistent access control test failed with error: #{e.message}\nBacktrace: #{e.backtrace.join("\n")}"
        end
      }
    end
  end
  
  private
  
  def setup_test_directories
    FileUtils.mkdir_p('./storage/tracks') unless Dir.exist?('./storage/tracks')
    FileUtils.mkdir_p('./tmp/test_files') unless Dir.exist?('./tmp/test_files')
  end
  
  def cleanup_test_directories
    FileUtils.rm_rf('./tmp/test_files') if Dir.exist?('./tmp/test_files')
  end
  
  def cleanup_test_files
    # Clean up test audio files
    Dir.glob('./storage/tracks/track_*.mp3').each { |f| File.delete(f) }
    Dir.glob('./tmp/test_files/*').each { |f| File.delete(f) }
  end
  
  def cleanup_test_database
    # Clean up test data in reverse dependency order
    DB[:track_votes].delete
    DB[:tracks].delete
    DB[:room_participants].delete
    DB[:rooms].delete
    DB[:users].delete
  end
  
  def create_test_audio_file(filename)
    file_path = File.join('./storage/tracks', filename)
    
    # Create a minimal valid MP3 file with ID3 header
    mp3_content = [
      'ID3',                    # ID3 header
      "\x03\x00",              # Version 2.3
      "\x00",                  # Flags
      "\x00\x00\x00\x00",      # Size
      # Add some MP3 frame data
      "\xFF\xFB\x90\x00",      # MP3 frame header (MPEG-1 Layer 3, 128kbps, 44.1kHz)
      "\x00" * 100             # Dummy audio data
    ].join
    
    File.open(file_path, 'wb') do |f|
      f.write(mp3_content)
      # Add more dummy data to make it a reasonable size
      f.write("\x00" * 1000)
    end
    
    file_path
  end
end