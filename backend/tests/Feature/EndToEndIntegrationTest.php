<?php

/**
 * End-to-End Integration Test for Spotik Backend
 * 
 * This test suite validates complete backend workflows and API integration.
 * It tests the integration of all backend components including:
 * - User authentication and registration
 * - Room creation and management
 * - File upload and validation
 * - WebSocket broadcasting
 * - Track voting and queue management
 * - Playback controls and synchronization
 * 
 * Requirements: All requirements (1-10)
 */

use App\Models\User;
use App\Models\Room;
use App\Models\Track;
use App\Models\RoomParticipant;
use App\Models\TrackVote;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Redis;
use Laravel\Sanctum\Sanctum;

uses(RefreshDatabase::class);

describe('End-to-End Backend Integration', function () {
    beforeEach(function () {
        // Clear Redis for clean state
        Redis::flushall();
        
        // Fake storage for file uploads
        Storage::fake('public');
        
        // Enable event broadcasting for testing
        Event::fake();
    });

    it('handles complete user registration to collaborative listening workflow', function () {
        // Step 1: User Registration
        $registrationData = [
            'username' => 'testuser',
            'email' => 'test@example.com',
            'password' => 'SecurePass123!',
            'password_confirmation' => 'SecurePass123!'
        ];

        $registrationResponse = $this->postJson('/api/register', $registrationData);

        $registrationResponse->assertStatus(201)
            ->assertJsonStructure([
                'message',
                'user' => ['id', 'username', 'email']
            ]);

        $user1 = User::where('email', 'test@example.com')->first();
        expect($user1)->not->toBeNull();
        expect($user1->username)->toBe('testuser');

        // Step 2: User Login
        $loginData = [
            'email' => 'test@example.com',
            'password' => 'SecurePass123!'
        ];

        $loginResponse = $this->postJson('/api/login', $loginData);

        $loginResponse->assertStatus(200)
            ->assertJsonStructure([
                'token',
                'user' => ['id', 'username', 'email']
            ]);

        $token1 = $loginResponse->json('token');
        expect($token1)->not->toBeNull();

        // Step 3: Create Second User for Multi-User Testing
        $user2Data = [
            'username' => 'seconduser',
            'email' => 'second@example.com',
            'password' => 'SecurePass456!',
            'password_confirmation' => 'SecurePass456!'
        ];

        $this->postJson('/api/register', $user2Data)->assertStatus(201);

        $user2LoginResponse = $this->postJson('/api/login', [
            'email' => 'second@example.com',
            'password' => 'SecurePass456!'
        ]);

        $token2 = $user2LoginResponse->json('token');
        $user2 = User::where('email', 'second@example.com')->first();

        // Step 4: Room Creation (User 1 as Admin)
        $roomData = [
            'name' => 'Test Collaborative Room'
        ];

        $roomResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token1,
            'Accept' => 'application/json'
        ])->postJson('/api/rooms', $roomData);

        $roomResponse->assertStatus(201)
            ->assertJsonStructure([
                'room' => [
                    'id', 'name', 'administrator_id', 'participants', 'track_queue'
                ]
            ]);

        $room = Room::first();
        expect($room->name)->toBe('Test Collaborative Room');
        expect($room->administrator_id)->toBe($user1->id);

        // Step 5: Second User Joins Room
        $joinResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token2,
            'Accept' => 'application/json'
        ])->postJson("/api/rooms/{$room->id}/join");

        $joinResponse->assertStatus(200);

        // Verify both users are participants
        $participants = RoomParticipant::where('room_id', $room->id)->get();
        expect($participants)->toHaveCount(2);
        expect($participants->pluck('user_id')->toArray())->toContain($user1->id, $user2->id);

        // Step 6: File Upload by User 1
        $audioFile = UploadedFile::fake()->create('test-song.mp3', 1024, 'audio/mpeg');

        $uploadResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token1,
            'Accept' => 'application/json'
        ])->postJson("/api/rooms/{$room->id}/tracks", [
            'audio_file' => $audioFile
        ]);

        $uploadResponse->assertStatus(201)
            ->assertJsonStructure([
                'track' => [
                    'id', 'room_id', 'uploader_id', 'filename', 'original_name',
                    'duration_seconds', 'vote_score'
                ]
            ]);

        $track1 = Track::first();
        expect($track1->room_id)->toBe($room->id);
        expect($track1->uploader_id)->toBe($user1->id);
        expect($track1->original_name)->toBe('test-song.mp3');

        // Verify file was stored
        Storage::disk('public')->assertExists($track1->file_path);

        // Step 7: File Upload by User 2
        $audioFile2 = UploadedFile::fake()->create('second-song.mp3', 2048, 'audio/mpeg');

        $uploadResponse2 = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token2,
            'Accept' => 'application/json'
        ])->postJson("/api/rooms/{$room->id}/tracks", [
            'audio_file' => $audioFile2
        ]);

        $uploadResponse2->assertStatus(201);

        $track2 = Track::where('uploader_id', $user2->id)->first();
        expect($track2)->not->toBeNull();

        // Step 8: Track Voting
        // User 1 votes for User 2's track
        $voteResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token1,
            'Accept' => 'application/json'
        ])->postJson("/api/tracks/{$track2->id}/vote");

        $voteResponse->assertStatus(200)
            ->assertJsonStructure([
                'vote' => ['track_id', 'user_id'],
                'track' => ['id', 'vote_score']
            ]);

        // User 2 also votes for their own track
        $this->withHeaders([
            'Authorization' => 'Bearer ' . $token2,
            'Accept' => 'application/json'
        ])->postJson("/api/tracks/{$track2->id}/vote");

        // Verify vote counts
        $track2->refresh();
        expect($track2->vote_score)->toBe(2);

        $votes = TrackVote::where('track_id', $track2->id)->get();
        expect($votes)->toHaveCount(2);

        // Step 9: Get Track Queue (Should be ordered by score)
        $queueResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token1,
            'Accept' => 'application/json'
        ])->getJson("/api/rooms/{$room->id}/queue");

        $queueResponse->assertStatus(200)
            ->assertJsonStructure([
                'tracks' => [
                    '*' => ['id', 'filename', 'vote_score', 'uploader']
                ]
            ]);

        $queue = $queueResponse->json('tracks');
        expect($queue)->toHaveCount(2);
        
        // Track 2 should be first (higher score)
        expect($queue[0]['id'])->toBe($track2->id);
        expect($queue[0]['vote_score'])->toBe(2);
        expect($queue[1]['id'])->toBe($track1->id);
        expect($queue[1]['vote_score'])->toBe(0);

        // Step 10: Playback Control (Admin Only)
        // Start playback of first track in queue
        $playResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token1,
            'Accept' => 'application/json'
        ])->postJson("/api/rooms/{$room->id}/playback/start", [
            'track_id' => $track2->id
        ]);

        $playResponse->assertStatus(200)
            ->assertJsonStructure([
                'playback_state' => [
                    'room_id', 'track_id', 'is_playing', 'started_at', 'server_time'
                ]
            ]);

        $room->refresh();
        expect($room->is_playing)->toBe(true);
        expect($room->current_track_id)->toBe($track2->id);
        expect($room->playback_started_at)->not->toBeNull();

        // Step 11: Test Non-Admin Playback Control (Should Fail)
        $unauthorizedPlayResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token2,
            'Accept' => 'application/json'
        ])->postJson("/api/rooms/{$room->id}/playback/start", [
            'track_id' => $track1->id
        ]);

        $unauthorizedPlayResponse->assertStatus(403)
            ->assertJson([
                'error' => 'Only room administrators can control playback'
            ]);

        // Step 12: Pause Playback
        $pauseResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token1,
            'Accept' => 'application/json'
        ])->postJson("/api/rooms/{$room->id}/playback/pause");

        $pauseResponse->assertStatus(200);

        $room->refresh();
        expect($room->is_playing)->toBe(false);
        expect($room->playback_paused_at)->not->toBeNull();

        // Step 13: Resume Playback
        $resumeResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token1,
            'Accept' => 'application/json'
        ])->postJson("/api/rooms/{$room->id}/playback/resume");

        $resumeResponse->assertStatus(200);

        $room->refresh();
        expect($room->is_playing)->toBe(true);
        expect($room->playback_started_at)->not->toBeNull();

        // Step 14: Skip Track
        $skipResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token1,
            'Accept' => 'application/json'
        ])->postJson("/api/rooms/{$room->id}/playback/skip");

        $skipResponse->assertStatus(200);

        $room->refresh();
        // Should move to next track in queue
        expect($room->current_track_id)->toBe($track1->id);

        // Step 15: User Leaves Room
        $leaveResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token2,
            'Accept' => 'application/json'
        ])->postJson("/api/rooms/{$room->id}/leave");

        $leaveResponse->assertStatus(200);

        // Verify user is no longer a participant
        $remainingParticipants = RoomParticipant::where('room_id', $room->id)->get();
        expect($remainingParticipants)->toHaveCount(1);
        expect($remainingParticipants->first()->user_id)->toBe($user1->id);

        // Step 16: Invalid File Upload Test
        $invalidFile = UploadedFile::fake()->create('document.txt', 100, 'text/plain');

        $invalidUploadResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token1,
            'Accept' => 'application/json'
        ])->postJson("/api/rooms/{$room->id}/tracks", [
            'audio_file' => $invalidFile
        ]);

        $invalidUploadResponse->assertStatus(422)
            ->assertJsonValidationErrors(['audio_file']);

        // Step 17: Test Authentication Errors
        $unauthenticatedResponse = $this->postJson("/api/rooms/{$room->id}/tracks", [
            'audio_file' => UploadedFile::fake()->create('song.mp3', 1024, 'audio/mpeg')
        ]);

        $unauthenticatedResponse->assertStatus(401);

        // Step 18: Test Room Not Found
        $nonExistentRoomResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token1,
            'Accept' => 'application/json'
        ])->getJson('/api/rooms/non-existent-room');

        $nonExistentRoomResponse->assertStatus(404);

        // Step 19: Test Vote Removal
        $removeVoteResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token1,
            'Accept' => 'application/json'
        ])->deleteJson("/api/tracks/{$track2->id}/vote");

        $removeVoteResponse->assertStatus(200);

        $track2->refresh();
        expect($track2->vote_score)->toBe(1); // Should decrease by 1

        // Step 20: Test Room Deletion (Admin Only)
        $deleteRoomResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token1,
            'Accept' => 'application/json'
        ])->deleteJson("/api/rooms/{$room->id}");

        $deleteRoomResponse->assertStatus(200);

        // Verify room and related data are cleaned up
        expect(Room::find($room->id))->toBeNull();
        expect(RoomParticipant::where('room_id', $room->id)->count())->toBe(0);
        expect(Track::where('room_id', $room->id)->count())->toBe(0);
    });

    it('handles WebSocket broadcasting events', function () {
        Event::fake([
            \App\Events\UserJoinedRoom::class,
            \App\Events\UserLeftRoom::class,
            \App\Events\TrackAdded::class,
            \App\Events\TrackVoted::class,
            \App\Events\PlaybackStarted::class,
            \App\Events\PlaybackPaused::class,
            \App\Events\PlaybackResumed::class,
            \App\Events\TrackSkipped::class,
        ]);

        // Create users and room
        $user1 = User::factory()->create();
        $user2 = User::factory()->create();
        $room = Room::factory()->create(['administrator_id' => $user1->id]);

        Sanctum::actingAs($user1);

        // Test user joining room event
        $this->postJson("/api/rooms/{$room->id}/join");
        Event::assertDispatched(\App\Events\UserJoinedRoom::class);

        // Test track upload event
        $audioFile = UploadedFile::fake()->create('test.mp3', 1024, 'audio/mpeg');
        $this->postJson("/api/rooms/{$room->id}/tracks", ['audio_file' => $audioFile]);
        Event::assertDispatched(\App\Events\TrackAdded::class);

        $track = Track::first();

        // Test voting event
        $this->postJson("/api/tracks/{$track->id}/vote");
        Event::assertDispatched(\App\Events\TrackVoted::class);

        // Test playback events
        $this->postJson("/api/rooms/{$room->id}/playback/start", ['track_id' => $track->id]);
        Event::assertDispatched(\App\Events\PlaybackStarted::class);

        $this->postJson("/api/rooms/{$room->id}/playback/pause");
        Event::assertDispatched(\App\Events\PlaybackPaused::class);

        $this->postJson("/api/rooms/{$room->id}/playback/resume");
        Event::assertDispatched(\App\Events\PlaybackResumed::class);

        $this->postJson("/api/rooms/{$room->id}/playback/skip");
        Event::assertDispatched(\App\Events\TrackSkipped::class);

        // Test user leaving room event
        $this->postJson("/api/rooms/{$room->id}/leave");
        Event::assertDispatched(\App\Events\UserLeftRoom::class);
    });

    it('handles concurrent operations correctly', function () {
        // Create multiple users
        $users = User::factory()->count(5)->create();
        $room = Room::factory()->create(['administrator_id' => $users[0]->id]);

        // Test concurrent room joining
        foreach ($users as $user) {
            Sanctum::actingAs($user);
            $response = $this->postJson("/api/rooms/{$room->id}/join");
            $response->assertStatus(200);
        }

        // Verify all users joined
        expect(RoomParticipant::where('room_id', $room->id)->count())->toBe(5);

        // Test concurrent file uploads
        $tracks = [];
        foreach ($users as $index => $user) {
            Sanctum::actingAs($user);
            $audioFile = UploadedFile::fake()->create("song{$index}.mp3", 1024, 'audio/mpeg');
            $response = $this->postJson("/api/rooms/{$room->id}/tracks", ['audio_file' => $audioFile]);
            $response->assertStatus(201);
            $tracks[] = $response->json('track.id');
        }

        // Verify all tracks uploaded
        expect(Track::where('room_id', $room->id)->count())->toBe(5);

        // Test concurrent voting
        foreach ($users as $user) {
            Sanctum::actingAs($user);
            // Each user votes for the first track
            $this->postJson("/api/tracks/{$tracks[0]}/vote");
        }

        // Verify vote count
        $firstTrack = Track::find($tracks[0]);
        expect($firstTrack->vote_score)->toBe(5);
    });

    it('validates file upload constraints', function () {
        $user = User::factory()->create();
        $room = Room::factory()->create(['administrator_id' => $user->id]);

        Sanctum::actingAs($user);

        // Test file size limit (assuming 10MB limit)
        $largeFile = UploadedFile::fake()->create('large.mp3', 11000, 'audio/mpeg'); // 11MB
        $response = $this->postJson("/api/rooms/{$room->id}/tracks", ['audio_file' => $largeFile]);
        $response->assertStatus(422);

        // Test invalid file type
        $textFile = UploadedFile::fake()->create('text.txt', 100, 'text/plain');
        $response = $this->postJson("/api/rooms/{$room->id}/tracks", ['audio_file' => $textFile]);
        $response->assertStatus(422);

        // Test missing file
        $response = $this->postJson("/api/rooms/{$room->id}/tracks", []);
        $response->assertStatus(422);

        // Test valid file types
        $validTypes = ['audio/mpeg', 'audio/wav', 'audio/mp4'];
        foreach ($validTypes as $type) {
            $validFile = UploadedFile::fake()->create('valid.mp3', 1024, $type);
            $response = $this->postJson("/api/rooms/{$room->id}/tracks", ['audio_file' => $validFile]);
            $response->assertStatus(201);
        }
    });

    it('maintains data integrity across operations', function () {
        $user1 = User::factory()->create();
        $user2 = User::factory()->create();
        $room = Room::factory()->create(['administrator_id' => $user1->id]);

        // Add participants
        RoomParticipant::create(['room_id' => $room->id, 'user_id' => $user1->id]);
        RoomParticipant::create(['room_id' => $room->id, 'user_id' => $user2->id]);

        // Add tracks
        $track1 = Track::factory()->create(['room_id' => $room->id, 'uploader_id' => $user1->id]);
        $track2 = Track::factory()->create(['room_id' => $room->id, 'uploader_id' => $user2->id]);

        // Add votes
        TrackVote::create(['track_id' => $track1->id, 'user_id' => $user2->id]);
        TrackVote::create(['track_id' => $track2->id, 'user_id' => $user1->id]);
        TrackVote::create(['track_id' => $track2->id, 'user_id' => $user2->id]);

        // Verify initial state
        expect($track1->fresh()->vote_score)->toBe(1);
        expect($track2->fresh()->vote_score)->toBe(2);

        // Test cascading deletes when user is deleted
        $user2->delete();

        // Votes by deleted user should be removed
        expect(TrackVote::where('user_id', $user2->id)->count())->toBe(0);
        
        // Vote scores should be updated
        expect($track1->fresh()->vote_score)->toBe(0);
        expect($track2->fresh()->vote_score)->toBe(1);

        // Room participation should be cleaned up
        expect(RoomParticipant::where('user_id', $user2->id)->count())->toBe(0);

        // Test room deletion cascades
        $room->delete();

        // All related data should be cleaned up
        expect(Track::where('room_id', $room->id)->count())->toBe(0);
        expect(RoomParticipant::where('room_id', $room->id)->count())->toBe(0);
        expect(TrackVote::whereIn('track_id', [$track1->id, $track2->id])->count())->toBe(0);
    });

    it('handles authentication edge cases', function () {
        $user = User::factory()->create();
        $room = Room::factory()->create(['administrator_id' => $user->id]);

        // Test expired token (simulate by using invalid token)
        $response = $this->withHeaders([
            'Authorization' => 'Bearer invalid-token',
            'Accept' => 'application/json'
        ])->getJson("/api/rooms/{$room->id}");

        $response->assertStatus(401);

        // Test missing token
        $response = $this->getJson("/api/rooms/{$room->id}");
        $response->assertStatus(401);

        // Test valid token
        Sanctum::actingAs($user);
        $response = $this->getJson("/api/rooms/{$room->id}");
        $response->assertStatus(200);
    });

    it('validates playback synchronization timing', function () {
        $user = User::factory()->create();
        $room = Room::factory()->create(['administrator_id' => $user->id]);
        $track = Track::factory()->create(['room_id' => $room->id, 'uploader_id' => $user->id]);

        Sanctum::actingAs($user);

        // Start playback
        $startTime = now();
        $response = $this->postJson("/api/rooms/{$room->id}/playback/start", ['track_id' => $track->id]);
        $response->assertStatus(200);

        $playbackData = $response->json('playback_state');
        $serverStartTime = \Carbon\Carbon::parse($playbackData['started_at']);
        $serverCurrentTime = \Carbon\Carbon::parse($playbackData['server_time']);

        // Verify timing accuracy (should be within 1 second)
        expect($serverStartTime->diffInSeconds($startTime))->toBeLessThan(1);
        expect($serverCurrentTime->diffInSeconds(now()))->toBeLessThan(1);

        // Test pause timing
        sleep(2); // Wait 2 seconds
        $pauseTime = now();
        $pauseResponse = $this->postJson("/api/rooms/{$room->id}/playback/pause");
        $pauseResponse->assertStatus(200);

        $room->refresh();
        $pausedAt = \Carbon\Carbon::parse($room->playback_paused_at);
        expect($pausedAt->diffInSeconds($pauseTime))->toBeLessThan(1);

        // Test resume timing
        sleep(1); // Wait 1 second while paused
        $resumeTime = now();
        $resumeResponse = $this->postJson("/api/rooms/{$room->id}/playback/resume");
        $resumeResponse->assertStatus(200);

        $resumeData = $resumeResponse->json('playback_state');
        $newStartTime = \Carbon\Carbon::parse($resumeData['started_at']);
        
        // New start time should account for pause duration
        $expectedStartTime = $resumeTime->subSeconds(2); // 2 seconds of playback before pause
        expect($newStartTime->diffInSeconds($expectedStartTime))->toBeLessThan(1);
    });
});