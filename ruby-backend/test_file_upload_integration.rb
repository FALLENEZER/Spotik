#!/usr/bin/env ruby

# Integration test for file upload functionality

# Mock logger
$logger = Object.new
def $logger.info(msg); puts "INFO: #{msg}"; end
def $logger.warn(msg); puts "WARN: #{msg}"; end
def $logger.error(msg); puts "ERROR: #{msg}"; end

require_relative 'app/services/file_service'
require 'tempfile'

puts "File Upload Integration Test"
puts "=" * 40

# Test 1: Initialize storage
puts "\n1. Initializing storage..."
FileService.initialize_storage
puts "✓ Storage directory created/verified"

# Test 2: Create a test MP3 file
puts "\n2. Creating test MP3 file..."
Tempfile.create(['test_upload', '.mp3']) do |tempfile|
  # Write a minimal MP3-like file with ID3 header
  tempfile.write("ID3\x03\x00\x00\x00\x00\x00\x00")  # ID3v2 header
  tempfile.write("TALB\x00\x00\x00\x05\x00\x00Test")  # Album tag
  tempfile.write("\xFF\xFB\x90\x00")  # MP3 frame sync
  tempfile.write("A" * 1000)  # Some audio data
  tempfile.rewind
  
  file_data = {
    tempfile: tempfile,
    filename: 'test_song.mp3',
    type: 'audio/mpeg'
  }
  
  puts "✓ Test MP3 file created (#{tempfile.size} bytes)"
  
  # Test 3: Validate the file
  puts "\n3. Validating file..."
  validation = FileService.validate_audio_file(file_data)
  
  if validation[:valid]
    puts "✓ File validation passed"
    puts "  - Extension: #{validation[:file_info][:extension]}"
    puts "  - MIME type: #{validation[:file_info][:content_type]}"
    puts "  - Size: #{validation[:file_info][:file_size]} bytes"
  else
    puts "✗ File validation failed:"
    validation[:errors].each { |error| puts "  - #{error}" }
    exit 1
  end
  
  # Test 4: Save the file
  puts "\n4. Saving file to storage..."
  save_result = FileService.save_uploaded_file(file_data, 'user123', 'room456')
  
  if save_result[:success]
    file_info = save_result[:file_info]
    puts "✓ File saved successfully"
    puts "  - Filename: #{file_info[:filename]}"
    puts "  - Original name: #{file_info[:original_name]}"
    puts "  - Duration: #{file_info[:duration_seconds]}s"
    puts "  - File size: #{file_info[:file_size_bytes]} bytes"
    puts "  - Path: #{file_info[:file_path]}"
    
    saved_filename = file_info[:filename]
    
    # Test 5: Verify file exists
    puts "\n5. Verifying saved file..."
    exists = FileService.file_exists?(saved_filename)
    puts "✓ File exists check: #{exists}"
    
    if exists
      # Test 6: Get file metadata
      puts "\n6. Getting file metadata..."
      metadata = FileService.get_file_metadata(saved_filename)
      
      if metadata[:success]
        puts "✓ Metadata retrieved:"
        puts "  - Size: #{metadata[:formatted_size]}"
        puts "  - MIME: #{metadata[:mime_type]}"
        puts "  - Duration: #{metadata[:duration_seconds]}s"
        puts "  - Bitrate: #{metadata[:bitrate]}kbps"
        puts "  - Sample rate: #{metadata[:sample_rate]}Hz"
        puts "  - Channels: #{metadata[:channels]}"
      else
        puts "✗ Failed to get metadata: #{metadata[:error]}"
      end
      
      # Test 7: Test file serving
      puts "\n7. Testing file serving..."
      serve_result = FileService.serve_file(saved_filename)
      
      if serve_result[:success]
        puts "✓ File serving prepared:"
        puts "  - MIME type: #{serve_result[:mime_type]}"
        puts "  - File size: #{serve_result[:file_size]} bytes"
        puts "  - ETag: #{serve_result[:etag]}"
        puts "  - Headers: #{serve_result[:headers].keys.length} headers"
        
        # Test 8: Test range request
        puts "\n8. Testing range request..."
        range_result = FileService.serve_file(saved_filename, "bytes=0-499")
        
        if range_result[:success] && range_result[:range_request]
          puts "✓ Range request handled:"
          puts "  - Status: #{range_result[:status]}"
          puts "  - Content length: #{range_result[:content_length]} bytes"
          puts "  - Range: #{range_result[:start_byte]}-#{range_result[:end_byte]}"
        else
          puts "✗ Range request failed"
        end
        
        # Test 9: Test content streaming
        puts "\n9. Testing content streaming..."
        content_chunks = []
        FileService.stream_file_content(serve_result[:file_path], 0, 100) do |chunk|
          content_chunks << chunk
        end
        
        total_streamed = content_chunks.join.length
        puts "✓ Content streaming: #{content_chunks.length} chunks, #{total_streamed} bytes"
        
      else
        puts "✗ File serving failed: #{serve_result[:error]}"
      end
      
      # Test 10: Cleanup
      puts "\n10. Cleaning up..."
      deleted = FileService.delete_file(saved_filename)
      puts "✓ File deleted: #{deleted}"
      
    else
      puts "✗ Saved file not found!"
    end
    
  else
    puts "✗ File save failed:"
    save_result[:errors].each { |error| puts "  - #{error}" }
  end
end

puts "\n" + "=" * 40
puts "File Upload Integration Test Complete"