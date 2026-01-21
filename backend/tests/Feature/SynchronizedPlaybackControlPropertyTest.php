<?php

namespace Tests\Feature;

use Tests\TestCase;
use App\Models\User;
use App\Models\Room;
use App\Models\Track;
use App\Events\PlaybackStarted;
use App\Events\PlaybackPaused;
use App\Events\PlaybackResumed;
use App\Events\TrackSkipped;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Carbon\Carbon;

class SynchronizedPlaybackControlPropertyTest extends TestCase
{
    use RefreshDatabase;

    /**
     * **Property 9: Synchronized Playback Control**
     * **Validates: Requirements 4.1, 4.2, 4.3, 4.4, 6.1, 6.2, 6.3**
     * 
     * For any Room_Administrator playback action (play, pause, resume, skip), 
     * the system should broadcast the action with accurate server timestamps 
     * to all participants and update the room's playback state consistently.
     */
    #[\PHPUnit\Framework\Attributes\Test]
    public function it_allows_room_administrators_to_control_playback_for_any_valid_track()
    {
        // **Validates: Requirements 6.1, 6.2, 6.3, 6.4**
        
        Event::fake();
        
        for ($iteration = 0; $iteration < 5; $iteration++) {
            // Create test users and room
            $admin = User::factory()->create();
            $participant = User::factory()->create();
            $nonParticipant = User::factory()->create();
            
            $room = Room::factory()->create(['administrator_id' => $admin->id]);
            $room->addParticipant($admin);
            $room->addParticipant($participant);
            
            // Create tracks in the room
            $track1 = Track::factory()->create([
                'room_id' => $room->id,
                'uploader_id' => $admin->id,
                'duration_seconds' => 180, // 3 minutes
            ]);
            
            $track2 = Track::factory()->create([
                'room_id' => $room->id,
                'uploader_id' => $participant->id,
                'duration_seconds' => 240, // 4 minutes
            ]);
            
            // Get authentication tokens
            $adminToken = auth()->login($admin);
            $participantToken = auth()->login($participant);
            $nonParticipantToken = auth()->login($nonParticipant);
            
            // Test 1: Admin can start playback
            $startResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->postJson("/api/rooms/{$room->id}/tracks/{$track1->id}/play");
            
            $startResponse->assertStatus(200)
                ->assertJsonStructure([
                    'success',
                    'message',
                    'data' => [
                        'track_id',
                        'started_at',
                        'server_time',
                    ]
                ]);
            
            // Verify room state updated correctly
            $room->refresh();
            $this->assertEquals($track1->id, $room->current_track_id);
            $this->assertTrue($room->is_playing);
            $this->assertNotNull($room->playback_started_at);
            $this->assertNull($room->playback_paused_at);
            
            // Verify PlaybackStarted event was broadcast
            Event::assertDispatched(PlaybackStarted::class, function ($event) use ($track1, $room) {
                return $event->track->id === $track1->id && 
                       $event->room->id === $room->id;
            });
            
            // Test 2: Non-admin cannot control playback
            $unauthorizedResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $participantToken,
            ])->postJson("/api/rooms/{$room->id}/playback/pause");
            
            $unauthorizedResponse->assertStatus(403)
                ->assertJson([
                    'success' => false,
                    'error' => 'Insufficient permissions'
                ]);
            
            // Test 3: Admin can pause playback
            $pauseResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->postJson("/api/rooms/{$room->id}/playback/pause");
            
            $pauseResponse->assertStatus(200)
                ->assertJsonStructure([
                    'success',
                    'message',
                    'data' => [
                        'track_id',
                        'paused_at',
                        'position',
                        'server_time',
                    ]
                ]);
            
            // Verify room state updated correctly
            $room->refresh();
            $this->assertFalse($room->is_playing);
            $this->assertNotNull($room->playback_paused_at);
            
            // Verify PlaybackPaused event was broadcast
            Event::assertDispatched(PlaybackPaused::class, function ($event) use ($track1, $room) {
                return $event->track->id === $track1->id && 
                       $event->room->id === $room->id;
            });
            
