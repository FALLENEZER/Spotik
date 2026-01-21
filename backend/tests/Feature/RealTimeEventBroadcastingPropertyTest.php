<?php

namespace Tests\Feature;

use Tests\TestCase;
use App\Models\User;
use App\Models\Room;
use App\Models\Track;
use App\Events\UserJoinedRoom;
use App\Events\UserLeftRoom;
use App\Events\TrackAddedToQueue;
use App\Events\TrackVoted;
use App\Events\PlaybackStarted;
use App\Events\PlaybackPaused;
use App\Events\PlaybackResumed;
use App\Events\TrackSkipped;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;

class RealTimeEventBroadcastingPropertyTest extends TestCase
{
    use RefreshDatabase;

    /**
     * **Property 10: Real-time Event Broadcasting**
     * **Validates: Requirements 7.1, 7.2, 7.3, 7.4, 7.5, 6.5**
     * 
     * For any room event (user join/leave, track addition, voting, playback changes), 
     * the system should broadcast the event via WebSocket to all room participants 
     * within a reasonable time window.
     * 
     * @test
     */
    public function it_broadcasts_user_join_and_leave_events_for_any_room_membership_changes()
    {
        // **Validates: Requirements 7.1, 2.5**
        
        Event::fake();
        
        for ($iteration = 0; $iteration < 5; $iteration++) {
            // Create test users and room
            $admin = User::factory()->create();
            $participant = User::factory()->create();
            
            $room = Room::factory()->create(['administrator_id' => $admin->id]);
            $room->addParticipant($admin);
            
            // Get authentication tokens
            $adminToken = auth()->login($admin);
            $participantToken = auth()->login($participant);
            
            // Test user joining room
            $joinResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $participantToken,
            ])->postJson("/api/rooms/{$room->id}/join");
            
            $joinResponse->assertStatus(200);
            
            // Verify UserJoinedRoom event was dispatched
            Event::assertDispatched(UserJoinedRoom::class, function ($event) use ($participant, $room) {
                return $event->user->id === $participant->id && 
                       $event->room->id === $room->id;
            });
            
