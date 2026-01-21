<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\Room;
use App\Models\Track;
use App\Events\PlaybackStarted;
use App\Events\PlaybackPaused;
use App\Events\PlaybackResumed;
use App\Events\TrackSkipped;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Tests\TestCase;
use Tymon\JWTAuth\Facades\JWTAuth;

class PlaybackControlTest extends TestCase
{
    use RefreshDatabase;

    private User $admin;
    private User $participant;
    private Room $room;
    private Track $track1;
    private Track $track2;
    private string $adminToken;
    private string $participantToken;

    protected function setUp(): void
    {
        parent::setUp();

        // Create test users
        $this->admin = User::factory()->create();
        $this->participant = User::factory()->create();

        // Generate JWT tokens
        $this->adminToken = JWTAuth::fromUser($this->admin);
        $this->participantToken = JWTAuth::fromUser($this->participant);

        // Create test room
        $this->room = Room::factory()->create([
            'administrator_id' => $this->admin->id,
        ]);

        // Add participant to room
        $this->room->addParticipant($this->participant);

        // Create test tracks
        $this->track1 = Track::factory()->create([
            'room_id' => $this->room->id,
            'uploader_id' => $this->admin->id,
        ]);

        $this->track2 = Track::factory()->create([
            'room_id' => $this->room->id,
            'uploader_id' => $this->participant->id,
        ]);
    }