            // Test 4: Admin can resume playback
            $resumeResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->postJson("/api/rooms/{$room->id}/playback/resume");
            
            $resumeResponse->assertStatus(200)
                ->assertJsonStructure([
                    'success',
                    'message',
                    'data' => [
                        'track_id',
                        'resumed_at',
                        'position',
                        'server_time',
                    ]
                ]);
            
            // Verify room state updated correctly
            $room->refresh();
            $this->assertTrue($room->is_playing);
            $this->assertNull($room->playback_paused_at);
            
            // Verify PlaybackResumed event was broadcast
            Event::assertDispatched(PlaybackResumed::class, function ($event) use ($track1, $room) {
                return $event->track->id === $track1->id && 
                       $event->room->id === $room->id;
            });
            
            // Test 5: Admin can skip to next track
            $skipResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->postJson("/api/rooms/{$room->id}/playback/skip");
            
            $skipResponse->assertStatus(200)
                ->assertJsonStructure([
                    'success',
                    'message',
                    'data' => [
                        'skipped_track_id',
                        'next_track_id',
                        'server_time',
                    ]
                ]);
            
            // Verify TrackSkipped event was broadcast
            Event::assertDispatched(TrackSkipped::class, function ($event) use ($track1, $room) {
                return $event->skippedTrack->id === $track1->id && 
                       $event->room->id === $room->id;
            });
            
