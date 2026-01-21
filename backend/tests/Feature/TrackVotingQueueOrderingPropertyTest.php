<?php

namespace Tests\Feature;

use Tests\TestCase;
use App\Models\User;
use App\Models\Room;
use App\Models\Track;
use App\Models\TrackVote;
use App\Models\RoomParticipant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tymon\JWTAuth\Facades\JWTAuth;

/**
 * Feature: spotik, Property 8: Track Voting and Queue Ordering
 * **Validates: Requirements 5.1, 5.2, 5.3, 5.4**
 * 
 * Property-based test that validates track voting and queue ordering system
 * works correctly across all valid inputs.
 */
class TrackVotingQueueOrderingPropertyTest extends TestCase
{
    use RefreshDatabase;

    /**
     * Property 8: Track Voting and Queue Ordering - Iteration 1
     * 
     * **Validates: Requirements 5.1, 5.2, 5.3, 5.4**
     * 
     * @test
     */
    public function property_track_voting_and_queue_ordering_iteration_1()
    {
        $this->runTrackVotingPropertyTest();
    }
    
    /**
     * Property 8: Track Voting and Queue Ordering - Iteration 2
     * 
     * **Validates: Requirements 5.1, 5.2, 5.3, 5.4**
     * 
     * @test
     */
    public function property_track_voting_and_queue_ordering_iteration_2()
    {
        $this->runTrackVotingPropertyTest();
    }
    
    /**
     * Property 8: Track Voting and Queue Ordering - Iteration 3
     * 
     * **Validates: Requirements 5.1, 5.2, 5.3, 5.4**
     * 
     * @test
     */
    public function property_track_voting_and_queue_ordering_iteration_3()
    {
        $this->runTrackVotingPropertyTest();
    }
    
    /**
     * Property 8: Track Voting and Queue Ordering - Iteration 4
     * 
     * **Validates: Requirements 5.1, 5.2, 5.3, 5.4**
     * 
     * @test
     */
    public function property_track_voting_and_queue_ordering_iteration_4()
    {
        $this->runTrackVotingPropertyTest();
    }
    
    /**
     * Property 8: Track Voting and Queue Ordering - Iteration 5
     * 
     * **Validates: Requirements 5.1, 5.2, 5.3, 5.4**
     * 
     * @test
     */
    public function property_track_voting_and_queue_ordering_iteration_5()
    {
        $this->runTrackVotingPropertyTest();
    }
    
    /**
     * Run a single iteration of the track voting property test
     */
    private function runTrackVotingPropertyTest(): void
    {
        // Generate random test data
        $numUsers = fake()->numberBetween(2, 5);
        $numTracks = fake()->numberBetween(2, 6);
        
        // Create users (first one is admin)
        $users = User::factory()->count($numUsers)->create();
        $admin = $users->first();
        
        // Create room with admin
        $room = Room::factory()->create(['administrator_id' => $admin->id]);
        
        // Add all users as participants
        foreach ($users as $user) {
            $room->addParticipant($user);
        }
        
        // Create tracks with different upload times (staggered by minutes)
        $tracks = collect();
        for ($i = 0; $i < $numTracks; $i++) {
            $uploader = $users->random();
            $track = Track::factory()->create([
                'room_id' => $room->id,
                'uploader_id' => $uploader->id,
                'vote_score' => 0,
                'created_at' => now()->subMinutes($numTracks - $i), // Earlier tracks have higher subMinutes
            ]);
            $tracks->push($track);
        }
        
        // Initial queue should be ordered by upload time (created_at ASC)
        $this->assertInitialQueueOrdering($room, $tracks);
        
        // Generate random voting patterns
        $votingActions = $this->generateRandomVotingActions($users, $tracks);
        
        // Execute voting actions and verify queue ordering after each action
        $this->executeVotingActionsAndVerifyOrdering($room, $votingActions);
        
        // Verify final state consistency
        $this->verifyFinalStateConsistency($room, $tracks, $users);
    }
    