    /** @test */
    public function it_allows_admin_to_start_track_playback()
    {
        Event::fake();

        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->adminToken,
        ])->postJson("/api/rooms/{$this->room->id}/tracks/{$this->track1->id}/play");

        $response->assertStatus(200)
            ->assertJson([
                'success' => true,
                'message' => 'Playback started successfully',
                'data' => [
                    'track_id' => $this->track1->id,
                ]
            ]);

        // Verify room state updated
        $this->room->refresh();
        $this->assertEquals($this->track1->id, $this->room->current_track_id);
        $this->assertTrue($this->room->is_playing);
        $this->assertNotNull($this->room->playback_started_at);
        $this->assertNull($this->room->playback_paused_at);

        // Verify event was broadcast
        Event::assertDispatched(PlaybackStarted::class, function ($event) {
            return $event->track->id === $this->track1->id &&
                   $event->room->id === $this->room->id;
        });
    }

    /** @test */
    public function it_prevents_non_admin_from_starting_playback()
    {
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->participantToken,
        ])->postJson("/api/rooms/{$this->room->id}/tracks/{$this->track1->id}/play");

        $response->assertStatus(403)
            ->assertJson([
                'success' => false,
                'message' => 'Only room administrator can control playback',
                'error' => 'Insufficient permissions'
            ]);

        // Verify room state unchanged
        $this->room->refresh();
        $this->assertNull($this->room->current_track_id);
        $this->assertFalse($this->room->is_playing);
    }

    /** @test */
    public function it_prevents_starting_track_from_different_room()
    {
        $otherRoom = Room::factory()->create();
        $otherTrack = Track::factory()->create(['room_id' => $otherRoom->id]);

        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->adminToken,
        ])->postJson("/api/rooms/{$this->room->id}/tracks/{$otherTrack->id}/play");

        $response->assertStatus(404)
            ->assertJson([
                'success' => false,
                'message' => 'Track does not belong to this room',
                'error' => 'Invalid track'
            ]);
    }

    /** @test */
    public function it_allows_admin_to_pause_playback()
    {
        Event::fake();

        // Start playback first
        $this->room->update([
            'current_track_id' => $this->track1->id,
            'playback_started_at' => now()->subSeconds(30),
            'is_playing' => true,
        ]);

        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->adminToken,
        ])->postJson("/api/rooms/{$this->room->id}/playback/pause");

        $response->assertStatus(200)
            ->assertJson([
                'success' => true,
                'message' => 'Playback paused successfully',
                'data' => [
                    'track_id' => $this->track1->id,
                ]
            ]);

        // Verify room state updated
        $this->room->refresh();
        $this->assertFalse($this->room->is_playing);
        $this->assertNotNull($this->room->playback_paused_at);

        // Verify event was broadcast
        Event::assertDispatched(PlaybackPaused::class);
    }

    /** @test */
    public function it_prevents_pausing_when_nothing_is_playing()
    {
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->adminToken,
        ])->postJson("/api/rooms/{$this->room->id}/playback/pause");

        $response->assertStatus(400)
            ->assertJson([
                'success' => false,
                'message' => 'No track is currently playing',
                'error' => 'No active playback'
            ]);
    }

    /** @test */
    public function it_allows_admin_to_resume_playback()
    {
        Event::fake();

        // Set up paused state
        $startTime = now()->subMinutes(2);
        $pauseTime = now()->subMinutes(1);
        
        $this->room->update([
            'current_track_id' => $this->track1->id,
            'playback_started_at' => $startTime,
            'playback_paused_at' => $pauseTime,
            'is_playing' => false,
        ]);

        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->adminToken,
        ])->postJson("/api/rooms/{$this->room->id}/playback/resume");

        $response->assertStatus(200)
            ->assertJson([
                'success' => true,
                'message' => 'Playback resumed successfully',
                'data' => [
                    'track_id' => $this->track1->id,
                ]
            ]);

        // Verify room state updated
        $this->room->refresh();
        $this->assertTrue($this->room->is_playing);
        $this->assertNull($this->room->playback_paused_at);

        // Verify event was broadcast
        Event::assertDispatched(PlaybackResumed::class);
    }

    /** @test */
    public function it_prevents_resuming_when_nothing_is_paused()
    {
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->adminToken,
        ])->postJson("/api/rooms/{$this->room->id}/playback/resume");

        $response->assertStatus(400)
            ->assertJson([
                'success' => false,
                'message' => 'No track is currently paused',
                'error' => 'No paused playback'
            ]);
    }

    /** @test */
    public function it_allows_admin_to_skip_track()
    {
        Event::fake();

        // Start playback
        $this->room->update([
            'current_track_id' => $this->track1->id,
            'playback_started_at' => now()->subSeconds(30),
            'is_playing' => true,
        ]);

        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->adminToken,
        ])->postJson("/api/rooms/{$this->room->id}/playback/skip");

        $response->assertStatus(200)
            ->assertJson([
                'success' => true,
                'message' => 'Track skipped successfully',
                'data' => [
                    'skipped_track_id' => $this->track1->id,
                ]
            ]);

        // Verify event was broadcast
        Event::assertDispatched(TrackSkipped::class);
    }

    /** @test */
    public function it_allows_admin_to_stop_playback()
    {
        Event::fake();

        // Start playback
        $this->room->update([
            'current_track_id' => $this->track1->id,
            'playback_started_at' => now()->subSeconds(30),
            'is_playing' => true,
        ]);

        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->adminToken,
        ])->postJson("/api/rooms/{$this->room->id}/playback/stop");

        $response->assertStatus(200)
            ->assertJson([
                'success' => true,
                'message' => 'Playback stopped successfully',
            ]);

        // Verify room state updated
        $this->room->refresh();
        $this->assertNull($this->room->current_track_id);
        $this->assertFalse($this->room->is_playing);
        $this->assertNull($this->room->playback_started_at);
        $this->assertNull($this->room->playback_paused_at);
    }

    /** @test */
    public function it_allows_participants_to_get_playback_status()
    {
        // Set up playing state
        $startTime = now()->subSeconds(45);
        $this->room->update([
            'current_track_id' => $this->track1->id,
            'playback_started_at' => $startTime,
            'is_playing' => true,
        ]);

        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->participantToken,
        ])->getJson("/api/rooms/{$this->room->id}/playback/status");

        $response->assertStatus(200)
            ->assertJson([
                'success' => true,
                'message' => 'Playback status retrieved successfully',
                'data' => [
                    'is_playing' => true,
                    'current_track' => [
                        'id' => $this->track1->id,
                        'filename' => $this->track1->filename,
                        'original_name' => $this->track1->original_name,
                        'duration_seconds' => $this->track1->duration_seconds,
                    ],
                ]
            ]);

        // Verify position is calculated correctly (approximately 45 seconds)
        $responseData = $response->json('data');
        $this->assertGreaterThanOrEqual(44, $responseData['position']);
        $this->assertLessThanOrEqual(46, $responseData['position']);
    }

    /** @test */
    public function it_prevents_non_participants_from_getting_status()
    {
        $nonParticipant = User::factory()->create();
        $nonParticipantToken = JWTAuth::fromUser($nonParticipant);

        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $nonParticipantToken,
        ])->getJson("/api/rooms/{$this->room->id}/playback/status");

        $response->assertStatus(403)
            ->assertJson([
                'success' => false,
                'message' => 'You must be a participant of this room to view playback status',
                'error' => 'Not a participant'
            ]);
    }

    /** @test */
    public function it_calculates_position_correctly_for_paused_track()
    {
        // Set up paused state - played for 60 seconds, then paused
        $startTime = now()->subMinutes(2);
        $pauseTime = now()->subMinutes(1);
        
        $this->room->update([
            'current_track_id' => $this->track1->id,
            'playback_started_at' => $startTime,
            'playback_paused_at' => $pauseTime,
            'is_playing' => false,
        ]);

        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->participantToken,
        ])->getJson("/api/rooms/{$this->room->id}/playback/status");

        $response->assertStatus(200);

        // Position should be approximately 60 seconds (time between start and pause)
        $responseData = $response->json('data');
        $this->assertGreaterThanOrEqual(59, $responseData['position']);
        $this->assertLessThanOrEqual(61, $responseData['position']);
        $this->assertFalse($responseData['is_playing']);
    }

    /** @test */
    public function it_requires_authentication_for_all_playback_endpoints()
    {
        $endpoints = [
            ['POST', "/api/rooms/{$this->room->id}/tracks/{$this->track1->id}/play"],
            ['POST', "/api/rooms/{$this->room->id}/playback/pause"],
            ['POST', "/api/rooms/{$this->room->id}/playback/resume"],
            ['POST', "/api/rooms/{$this->room->id}/playback/skip"],
            ['POST', "/api/rooms/{$this->room->id}/playback/stop"],
            ['GET', "/api/rooms/{$this->room->id}/playback/status"],
        ];

        foreach ($endpoints as [$method, $url]) {
            $response = $this->json($method, $url);
            $response->assertStatus(401);
        }
    }

    /** @test */
    public function it_handles_server_timing_calculations_correctly()
    {
        Event::fake();

        // Start playback
        $beforeStart = now();
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->adminToken,
        ])->postJson("/api/rooms/{$this->room->id}/tracks/{$this->track1->id}/play");
        $afterStart = now();

        $response->assertStatus(200);
        $responseData = $response->json('data');

        // Verify timestamps are within expected range
        $startedAt = \Carbon\Carbon::parse($responseData['started_at']);
        $serverTime = \Carbon\Carbon::parse($responseData['server_time']);

        $this->assertTrue($startedAt->between($beforeStart, $afterStart));
        $this->assertTrue($serverTime->between($beforeStart, $afterStart));

        // Verify room state matches response
        $this->room->refresh();
        $this->assertEquals($startedAt->toDateTimeString(), $this->room->playback_started_at->toDateTimeString());
    }
}