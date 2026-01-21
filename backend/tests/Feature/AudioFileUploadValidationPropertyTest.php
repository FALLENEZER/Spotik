<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\Room;
use App\Models\Track;
use App\Models\RoomParticipant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;
use Tymon\JWTAuth\Facades\JWTAuth;

/**
 * Property-Based Test for Audio File Upload and Validation
 * 
 * **Feature: spotik, Property 6: Audio File Upload and Validation**
 * **Validates: Requirements 3.1, 3.3, 3.4**
 * 
 * This test validates that for any valid audio file (MP3, WAV, M4A) uploaded by a room participant,
 * the system should store the file securely and add it to the room's track queue.
 */
class AudioFileUploadValidationPropertyTest extends TestCase
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
    public function it_uploads_and_stores_valid_audio_files_for_any_room_participant()
    {
        // **Property 6: Audio File Upload and Validation**
        // **Validates: Requirements 3.1, 3.3, 3.4**
        // Property: For any valid audio file (MP3, WAV, M4A) uploaded by a room participant,
        // the system should store the file securely and add it to the room's track queue

        // Run property test with multiple iterations
        for ($iteration = 0; $iteration < 100; $iteration++) {
            // Generate random room administrator
            $admin = User::factory()->create([
                'username' => fake()->unique()->userName(),
                'email' => fake()->unique()->safeEmail(),
            ]);
            $adminToken = JWTAuth::fromUser($admin);

            // Create room
            $roomData = ['name' => $this->generateValidRoomName()];
            $roomResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->postJson('/api/rooms', $roomData);

            $roomResponse->assertStatus(201);
            $roomId = $roomResponse->json('data.id');
            $room = Room::find($roomId);

            // Generate random participant (could be admin or different user)
            $isAdminUpload = fake()->boolean(30); // 30% chance admin uploads, 70% regular participant
            
            if ($isAdminUpload) {
                $uploader = $admin;
                $uploaderToken = $adminToken;
            } else {
                $uploader = User::factory()->create([
                    'username' => fake()->unique()->userName(),
                    'email' => fake()->unique()->safeEmail(),
                ]);
                $uploaderToken = JWTAuth::fromUser($uploader);
                
                // Join room as participant
                $joinResponse = $this->withHeaders([
                    'Authorization' => 'Bearer ' . $uploaderToken,
                ])->postJson("/api/rooms/{$roomId}/join");
                $joinResponse->assertStatus(200);
            }

            // Generate random valid audio file
            $audioFileData = $this->generateValidAudioFile();
            $audioFile = $audioFileData['file'];
            $expectedMimeType = $audioFileData['mime_type'];
            $expectedExtension = $audioFileData['extension'];

            // Test file upload
            $uploadResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $uploaderToken,
            ])->postJson("/api/rooms/{$roomId}/tracks", [
                'audio_file' => $audioFile,
            ]);

            // **Requirement 3.1 Validation**: Valid audio file upload should store securely
            $uploadResponse->assertStatus(201)
                          ->assertJsonStructure([
                              'message',
                              'track' => [
                                  'id',
                                  'original_name',
                                  'duration_seconds',
                                  'formatted_duration',
                                  'file_size_bytes',
                                  'formatted_file_size',
                                  'mime_type',
                                  'vote_score',
                                  'uploader' => ['id', 'username'],
                                  'user_has_voted',
                                  'created_at',
                                  'file_url',
                              ]
                          ])
                          ->assertJson([
                              'message' => 'Track uploaded successfully',
                              'track' => [
                                  'original_name' => $audioFile->getClientOriginalName(),
                                  'mime_type' => $expectedMimeType,
                                  'vote_score' => 0,
                                  'uploader' => [
                                      'id' => $uploader->id,
                                      'username' => $uploader->username,
                                  ],
                                  'user_has_voted' => false,
                              ]
                          ]);

            $trackId = $uploadResponse->json('track.id');
            $this->assertNotNull($trackId);

            // Verify track was stored in database
            $this->assertDatabaseHas('tracks', [
                'id' => $trackId,
                'room_id' => $roomId,
                'uploader_id' => $uploader->id,
                'original_name' => $audioFile->getClientOriginalName(),
                'mime_type' => $expectedMimeType,
                'vote_score' => 0,
            ]);

            $track = Track::find($trackId);
            $this->assertNotNull($track);

            // **Requirement 3.1 Validation**: Verify file was stored securely using Laravel Storage
            $this->assertTrue(Storage::disk('audio')->exists($track->file_path));
            $this->assertStringStartsWith('tracks/', $track->file_path);
            $this->assertStringEndsWith('.' . $expectedExtension, $track->file_path);

            // Verify file metadata was extracted correctly
            $this->assertGreaterThan(0, $track->file_size_bytes);
            $this->assertGreaterThanOrEqual(0, $track->duration_seconds);
            $this->assertNotEmpty($track->filename);
            $this->assertNotEmpty($track->file_path);

            // **Requirement 3.3 Validation**: Audio file should be added to room's track queue
            $queueResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $uploaderToken,
            ])->getJson("/api/rooms/{$roomId}/tracks");

            $queueResponse->assertStatus(200)
                         ->assertJsonStructure([
                             'tracks' => [
                                 '*' => [
                                     'id',
                                     'original_name',
                                     'duration_seconds',
                                     'formatted_duration',
                                     'file_size_bytes',
                                     'formatted_file_size',
                                     'mime_type',
                                     'vote_score',
                                     'uploader',
                                     'user_has_voted',
                                     'created_at',
                                     'file_url',
                                 ]
                             ],
                             'total_count'
                         ]);

            $tracks = $queueResponse->json('tracks');
            $this->assertCount(1, $tracks);
            $this->assertEquals($trackId, $tracks[0]['id']);
            $this->assertEquals($audioFile->getClientOriginalName(), $tracks[0]['original_name']);

            // **Requirement 3.4 Validation**: Verify supported audio format was accepted
            $supportedMimeTypes = ['audio/mpeg', 'audio/wav', 'audio/mp4', 'audio/x-m4a'];
            $this->assertContains($track->mime_type, $supportedMimeTypes);

            $supportedExtensions = ['mp3', 'wav', 'm4a'];
            $fileExtension = pathinfo($track->original_name, PATHINFO_EXTENSION);
            $this->assertContains(strtolower($fileExtension), $supportedExtensions);

            // Verify file can be served (skip in testing with fake storage)
            if (!app()->environment('testing')) {
                $this->assertTrue($track->fileExists());
            }
            $this->assertNotEmpty($track->getFileUrl());

            // Verify track relationships
            $this->assertEquals($roomId, $track->room_id);
            $this->assertEquals($uploader->id, $track->uploader_id);
            $this->assertEquals($room->id, $track->room->id);
            $this->assertEquals($uploader->id, $track->uploader->id);

            // Verify track is in room's queue with correct ordering
            $roomTracks = $room->trackQueue()->get();
            $this->assertCount(1, $roomTracks);
            $this->assertEquals($trackId, $roomTracks->first()->id);

            // Verify formatted values
            $this->assertMatchesRegularExpression('/^\d+:\d{2}$/', $track->getFormattedDuration());
            $this->assertMatchesRegularExpression('/^[\d.]+\s+(B|KB|MB|GB)$/', $track->getFormattedFileSize());

            // Test file size validation boundaries
            $this->assertLessThanOrEqual(Track::MAX_FILE_SIZE, $track->file_size_bytes);
            $this->assertGreaterThan(0, $track->file_size_bytes);

            // Verify voting functionality works with uploaded track
            $voteResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $uploaderToken,
            ])->postJson("/api/rooms/{$roomId}/tracks/{$trackId}/vote");

            $voteResponse->assertStatus(200)
                        ->assertJsonStructure([
                            'message',
                            'vote_score',
                            'user_has_voted',
                        ])
                        ->assertJson([
                            'user_has_voted' => true,
                        ]);

            $voteScore = $voteResponse->json('vote_score');
            $this->assertGreaterThan(0, $voteScore);

            // Verify vote was recorded
            $this->assertDatabaseHas('track_votes', [
                'track_id' => $trackId,
                'user_id' => $uploader->id,
            ]);

            // Clean up for next iteration
            $room->delete();
        }
    }

    /** @test */
    public function it_handles_various_valid_audio_file_formats_consistently()
    {
        // Property: The system should handle all supported audio formats (MP3, WAV, M4A) consistently
        
        $supportedFormats = [
            ['extension' => 'mp3', 'mime_type' => 'audio/mpeg'],
            ['extension' => 'wav', 'mime_type' => 'audio/wav'],
            ['extension' => 'm4a', 'mime_type' => 'audio/mp4'],
            ['extension' => 'm4a', 'mime_type' => 'audio/x-m4a'],
        ];

        foreach ($supportedFormats as $format) {
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

            // Create participant
            $participant = User::factory()->create([
                'username' => fake()->unique()->userName(),
                'email' => fake()->unique()->safeEmail(),
            ]);
            $participantToken = JWTAuth::fromUser($participant);

            $this->withHeaders([
                'Authorization' => 'Bearer ' . $participantToken,
            ])->postJson("/api/rooms/{$roomId}/join")->assertStatus(200);

            // Test file upload for this format
            $audioFile = $this->createTestAudioFile($format['extension'], $format['mime_type']);

            $uploadResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $participantToken,
            ])->postJson("/api/rooms/{$roomId}/tracks", [
                'audio_file' => $audioFile,
            ]);

            // Verify consistent behavior across all formats
            $uploadResponse->assertStatus(201)
                          ->assertJsonStructure([
                              'message',
                              'track' => [
                                  'id',
                                  'original_name',
                                  'duration_seconds',
                                  'file_size_bytes',
                                  'mime_type',
                                  'vote_score',
                                  'uploader',
                                  'file_url',
                              ]
                          ])
                          ->assertJson([
                              'message' => 'Track uploaded successfully',
                              'track' => [
                                  'mime_type' => $format['mime_type'],
                                  'vote_score' => 0,
                              ]
                          ]);

            $trackId = $uploadResponse->json('track.id');
            $track = Track::find($trackId);

            // Verify file was stored correctly
            $this->assertTrue(Storage::disk('audio')->exists($track->file_path));
            $this->assertEquals($format['mime_type'], $track->mime_type);
            $this->assertStringEndsWith('.' . $format['extension'], $track->file_path);

            // Verify track appears in queue
            $queueResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $participantToken,
            ])->getJson("/api/rooms/{$roomId}/tracks");

            $queueResponse->assertStatus(200);
            $tracks = $queueResponse->json('tracks');
            $this->assertCount(1, $tracks);
            $this->assertEquals($trackId, $tracks[0]['id']);

            // Clean up
            Room::find($roomId)->delete();
        }
    }

    /** @test */
    public function it_maintains_track_queue_ordering_with_multiple_uploads()
    {
        // Property: Track queue should maintain proper ordering (by vote score desc, then created_at asc)
        
        for ($iteration = 0; $iteration < 10; $iteration++) {
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

            // Create multiple participants
            $participants = [];
            for ($i = 0; $i < 3; $i++) {
                $participant = User::factory()->create([
                    'username' => fake()->unique()->userName(),
                    'email' => fake()->unique()->safeEmail(),
                ]);
                $participants[] = $participant;
                
                $participantToken = JWTAuth::fromUser($participant);
                $this->withHeaders([
                    'Authorization' => 'Bearer ' . $participantToken,
                ])->postJson("/api/rooms/{$roomId}/join")->assertStatus(200);
            }

            // Upload multiple tracks
            $uploadedTracks = [];
            foreach ($participants as $index => $participant) {
                $participantToken = JWTAuth::fromUser($participant);
                $audioFileData = $this->generateValidAudioFile();

                $uploadResponse = $this->withHeaders([
                    'Authorization' => 'Bearer ' . $participantToken,
                ])->postJson("/api/rooms/{$roomId}/tracks", [
                    'audio_file' => $audioFileData['file'],
                ]);

                $uploadResponse->assertStatus(201);
                $trackId = $uploadResponse->json('track.id');
                $uploadedTracks[] = [
                    'id' => $trackId,
                    'uploader' => $participant,
                    'upload_order' => $index,
                ];

                // Ensure different created_at timestamps by updating the track
                if ($index > 0) {
                    // Update the created_at to ensure proper ordering
                    \DB::table('tracks')
                        ->where('id', $trackId)
                        ->update(['created_at' => now()->addSeconds($index)]);
                }
            }

            // Verify initial queue ordering (by created_at since all have 0 votes)
            $queueResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->getJson("/api/rooms/{$roomId}/tracks");

            $queueResponse->assertStatus(200);
            $tracks = $queueResponse->json('tracks');
            $this->assertCount(3, $tracks);

            // All tracks should have 0 votes initially, so ordered by created_at (first uploaded first)
            for ($i = 0; $i < 3; $i++) {
                $this->assertEquals($uploadedTracks[$i]['id'], $tracks[$i]['id']);
                $this->assertEquals(0, $tracks[$i]['vote_score']);
            }

            // Add votes to change ordering
            // Vote for the last uploaded track (should move to top)
            $lastTrackId = $uploadedTracks[2]['id'];
            $voteResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->postJson("/api/rooms/{$roomId}/tracks/{$lastTrackId}/vote");
            $voteResponse->assertStatus(200);

            // Vote for the middle track (should be second)
            $middleTrackId = $uploadedTracks[1]['id'];
            $voteResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . JWTAuth::fromUser($participants[0]),
            ])->postJson("/api/rooms/{$roomId}/tracks/{$middleTrackId}/vote");
            $voteResponse->assertStatus(200);

            // Verify new queue ordering
            $newQueueResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->getJson("/api/rooms/{$roomId}/tracks");

            $newQueueResponse->assertStatus(200);
            $newTracks = $newQueueResponse->json('tracks');
            $this->assertCount(3, $newTracks);

            // Should be ordered: middle track (1 vote, uploaded earlier), last track (1 vote, uploaded later), first track (0 votes)
            $this->assertEquals($middleTrackId, $newTracks[0]['id']);
            $this->assertEquals(1, $newTracks[0]['vote_score']);
            
            $this->assertEquals($lastTrackId, $newTracks[1]['id']);
            $this->assertEquals(1, $newTracks[1]['vote_score']);
            
            $this->assertEquals($uploadedTracks[0]['id'], $newTracks[2]['id']);
            $this->assertEquals(0, $newTracks[2]['vote_score']);

            // Clean up
            Room::find($roomId)->delete();
        }
    }

    /** @test */
    public function it_validates_file_metadata_extraction_for_all_supported_formats()
    {
        // Property: System should extract valid metadata (duration, size) from all supported audio formats
        
        $testCases = [
            ['extension' => 'mp3', 'mime_type' => 'audio/mpeg'],
            ['extension' => 'wav', 'mime_type' => 'audio/wav'],
            ['extension' => 'm4a', 'mime_type' => 'audio/mp4'],
        ];

        foreach ($testCases as $testCase) {
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

            // Create test audio file
            $audioFile = $this->createTestAudioFile($testCase['extension'], $testCase['mime_type']);

            // Upload file
            $uploadResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $userToken,
            ])->postJson("/api/rooms/{$roomId}/tracks", [
                'audio_file' => $audioFile,
            ]);

            $uploadResponse->assertStatus(201);
            $trackData = $uploadResponse->json('track');

            // Verify metadata was extracted
            $this->assertIsInt($trackData['duration_seconds']);
            $this->assertGreaterThanOrEqual(0, $trackData['duration_seconds']);
            
            $this->assertIsInt($trackData['file_size_bytes']);
            $this->assertGreaterThan(0, $trackData['file_size_bytes']);
            
            $this->assertIsString($trackData['formatted_duration']);
            $this->assertMatchesRegularExpression('/^\d+:\d{2}$/', $trackData['formatted_duration']);
            
            $this->assertIsString($trackData['formatted_file_size']);
            $this->assertMatchesRegularExpression('/^[\d.]+\s+(B|KB|MB|GB)$/', $trackData['formatted_file_size']);

            $this->assertEquals($testCase['mime_type'], $trackData['mime_type']);

            // Verify database record
            $track = Track::find($trackData['id']);
            $this->assertNotNull($track);
            $this->assertEquals($testCase['mime_type'], $track->mime_type);
            $this->assertGreaterThanOrEqual(0, $track->duration_seconds);
            $this->assertGreaterThan(0, $track->file_size_bytes);

            // Clean up
            Room::find($roomId)->delete();
        }
    }

    /**
     * Generate a valid audio file for testing
     */
    private function generateValidAudioFile(): array
    {
        $formats = [
            ['extension' => 'mp3', 'mime_type' => 'audio/mpeg'],
            ['extension' => 'wav', 'mime_type' => 'audio/wav'],
            ['extension' => 'm4a', 'mime_type' => 'audio/mp4'],
            ['extension' => 'm4a', 'mime_type' => 'audio/x-m4a'],
        ];

        $format = fake()->randomElement($formats);
        
        return [
            'file' => $this->createTestAudioFile($format['extension'], $format['mime_type']),
            'extension' => $format['extension'],
            'mime_type' => $format['mime_type'],
        ];
    }

    /**
     * Create a test audio file
     */
    private function createTestAudioFile(string $extension, string $mimeType): UploadedFile
    {
        // Create a minimal valid audio file content based on format
        $content = $this->generateMinimalAudioContent($extension);
        
        $filename = fake()->word() . '_' . fake()->numberBetween(1, 999) . '.' . $extension;
        $size = strlen($content);
        
        return UploadedFile::fake()->createWithContent($filename, $content)
                          ->mimeType($mimeType);
    }

    /**
     * Generate minimal valid audio content for testing
     */
    private function generateMinimalAudioContent(string $extension): string
    {
        switch ($extension) {
            case 'mp3':
                // Minimal MP3 header
                return "\xFF\xFB\x90\x00" . str_repeat("\x00", 1000);
            
            case 'wav':
                // Minimal WAV header
                $header = "RIFF" . pack('V', 36) . "WAVE";
                $header .= "fmt " . pack('V', 16) . pack('v', 1) . pack('v', 1);
                $header .= pack('V', 44100) . pack('V', 88200) . pack('v', 2) . pack('v', 16);
                $header .= "data" . pack('V', 0);
                return $header . str_repeat("\x00", 1000);
            
            case 'm4a':
                // Minimal M4A/MP4 header
                return "\x00\x00\x00\x20ftypM4A " . str_repeat("\x00", 1000);
            
            default:
                return str_repeat("\x00", 1000);
        }
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
            fn() => fake()->firstName() . "'s Room",
        ];

        $nameGenerator = fake()->randomElement($nameTypes);
        $name = $nameGenerator();

        return substr($name, 0, 100);
    }
}