    /**
     * Verify initial queue ordering (by upload time when all scores are 0)
     */
    private function assertInitialQueueOrdering(Room $room, $tracks): void
    {
        $token = JWTAuth::fromUser($room->administrator);
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->getJson("/api/rooms/{$room->id}/tracks");
        
        $response->assertStatus(200);
        $queueTracks = $response->json('tracks');
        
        $this->assertCount($tracks->count(), $queueTracks);
        
        // Should be ordered by created_at ASC (earliest first)
        $expectedOrder = $tracks->sortBy('created_at')->pluck('id')->toArray();
        $actualOrder = collect($queueTracks)->pluck('id')->toArray();
        
        $this->assertEquals($expectedOrder, $actualOrder, 
            "Initial queue should be ordered by upload time (created_at ASC)");
        
        // All tracks should have 0 votes initially
        foreach ($queueTracks as $track) {
            $this->assertEquals(0, $track['vote_score'], 
                "All tracks should start with 0 votes");
        }
    }
    
    /**
     * Generate random voting actions (vote/unvote combinations)
     */
    private function generateRandomVotingActions($users, $tracks): array
    {
        $actions = [];
        $numActions = fake()->numberBetween(3, 10);
        
        for ($i = 0; $i < $numActions; $i++) {
            $user = $users->random();
            $track = $tracks->random();
            $action = fake()->randomElement(['vote', 'unvote']);
            
            $actions[] = [
                'user' => $user,
                'track' => $track,
                'action' => $action,
            ];
        }
        
        return $actions;
    }
    
    /**
     * Execute voting actions and verify queue ordering after each action
     */
    private function executeVotingActionsAndVerifyOrdering(Room $room, array $votingActions): void
    {
        $voteTracker = []; // Track votes per user per track
        
        foreach ($votingActions as $actionData) {
            $user = $actionData['user'];
            $track = $actionData['track'];
            $action = $actionData['action'];
            
            $token = JWTAuth::fromUser($user);
            $userTrackKey = $user->id . '_' . $track->id;
            $hasVoted = isset($voteTracker[$userTrackKey]);
            
            if ($action === 'vote' && !$hasVoted) {
                // Only vote if user hasn't voted for this track yet
                $response = $this->withHeaders([
                    'Authorization' => 'Bearer ' . $token,
                ])->postJson("/api/rooms/{$room->id}/tracks/{$track->id}/vote");
                
                $response->assertStatus(200);
                $voteTracker[$userTrackKey] = true;
                $this->assertTrue($response->json('user_has_voted'));
                
            } elseif ($action === 'unvote' && $hasVoted) {
                // Only unvote if user has voted for this track
                $response = $this->withHeaders([
                    'Authorization' => 'Bearer ' . $token,
                ])->deleteJson("/api/rooms/{$room->id}/tracks/{$track->id}/vote");
                
                $response->assertStatus(200);
                unset($voteTracker[$userTrackKey]);
                $this->assertFalse($response->json('user_has_voted'));
            }
            // Skip actions that would be no-ops (voting when already voted, unvoting when not voted)
            
            // Verify queue ordering after this action
            $this->verifyQueueOrdering($room, $voteTracker);
        }
    }
    
