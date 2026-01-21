#!/usr/bin/env ruby

# Test Laravel file storage compatibility

require_relative 'app/services/file_service'
require 'logger'

# Setup logger for testing
$logger = Logger.new(STDOUT)
$logger.level = Logger::INFO

puts "Testing Laravel Storage Compatibility"
puts "=" * 50

# Test Laravel file access
laravel_audio_dir = '../backend/storage/app/audio/tracks'

if Dir.exist?(laravel_audio_dir)
  puts "\n✓ Laravel audio directory found: #{laravel_audio_dir}"
  
  # List Laravel files
  laravel_files = Dir.glob("#{laravel_audio_dir}/*")
  puts "Found #{laravel_files.length} Laravel audio files"
  
  if laravel_files.any?
    # Test accessing a Laravel file
    test_file = File.basename(laravel_files.first)
    puts "\nTesting access to Laravel file: #{test_file}"
    
    # Test file existence
    exists = FileService.file_exists?(test_file)
    puts "✓ File exists check: #{exists}"
    
    if exists
      # Test file path finding
      file_path = FileService.find_file_path(test_file)
      puts "✓ File path found: #{file_path}"
      
      # Test metadata extraction
      metadata = FileService.get_file_metadata(test_file)
      if metadata[:success]
        puts "✓ Metadata extracted:"
        puts "  - Size: #{metadata[:formatted_size]}"
        puts "  - MIME: #{metadata[:mime_type]}"
        puts "  - Duration: #{metadata[:duration_seconds]}s"
        puts "  - Bitrate: #{metadata[:bitrate]}kbps"
      else
        puts "✗ Metadata extraction failed: #{metadata[:error]}"
      end
      
      # Test file serving
      serve_result = FileService.serve_file(test_file)
      if serve_result[:success]
        puts "✓ File serving setup successful"
        puts "  - Headers: #{serve_result[:headers].keys.join(', ')}"
        puts "  - ETag: #{serve_result[:etag]}"
      else
        puts "✗ File serving failed: #{serve_result[:error]}"
      end
    end
  else
    puts "ℹ No Laravel audio files found to test"
  end
else
  puts "ℹ Laravel audio directory not found: #{laravel_audio_dir}"
  puts "This is expected if running outside the full project structure"
end

# Test storage initialization with Laravel compatibility
puts "\nTesting storage initialization with Laravel compatibility..."
FileService.initialize_storage

# Check if symlink was created
symlink_path = './storage/tracks/laravel_tracks'
if File.exist?(symlink_path)
  puts "✓ Laravel compatibility symlink created: #{symlink_path}"
  if File.symlink?(symlink_path)
    puts "✓ Symlink target: #{File.readlink(symlink_path)}"
  end
else
  puts "ℹ Laravel compatibility symlink not created (Laravel directory may not exist)"
end

puts "\n" + "=" * 50
puts "Laravel Compatibility Test Complete"