# File Service - Handles audio file upload, validation, and storage
# Compatible with Laravel file handling and storage structure

require 'fileutils'
require 'mime/types'
require 'securerandom'
require 'digest'
require 'time'

# Extend Time class for HTTP date formatting
class Time
  def httpdate
    strftime('%a, %d %b %Y %H:%M:%S GMT')
  end
end

class FileService
  # Constants (Laravel compatibility)
  UPLOAD_DIR = './storage/tracks'
  LARAVEL_AUDIO_DIR = '../backend/storage/app/audio/tracks'  # Laravel compatibility path
  
  SUPPORTED_MIME_TYPES = [
    'audio/mpeg',     # MP3
    'audio/wav',      # WAV
    'audio/mp4',      # M4A
    'audio/x-m4a'     # M4A alternative
  ].freeze
  
  SUPPORTED_EXTENSIONS = %w[mp3 wav m4a].freeze
  MAX_FILE_SIZE = 50 * 1024 * 1024  # 50MB in bytes
  CACHE_TTL = 3600  # 1 hour cache TTL
  BUFFER_SIZE = 65536  # 64KB buffer for streaming
  
  class << self
    # Initialize storage directory with Laravel compatibility
    def initialize_storage
      FileUtils.mkdir_p(UPLOAD_DIR) unless Dir.exist?(UPLOAD_DIR)
      
      # Create symlink to Laravel storage if it exists and we don't have one
      if Dir.exist?(LARAVEL_AUDIO_DIR) && !File.exist?("#{UPLOAD_DIR}/laravel_tracks")
        begin
          FileUtils.ln_s(File.expand_path(LARAVEL_AUDIO_DIR), "#{UPLOAD_DIR}/laravel_tracks")
          $logger&.info "Created symlink to Laravel audio storage for compatibility"
        rescue => e
          $logger&.warn "Could not create Laravel compatibility symlink: #{e.message}"
        end
      end
    end
    
    # Validate uploaded file
    def validate_audio_file(file_data)
      errors = []
      
      # Check if file data is present
      unless file_data && file_data[:tempfile]
        errors << 'No file provided'
        return { valid: false, errors: errors }
      end
      
      # Get file info
      tempfile = file_data[:tempfile]
      filename = file_data[:filename] || ''
      content_type = file_data[:type] || ''
      file_size = tempfile.size
      
      # Check file size
      if file_size > MAX_FILE_SIZE
        errors << "File size (#{format_file_size(file_size)}) exceeds maximum allowed size (#{format_file_size(MAX_FILE_SIZE)})"
      end
      
      if file_size == 0
        errors << 'File is empty'
      end
      
      # Check file extension
      extension = File.extname(filename).downcase.gsub('.', '')
      unless SUPPORTED_EXTENSIONS.include?(extension)
        errors << "Unsupported file extension: .#{extension}. Supported: #{SUPPORTED_EXTENSIONS.join(', ')}"
      end
      
      # Check MIME type
      unless SUPPORTED_MIME_TYPES.include?(content_type)
        errors << "Unsupported MIME type: #{content_type}. Supported: #{SUPPORTED_MIME_TYPES.join(', ')}"
      end
      
      # Basic file content validation
      tempfile.rewind
      content = tempfile.read(1024) # Read first 1KB for validation
      tempfile.rewind
      
      if content.empty?
        errors << 'File appears to be empty or corrupted'
      end
      
      # Check for valid audio file headers (basic validation)
      unless valid_audio_header?(content, extension)
        errors << 'File does not appear to be a valid audio file'
      end
      
      {
        valid: errors.empty?,
        errors: errors,
        file_info: {
          filename: filename,
          extension: extension,
          content_type: content_type,
          file_size: file_size
        }
      }
    end
    
    # Save uploaded file to storage
    def save_uploaded_file(file_data, user_id, room_id)
      initialize_storage
      
      # Validate file first
      validation = validate_audio_file(file_data)
      unless validation[:valid]
        return { success: false, errors: validation[:errors] }
      end
      
      tempfile = file_data[:tempfile]
      original_name = file_data[:filename]
      extension = File.extname(original_name).downcase
      
      # Generate unique filename
      unique_filename = "#{SecureRandom.uuid}#{extension}"
      file_path = File.join(UPLOAD_DIR, unique_filename)
      
      begin
        # Copy file from temp location to storage
        tempfile.rewind
        File.open(file_path, 'wb') do |f|
          f.write(tempfile.read)
        end
        
        # Extract metadata
        metadata = extract_audio_metadata(file_path, extension)
        
        {
          success: true,
          file_info: {
            filename: unique_filename,
            original_name: original_name,
            file_path: file_path,
            relative_path: "tracks/#{unique_filename}",
            duration_seconds: metadata[:duration],
            file_size_bytes: File.size(file_path),
            mime_type: file_data[:type]
          }
        }
        
      rescue => e
        # Clean up file if something went wrong
        File.delete(file_path) if File.exist?(file_path)
        
        {
          success: false,
          errors: ["Failed to save file: #{e.message}"]
        }
      end
    end
    
    # Serve file for streaming with proper headers and caching
    def serve_file(filename, range_header = nil)
      file_path = find_file_path(filename)
      
      unless file_path && File.exist?(file_path)
        return { success: false, error: 'File not found' }
      end
      
      # Get file metadata
      file_size = File.size(file_path)
      extension = File.extname(filename).downcase
      mime_type = get_mime_type_for_extension(extension)
      last_modified = File.mtime(file_path)
      
      # Generate ETag for caching
      etag = generate_etag(filename, last_modified, file_size)
      
      # Prepare base headers
      headers = {
        'Content-Type' => mime_type,
        'Accept-Ranges' => 'bytes',
        'Cache-Control' => 'public, max-age=3600, immutable',
        'ETag' => etag,
        'Last-Modified' => last_modified.httpdate,
        'Content-Disposition' => "inline; filename=\"#{File.basename(filename)}\"",
        'X-Content-Type-Options' => 'nosniff'
      }
      
      # Handle range requests for audio streaming
      if range_header
        return handle_range_request(file_path, file_size, range_header, headers)
      end
      
      # Full file response
      headers['Content-Length'] = file_size.to_s
      
      {
        success: true,
        file_path: file_path,
        file_size: file_size,
        mime_type: mime_type,
        headers: headers,
        filename: filename,
        etag: etag,
        last_modified: last_modified
      }
    end
    
    # Handle HTTP Range requests for audio streaming
    def handle_range_request(file_path, file_size, range_header, base_headers)
      # Parse range header (e.g., "bytes=0-1023")
      unless range_header.match(/bytes=(\d+)-(\d*)/)
        # Invalid range, return full file
        base_headers['Content-Length'] = file_size.to_s
        return {
          success: true,
          file_path: file_path,
          file_size: file_size,
          headers: base_headers,
          range_request: false
        }
      end
      
      start_byte = $1.to_i
      end_byte = $2.empty? ? file_size - 1 : $2.to_i
      
      # Validate range
      if start_byte > end_byte || start_byte >= file_size || end_byte >= file_size
        return {
          success: false,
          error: 'Invalid range',
          status: 416,
          headers: { 'Content-Range' => "bytes */#{file_size}" }
        }
      end
      
      content_length = end_byte - start_byte + 1
      
      headers = base_headers.merge({
        'Content-Length' => content_length.to_s,
        'Content-Range' => "bytes #{start_byte}-#{end_byte}/#{file_size}"
      })
      
      {
        success: true,
        file_path: file_path,
        file_size: file_size,
        headers: headers,
        range_request: true,
        start_byte: start_byte,
        end_byte: end_byte,
        content_length: content_length,
        status: 206
      }
    end
    
    # Stream file content with proper buffering
    def stream_file_content(file_path, start_byte = 0, content_length = nil)
      content_length ||= File.size(file_path) - start_byte
      
      File.open(file_path, 'rb') do |file|
        file.seek(start_byte) if start_byte > 0
        
        bytes_remaining = content_length
        buffer = ''
        
        while bytes_remaining > 0 && !file.eof?
          bytes_to_read = [BUFFER_SIZE, bytes_remaining].min
          data = file.read(bytes_to_read)
          break if data.nil?
          
          buffer << data
          bytes_remaining -= data.length
          
          # Yield chunks for streaming
          if block_given?
            yield data
          end
        end
        
        # Return full content if no block given
        buffer unless block_given?
      end
    end
    
    # Get file metadata with caching support
    def get_file_metadata(filename)
      file_path = find_file_path(filename)
      
      unless file_path && File.exist?(file_path)
        return { success: false, error: 'File not found' }
      end
      
      file_size = File.size(file_path)
      extension = File.extname(filename).downcase
      mime_type = get_mime_type_for_extension(extension)
      last_modified = File.mtime(file_path)
      
      # Extract audio metadata
      audio_metadata = extract_audio_metadata(file_path, extension)
      
      {
        success: true,
        filename: filename,
        file_size: file_size,
        mime_type: mime_type,
        last_modified: last_modified,
        formatted_size: format_file_size(file_size),
        duration_seconds: audio_metadata[:duration],
        bitrate: audio_metadata[:bitrate],
        sample_rate: audio_metadata[:sample_rate],
        channels: audio_metadata[:channels]
      }
    end
    
    # Delete file from storage
    def delete_file(filename)
      file_path = File.join(UPLOAD_DIR, filename)
      
      if File.exist?(file_path)
        File.delete(file_path)
        true
      else
        false
      end
    end
    
    # Check if file exists in any storage location
    def file_exists?(filename)
      find_file_path(filename) != nil
    end
    
    # Find file path checking both Ruby and Laravel storage locations
    def find_file_path(filename)
      # Check Ruby storage first
      ruby_path = File.join(UPLOAD_DIR, filename)
      return ruby_path if File.exist?(ruby_path)
      
      # Check Laravel storage for compatibility
      if Dir.exist?(LARAVEL_AUDIO_DIR)
        laravel_path = File.join(LARAVEL_AUDIO_DIR, filename)
        return laravel_path if File.exist?(laravel_path)
      end
      
      nil
    end
    
    # Generate ETag for caching
    def generate_etag(filename, last_modified, file_size)
      content = "#{filename}-#{last_modified.to_i}-#{file_size}"
      Digest::MD5.hexdigest(content)
    end
    
    # Check if request should return 304 Not Modified
    def not_modified?(if_none_match, if_modified_since, etag, last_modified)
      # Check ETag
      return true if if_none_match && if_none_match == etag
      
      # Check Last-Modified
      if if_modified_since
        begin
          client_time = Time.httpdate(if_modified_since)
          return true if last_modified <= client_time
        rescue ArgumentError
          # Invalid date format, ignore
        end
      end
      
      false
    end
    
    private
    
    # Basic audio file header validation
    def valid_audio_header?(content, extension)
      return false if content.nil? || content.empty?
      
      case extension
      when 'mp3'
        # MP3 files should start with ID3 tag or MP3 frame sync
        content.start_with?('ID3') || content.bytes[0..1] == [0xFF, 0xFB] || content.bytes[0..1] == [0xFF, 0xFA]
      when 'wav'
        # WAV files should start with RIFF header
        content.start_with?('RIFF') && content[8..11] == 'WAVE'
      when 'm4a'
        # M4A files should have ftyp box
        content.include?('ftyp') && (content.include?('M4A ') || content.include?('mp42'))
      else
        # For unknown extensions, just check it's not empty and not all null bytes
        !content.bytes.all? { |b| b == 0 }
      end
    end
    
    # Extract audio metadata using file analysis
    def extract_audio_metadata(file_path, extension)
      begin
        file_size = File.size(file_path)
        
        # Try to extract real metadata based on file format
        case extension.downcase
        when '.mp3'
          extract_mp3_metadata(file_path, file_size)
        when '.wav'
          extract_wav_metadata(file_path, file_size)
        when '.m4a'
          extract_m4a_metadata(file_path, file_size)
        else
          # Fallback to estimated metadata
          estimate_metadata(file_size, extension)
        end
      rescue => e
        $logger&.warn "Failed to extract metadata for #{file_path}: #{e.message}"
        estimate_metadata(File.size(file_path), extension)
      end
    end
    
    # Extract MP3 metadata from file headers
    def extract_mp3_metadata(file_path, file_size)
      File.open(file_path, 'rb') do |file|
        # Look for MP3 frame header
        file.rewind
        data = file.read(4096) # Read first 4KB
        
        # Basic MP3 frame detection
        if data && data.length >= 4
          # Look for sync word (0xFFE or 0xFFF)
          (0..data.length-4).each do |i|
            if (data.getbyte(i) == 0xFF) && ((data.getbyte(i+1) & 0xE0) == 0xE0)
              # Found potential MP3 frame
              header = data[i, 4].unpack('N')[0]
              
              # Extract bitrate and sample rate from header
              version = (header >> 19) & 3
              layer = (header >> 17) & 3
              bitrate_index = (header >> 12) & 15
              sample_rate_index = (header >> 10) & 3
              
              bitrate = get_mp3_bitrate(version, layer, bitrate_index)
              sample_rate = get_mp3_sample_rate(version, sample_rate_index)
              
              if bitrate > 0 && sample_rate > 0
                duration = (file_size * 8) / (bitrate * 1000)
                return {
                  duration: [duration.to_i, 30].max,
                  bitrate: bitrate,
                  sample_rate: sample_rate,
                  channels: 2  # Assume stereo
                }
              end
            end
          end
        end
      end
      
      # Fallback if header parsing fails
      estimate_metadata(file_size, '.mp3')
    end
    
    # Extract WAV metadata from file headers
    def extract_wav_metadata(file_path, file_size)
      File.open(file_path, 'rb') do |file|
        # Read WAV header
        header = file.read(44)
        
        if header && header.length >= 44 && header[0, 4] == 'RIFF' && header[8, 4] == 'WAVE'
          # Parse WAV header
          sample_rate = header[24, 4].unpack('V')[0]
          byte_rate = header[28, 4].unpack('V')[0]
          channels = header[22, 2].unpack('v')[0]
          bits_per_sample = header[34, 2].unpack('v')[0]
          
          if sample_rate > 0 && byte_rate > 0
            duration = (file_size - 44) / byte_rate
            bitrate = (byte_rate * 8) / 1000
            
            return {
              duration: [duration.to_i, 30].max,
              bitrate: bitrate.to_i,
              sample_rate: sample_rate,
              channels: channels
            }
          end
        end
      end
      
      # Fallback if header parsing fails
      estimate_metadata(file_size, '.wav')
    end
    
    # Extract M4A metadata (basic implementation)
    def extract_m4a_metadata(file_path, file_size)
      File.open(file_path, 'rb') do |file|
        # Look for ftyp box and other metadata
        data = file.read(1024)
        
        if data && data.include?('ftyp') && (data.include?('M4A ') || data.include?('mp42'))
          # This is a valid M4A file, use estimation
          # Real M4A parsing would require more complex box parsing
          return estimate_metadata(file_size, '.m4a')
        end
      end
      
      estimate_metadata(file_size, '.m4a')
    end
    
    # Get MP3 bitrate from header values
    def get_mp3_bitrate(version, layer, bitrate_index)
      # MP3 bitrate table (simplified)
      bitrates = {
        1 => { # MPEG-1
          1 => [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448, 0], # Layer III
          2 => [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 0],    # Layer II
          3 => [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0]     # Layer I
        }
      }
      
      return 0 if bitrate_index == 0 || bitrate_index == 15
      
      bitrates.dig(version, layer, bitrate_index) || 128 # Default to 128 kbps
    end
    
    # Get MP3 sample rate from header values
    def get_mp3_sample_rate(version, sample_rate_index)
      sample_rates = {
        1 => [44100, 48000, 32000], # MPEG-1
        2 => [22050, 24000, 16000], # MPEG-2
        3 => [11025, 12000, 8000]   # MPEG-2.5
      }
      
      sample_rates.dig(version, sample_rate_index) || 44100 # Default to 44.1kHz
    end
    
    # Estimate metadata based on file size and format
    def estimate_metadata(file_size, extension)
      # Rough estimates based on typical encoding parameters
      case extension.downcase
      when '.mp3'
        # Assume ~128kbps MP3
        bitrate = 128
        duration = (file_size * 8) / (bitrate * 1000)
      when '.wav'
        # Assume ~1.4Mbps WAV (44.1kHz, 16-bit, stereo)
        bitrate = 1411
        duration = (file_size * 8) / (bitrate * 1000)
      when '.m4a'
        # Assume ~128kbps M4A
        bitrate = 128
        duration = (file_size * 8) / (bitrate * 1000)
      else
        bitrate = 128
        duration = 120 # Default 2 minutes
      end
      
      {
        duration: [duration.to_i, 30].max, # Minimum 30 seconds
        bitrate: bitrate,
        sample_rate: 44100,
        channels: 2
      }
    end
    
    # Get MIME type for file extension
    def get_mime_type_for_extension(extension)
      case extension.downcase
      when '.mp3'
        'audio/mpeg'
      when '.wav'
        'audio/wav'
      when '.m4a'
        'audio/mp4'
      else
        'application/octet-stream'
      end
    end
    
    # Format file size for human reading
    def format_file_size(bytes)
      units = %w[B KB MB GB]
      size = bytes.to_f
      
      units.each_with_index do |unit, i|
        return "#{size.round(2)} #{unit}" if size < 1024 || i == units.length - 1
        size /= 1024
      end
    end
  end
end