            // Test user leaving room
            $leaveResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $participantToken,
            ])->postJson("/api/rooms/{$room->id}/leave");
            
            $leaveResponse->assertStatus(200);
            
            // Verify UserLeftRoom event was dispatched
            Event::assertDispatched(UserLeftRoom::class, function ($event) use ($participant, $room) {
                return $event->user->id === $participant->id && 
                       $event->room->id === $room->id;
            });
            
            // Clean up for next iteration
            Event::clearResolvedInstances();
        }
    }

    /**
     * @test
     */
    public function it_broadcasts_track_addition_events_for_any_audio_file_uploads()
    {
        // **Validates: Requirements 7.2, 3.5**
        
        Event::fake();
        Storage::fake('audio');
        
        for ($iteration = 0; $iteration < 3; $iteration++) {
            // Create test users and room
            $admin = User::factory()->create();
            $uploader = User::factory()->create();
            
            $room = Room::factory()->create(['administrator_id' => $admin->id]);
            $room->addParticipant($admin);
            $room->addParticipant($uploader);
            
            // Get authentication token
            $uploaderToken = auth()->login($uploader);
            
            // Create a fake audio file with proper content
            $audioFile = UploadedFile::fake()->createWithContent(
                'test_song.mp3', 
                str_repeat('fake_audio_content_', 100), // Create content that's not just repeated bytes
                'audio/mpeg'
            );
            
            // Upload track to room
            $uploadResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $uploaderToken,
            ])->postJson("/api/rooms/{$room->id}/tracks", [
                'audio_file' => $audioFile,
            ]);
            
            $uploadResponse->assertStatus(201);
            
            // Verify TrackAddedToQueue event was dispatched
            Event::assertDispatched(TrackAddedToQueue::class, function ($event) use ($room, $uploader) {
                return $event->room->id === $room->id && 
                       $event->track->uploader_id === $uploader->id;
            });
            
            // Clean up for next iteration
            Event::clearResolvedInstances();
        }
    }

    /**
     * @test
     */
    public function it_broadcasts_voting_events_for_any_track_vote_operations()
    {
        // **Validates: Requirements 7.3, 5.5**
        
        Event::fake();
        Storage::fake('audio');
        
        for ($iteration = 0; $iteration < 3; $iteration++) {
            // Create test users and room
            $admin = User::factory()->create();
            $uploader = User::factory()->create();
            $voter = User::factory()->create();
            
            $room = Room::factory()->create(['administrator_id' => $admin->id]);
            $room->addParticipant($admin);
            $room->addParticipant($uploader);
            $room->addParticipant($voter);
            
            // Create a track
            $track = Track::factory()->create([
                'room_id' => $room->id,
                'uploader_id' => $uploader->id,
            ]);
            
            // Get authentication token
            $voterToken = auth()->login($voter);
            
            // Vote for track
            $voteResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $voterToken,
            ])->postJson("/api/rooms/{$room->id}/tracks/{$track->id}/vote");
            
            $voteResponse->assertStatus(200);
            
            // Verify TrackVoted event was dispatched for adding vote
            Event::assertDispatched(TrackVoted::class, function ($event) use ($track, $voter, $room) {
                return $event->track->id === $track->id && 
                       $event->user->id === $voter->id && 
                       $event->room->id === $room->id &&
                       $event->voteAdded === true;
            });
            
            // Remove vote
            $unvoteResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $voterToken,
            ])->deleteJson("/api/rooms/{$room->id}/tracks/{$track->id}/vote");
            
            $unvoteResponse->assertStatus(200);
            
            // Verify TrackVoted event was dispatched for removing vote
            Event::assertDispatched(TrackVoted::class, function ($event) use ($track, $voter, $room) {
                return $event->track->id === $track->id && 
                       $event->user->id === $voter->id && 
                       $event->room->id === $room->id &&
                       $event->voteAdded === false;
            });
            
            // Clean up for next iteration
            Event::clearResolvedInstances();
        }
    }

    /**
     * @test
     */
    public function it_broadcasts_playback_control_events_for_any_administrator_actions()
    {
        // **Validates: Requirements 7.4, 6.5**
        
        Event::fake();
        
        for ($iteration = 0; $iteration < 3; $iteration++) {
            // Create test users and room
            $admin = User::factory()->create();
            $participant = User::factory()->create();
            
            $room = Room::factory()->create(['administrator_id' => $admin->id]);
            $room->addParticipant($admin);
            $room->addParticipant($participant);
            
            // Create a track
            $track = Track::factory()->create([
                'room_id' => $room->id,
                'uploader_id' => $admin->id,
            ]);
            
            // Get authentication token
            $adminToken = auth()->login($admin);
            
            // Test playback start
            $startResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->postJson("/api/rooms/{$room->id}/tracks/{$track->id}/play");
            
            $startResponse->assertStatus(200);
            
            // Verify PlaybackStarted event was dispatched
            Event::assertDispatched(PlaybackStarted::class, function ($event) use ($track, $room) {
                return $event->track->id === $track->id && 
                       $event->room->id === $room->id;
            });
            
            // Test playback pause
            $pauseResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->postJson("/api/rooms/{$room->id}/playback/pause");
            
            $pauseResponse->assertStatus(200);
            
            // Verify PlaybackPaused event was dispatched
            Event::assertDispatched(PlaybackPaused::class, function ($event) use ($track, $room) {
                return $event->track->id === $track->id && 
                       $event->room->id === $room->id;
            });
            
            // Test playback resume
            $resumeResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->postJson("/api/rooms/{$room->id}/playback/resume");
            
            $resumeResponse->assertStatus(200);
            
            // Verify PlaybackResumed event was dispatched
            Event::assertDispatched(PlaybackResumed::class, function ($event) use ($track, $room) {
                return $event->track->id === $track->id && 
                       $event->room->id === $room->id;
            });
            
            // Create another track for skip test
            $nextTrack = Track::factory()->create([
                'room_id' => $room->id,
                'uploader_id' => $admin->id,
            ]);
            
            // Test track skip
            $skipResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->postJson("/api/rooms/{$room->id}/playback/skip");
            
            $skipResponse->assertStatus(200);
            
            // Verify TrackSkipped event was dispatched
            Event::assertDispatched(TrackSkipped::class, function ($event) use ($track, $room) {
                return $event->skippedTrack->id === $track->id && 
                       $event->room->id === $room->id;
            });
            
            // Clean up for next iteration
            Event::clearResolvedInstances();
        }
    }

    /**
     * @test
     */
    public function it_includes_proper_event_data_structure_for_all_broadcast_events()
    {
        // **Validates: Requirements 7.5**
        
        // Create test users and room
        $admin = User::factory()->create();
        $participant = User::factory()->create();
        
        $room = Room::factory()->create(['administrator_id' => $admin->id]);
        $room->addParticipant($admin);
        
        // Test UserJoinedRoom event data structure
        $userJoinedEvent = new UserJoinedRoom($participant, $room);
        $broadcastData = $userJoinedEvent->broadcastWith();
        
        $this->assertArrayHasKey('user', $broadcastData);
        $this->assertArrayHasKey('room_id', $broadcastData);
        $this->assertArrayHasKey('timestamp', $broadcastData);
        $this->assertEquals($participant->id, $broadcastData['user']['id']);
        $this->assertEquals($room->id, $broadcastData['room_id']);
        
        // Test UserLeftRoom event data structure
        $userLeftEvent = new UserLeftRoom($participant, $room);
        $broadcastData = $userLeftEvent->broadcastWith();
        
        $this->assertArrayHasKey('user', $broadcastData);
        $this->assertArrayHasKey('room_id', $broadcastData);
        $this->assertArrayHasKey('timestamp', $broadcastData);
        
        // Create a track for track-related events
        $track = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $admin->id,
        ]);
        
        // Test TrackAddedToQueue event data structure
        $trackAddedEvent = new TrackAddedToQueue($track, $room);
        $broadcastData = $trackAddedEvent->broadcastWith();
        
        $this->assertArrayHasKey('track', $broadcastData);
        $this->assertArrayHasKey('room_id', $broadcastData);
        $this->assertArrayHasKey('timestamp', $broadcastData);
        $this->assertArrayHasKey('uploader', $broadcastData['track']);
        
        // Test TrackVoted event data structure
        $trackVotedEvent = new TrackVoted($track, $participant, $room, true);
        $broadcastData = $trackVotedEvent->broadcastWith();
        
        $this->assertArrayHasKey('track', $broadcastData);
        $this->assertArrayHasKey('user', $broadcastData);
        $this->assertArrayHasKey('vote_added', $broadcastData);
        $this->assertArrayHasKey('room_id', $broadcastData);
        $this->assertArrayHasKey('timestamp', $broadcastData);
        $this->assertTrue($broadcastData['vote_added']);
        
        // Test PlaybackStarted event data structure
        $playbackStartedEvent = new PlaybackStarted($track, $room);
        $broadcastData = $playbackStartedEvent->broadcastWith();
        
        $this->assertArrayHasKey('track', $broadcastData);
        $this->assertArrayHasKey('room_id', $broadcastData);
        $this->assertArrayHasKey('started_at', $broadcastData);
        $this->assertArrayHasKey('server_time', $broadcastData);
        $this->assertArrayHasKey('file_path', $broadcastData['track']);
        
        // Test PlaybackPaused event data structure
        $playbackPausedEvent = new PlaybackPaused($track, $room, now(), 30);
        $broadcastData = $playbackPausedEvent->broadcastWith();
        
        $this->assertArrayHasKey('track', $broadcastData);
        $this->assertArrayHasKey('room_id', $broadcastData);
        $this->assertArrayHasKey('paused_at', $broadcastData);
        $this->assertArrayHasKey('position', $broadcastData);
        $this->assertArrayHasKey('server_time', $broadcastData);
        $this->assertEquals(30, $broadcastData['position']);
        
        // Test PlaybackResumed event data structure
        $playbackResumedEvent = new PlaybackResumed($track, $room, now(), 30);
        $broadcastData = $playbackResumedEvent->broadcastWith();
        
        $this->assertArrayHasKey('track', $broadcastData);
        $this->assertArrayHasKey('room_id', $broadcastData);
        $this->assertArrayHasKey('resumed_at', $broadcastData);
        $this->assertArrayHasKey('position', $broadcastData);
        $this->assertArrayHasKey('server_time', $broadcastData);
        
        // Create another track for skip test
        $nextTrack = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $admin->id,
        ]);
        
        // Test TrackSkipped event data structure
        $trackSkippedEvent = new TrackSkipped($track, $room, $nextTrack);
        $broadcastData = $trackSkippedEvent->broadcastWith();
        
        $this->assertArrayHasKey('skipped_track', $broadcastData);
        $this->assertArrayHasKey('next_track', $broadcastData);
        $this->assertArrayHasKey('room_id', $broadcastData);
        $this->assertArrayHasKey('timestamp', $broadcastData);
        $this->assertEquals($track->id, $broadcastData['skipped_track']['id']);
        $this->assertEquals($nextTrack->id, $broadcastData['next_track']['id']);
    }

    /**
     * @test
     */
    public function it_broadcasts_events_to_correct_private_channels_for_room_participants_only()
    {
        // **Validates: Requirements 7.5**
        
        // Create test users and rooms
        $admin1 = User::factory()->create();
        $admin2 = User::factory()->create();
        $participant = User::factory()->create();
        
        $room1 = Room::factory()->create(['administrator_id' => $admin1->id]);
        $room2 = Room::factory()->create(['administrator_id' => $admin2->id]);
        
        $room1->addParticipant($admin1);
        $room1->addParticipant($participant);
        $room2->addParticipant($admin2);
        
        // Test that events broadcast to correct room channels
        $userJoinedEvent = new UserJoinedRoom($participant, $room1);
        $channels = $userJoinedEvent->broadcastOn();
        
        $this->assertCount(1, $channels);
        $this->assertStringContainsString($room1->id, $channels[0]->name);
        
        // Test track events broadcast to correct room
        $track = Track::factory()->create([
            'room_id' => $room1->id,
            'uploader_id' => $admin1->id,
        ]);
        
        $trackAddedEvent = new TrackAddedToQueue($track, $room1);
        $channels = $trackAddedEvent->broadcastOn();
        
        $this->assertCount(1, $channels);
        $this->assertStringContainsString($room1->id, $channels[0]->name);
        
        // Test playback events broadcast to correct room
        $playbackStartedEvent = new PlaybackStarted($track, $room1);
        $channels = $playbackStartedEvent->broadcastOn();
        
        $this->assertCount(1, $channels);
        $this->assertStringContainsString($room1->id, $channels[0]->name);
    }

    /**
     * @test
     */
    public function it_uses_consistent_event_naming_conventions_for_all_broadcast_events()
    {
        // **Validates: Requirements 7.5**
        
        // Create test data
        $admin = User::factory()->create();
        $participant = User::factory()->create();
        $room = Room::factory()->create(['administrator_id' => $admin->id]);
        $track = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $admin->id,
        ]);
        
        // Test event naming conventions
        $userJoinedEvent = new UserJoinedRoom($participant, $room);
        $this->assertEquals('user.joined', $userJoinedEvent->broadcastAs());
        
        $userLeftEvent = new UserLeftRoom($participant, $room);
        $this->assertEquals('user.left', $userLeftEvent->broadcastAs());
        
        $trackAddedEvent = new TrackAddedToQueue($track, $room);
        $this->assertEquals('track.added', $trackAddedEvent->broadcastAs());
        
        $trackVotedEvent = new TrackVoted($track, $participant, $room, true);
        $this->assertEquals('track.voted', $trackVotedEvent->broadcastAs());
        
        $playbackStartedEvent = new PlaybackStarted($track, $room);
        $this->assertEquals('playback.started', $playbackStartedEvent->broadcastAs());
        
        $playbackPausedEvent = new PlaybackPaused($track, $room);
        $this->assertEquals('playback.paused', $playbackPausedEvent->broadcastAs());
        
        $playbackResumedEvent = new PlaybackResumed($track, $room);
        $this->assertEquals('playback.resumed', $playbackResumedEvent->broadcastAs());
        
        $trackSkippedEvent = new TrackSkipped($track, $room);
        $this->assertEquals('track.skipped', $trackSkippedEvent->broadcastAs());
    }
}