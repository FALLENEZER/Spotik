<?php

namespace Tests\Feature;

use Tests\TestCase;
use App\Models\User;
use App\Models\Room;
use App\Models\Track;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tymon\JWTAuth\Facades\JWTAuth;

class TrackVotingQueueTest extends TestCase
{
    use RefreshDatabase;

    /** @test */
    public function it_reorders_queue_when_tracks_receive_votes()
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
        
        // Create tracks with different upload times
        $track1 = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $admin->id,
            'vote_score' => 0,
            'created_at' => now()->subMinutes(3) // Uploaded first
        ]);
        
        $track2 = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $participant1->id,
            'vote_score' => 0,
            'created_at' => now()->subMinutes(2) // Uploaded second
        ]);
        
        $track3 = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $participant2->id,
            'vote_score' => 0,
            'created_at' => now()->subMinutes(1) // Uploaded third
        ]);

        // Initial queue should be ordered by upload time (created_at ASC)
        $token = JWTAuth::fromUser($admin);
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->getJson("/api/rooms/{$room->id}/tracks");

        $response->assertStatus(200);
        $tracks = $response->json('tracks');
        
        $this->assertCount(3, $tracks);
        $this->assertEquals($track1->id, $tracks[0]['id']); // First uploaded
        $this->assertEquals($track2->id, $tracks[1]['id']); // Second uploaded
        $this->assertEquals($track3->id, $tracks[2]['id']); // Third uploaded

        // Vote for track3 (should move to top)
        $voteResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->postJson("/api/rooms/{$room->id}/tracks/{$track3->id}/vote");
        
        $voteResponse->assertStatus(200);
        $this->assertEquals(1, $voteResponse->json('vote_score'));

        // Check new queue ordering
        $newResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->getJson("/api/rooms/{$room->id}/tracks");

        $newResponse->assertStatus(200);
        $newTracks = $newResponse->json('tracks');
        
        $this->assertCount(3, $newTracks);
        $this->assertEquals($track3->id, $newTracks[0]['id']); // Now first (1 vote)
        $this->assertEquals(1, $newTracks[0]['vote_score']);
        $this->assertEquals($track1->id, $newTracks[1]['id']); // Second (0 votes, uploaded earlier)
        $this->assertEquals(0, $newTracks[1]['vote_score']);
        $this->assertEquals($track2->id, $newTracks[2]['id']); // Third (0 votes, uploaded later)
        $this->assertEquals(0, $newTracks[2]['vote_score']);

        // Vote for track1 (should move to top, but after track3 since track3 was voted first)
        $participant1Token = JWTAuth::fromUser($participant1);
        $voteResponse2 = $this->withHeaders([
            'Authorization' => 'Bearer ' . $participant1Token,
        ])->postJson("/api/rooms/{$room->id}/tracks/{$track1->id}/vote");
        
        $voteResponse2->assertStatus(200);
        $this->assertEquals(1, $voteResponse2->json('vote_score'));

        // Check final queue ordering
        $finalResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->getJson("/api/rooms/{$room->id}/tracks");

        $finalResponse->assertStatus(200);
        $finalTracks = $finalResponse->json('tracks');
        
        $this->assertCount(3, $finalTracks);
        
        // Both track3 and track1 have 1 vote, so they should be ordered by upload time (track1 first)
        $this->assertEquals($track1->id, $finalTracks[0]['id']); // First (1 vote, uploaded earlier)
        $this->assertEquals(1, $finalTracks[0]['vote_score']);
        $this->assertEquals($track3->id, $finalTracks[1]['id']); // Second (1 vote, uploaded later)
        $this->assertEquals(1, $finalTracks[1]['vote_score']);
        $this->assertEquals($track2->id, $finalTracks[2]['id']); // Third (0 votes)
        $this->assertEquals(0, $finalTracks[2]['vote_score']);
    }

    /** @test */
    public function it_handles_vote_removal_and_reorders_queue()
    {
        // Create users
        $admin = User::factory()->create();
        $participant = User::factory()->create();
        
        // Create room
        $room = Room::factory()->create(['administrator_id' => $admin->id]);
        $room->addParticipant($admin);
        $room->addParticipant($participant);
        
        // Create tracks
        $track1 = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $admin->id,
            'vote_score' => 0,
            'created_at' => now()->subMinutes(2), // Uploaded first
        ]);
        
        $track2 = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $participant->id,
            'vote_score' => 0,
            'created_at' => now()->subMinutes(1), // Uploaded second
        ]);

        // Vote for track2
        $token = JWTAuth::fromUser($admin);
        $voteResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->postJson("/api/rooms/{$room->id}/tracks/{$track2->id}/vote");
        
        $voteResponse->assertStatus(200);

        // Verify track2 is now first
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->getJson("/api/rooms/{$room->id}/tracks");

        $tracks = $response->json('tracks');
        $this->assertEquals($track2->id, $tracks[0]['id']);
        $this->assertEquals(1, $tracks[0]['vote_score']);

        // Remove vote from track2
        $unvoteResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->deleteJson("/api/rooms/{$room->id}/tracks/{$track2->id}/vote");
        
        $unvoteResponse->assertStatus(200);
        $this->assertEquals(0, $unvoteResponse->json('vote_score'));

        // Verify queue is back to original order (by upload time)
        $finalResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->getJson("/api/rooms/{$room->id}/tracks");

        $finalTracks = $finalResponse->json('tracks');
        $this->assertEquals($track1->id, $finalTracks[0]['id']); // First uploaded
        $this->assertEquals(0, $finalTracks[0]['vote_score']);
        $this->assertEquals($track2->id, $finalTracks[1]['id']); // Second uploaded
        $this->assertEquals(0, $finalTracks[1]['vote_score']);
    }
}