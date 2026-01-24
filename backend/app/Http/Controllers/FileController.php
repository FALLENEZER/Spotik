<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\HttpFoundation\StreamedResponse;

class FileController extends Controller
{
    private const CACHE_TTL = 3600; // 1 hour
    private const BUFFER_SIZE = 65536; // 64KB buffer for better performance
    private const MAX_CACHE_FILE_SIZE = 10485760; // 10MB - don't cache files larger than this

    /**
     * Serve audio files with proper headers and streaming support
     */
    public function serve(Request $request, string $filename): Response
    {
        try {
            // Construct the file path
            $filePath = 'tracks/' . $filename;
            
            // Check cache first for file metadata
            $cacheKey = "file_metadata:{$filename}";
            $fileMetadata = Cache::remember($cacheKey, self::CACHE_TTL, function () use ($filePath) {
                if (!Storage::disk('audio')->exists($filePath)) {
                    return null;
                }

                $full = Storage::disk('audio')->path($filePath);
                return [
                    'size' => Storage::disk('audio')->size($filePath),
                    'mime_type' => mime_content_type($full) ?: 'application/octet-stream',
                    'last_modified' => Storage::disk('audio')->lastModified($filePath),
                ];
            });

            if (!$fileMetadata) {
                return response()->json([
                    'error' => 'Audio file not found'
                ], 404);
            }

            // Validate that it's an audio file
            if (!str_starts_with($fileMetadata['mime_type'], 'audio/')) {
                return response()->json([
                    'error' => 'Invalid file type'
                ], 403);
            }

            $fullPath = Storage::disk('audio')->path($filePath);
            $fileSize = $fileMetadata['size'];
            $mimeType = $fileMetadata['mime_type'];
            $lastModified = $fileMetadata['last_modified'];

            // Handle conditional requests (If-Modified-Since, ETag)
            $etag = md5($filename . $lastModified . $fileSize);
            $lastModifiedDate = gmdate('D, d M Y H:i:s', $lastModified) . ' GMT';

            // Check If-None-Match (ETag)
            if ($request->header('If-None-Match') === $etag) {
                return response('', 304);
            }

            // Check If-Modified-Since
            if ($request->header('If-Modified-Since') === $lastModifiedDate) {
                return response('', 304);
            }

            // Base headers for all responses
            $headers = [
                'Content-Type' => $mimeType,
                'Accept-Ranges' => 'bytes',
                'Cache-Control' => 'public, max-age=3600, immutable',
                'ETag' => $etag,
                'Last-Modified' => $lastModifiedDate,
                'Content-Disposition' => 'inline; filename="' . basename($filename) . '"',
                'X-Content-Type-Options' => 'nosniff',
            ];

            // Handle range requests for audio streaming
            $rangeHeader = $request->header('Range');
            
            if ($rangeHeader) {
                return $this->handleRangeRequest($fullPath, $fileSize, $mimeType, $rangeHeader, $headers);
            }

            // For small files, try to serve from cache
            if ($fileSize <= self::MAX_CACHE_FILE_SIZE) {
                $fileCacheKey = "file_content:{$filename}";
                $fileContent = Cache::remember($fileCacheKey, self::CACHE_TTL, function () use ($fullPath) {
                    return file_get_contents($fullPath);
                });

                if ($fileContent !== false) {
                    $headers['Content-Length'] = strlen($fileContent);
                    return response($fileContent, 200, $headers);
                }
            }

            // Stream large files directly
            $headers['Content-Length'] = $fileSize;
            return response()->stream(function () use ($fullPath) {
                $this->streamFile($fullPath);
            }, 200, $headers);

        } catch (\Exception $e) {
            Log::error('File serving error', [
                'filename' => $filename,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);

            return response()->json([
                'error' => 'Failed to serve audio file',
                'message' => config('app.debug') ? $e->getMessage() : 'Internal server error'
            ], 500);
        }
    }

    /**
     * Handle HTTP Range requests for audio streaming with optimized buffering
     */
    private function handleRangeRequest(string $filePath, int $fileSize, string $mimeType, string $rangeHeader, array $baseHeaders = []): StreamedResponse
    {
        // Parse range header (e.g., "bytes=0-1023")
        if (!preg_match('/bytes=(\d+)-(\d*)/', $rangeHeader, $matches)) {
            return response()->stream(function () use ($filePath) {
                $this->streamFile($filePath);
            }, 200, array_merge($baseHeaders, [
                'Content-Length' => $fileSize,
            ]));
        }

        $start = (int) $matches[1];
        $end = !empty($matches[2]) ? (int) $matches[2] : $fileSize - 1;

        // Validate range
        if ($start > $end || $start >= $fileSize || $end >= $fileSize) {
            return response()->stream(function () {}, 416, [
                'Content-Range' => "bytes */{$fileSize}",
            ]);
        }

        $contentLength = $end - $start + 1;

        $headers = array_merge($baseHeaders, [
            'Content-Length' => $contentLength,
            'Content-Range' => "bytes {$start}-{$end}/{$fileSize}",
        ]);

        return response()->stream(function () use ($filePath, $start, $contentLength) {
            $this->streamFileRange($filePath, $start, $contentLength);
        }, 206, $headers);
    }

    /**
     * Stream entire file with optimized buffering
     */
    private function streamFile(string $filePath): void
    {
        $stream = fopen($filePath, 'rb');
        if (!$stream) {
            return;
        }

        try {
            while (!feof($stream)) {
                $data = fread($stream, self::BUFFER_SIZE);
                if ($data === false) {
                    break;
                }
                
                echo $data;
                
                // Flush output to client
                if (ob_get_level()) {
                    ob_flush();
                }
                flush();

                // Check if client disconnected
                if (connection_aborted()) {
                    break;
                }
            }
        } finally {
            fclose($stream);
        }
    }

    /**
     * Stream file range with optimized buffering
     */
    private function streamFileRange(string $filePath, int $start, int $contentLength): void
    {
        $stream = fopen($filePath, 'rb');
        if (!$stream) {
            return;
        }

        try {
            fseek($stream, $start);
            
            $bytesRemaining = $contentLength;
            
            while ($bytesRemaining > 0 && !feof($stream)) {
                $bytesToRead = min(self::BUFFER_SIZE, $bytesRemaining);
                $data = fread($stream, $bytesToRead);
                
                if ($data === false) {
                    break;
                }
                
                echo $data;
                $bytesRemaining -= strlen($data);
                
                // Flush output to client
                if (ob_get_level()) {
                    ob_flush();
                }
                flush();

                // Check if client disconnected
                if (connection_aborted()) {
                    break;
                }
            }
        } finally {
            fclose($stream);
        }
    }

    /**
     * Get file metadata with caching
     */
    public function metadata(Request $request, string $filename): Response
    {
        try {
            $filePath = 'tracks/' . $filename;
            
            $cacheKey = "file_metadata:{$filename}";
            $metadata = Cache::remember($cacheKey, self::CACHE_TTL, function () use ($filePath) {
                if (!Storage::disk('audio')->exists($filePath)) {
                    return null;
                }

                $full = Storage::disk('audio')->path($filePath);
                return [
                    'size' => Storage::disk('audio')->size($filePath),
                    'mime_type' => mime_content_type($full) ?: 'application/octet-stream',
                    'last_modified' => Storage::disk('audio')->lastModified($filePath),
                ];
            });

            if (!$metadata) {
                return response()->json([
                    'error' => 'File not found'
                ], 404);
            }

            return response()->json([
                'filename' => $filename,
                'size' => $metadata['size'],
                'mime_type' => $metadata['mime_type'],
                'last_modified' => $metadata['last_modified'],
                'formatted_size' => $this->formatBytes($metadata['size']),
            ]);

        } catch (\Exception $e) {
            return response()->json([
                'error' => 'Failed to get file metadata',
                'message' => config('app.debug') ? $e->getMessage() : 'Internal server error'
            ], 500);
        }
    }

    public function servePublic(Request $request, string $path): Response
    {
        try {
            if (!preg_match('/^(room_covers|track_covers)\\//', $path)) {
                return response()->json(['error' => 'Invalid path'], 403);
            }

            if (!Storage::disk('public')->exists($path)) {
                return response()->json(['error' => 'File not found'], 404);
            }

            $mimeType = mime_content_type(Storage::disk('public')->path($path)) ?: 'application/octet-stream';
            $fullPath = Storage::disk('public')->path($path);

            return response()->file($fullPath, [
                'Content-Type' => $mimeType,
                'Cache-Control' => 'public, max-age=3600',
            ]);
        } catch (\Exception $e) {
            Log::error('Public file serving error', [
                'path' => $path,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
            
            return response()->json([
                'error' => 'Failed to serve file',
                'message' => config('app.debug') ? $e->getMessage() : 'Internal server error'
            ], 500);
        }
    }

    /**
     * Format bytes to human readable format
     */
    private function formatBytes(int $bytes): string
    {
        $units = ['B', 'KB', 'MB', 'GB'];
        $bytes = max($bytes, 0);
        $pow = floor(($bytes ? log($bytes) : 0) / log(1024));
        $pow = min($pow, count($units) - 1);
        
        $bytes /= (1 << (10 * $pow));
        
        return round($bytes, 2) . ' ' . $units[$pow];
    }
}
