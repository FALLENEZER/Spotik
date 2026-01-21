<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\Room;
use App\Models\Track;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;
use Tymon\JWTAuth\Facades\JWTAuth;

/**
 * Property-Based Test for Invalid File Rejection
 * 
 * **Feature: spotik, Property 7: Invalid File Rejection**
 * **Validates: Requirements 3.2**
 * 
 * This test validates that for any invalid file type or malformed audio file,
 * the system should reject the upload and return an appropriate error message
 * without affecting the track queue.
 */
class InvalidFileRejectionPropertyTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        
        // Set up storage for testing
        Storage::fake('audio');
        
        // Create audio directory
        Storage::disk('audio')->makeDirectory('tracks');
    }

    /** @test */
    public function it_rejects_invalid_file_types_with_appropriate_error_messages()
    {
        // **Property 7: Invalid File Rejection**
        // **Validates: Requirements 3.2**
        // Property: For any invalid file type or malformed audio file, the system should
        // reject the upload and return an appropriate error message without affecting the track queue

        // Run property test with multiple iterations
        for ($iteration = 0; $iteration < 100; $iteration++) {
            // Create test environment
            $admin = User::factory()->create([
                'username' => fake()->unique()->userName(),
                'email' => fake()->unique()->safeEmail(),
            ]);
            $adminToken = JWTAuth::fromUser($admin);

            $roomData = ['name' => $this->generateValidRoomName()];
            $roomResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->postJson('/api/rooms', $roomData);

            $roomResponse->assertStatus(201);
            $roomId = $roomResponse->json('data.id');
            $room = Room::find($roomId);

            // Create participant
            $participant = User::factory()->create([
                'username' => fake()->unique()->userName(),
                'email' => fake()->unique()->safeEmail(),
            ]);
            $participantToken = JWTAuth::fromUser($participant);

            $this->withHeaders([
                'Authorization' => 'Bearer ' . $participantToken,
            ])->postJson("/api/rooms/{$roomId}/join")->assertStatus(200);

            // Get initial track count
            $initialTrackCount = Track::where('room_id', $roomId)->count();
            $this->assertEquals(0, $initialTrackCount);

            // Generate random invalid file
            $invalidFileData = $this->generateInvalidFile();
            $invalidFile = $invalidFileData['file'];
            $expectedErrorType = $invalidFileData['error_type'];

            // Test invalid file upload
            $uploadResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $participantToken,
            ])->postJson("/api/rooms/{$roomId}/tracks", [
                'audio_file' => $invalidFile,
            ]);

            // **Requirement 3.2 Validation**: Invalid file type should be rejected with error message
            $uploadResponse->assertStatus(422)
                          ->assertJsonStructure([
                              'error',
                              'errors'
                          ]);

            $responseData = $uploadResponse->json();
            $this->assertEquals('Validation failed', $responseData['error']);
            $this->assertArrayHasKey('errors', $responseData);
            $this->assertArrayHasKey('audio_file', $responseData['errors']);

            // Verify appropriate error message based on error type
            $errorMessages = $responseData['errors']['audio_file'];
            $this->assertIsArray($errorMessages);
            $this->assertNotEmpty($errorMessages);

            switch ($expectedErrorType) {
                case 'invalid_extension':
                    $this->assertTrue(
                        $this->containsErrorMessage($errorMessages, ['mimes', 'extension', 'type']) ||
                        $this->containsErrorMessage($errorMessages, ['uploaded', 'file', 'must', 'type']),
                        'Should contain file type/extension error message'
                    );
                    break;
                
                case 'invalid_mime_type':
                    $this->assertTrue(
                        $this->containsErrorMessage($errorMessages, ['mimetypes', 'mime', 'type']) ||
                        $this->containsErrorMessage($errorMessages, ['uploaded', 'file', 'must', 'type']),
                        'Should contain MIME type error message'
                    );
                    break;
                
                case 'file_too_large':
                    $this->assertTrue(
                        $this->containsErrorMessage($errorMessages, ['greater', 'kilobytes']) ||
                        $this->containsErrorMessage($errorMessages, ['max', 'size', 'large']),
                        'Should contain file size error message'
                    );
                    break;
                
                case 'not_a_file':
                    $this->assertTrue(
                        $this->containsErrorMessage($errorMessages, ['file', 'required']) ||
                        $this->containsErrorMessage($errorMessages, ['field', 'required']),
                        'Should contain file requirement error message'
                    );
                    break;
                
                case 'corrupted_file':
                    // May pass initial validation but fail during processing
                    if ($uploadResponse->status() === 422) {
                        $this->assertTrue(
                            $this->containsErrorMessage($errorMessages, ['file', 'invalid', 'corrupted']),
                            'Should contain file corruption error message'
                        );
                    }
                    break;
            }

            // Verify track was NOT created in database
            $finalTrackCount = Track::where('room_id', $roomId)->count();
            $this->assertEquals($initialTrackCount, $finalTrackCount, 'Track count should not change after invalid upload');

            // Verify no files were stored
            $storedFiles = Storage::disk('audio')->files('tracks');
            $this->assertEmpty($storedFiles, 'No files should be stored for invalid uploads');

            // Verify track queue remains empty
            $queueResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $participantToken,
            ])->getJson("/api/rooms/{$roomId}/tracks");

            $queueResponse->assertStatus(200)
                         ->assertJson([
                             'tracks' => [],
                             'total_count' => 0,
                         ]);

            // Verify room state is unchanged
            $room->refresh();
            $this->assertNull($room->current_track_id);
            $this->assertFalse($room->is_playing);

            // Clean up for next iteration
            $room->delete();
        }
    }

    /** @test */
    public function it_rejects_files_exceeding_maximum_size_limit()
    {
        // Property: Files exceeding the maximum size limit (50MB) should be rejected
        
        for ($iteration = 0; $iteration < 10; $iteration++) {
            // Create test environment
            $user = User::factory()->create([
                'username' => fake()->unique()->userName(),
                'email' => fake()->unique()->safeEmail(),
            ]);
            $userToken = JWTAuth::fromUser($user);

            $roomData = ['name' => $this->generateValidRoomName()];
            $roomResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $userToken,
            ])->postJson('/api/rooms', $roomData);

            $roomResponse->assertStatus(201);
            $roomId = $roomResponse->json('data.id');

            // Create oversized file (larger than 50MB)
            $oversizedFile = $this->createOversizedFile();

            // Test upload
            $uploadResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $userToken,
            ])->postJson("/api/rooms/{$roomId}/tracks", [
                'audio_file' => $oversizedFile,
            ]);

            // Verify rejection
            $uploadResponse->assertStatus(422)
                          ->assertJsonStructure([
                              'error',
                              'errors' => [
                                  'audio_file'
                              ]
                          ]);

            $errorMessages = $uploadResponse->json('errors.audio_file');
            
            $this->assertTrue(
                $this->containsErrorMessage($errorMessages, ['greater', 'kilobytes']) ||
                $this->containsErrorMessage($errorMessages, ['max', 'size', 'large']),
                'Should contain file size error message'
            );

            // Verify no track was created
            $this->assertEquals(0, Track::where('room_id', $roomId)->count());

            // Verify no files were stored
            $this->assertEmpty(Storage::disk('audio')->files('tracks'));

            // Clean up
            Room::find($roomId)->delete();
        }
    }

    /** @test */
    public function it_rejects_unsupported_file_extensions_consistently()
    {
        // Property: All unsupported file extensions should be rejected consistently
        
        $unsupportedExtensions = [
            'txt', 'doc', 'pdf', 'jpg', 'png', 'gif', 'zip', 'exe',
            'avi', 'mov', 'mkv', 'flv', 'wmv', 'ogg', 'flac', 'aac',
            'wma', 'ra', 'au', 'aiff', 'caf', 'opus', 'webm'
        ];

        foreach ($unsupportedExtensions as $extension) {
            // Create test environment
            $user = User::factory()->create([
                'username' => fake()->unique()->userName(),
                'email' => fake()->unique()->safeEmail(),
            ]);
            $userToken = JWTAuth::fromUser($user);

            $roomData = ['name' => $this->generateValidRoomName()];
            $roomResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $userToken,
            ])->postJson('/api/rooms', $roomData);

            $roomResponse->assertStatus(201);
            $roomId = $roomResponse->json('data.id');

            // Create file with unsupported extension
            $unsupportedFile = $this->createFileWithExtension($extension);

            // Test upload
            $uploadResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $userToken,
            ])->postJson("/api/rooms/{$roomId}/tracks", [
                'audio_file' => $unsupportedFile,
            ]);

            // Verify consistent rejection
            $uploadResponse->assertStatus(422)
                          ->assertJsonStructure([
                              'error',
                              'errors' => [
                                  'audio_file'
                              ]
                          ]);

            $errorMessages = $uploadResponse->json('errors.audio_file');
            $this->assertTrue(
                $this->containsErrorMessage($errorMessages, ['mimes', 'extension', 'type']) ||
                $this->containsErrorMessage($errorMessages, ['uploaded', 'file', 'must', 'type']),
                "Should reject .{$extension} files with appropriate error message"
            );

            // Verify no track was created
            $this->assertEquals(0, Track::where('room_id', $roomId)->count());

            // Clean up
            Room::find($roomId)->delete();
        }
    }

    /** @test */
    public function it_rejects_unsupported_mime_types_consistently()
    {
        // Property: All unsupported MIME types should be rejected consistently
        
        $unsupportedMimeTypes = [
            'text/plain',
            'application/pdf',
            'image/jpeg',
            'image/png',
            'video/mp4',
            'video/avi',
            'application/zip',
            'audio/ogg',
            'audio/flac',
            'audio/aac',
            'audio/wma',
            'audio/x-ms-wma',
            'audio/vnd.rn-realaudio',
            'audio/x-aiff',
            'audio/x-caf',
            'audio/opus',
            'audio/webm',
        ];

        foreach ($unsupportedMimeTypes as $mimeType) {
            // Create test environment
            $user = User::factory()->create([
                'username' => fake()->unique()->userName(),
                'email' => fake()->unique()->safeEmail(),
            ]);
            $userToken = JWTAuth::fromUser($user);

            $roomData = ['name' => $this->generateValidRoomName()];
            $roomResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $userToken,
            ])->postJson('/api/rooms', $roomData);

            $roomResponse->assertStatus(201);
            $roomId = $roomResponse->json('data.id');

            // Create file with unsupported MIME type
            $unsupportedFile = $this->createFileWithMimeType($mimeType);

            // Test upload
            $uploadResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $userToken,
            ])->postJson("/api/rooms/{$roomId}/tracks", [
                'audio_file' => $unsupportedFile,
            ]);

            // Verify consistent rejection
            $uploadResponse->assertStatus(422)
                          ->assertJsonStructure([
                              'error',
                              'errors' => [
                                  'audio_file'
                              ]
                          ]);

            $errorMessages = $uploadResponse->json('errors.audio_file');
            $this->assertTrue(
                $this->containsErrorMessage($errorMessages, ['mimetypes', 'mime', 'type']) ||
                $this->containsErrorMessage($errorMessages, ['mimes', 'extension']) ||
                $this->containsErrorMessage($errorMessages, ['uploaded', 'file', 'must', 'type']),
                "Should reject {$mimeType} files with appropriate error message"
            );

            // Verify no track was created
            $this->assertEquals(0, Track::where('room_id', $roomId)->count());

            // Clean up
            Room::find($roomId)->delete();
        }
    }

    /** @test */
    public function it_handles_corrupted_and_malformed_files_gracefully()
    {
        // Property: Corrupted or malformed files should be handled gracefully without system errors
        
        $corruptedFileTypes = [
            'empty_file',
            'truncated_header',
            'invalid_header',
            'mixed_format',
            'binary_garbage',
        ];

        foreach ($corruptedFileTypes as $corruptionType) {
            // Create test environment
            $user = User::factory()->create([
                'username' => fake()->unique()->userName(),
                'email' => fake()->unique()->safeEmail(),
            ]);
            $userToken = JWTAuth::fromUser($user);

            $roomData = ['name' => $this->generateValidRoomName()];
            $roomResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $userToken,
            ])->postJson('/api/rooms', $roomData);

            $roomResponse->assertStatus(201);
            $roomId = $roomResponse->json('data.id');

            // Create corrupted file
            $corruptedFile = $this->createCorruptedFile($corruptionType);

            // Test upload
            $uploadResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $userToken,
            ])->postJson("/api/rooms/{$roomId}/tracks", [
                'audio_file' => $corruptedFile,
            ]);

            // Should be rejected gracefully (either 422 validation error or 500 with proper error handling)
            $this->assertContains($uploadResponse->status(), [422, 500]);

            if ($uploadResponse->status() === 422) {
                $uploadResponse->assertJsonStructure([
                    'error',
                    'errors'
                ]);
            } else {
                $uploadResponse->assertJsonStructure([
                    'error',
                    'message'
                ]);
            }

            // Verify no track was created
            $this->assertEquals(0, Track::where('room_id', $roomId)->count());

            // Verify no files were stored
            $this->assertEmpty(Storage::disk('audio')->files('tracks'));

            // Clean up
            Room::find($roomId)->delete();
        }
    }

    /** @test */
    public function it_maintains_system_integrity_after_invalid_upload_attempts()
    {
        // Property: System should maintain integrity and continue functioning after invalid upload attempts
        
        for ($iteration = 0; $iteration < 5; $iteration++) {
            // Create test environment
            $user = User::factory()->create([
                'username' => fake()->unique()->userName(),
                'email' => fake()->unique()->safeEmail(),
            ]);
            $userToken = JWTAuth::fromUser($user);

            $roomData = ['name' => $this->generateValidRoomName()];
            $roomResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $userToken,
            ])->postJson('/api/rooms', $roomData);

            $roomResponse->assertStatus(201);
            $roomId = $roomResponse->json('data.id');

            // Attempt multiple invalid uploads
            for ($attempt = 0; $attempt < 5; $attempt++) {
                $invalidFile = $this->generateInvalidFile()['file'];
                
                $uploadResponse = $this->withHeaders([
                    'Authorization' => 'Bearer ' . $userToken,
                ])->postJson("/api/rooms/{$roomId}/tracks", [
                    'audio_file' => $invalidFile,
                ]);

                // Should be rejected
                $this->assertContains($uploadResponse->status(), [422, 500]);
            }

            // Verify system still functions correctly
            // 1. Can still get room details
            $roomResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $userToken,
            ])->getJson("/api/rooms/{$roomId}");
            $roomResponse->assertStatus(200);

            // 2. Can still get track queue
            $queueResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $userToken,
            ])->getJson("/api/rooms/{$roomId}/tracks");
            $queueResponse->assertStatus(200)
                         ->assertJson([
                             'tracks' => [],
                             'total_count' => 0,
                         ]);

            // 3. Can still upload valid file
            $validFile = $this->createValidAudioFile();
            $validUploadResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $userToken,
            ])->postJson("/api/rooms/{$roomId}/tracks", [
                'audio_file' => $validFile,
            ]);
            $validUploadResponse->assertStatus(201);

            // 4. Verify valid upload worked
            $this->assertEquals(1, Track::where('room_id', $roomId)->count());

            // Clean up
            Room::find($roomId)->delete();
        }
    }

    /**
     * Generate an invalid file for testing
     */
    private function generateInvalidFile(): array
    {
        $invalidTypes = [
            'invalid_extension',
            'invalid_mime_type',
            'file_too_large',
            'corrupted_file',
        ];

        $errorType = fake()->randomElement($invalidTypes);

        switch ($errorType) {
            case 'invalid_extension':
                return [
                    'file' => $this->createFileWithExtension(fake()->randomElement(['txt', 'jpg', 'pdf', 'zip'])),
                    'error_type' => $errorType,
                ];

            case 'invalid_mime_type':
                return [
                    'file' => $this->createFileWithMimeType(fake()->randomElement(['text/plain', 'image/jpeg', 'application/pdf'])),
                    'error_type' => $errorType,
                ];

            case 'file_too_large':
                return [
                    'file' => $this->createOversizedFile(),
                    'error_type' => $errorType,
                ];

            case 'corrupted_file':
                return [
                    'file' => $this->createCorruptedFile('binary_garbage'),
                    'error_type' => $errorType,
                ];

            default:
                return [
                    'file' => $this->createFileWithExtension('txt'),
                    'error_type' => 'invalid_extension',
                ];
        }
    }

    /**
     * Create a file with specific extension
     */
    private function createFileWithExtension(string $extension): UploadedFile
    {
        $filename = fake()->word() . '.' . $extension;
        $content = fake()->text(1000);
        
        return UploadedFile::fake()->createWithContent($filename, $content);
    }

    /**
     * Create a file with specific MIME type
     */
    private function createFileWithMimeType(string $mimeType): UploadedFile
    {
        $filename = fake()->word() . '.mp3'; // Use valid extension but wrong MIME type
        $content = fake()->text(1000);
        
        return UploadedFile::fake()->createWithContent($filename, $content)
                          ->mimeType($mimeType);
    }

    /**
     * Create an oversized file (larger than 50MB)
     */
    private function createOversizedFile(): UploadedFile
    {
        $filename = fake()->word() . '.mp3';
        // Create content larger than 50MB
        $oversizeKB = (Track::MAX_FILE_SIZE / 1024) + 1000; // 1MB over the limit
        
        return UploadedFile::fake()->create($filename, $oversizeKB, 'audio/mpeg');
    }

    /**
     * Create a corrupted file
     */
    private function createCorruptedFile(string $corruptionType): UploadedFile
    {
        $filename = fake()->word() . '.mp3';
        
        switch ($corruptionType) {
            case 'empty_file':
                $content = '';
                break;
                
            case 'truncated_header':
                $content = "\xFF\xFB"; // Incomplete MP3 header
                break;
                
            case 'invalid_header':
                $content = "\x00\x00\x00\x00" . str_repeat("\x00", 100);
                break;
                
            case 'mixed_format':
                $content = "\xFF\xFB\x90\x00" . "RIFF" . str_repeat("\x00", 100); // MP3 + WAV headers
                break;
                
            case 'binary_garbage':
            default:
                $content = str_repeat(chr(fake()->numberBetween(0, 255)), 1000);
                break;
        }
        
        return UploadedFile::fake()->createWithContent($filename, $content)
                          ->mimeType('audio/mpeg');
    }

    /**
     * Create a valid audio file for testing
     */
    private function createValidAudioFile(): UploadedFile
    {
        $filename = fake()->word() . '.mp3';
        // Minimal valid MP3 content
        $content = "\xFF\xFB\x90\x00" . str_repeat("\x00", 1000);
        
        return UploadedFile::fake()->createWithContent($filename, $content)
                          ->mimeType('audio/mpeg');
    }

    /**
     * Check if error messages contain expected keywords
     */
    private function containsErrorMessage(array $messages, array $keywords): bool
    {
        $allMessages = implode(' ', $messages);
        $lowerMessages = strtolower($allMessages);
        
        foreach ($keywords as $keyword) {
            if (str_contains($lowerMessages, strtolower($keyword))) {
                return true;
            }
        }
        
        return false;
    }

    /**
     * Generate a valid room name for testing
     */
    private function generateValidRoomName(): string
    {
        $nameTypes = [
            fn() => fake()->words(2, true),
            fn() => fake()->company() . ' Room',
            fn() => fake()->colorName() . ' ' . fake()->word(),
            fn() => 'Room ' . fake()->numberBetween(1, 9999),
        ];

        $nameGenerator = fake()->randomElement($nameTypes);
        $name = $nameGenerator();

        return substr($name, 0, 100);
    }
}