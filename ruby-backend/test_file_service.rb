#!/usr/bin/env ruby

# Test script for enhanced file service functionality

require_relative 'app/services/file_service'
require 'tempfile'
require 'logger'

# Setup logger for testing
$logger = Logger.new(STDOUT)
$logger.level = Logger::INFO

puts "Testing Enhanced File Service"
puts "=" * 50

# Test 1: Initialize storage
puts "\n1. Testing storage initialization..."
FileService.initialize_storage
puts "✓ Storage initialized"

# Test 2: File validation
puts "\n2. Testing file validation..."

# Create a mock MP3 file for testing
Tempfile.create(['test', '.mp3']) do |tempfile|
  # Write MP3-like header
  tempfile.write("ID3\x03\x00\x00\x00\x00\x00\x00")
  tempfile.write("A" * 1000) # Some content
  tempfile.rewind
  
  file_data = {
    tempfile: tempfile,
    filename: 'test.mp3',
    type: 'audio/mpeg'
  }
  
  validation = FileService.validate_audio_file(file_data)
  
  if validation[:valid]
    puts "✓ MP3 file validation passed"
  else
    puts "✗ MP3 file validation failed: #{validation[:errors].join(', ')}"
  end
end

# Test 3: MIME type detection
puts "\n3. Testing MIME type detection..."
test_cases = [
  ['.mp3', 'audio/mpeg'],
  ['.wav', 'audio/wav'],
  ['.m4a', 'audio/mp4']
]

test_cases.each do |ext, expected_mime|
  actual_mime = FileService.send(:get_mime_type_for_extension, ext)
  if actual_mime == expected_mime
    puts "✓ #{ext} -> #{actual_mime}"
  else
    puts "✗ #{ext} -> #{actual_mime} (expected #{expected_mime})"
  end
end

# Test 4: ETag generation
puts "\n4. Testing ETag generation..."
filename = "test.mp3"
last_modified = Time.now
file_size = 1024

etag1 = FileService.send(:generate_etag, filename, last_modified, file_size)
etag2 = FileService.send(:generate_etag, filename, last_modified, file_size)

if etag1 == etag2
  puts "✓ ETag generation is consistent: #{etag1}"
else
  puts "✗ ETag generation is inconsistent"
end

# Test 5: File size formatting
puts "\n5. Testing file size formatting..."
test_sizes = [
  [1024, "1.0 KB"],
  [1048576, "1.0 MB"],
  [1073741824, "1.0 GB"]
]

test_sizes.each do |size, expected|
  actual = FileService.send(:format_file_size, size)
  if actual == expected
    puts "✓ #{size} bytes -> #{actual}"
  else
    puts "✗ #{size} bytes -> #{actual} (expected #{expected})"
  end
end

# Test 6: Audio metadata estimation
puts "\n6. Testing audio metadata estimation..."
test_metadata = FileService.send(:estimate_metadata, 4000000, '.mp3') # ~4MB MP3

if test_metadata[:duration] > 0 && test_metadata[:bitrate] > 0
  puts "✓ Metadata estimation: #{test_metadata[:duration]}s, #{test_metadata[:bitrate]}kbps"
else
  puts "✗ Metadata estimation failed"
end

# Test 7: Range header parsing (if we have existing files)
puts "\n7. Testing file existence check..."
if Dir.exist?('./storage/tracks')
  files = Dir.glob('./storage/tracks/*')
  if files.any?
    test_file = File.basename(files.first)
    exists = FileService.file_exists?(test_file)
    puts "✓ File existence check: #{test_file} -> #{exists}"
  else
    puts "ℹ No files in storage to test"
  end
else
  puts "ℹ Storage directory not found"
end

puts "\n" + "=" * 50
puts "File Service Test Complete"