    /**
     * Verify queue ordering matches expected rules
     */
    private function verifyQueueOrdering(Room $room, array $voteTracker): void
    {
        $token = JWTAuth::fromUser($room->administrator);
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->getJson("/api/rooms/{$room->id}/tracks");
        
        $response->assertStatus(200);
        $queueTracks = $response->json('tracks');
        
        // Calculate expected vote scores
        $expectedScores = [];
        foreach ($queueTracks as $track) {
            $trackId = $track['id'];
            $voteCount = 0;
            
            foreach ($voteTracker as $key => $voted) {
                if (str_ends_with($key, '_' . $trackId)) {
                    $voteCount++;
                }
            }
            
            $expectedScores[$trackId] = $voteCount;
        }
        
        // Verify vote scores match expected
        foreach ($queueTracks as $track) {
            $trackId = $track['id'];
            $expectedScore = $expectedScores[$trackId];
            
            $this->assertEquals($expectedScore, $track['vote_score'], 
                "Track {$trackId} should have {$expectedScore} votes but has {$track['vote_score']}");
        }
        
        // Verify ordering: by vote_score DESC, then by created_at ASC
        for ($i = 0; $i < count($queueTracks) - 1; $i++) {
            $current = $queueTracks[$i];
            $next = $queueTracks[$i + 1];
            
            if ($current['vote_score'] === $next['vote_score']) {
                // Same score: should be ordered by created_at ASC (earlier first)
                $currentTime = strtotime($current['created_at']);
                $nextTime = strtotime($next['created_at']);
                
                $this->assertLessThanOrEqual($nextTime, $currentTime,
                    "Tracks with same vote score should be ordered by upload time (earlier first). " .
                    "Track {$current['id']} (uploaded {$current['created_at']}) should come before " .
                    "Track {$next['id']} (uploaded {$next['created_at']})");
            } else {
                // Different scores: should be ordered by vote_score DESC (higher first)
                $this->assertGreaterThan($next['vote_score'], $current['vote_score'],
                    "Tracks should be ordered by vote score (higher first). " .
                    "Track {$current['id']} ({$current['vote_score']} votes) should come before " .
                    "Track {$next['id']} ({$next['vote_score']} votes)");
            }
        }
    }
    
    /**
     * Verify final state consistency between database and API
     */
    private function verifyFinalStateConsistency(Room $room, $tracks, $users): void
    {
        // Get final queue from API
        $token = JWTAuth::fromUser($room->administrator);
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->getJson("/api/rooms/{$room->id}/tracks");
        
        $response->assertStatus(200);
        $apiTracks = $response->json('tracks');
        
        // Get tracks directly from database
        $dbTracks = $room->trackQueue()->get();
        
        $this->assertCount($dbTracks->count(), $apiTracks, 
            "API and database should return same number of tracks");
        
        // Verify each track's data consistency
        foreach ($apiTracks as $index => $apiTrack) {
            $dbTrack = $dbTracks[$index];
            
            $this->assertEquals($dbTrack->id, $apiTrack['id']);
            $this->assertEquals($dbTrack->vote_score, $apiTrack['vote_score']);
            
            // Verify vote count matches actual votes in database
            $actualVoteCount = TrackVote::where('track_id', $dbTrack->id)->count();
            $this->assertEquals($actualVoteCount, $dbTrack->vote_score,
                "Track {$dbTrack->id} vote_score should match actual vote count in database");
        }
        
        // Verify no duplicate votes exist
        $allVotes = TrackVote::whereIn('track_id', $tracks->pluck('id'))->get();
        $duplicateCheck = $allVotes->groupBy(['track_id', 'user_id'])->filter(function ($group) {
            return $group->count() > 1;
        });
        
        $this->assertTrue($duplicateCheck->isEmpty(),
            "No duplicate votes should exist for same user-track combination. Found duplicates: " . 
            $duplicateCheck->keys()->implode(', '));
    }
    
    /**
     * Test edge case: Single user voting for all tracks
     * 
     * @test
     */
    public function property_single_user_voting_maintains_upload_time_ordering()
    {
        $numTracks = fake()->numberBetween(3, 5);
        
        // Create admin user
        $admin = User::factory()->create();
        $room = Room::factory()->create(['administrator_id' => $admin->id]);
        $room->addParticipant($admin);
        
        // Create tracks with different upload times
        $tracks = collect();
        for ($i = 0; $i < $numTracks; $i++) {
            $track = Track::factory()->create([
                'room_id' => $room->id,
                'uploader_id' => $admin->id,
                'vote_score' => 0,
                'created_at' => now()->subMinutes($numTracks - $i),
            ]);
            $tracks->push($track);
        }
        
        $token = JWTAuth::fromUser($admin);
        
        // Vote for all tracks (they should all have 1 vote)
        foreach ($tracks as $track) {
            $response = $this->withHeaders([
                'Authorization' => 'Bearer ' . $token,
            ])->postJson("/api/rooms/{$room->id}/tracks/{$track->id}/vote");
            
            $response->assertStatus(200);
            $this->assertEquals(1, $response->json('vote_score'));
        }
        
        // Verify final ordering is by upload time (since all have same score)
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->getJson("/api/rooms/{$room->id}/tracks");
        
        $response->assertStatus(200);
        $queueTracks = $response->json('tracks');
        
        // All should have 1 vote and be ordered by created_at ASC
        $expectedOrder = $tracks->sortBy('created_at')->pluck('id')->toArray();
        $actualOrder = collect($queueTracks)->pluck('id')->toArray();
        
        $this->assertEquals($expectedOrder, $actualOrder,
            "When all tracks have same vote score, they should be ordered by upload time");
        
        foreach ($queueTracks as $track) {
            $this->assertEquals(1, $track['vote_score']);
        }
    }
    
