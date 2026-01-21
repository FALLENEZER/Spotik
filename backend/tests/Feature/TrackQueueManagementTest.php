<?php

namespace Tests\Feature;

use Tests\TestCase;
use App\Models\User;
use App\Models\Room;
use App\Models\Track;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tymon\JWTAuth\Facades\JWTAuth;
use Illuminate\Http\UploadedFile;

class TrackQueueManagementTest extends TestCase
{
    use RefreshDatabase;

    /** @test */
    public function it_can_get_track_queue_for_room()
    {
        // Create users
        $admin = User::factory()->create();
        $participant = User::factory()->create();
        
        // Create room
        $room = Room::factory()->create(['administrator_id' => $admin->id]);
        $room->addParticipant($admin);
        $room->addParticipant($participant);
        
        // Create tracks with different vote scores
        $track1 = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $admin->id,
            'vote_score' => 0,
            'created_at' => now()->subMinutes(3)
        ]);
        
        $track2 = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $participant->id,
            'vote_score' => 2,
            'created_at' => now()->subMinutes(2)
        ]);
        
        $track3 = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $admin->id,
            'vote_score' => 1,
            'created_at' => now()->subMinutes(1)
        ]);

        // Get track queue
        $token = JWTAuth::fromUser($admin);
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->getJson("/api/rooms/{$room->id}/tracks");

        $response->assertStatus(200);
        $tracks = $response->json('tracks');
        
        // Should be ordered by vote_score DESC, then created_at ASC
        // Expected order: track2 (2 votes), track3 (1 vote), track1 (0 votes)
        $this->assertCount(3, $tracks);
        $this->assertEquals($track2->id, $tracks[0]['id']);
        $this->assertEquals(2, $tracks[0]['vote_score']);
        
        $this->assertEquals($track3->id, $tracks[1]['id']);
        $this->assertEquals(1, $tracks[1]['vote_score']);
        
        $this->assertEquals($track1->id, $tracks[2]['id']);
        $this->assertEquals(0, $tracks[2]['vote_score']);
    }

    /** @test */
    public function it_orders_tracks_by_upload_time_when_vote_scores_are_equal()
    {
        // Create users
        $admin = User::factory()->create();
        $participant = User::factory()->create();
        
        // Create room
        $room = Room::factory()->create(['administrator_id' => $admin->id]);
        $room->addParticipant($admin);
        $room->addParticipant($participant);
        
        // Create tracks with same vote scores but different upload times
        $track1 = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $admin->id,
            'vote_score' => 1,
            'created_at' => now()->subMinutes(3) // Uploaded first
        ]);
        
        $track2 = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $participant->id,
            'vote_score' => 1,
            'created_at' => now()->subMinutes(2) // Uploaded second
        ]);
        
        $track3 = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $admin->id,
            'vote_score' => 1,
            'created_at' => now()->subMinutes(1) // Uploaded third
        ]);

        // Get track queue
        $token = JWTAuth::fromUser($admin);
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->getJson("/api/rooms/{$room->id}/tracks");

        $response->assertStatus(200);
        $tracks = $response->json('tracks');
        
        // Should be ordered by created_at ASC when vote scores are equal
        // Expected order: track1 (earliest), track2 (middle), track3 (latest)
        $this->assertCount(3, $tracks);
        $this->assertEquals($track1->id, $tracks[0]['id']);
        $this->assertEquals($track2->id, $tracks[1]['id']);
        $this->assertEquals($track3->id, $tracks[2]['id']);
    }

    /** @test */
    public function it_can_add_track_to_room_queue()
    {
        // Create users
        $admin = User::factory()->create();
        $participant = User::factory()->create();
        
        // Create room
        $room = Room::factory()->create(['administrator_id' => $admin->id]);
        $room->addParticipant($admin);
        $room->addParticipant($participant);

        // Create a fake audio file
        $audioFile = UploadedFile::fake()->create('test.mp3', 1000, 'audio/mpeg');

        // Upload track
        $token = JWTAuth::fromUser($participant);
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->postJson("/api/rooms/{$room->id}/tracks", [
            'audio_file' => $audioFile,
        ]);

        $response->assertStatus(201);
        $trackData = $response->json('track');
        
        // Verify track was added to queue
        $queueResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->getJson("/api/rooms/{$room->id}/tracks");

        $queueResponse->assertStatus(200);
        $tracks = $queueResponse->json('tracks');
        
        $this->assertCount(1, $tracks);
        $this->assertEquals($trackData['id'], $tracks[0]['id']);
        $this->assertEquals(0, $tracks[0]['vote_score']); // Initial vote score should be 0
    }

    /** @test */
    public function it_can_remove_track_from_queue_as_admin()
    {
        // Create users
        $admin = User::factory()->create();
        $participant = User::factory()->create();
        
        // Create room
        $room = Room::factory()->create(['administrator_id' => $admin->id]);
        $room->addParticipant($admin);
        $room->addParticipant($participant);
        
        // Create track
        $track = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $participant->id,
        ]);

        // Admin removes track
        $token = JWTAuth::fromUser($admin);
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->deleteJson("/api/rooms/{$room->id}/tracks/{$track->id}");

        $response->assertStatus(200);
        
        // Verify track was removed from queue
        $queueResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->getJson("/api/rooms/{$room->id}/tracks");

        $queueResponse->assertStatus(200);
        $tracks = $queueResponse->json('tracks');
        
        $this->assertCount(0, $tracks);
    }

    /** @test */
    public function it_can_remove_own_track_from_queue()
    {
        // Create users
        $admin = User::factory()->create();
        $participant = User::factory()->create();
        
        // Create room
        $room = Room::factory()->create(['administrator_id' => $admin->id]);
        $room->addParticipant($admin);
        $room->addParticipant($participant);
        
        // Create track uploaded by participant
        $track = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $participant->id,
        ]);

        // Participant removes their own track
        $token = JWTAuth::fromUser($participant);
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->deleteJson("/api/rooms/{$room->id}/tracks/{$track->id}");

        $response->assertStatus(200);
        
        // Verify track was removed from queue
        $queueResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->getJson("/api/rooms/{$room->id}/tracks");

        $queueResponse->assertStatus(200);
        $tracks = $queueResponse->json('tracks');
        
        $this->assertCount(0, $tracks);
    }

    /** @test */
    public function it_prevents_non_admin_from_removing_others_tracks()
    {
        // Create users
        $admin = User::factory()->create();
        $participant1 = User::factory()->create();
        $participant2 = User::factory()->create();
        
        // Create room
        $room = Room::factory()->create(['administrator_id' => $admin->id]);
        $room->addParticipant($admin);
        $room->addParticipant($participant1);
        $room->addParticipant($participant2);
        
        // Create track uploaded by participant1
        $track = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $participant1->id,
        ]);

        // Participant2 tries to remove participant1's track
        $token = JWTAuth::fromUser($participant2);
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->deleteJson("/api/rooms/{$room->id}/tracks/{$track->id}");

        $response->assertStatus(403);
        
        // Verify track is still in queue
        $queueResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->getJson("/api/rooms/{$room->id}/tracks");

        $queueResponse->assertStatus(200);
        $tracks = $queueResponse->json('tracks');
        
        $this->assertCount(1, $tracks);
        $this->assertEquals($track->id, $tracks[0]['id']);
    }
}