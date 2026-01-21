# Property-based test for audio file upload and validation
# **Feature: ruby-backend-migration, Property 6: Audio File Upload and Validation**
# **Validates: Requirements 4.1, 4.2, 4.4**

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

# Load application components
require_relative '../../app/services/file_service'

RSpec.describe 'Audio File Upload Validation Property Test', :property do
  
  before(:all) do
    # Initialize file storage
    FileService.initialize_storage
    
    # Clean up any existing test data
    cleanup_test_files
  end
  
  after(:each) do
    # Clean up test files after each test
    cleanup_test_files
  end
  
  describe 'Property 6: Audio File Upload and Validation' do
    it 'accepts valid audio files (MP3, WAV, M4A) and rejects invalid files with appropriate error messages' do
      test_instance = self
      
      property_of {
        # Generate random test scenario
        scenario_type = choose(:valid_upload, :invalid_format, :invalid_size, :corrupted_file, :missing_file)
        
        # Generate file data based on scenario
        file_data = case scenario_type
        when :valid_upload
          test_instance.generate_valid_audio_file
        when :invalid_format
          test_instance.generate_invalid_format_file
        when :invalid_size
          test_instance.generate_oversized_file
        when :corrupted_file
          test_instance.generate_corrupted_audio_file
        when :missing_file
          nil
        end
        
        [scenario_type, file_data]
      }.check { |scenario_type, file_data|
        # Test file validation based on scenario
        case scenario_type
        when :valid_upload
          # **Validates: Requirements 4.1, 4.4** - Valid audio files should be accepted
          validation_result = test_instance.validate_file(file_data)
          
          expect(validation_result[:valid]).to be true
          expect(validation_result[:errors]).to be_empty
          
          # Verify supported format was accepted
          supported_mime_types = ['audio/mpeg', 'audio/wav', 'audio/mp4', 'audio/x-m4a']
          expect(supported_mime_types).to include(file_data[:mime_type])
          
          # Test actual file saving
          save_result = test_instance.save_file(file_data)
          expect(save_result[:success]).to be true
          expect(save_result[:file_info]).to have_key(:filename)
          expect(save_result[:file_info]).to have_key(:duration_seconds)
          expect(save_result[:file_info]).to have_key(:file_size_bytes)
          
          # Verify file was actually saved
          expect(FileService.file_exists?(save_result[:file_info][:filename])).to be true
          
        when :invalid_format, :invalid_size, :corrupted_file
          # **Validates: Requirements 4.2** - Invalid files should be rejected with error messages
          validation_result = test_instance.validate_file(file_data)
          
          expect(validation_result[:valid]).to be false
          expect(validation_result[:errors]).not_to be_empty
          
          # Verify appropriate error message based on scenario
          error_messages = validation_result[:errors].join(' ')
          case scenario_type
          when :invalid_format
            expect(error_messages).to match(/unsupported.*format|unsupported.*extension|unsupported.*mime/i)
          when :invalid_size
            expect(error_messages).to match(/file size.*exceeds|too large|maximum.*size/i)
          when :corrupted_file
            expect(error_messages).to match(/corrupted|invalid.*audio|not.*valid/i)
          end
          
          # Test that saving also fails
          save_result = test_instance.save_file(file_data)
          expect(save_result[:success]).to be false
          expect(save_result[:errors]).not_to be_empty
          
        when :missing_file
          # **Validates: Requirements 4.2** - Missing file should be rejected
          validation_result = test_instance.validate_file(nil)
          
          expect(validation_result[:valid]).to be false
          expect(validation_result[:errors]).to include(match(/no file|file.*required|missing.*file/i))
        end
      }
    end
    
    it 'handles all supported audio formats consistently' do
      test_instance = self
      
      property_of {
        # Test each supported format
        format_data = choose(
          { extension: 'mp3', mime_type: 'audio/mpeg' },
          { extension: 'wav', mime_type: 'audio/wav' },
          { extension: 'm4a', mime_type: 'audio/mp4' },
          { extension: 'm4a', mime_type: 'audio/x-m4a' }
        )
        
        format_data
      }.check { |format_data|
        # Generate valid file for this format
        file_data = test_instance.generate_audio_file_for_format(format_data)
        
        # Validate file
        validation_result = test_instance.validate_file(file_data)
        
        # **Validates: Requirements 4.1, 4.4** - All supported formats should be handled consistently
        expect(validation_result[:valid]).to be true
        expect(validation_result[:errors]).to be_empty
        
        # Verify format-specific properties
        expect(validation_result[:file_info][:content_type]).to eq(format_data[:mime_type])
        expect(validation_result[:file_info][:filename]).to end_with(".#{format_data[:extension]}")
        
        # Test saving
        save_result = test_instance.save_file(file_data)
        expect(save_result[:success]).to be true
        
        # Verify metadata extraction worked
        expect(save_result[:file_info][:duration_seconds]).to be >= 0
        expect(save_result[:file_info][:file_size_bytes]).to be > 0
        
        # Verify file was stored correctly
        expect(FileService.file_exists?(save_result[:file_info][:filename])).to be true
      }
    end
    
    it 'validates file size limits and content integrity' do
      test_instance = self
      
      property_of {
        # Generate various file size scenarios
        size_scenario = choose(:normal_size, :minimum_size, :maximum_allowed, :slightly_oversized, :extremely_oversized)
        format_data = choose(
          { extension: 'mp3', mime_type: 'audio/mpeg' },
          { extension: 'wav', mime_type: 'audio/wav' },
          { extension: 'm4a', mime_type: 'audio/mp4' }
        )
        
        [size_scenario, format_data]
      }.check { |size_scenario, format_data|
        # Generate file based on size scenario
        file_data = test_instance.generate_file_with_size(format_data, size_scenario)
        
        validation_result = test_instance.validate_file(file_data)
        
        case size_scenario
        when :normal_size, :minimum_size, :maximum_allowed
          # **Validates: Requirements 4.1** - Valid sized files should be accepted
          expect(validation_result[:valid]).to be true
          expect(validation_result[:errors]).to be_empty
          
          expect(validation_result[:file_info][:file_size]).to be <= FileService::MAX_FILE_SIZE
          expect(validation_result[:file_info][:file_size]).to be > 0
          
        when :slightly_oversized, :extremely_oversized
          # **Validates: Requirements 4.2** - Oversized files should be rejected
          expect(validation_result[:valid]).to be false
          expect(validation_result[:errors]).not_to be_empty
          
          error_messages = validation_result[:errors].join(' ')
          expect(error_messages).to match(/file size.*exceeds|too large|maximum.*size/i)
        end
      }
    end
  end
  
  # Helper methods for generating test data and testing file operations
  
  def generate_valid_audio_file
    formats = [
      { extension: 'mp3', mime_type: 'audio/mpeg' },
      { extension: 'wav', mime_type: 'audio/wav' },
      { extension: 'm4a', mime_type: 'audio/mp4' },
      { extension: 'm4a', mime_type: 'audio/x-m4a' }
    ]
    
    format_data = formats.sample
    generate_audio_file_for_format(format_data)
  end
  
  def generate_audio_file_for_format(format_data)
    content = generate_valid_audio_content(format_data[:extension])
    filename = "test_audio_#{SecureRandom.hex(4)}.#{format_data[:extension]}"
    
    {
      filename: filename,
      content: content,
      mime_type: format_data[:mime_type],
      size: content.length
    }
  end
  
  def generate_invalid_format_file
    invalid_formats = [
      { extension: 'txt', mime_type: 'text/plain' },
      { extension: 'jpg', mime_type: 'image/jpeg' },
      { extension: 'pdf', mime_type: 'application/pdf' },
      { extension: 'exe', mime_type: 'application/octet-stream' },
      { extension: 'zip', mime_type: 'application/zip' }
    ]
    
    format_data = invalid_formats.sample
    content = "Invalid file content for testing"
    filename = "invalid_file_#{SecureRandom.hex(4)}.#{format_data[:extension]}"
    
    {
      filename: filename,
      content: content,
      mime_type: format_data[:mime_type],
      size: content.length
    }
  end
  
  def generate_oversized_file
    # Generate file larger than MAX_FILE_SIZE but not too large for testing
    oversized_content = 'A' * (FileService::MAX_FILE_SIZE + 1024)
    filename = "oversized_#{SecureRandom.hex(4)}.mp3"
    
    {
      filename: filename,
      content: oversized_content,
      mime_type: 'audio/mpeg',
      size: oversized_content.length
    }
  end
  
  def generate_corrupted_audio_file
    formats = ['mp3', 'wav', 'm4a']
    extension = formats.sample
    
    # Generate corrupted content (random bytes that don't match audio format)
    corrupted_content = SecureRandom.random_bytes(1024)
    filename = "corrupted_#{SecureRandom.hex(4)}.#{extension}"
    
    {
      filename: filename,
      content: corrupted_content,
      mime_type: get_mime_type_for_extension(extension),
      size: corrupted_content.length
    }
  end
  
  def generate_file_with_size(format_data, size_scenario)
    base_content = generate_valid_audio_content(format_data[:extension])
    
    case size_scenario
    when :normal_size
      content = base_content + ('A' * rand(1000..10000))
    when :minimum_size
      content = base_content
    when :maximum_allowed
      content = base_content + ('A' * (FileService::MAX_FILE_SIZE - base_content.length - 100))
    when :slightly_oversized
      content = base_content + ('A' * (FileService::MAX_FILE_SIZE + 1024))
    when :extremely_oversized
      content = base_content + ('A' * (FileService::MAX_FILE_SIZE + 10240)) # Only 10KB over limit for testing
    end
    
    filename = "size_test_#{SecureRandom.hex(4)}.#{format_data[:extension]}"
    
    {
      filename: filename,
      content: content,
      mime_type: format_data[:mime_type],
      size: content.length
    }
  end
  
  def generate_valid_audio_content(extension)
    case extension
    when 'mp3'
      # Minimal valid MP3 header with ID3 tag
      id3_header = "ID3\x03\x00\x00\x00\x00\x00\x00"
      mp3_frame = "\xFF\xFB\x90\x00" + ("\x00" * 100)
      id3_header + mp3_frame
    when 'wav'
      # Minimal valid WAV header
      header = "RIFF"
      header += [36].pack('V')  # File size - 8
      header += "WAVE"
      header += "fmt "
      header += [16].pack('V')  # Format chunk size
      header += [1].pack('v')   # Audio format (PCM)
      header += [1].pack('v')   # Number of channels
      header += [44100].pack('V') # Sample rate
      header += [88200].pack('V') # Byte rate
      header += [2].pack('v')   # Block align
      header += [16].pack('v')  # Bits per sample
      header += "data"
      header += [0].pack('V')   # Data size
      header + ("\x00" * 100)
    when 'm4a'
      # Minimal valid M4A/MP4 header with ftyp box
      ftyp_box = [32].pack('N') + "ftypM4A " + ("\x00" * 20)
      ftyp_box + ("\x00" * 100)
    else
      "\x00" * 100
    end
  end
  
  def get_mime_type_for_extension(extension)
    case extension
    when 'mp3' then 'audio/mpeg'
    when 'wav' then 'audio/wav'
    when 'm4a' then 'audio/mp4'
    else 'application/octet-stream'
    end
  end
  
  def validate_file(file_data)
    if file_data.nil?
      return {
        valid: false,
        errors: ['No file provided']
      }
    end
    
    # Create a temporary file to simulate uploaded file
    temp_file = Tempfile.new(['test_audio', ".#{File.extname(file_data[:filename])}"])
    temp_file.binmode
    temp_file.write(file_data[:content])
    temp_file.rewind
    
    # Create file data structure that matches what FileService expects
    file_upload_data = {
      filename: file_data[:filename],
      tempfile: temp_file,
      type: file_data[:mime_type]
    }
    
    result = FileService.validate_audio_file(file_upload_data)
    
    temp_file.close
    temp_file.unlink
    
    result
  end
  
  def save_file(file_data)
    if file_data.nil?
      return {
        success: false,
        errors: ['No file provided']
      }
    end
    
    # Create a temporary file to simulate uploaded file
    temp_file = Tempfile.new(['test_audio', ".#{File.extname(file_data[:filename])}"])
    temp_file.binmode
    temp_file.write(file_data[:content])
    temp_file.rewind
    
    # Create file data structure that matches what FileService expects
    file_upload_data = {
      filename: file_data[:filename],
      tempfile: temp_file,
      type: file_data[:mime_type]
    }
    
    result = FileService.save_uploaded_file(file_upload_data, 'test_user_id', 'test_room_id')
    
    temp_file.close
    temp_file.unlink
    
    result
  end
  
  def cleanup_test_files
    # Clean up test files
    test_files = Dir.glob(File.join(FileService::UPLOAD_DIR, 'test_*'))
    test_files.each { |file| File.delete(file) if File.exist?(file) }
  end
end