    /**
     * Test edge case: Vote removal reordering
     * 
     * @test
     */
    public function property_vote_removal_correctly_reorders_queue()
    {
        // Create users and room
        $users = User::factory()->count(3)->create();
        $admin = $users->first();
        $room = Room::factory()->create(['administrator_id' => $admin->id]);
        
        foreach ($users as $user) {
            $room->addParticipant($user);
        }
        
        // Create 3 tracks
        $track1 = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $admin->id,
            'vote_score' => 0,
            'created_at' => now()->subMinutes(3),
        ]);
        
        $track2 = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $users[1]->id,
            'vote_score' => 0,
            'created_at' => now()->subMinutes(2),
        ]);
        
        $track3 = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $users[2]->id,
            'vote_score' => 0,
            'created_at' => now()->subMinutes(1),
        ]);
        
        $adminToken = JWTAuth::fromUser($admin);
        $user1Token = JWTAuth::fromUser($users[1]);
        
        // Give track3 two votes (should be first)
        $this->withHeaders(['Authorization' => 'Bearer ' . $adminToken])
             ->postJson("/api/rooms/{$room->id}/tracks/{$track3->id}/vote")
             ->assertStatus(200);
             
        $this->withHeaders(['Authorization' => 'Bearer ' . $user1Token])
             ->postJson("/api/rooms/{$room->id}/tracks/{$track3->id}/vote")
             ->assertStatus(200);
        
        // Give track1 one vote (should be second)
        $this->withHeaders(['Authorization' => 'Bearer ' . $adminToken])
             ->postJson("/api/rooms/{$room->id}/tracks/{$track1->id}/vote")
             ->assertStatus(200);
        
        // Verify ordering: track3 (2 votes), track1 (1 vote), track2 (0 votes)
        $response = $this->withHeaders(['Authorization' => 'Bearer ' . $adminToken])
                         ->getJson("/api/rooms/{$room->id}/tracks");
        
        $tracks = $response->json('tracks');
        $this->assertEquals($track3->id, $tracks[0]['id']);
        $this->assertEquals(2, $tracks[0]['vote_score']);
        $this->assertEquals($track1->id, $tracks[1]['id']);
        $this->assertEquals(1, $tracks[1]['vote_score']);
        $this->assertEquals($track2->id, $tracks[2]['id']);
        $this->assertEquals(0, $tracks[2]['vote_score']);
        
        // Remove one vote from track3
        $this->withHeaders(['Authorization' => 'Bearer ' . $adminToken])
             ->deleteJson("/api/rooms/{$room->id}/tracks/{$track3->id}/vote")
             ->assertStatus(200);
        
        // Now track3 and track1 both have 1 vote, should be ordered by upload time
        $response = $this->withHeaders(['Authorization' => 'Bearer ' . $adminToken])
                         ->getJson("/api/rooms/{$room->id}/tracks");
        
        $tracks = $response->json('tracks');
        $this->assertEquals($track1->id, $tracks[0]['id']); // Earlier upload
        $this->assertEquals(1, $tracks[0]['vote_score']);
        $this->assertEquals($track3->id, $tracks[1]['id']); // Later upload
        $this->assertEquals(1, $tracks[1]['vote_score']);
        $this->assertEquals($track2->id, $tracks[2]['id']);
        $this->assertEquals(0, $tracks[2]['vote_score']);
    }
}