            // Clean up for next iteration
            Event::clearResolvedInstances();
        }
    }

    /**
     * **Validates: Requirements 4.4**
     */
    #[\PHPUnit\Framework\Attributes\Test]
    public function it_maintains_accurate_server_side_timing_calculations_for_any_playback_sequence()
    {
        // **Validates: Requirements 4.4**
        
        for ($iteration = 0; $iteration < 3; $iteration++) {
            // Create test users and room
            $admin = User::factory()->create();
            $room = Room::factory()->create(['administrator_id' => $admin->id]);
            $room->addParticipant($admin);
            
            // Create a track
            $track = Track::factory()->create([
                'room_id' => $room->id,
                'uploader_id' => $admin->id,
                'duration_seconds' => 300, // 5 minutes
            ]);
            
            $adminToken = auth()->login($admin);
            
            // Start playback and record timing
            $startTime = Carbon::now();
            $startResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->postJson("/api/rooms/{$room->id}/tracks/{$track->id}/play");
            $endTime = Carbon::now();
            
            $startResponse->assertStatus(200);
            $startData = $startResponse->json('data');
            
            // Verify server timestamps are within expected range
            $reportedStartTime = Carbon::parse($startData['started_at']);
            $reportedServerTime = Carbon::parse($startData['server_time']);
            
            $this->assertTrue($reportedStartTime->between($startTime, $endTime));
            $this->assertTrue($reportedServerTime->between($startTime, $endTime));
            
            // Wait a short time to simulate playback
            sleep(2); // Use 2 seconds for more reliable integer-based timing
            
            // Pause and verify position calculation
            $pauseResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->postJson("/api/rooms/{$room->id}/playback/pause");
            
            $pauseResponse->assertStatus(200);
            $pauseData = $pauseResponse->json('data');
            
            // Verify position is a reasonable numeric value
            $actualPosition = $pauseData['position'];
            $this->assertIsNumeric($actualPosition);
            $this->assertGreaterThanOrEqual(1, $actualPosition); // At least 1 second
            $this->assertLessThanOrEqual(4, $actualPosition); // But not more than 4 seconds
            
            // Wait while paused
            sleep(1);
            
            // Resume and verify timing adjustment
            $resumeResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->postJson("/api/rooms/{$room->id}/playback/resume");
            
            $resumeResponse->assertStatus(200);
            $resumeData = $resumeResponse->json('data');
            
            // Position should remain the same as when paused (within tolerance for timing precision)
            $this->assertEqualsWithDelta($pauseData['position'], $resumeData['position'], 1.0);
            
            // Verify room state reflects timing adjustment (check that start time was adjusted)
            $room->refresh();
            $this->assertNotNull($room->playback_started_at);
            $this->assertNull($room->playback_paused_at);
            $this->assertTrue($room->is_playing);
            
            // The new start time should be different from the original start time
            $this->assertNotEquals(
                $reportedStartTime->toDateTimeString(), 
                $room->playback_started_at->toDateTimeString()
            );
        }
    }

    /**
     * **Validates: Requirements 4.1, 4.2, 4.3, 4.5**
     */
    #[\PHPUnit\Framework\Attributes\Test]
    public function it_broadcasts_playback_events_with_consistent_data_structure_for_all_operations()
    {
        // **Validates: Requirements 4.1, 4.2, 4.3, 4.5**
        
        Event::fake();
        
        // Create test users and room
        $admin = User::factory()->create();
        $room = Room::factory()->create(['administrator_id' => $admin->id]);
        $room->addParticipant($admin);
        
        // Create tracks
        $track1 = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $admin->id,
        ]);
        
        $track2 = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $admin->id,
        ]);
        
        $adminToken = auth()->login($admin);
        
        // Test PlaybackStarted event structure
        $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->postJson("/api/rooms/{$room->id}/tracks/{$track1->id}/play");
        
        Event::assertDispatched(PlaybackStarted::class, function ($event) use ($track1, $room) {
            $broadcastData = $event->broadcastWith();
            
            // Verify required fields are present
            $this->assertArrayHasKey('track', $broadcastData);
            $this->assertArrayHasKey('room_id', $broadcastData);
            $this->assertArrayHasKey('started_at', $broadcastData);
            $this->assertArrayHasKey('server_time', $broadcastData);
            
            // Verify track data structure
            $this->assertArrayHasKey('id', $broadcastData['track']);
            $this->assertArrayHasKey('filename', $broadcastData['track']);
            $this->assertArrayHasKey('duration_seconds', $broadcastData['track']);
            $this->assertArrayHasKey('file_path', $broadcastData['track']);
            
            // Verify data correctness
            $this->assertEquals($track1->id, $broadcastData['track']['id']);
            $this->assertEquals($room->id, $broadcastData['room_id']);
            
            return true;
        });
        
        // Test PlaybackPaused event structure
        $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->postJson("/api/rooms/{$room->id}/playback/pause");
        
        Event::assertDispatched(PlaybackPaused::class, function ($event) use ($track1, $room) {
            $broadcastData = $event->broadcastWith();
            
            // Verify required fields are present
            $this->assertArrayHasKey('track', $broadcastData);
            $this->assertArrayHasKey('room_id', $broadcastData);
            $this->assertArrayHasKey('paused_at', $broadcastData);
            $this->assertArrayHasKey('position', $broadcastData);
            $this->assertArrayHasKey('server_time', $broadcastData);
            
            // Verify position is a valid number
            $this->assertIsNumeric($broadcastData['position']);
            $this->assertGreaterThanOrEqual(0, $broadcastData['position']);
            
            return true;
        });
        
        // Test PlaybackResumed event structure
        $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->postJson("/api/rooms/{$room->id}/playback/resume");
        
        Event::assertDispatched(PlaybackResumed::class, function ($event) use ($track1, $room) {
            $broadcastData = $event->broadcastWith();
            
            // Verify required fields are present
            $this->assertArrayHasKey('track', $broadcastData);
            $this->assertArrayHasKey('room_id', $broadcastData);
            $this->assertArrayHasKey('resumed_at', $broadcastData);
            $this->assertArrayHasKey('position', $broadcastData);
            $this->assertArrayHasKey('server_time', $broadcastData);
            
            return true;
        });
        
        // Test TrackSkipped event structure
        $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->postJson("/api/rooms/{$room->id}/playback/skip");
        
        Event::assertDispatched(TrackSkipped::class, function ($event) use ($room) {
            $broadcastData = $event->broadcastWith();
            
            // Verify required fields are present
            $this->assertArrayHasKey('skipped_track', $broadcastData);
            $this->assertArrayHasKey('room_id', $broadcastData);
            $this->assertArrayHasKey('timestamp', $broadcastData);
            
            // next_track may be null if no more tracks in queue
            $this->assertArrayHasKey('next_track', $broadcastData);
            
            return true;
        });
    }

    /**
     * **Validates: Requirements 4.2, 4.3, 4.4**
     */
    #[\PHPUnit\Framework\Attributes\Test]
    public function it_maintains_position_tracking_accuracy_across_pause_resume_cycles()
    {
        // **Validates: Requirements 4.2, 4.3, 4.4**
        
        // Create test users and room
        $admin = User::factory()->create();
        $room = Room::factory()->create(['administrator_id' => $admin->id]);
        $room->addParticipant($admin);
        
        // Create a track
        $track = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $admin->id,
            'duration_seconds' => 600, // 10 minutes
        ]);
        
        $adminToken = auth()->login($admin);
        
        // Start playback
        $startResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->postJson("/api/rooms/{$room->id}/tracks/{$track->id}/play");
        
        $startResponse->assertStatus(200);
        
        // Test pause/resume cycle
        sleep(1); // Play for 1 second
        
        // Pause
        $pauseResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->postJson("/api/rooms/{$room->id}/playback/pause");
        
        $pauseResponse->assertStatus(200);
        $pauseData = $pauseResponse->json('data');
        
        // Verify position is reasonable
        $this->assertIsNumeric($pauseData['position']);
        $this->assertGreaterThan(0, $pauseData['position']);
        $this->assertLessThan(10, $pauseData['position']); // Should be less than 10 seconds
        
        $pausedPosition = $pauseData['position'];
        
        // Stay paused briefly
        sleep(1);
        
        // Resume
        $resumeResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->postJson("/api/rooms/{$room->id}/playback/resume");
        
        $resumeResponse->assertStatus(200);
        $resumeData = $resumeResponse->json('data');
        
        // Position should remain approximately the same as when paused
        $this->assertEqualsWithDelta($pausedPosition, $resumeData['position'], 1.0);
        
        // Play a bit more and verify position increases
        sleep(1);
        
        $statusResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->getJson("/api/rooms/{$room->id}/playback/status");
        
        $statusResponse->assertStatus(200);
        $currentPosition = $statusResponse->json('data.position');
        
        // Current position should be greater than paused position
        $this->assertGreaterThan($pausedPosition, $currentPosition);
        
        // Verify room state is consistent
        $room->refresh();
        $this->assertTrue($room->is_playing);
        $this->assertNull($room->playback_paused_at);
        $this->assertNotNull($room->playback_started_at);
    }

    /**
     * **Validates: Requirements 6.4**
     */
    #[\PHPUnit\Framework\Attributes\Test]
    public function it_prevents_unauthorized_playback_control_for_any_non_administrator_user()
    {
        // **Validates: Requirements 6.4**
        
        for ($iteration = 0; $iteration < 3; $iteration++) {
            // Create test users and room
            $admin = User::factory()->create();
            $participant = User::factory()->create();
            $nonParticipant = User::factory()->create();
            
            $room = Room::factory()->create(['administrator_id' => $admin->id]);
            $room->addParticipant($admin);
            $room->addParticipant($participant);
            
            // Create a track
            $track = Track::factory()->create([
                'room_id' => $room->id,
                'uploader_id' => $admin->id,
            ]);
            
            // Get authentication tokens
            $participantToken = auth()->login($participant);
            $nonParticipantToken = auth()->login($nonParticipant);
            
            // Test that participant cannot start playback
            $startResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $participantToken,
            ])->postJson("/api/rooms/{$room->id}/tracks/{$track->id}/play");
            
            $startResponse->assertStatus(403)
                ->assertJson([
                    'success' => false,
                    'error' => 'Insufficient permissions'
                ]);
            
            // Start playback as admin for further tests
            $adminToken = auth()->login($admin);
            $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->postJson("/api/rooms/{$room->id}/tracks/{$track->id}/play");
            
            // Test that participant cannot pause
            $pauseResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $participantToken,
            ])->postJson("/api/rooms/{$room->id}/playback/pause");
            
            $pauseResponse->assertStatus(403)
                ->assertJson([
                    'success' => false,
                    'error' => 'Insufficient permissions'
                ]);
            
            // Test that non-participant cannot control playback
            $nonParticipantResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $nonParticipantToken,
            ])->postJson("/api/rooms/{$room->id}/playback/pause");
            
            $nonParticipantResponse->assertStatus(403);
            
            // Test that participant cannot skip
            $skipResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $participantToken,
            ])->postJson("/api/rooms/{$room->id}/playback/skip");
            
            $skipResponse->assertStatus(403)
                ->assertJson([
                    'success' => false,
                    'error' => 'Insufficient permissions'
                ]);
            
            // Verify room state was not affected by unauthorized attempts
            $room->refresh();
            $this->assertEquals($track->id, $room->current_track_id);
            $this->assertTrue($room->is_playing);
        }
    }

    /**
     * **Validates: Requirements 4.1, 4.2, 4.3, 6.1, 6.2, 6.3**
     */
    #[\PHPUnit\Framework\Attributes\Test]
    public function it_handles_edge_cases_in_playback_control_operations()
    {
        // **Validates: Requirements 4.1, 4.2, 4.3, 6.1, 6.2, 6.3**
        
        // Create test users and room
        $admin = User::factory()->create();
        $room = Room::factory()->create(['administrator_id' => $admin->id]);
        $room->addParticipant($admin);
        
        $track = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $admin->id,
        ]);
        
        $adminToken = auth()->login($admin);
        
        // Test 1: Cannot pause when nothing is playing
        $pauseResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->postJson("/api/rooms/{$room->id}/playback/pause");
        
        $pauseResponse->assertStatus(400)
            ->assertJson([
                'success' => false,
                'error' => 'No active playback'
            ]);
        
        // Test 2: Cannot resume when nothing is paused
        $resumeResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->postJson("/api/rooms/{$room->id}/playback/resume");
        
        $resumeResponse->assertStatus(400)
            ->assertJson([
                'success' => false,
                'error' => 'No paused playback'
            ]);
        
        // Test 3: Cannot skip when no track is playing
        $skipResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->postJson("/api/rooms/{$room->id}/playback/skip");
        
        $skipResponse->assertStatus(400)
            ->assertJson([
                'success' => false,
                'error' => 'No active track'
            ]);
        
        // Test 4: Cannot start track from different room
        $otherRoom = Room::factory()->create();
        $otherTrack = Track::factory()->create(['room_id' => $otherRoom->id]);
        
        $invalidTrackResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->postJson("/api/rooms/{$room->id}/tracks/{$otherTrack->id}/play");
        
        $invalidTrackResponse->assertStatus(404)
            ->assertJson([
                'success' => false,
                'error' => 'Invalid track'
            ]);
        
        // Test 5: Cannot resume already playing track
        $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->postJson("/api/rooms/{$room->id}/tracks/{$track->id}/play");
        
        $resumePlayingResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->postJson("/api/rooms/{$room->id}/playback/resume");
        
        $resumePlayingResponse->assertStatus(400)
            ->assertJson([
                'success' => false,
                'error' => 'No paused playback'
            ]);
        
        // Test 6: Cannot pause already paused track
        $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->postJson("/api/rooms/{$room->id}/playback/pause");
        
        $pausePausedResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->postJson("/api/rooms/{$room->id}/playback/pause");
        
        $pausePausedResponse->assertStatus(400)
            ->assertJson([
                'success' => false,
                'error' => 'No active playback'
            ]);
    }
}