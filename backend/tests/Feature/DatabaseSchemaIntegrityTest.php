<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\Room;
use App\Models\Track;
use App\Models\RoomParticipant;
use App\Models\TrackVote;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Property-Based Test for Database Schema Integrity
 * 
 * **Feature: spotik, Property 11: Data Persistence and Integrity**
 * **Validates: Requirements 8.1, 8.2, 8.5**
 * 
 * This test validates that for any data operation (user creation, room creation, 
 * track upload, vote), the system persists the data reliably in PostgreSQL and 
 * maintains referential integrity.
 */
class DatabaseSchemaIntegrityTest extends TestCase
{
    use RefreshDatabase;

    /**
     * Test that user data is persisted correctly and retrievable.
     * Property: For any valid user data, the system should persist it correctly
     */
    public function test_maintains_data_persistence_for_user_operations(): void
    {
        $userData = [
            'username' => fake()->unique()->userName(),
            'email' => fake()->unique()->safeEmail(),
            'password_hash' => bcrypt('password123'),
        ];

        $user = User::create($userData);

        // Verify data is persisted correctly
        $this->assertInstanceOf(User::class, $user);
        $this->assertNotNull($user->id);
        $this->assertEquals($userData['username'], $user->username);
        $this->assertEquals($userData['email'], $user->email);
        $this->assertEquals($userData['password_hash'], $user->password_hash);
        
        // Verify data is retrievable from database
        $retrievedUser = User::find($user->id);
        $this->assertNotNull($retrievedUser);
        $this->assertEquals($userData['username'], $retrievedUser->username);
        $this->assertEquals($userData['email'], $retrievedUser->email);
    }

    /**
     * Test that foreign key constraints are enforced for room-user relationships.
     * Property: Foreign key constraints should be enforced for room-user relationships
     */
    public function test_maintains_referential_integrity_for_room_user_relationships(): void
    {
        $user = User::factory()->create();
        
        $roomData = [
            'name' => fake()->words(3, true),
            'administrator_id' => $user->id,
            'is_playing' => false,
        ];

        $room = Room::create($roomData);

        // Verify room is created with correct administrator
        $this->assertEquals($user->id, $room->administrator_id);
        $this->assertInstanceOf(User::class, $room->administrator);
        $this->assertEquals($user->id, $room->administrator->id);
        
        // Verify cascade behavior - deleting user should affect room
        $roomId = $room->id;
        $user->delete();
        
        // Room should be deleted due to cascade constraint
        $this->assertNull(Room::find($roomId));
    }

    /**
     * Test that unique constraints prevent duplicate data.
     * Property: Unique constraints should prevent duplicate data
     */
    public function test_enforces_unique_constraints_to_prevent_duplicates(): void
    {
        $userData = [
            'username' => 'testuser123',
            'email' => 'test@example.com',
            'password_hash' => bcrypt('password'),
        ];

        // Create first user
        $user1 = User::create($userData);
        $this->assertInstanceOf(User::class, $user1);

        // Attempt to create duplicate username should fail
        $this->expectException(QueryException::class);
        User::create([
            'username' => $userData['username'], // Same username
            'email' => 'different@example.com',
            'password_hash' => bcrypt('password'),
        ]);
    }

    /**
     * Test that unique constraints prevent duplicate emails.
     */
    public function test_enforces_unique_email_constraints(): void
    {
        $userData = [
            'username' => 'testuser123',
            'email' => 'test@example.com',
            'password_hash' => bcrypt('password'),
        ];

        // Create first user
        $user1 = User::create($userData);
        $this->assertInstanceOf(User::class, $user1);

        // Attempt to create duplicate email should fail
        $this->expectException(QueryException::class);
        User::create([
            'username' => 'differentuser',
            'email' => $userData['email'], // Same email
            'password_hash' => bcrypt('password'),
        ]);
    }

    /**
     * Test complex foreign key relationships for tracks.
     * Property: Complex foreign key relationships should be maintained
     */
    public function test_maintains_referential_integrity_for_track_relationships(): void
    {
        $user = User::factory()->create();
        $room = Room::factory()->create(['administrator_id' => $user->id]);
        
        $trackData = [
            'room_id' => $room->id,
            'uploader_id' => $user->id,
            'filename' => fake()->uuid() . '.mp3',
            'original_name' => fake()->words(3, true) . '.mp3',
            'file_path' => 'tracks/' . fake()->uuid() . '.mp3',
            'duration_seconds' => fake()->numberBetween(30, 600),
            'file_size_bytes' => fake()->numberBetween(1000000, 50000000),
            'mime_type' => 'audio/mpeg',
            'vote_score' => 0,
        ];

        $track = Track::create($trackData);

        // Verify relationships are established correctly
        $this->assertEquals($room->id, $track->room_id);
        $this->assertEquals($user->id, $track->uploader_id);
        $this->assertInstanceOf(Room::class, $track->room);
        $this->assertInstanceOf(User::class, $track->uploader);
        
        // Verify cascade delete behavior
        $trackId = $track->id;
        $room->delete();
        
        // Track should be deleted due to cascade constraint
        $this->assertNull(Track::find($trackId));
    }

    /**
     * Test that duplicate room participants are prevented.
     * Property: Unique constraints should prevent duplicate room participants
     */
    public function test_prevents_duplicate_room_participants(): void
    {
        $user = User::factory()->create();
        $room = Room::factory()->create();

        // Create first participation
        $participant1 = RoomParticipant::create([
            'room_id' => $room->id,
            'user_id' => $user->id,
            'joined_at' => now(),
        ]);

        $this->assertInstanceOf(RoomParticipant::class, $participant1);

        // Attempt to create duplicate participation should fail
        $this->expectException(QueryException::class);
        RoomParticipant::create([
            'room_id' => $room->id,
            'user_id' => $user->id,
            'joined_at' => now(),
        ]);
    }

    /**
     * Test that duplicate track votes are prevented.
     * Property: Unique constraints should prevent duplicate votes from same user
     */
    public function test_prevents_duplicate_track_votes(): void
    {
        $user = User::factory()->create();
        $track = Track::factory()->create();

        // Create first vote
        $vote1 = TrackVote::create([
            'track_id' => $track->id,
            'user_id' => $user->id,
            'created_at' => now(),
        ]);

        $this->assertInstanceOf(TrackVote::class, $vote1);

        // Attempt to create duplicate vote should fail
        $this->expectException(QueryException::class);
        TrackVote::create([
            'track_id' => $track->id,
            'user_id' => $user->id,
            'created_at' => now(),
        ]);
    }

    /**
     * Test data integrity across concurrent operations.
     * Property: Data integrity should be maintained even with concurrent operations
     */
    public function test_maintains_data_integrity_across_concurrent_operations(): void
    {
        $user = User::factory()->create();
        $room = Room::factory()->create(['administrator_id' => $user->id]);
        
        // Create multiple tracks concurrently (simulated)
        $tracks = [];
        for ($i = 0; $i < 5; $i++) {
            $tracks[] = Track::factory()->create([
                'room_id' => $room->id,
                'uploader_id' => $user->id,
            ]);
        }

        // Verify all tracks are properly linked
        $this->assertCount(5, $tracks);
        foreach ($tracks as $track) {
            $this->assertEquals($room->id, $track->room_id);
            $this->assertEquals($user->id, $track->uploader_id);
            $this->assertInstanceOf(Room::class, $track->room);
            $this->assertInstanceOf(User::class, $track->uploader);
        }

        // Create votes for tracks
        $otherUsers = User::factory()->count(3)->create();
        foreach ($tracks as $track) {
            foreach ($otherUsers as $voter) {
                TrackVote::create([
                    'track_id' => $track->id,
                    'user_id' => $voter->id,
                    'created_at' => now(),
                ]);
            }
        }

        // Verify vote counts are correct
        foreach ($tracks as $track) {
            $this->assertEquals(3, $track->votes()->count());
        }
    }

    /**
     * Test cascade deletes work properly across all relationships.
     * Property: Cascade deletes should work properly to maintain referential integrity
     */
    public function test_handles_cascade_deletes_properly_across_all_relationships(): void
    {
        $user = User::factory()->create();
        $room = Room::factory()->create(['administrator_id' => $user->id]);
        $track = Track::factory()->create([
            'room_id' => $room->id,
            'uploader_id' => $user->id,
        ]);
        
        // Create room participant
        $participant = RoomParticipant::create([
            'room_id' => $room->id,
            'user_id' => $user->id,
            'joined_at' => now(),
        ]);
        
        // Create track vote
        $otherUser = User::factory()->create();
        $vote = TrackVote::create([
            'track_id' => $track->id,
            'user_id' => $otherUser->id,
            'created_at' => now(),
        ]);

        $roomId = $room->id;
        $trackId = $track->id;
        $participantId = $participant->id;
        $voteId = $vote->id;

        // Delete the room - should cascade to tracks, participants, and votes
        $room->delete();

        // Verify cascade deletes worked
        $this->assertNull(Room::find($roomId));
        $this->assertNull(Track::find($trackId));
        $this->assertNull(RoomParticipant::find($participantId));
        $this->assertNull(TrackVote::find($voteId));
        
        // User should still exist (not cascaded)
        $this->assertNotNull(User::find($user->id));
        $this->assertNotNull(User::find($otherUser->id));
    }

    /**
     * Test data consistency during complex multi-table operations.
     * Property: Complex multi-table operations should maintain consistency
     */
    public function test_maintains_data_consistency_during_complex_operations(): void
    {
        $admin = User::factory()->create();
        $room = Room::factory()->create(['administrator_id' => $admin->id]);
        
        // Add multiple participants
        $participants = User::factory()->count(3)->create();
        foreach ($participants as $participant) {
            RoomParticipant::create([
                'room_id' => $room->id,
                'user_id' => $participant->id,
                'joined_at' => now(),
            ]);
        }
        
        // Each participant uploads a track
        $tracks = [];
        foreach ($participants as $participant) {
            $tracks[] = Track::factory()->create([
                'room_id' => $room->id,
                'uploader_id' => $participant->id,
            ]);
        }
        
        // All participants vote for all tracks (except their own)
        foreach ($participants as $voter) {
            foreach ($tracks as $track) {
                if ($track->uploader_id !== $voter->id) {
                    TrackVote::create([
                        'track_id' => $track->id,
                        'user_id' => $voter->id,
                        'created_at' => now(),
                    ]);
                }
            }
        }
        
        // Verify data consistency
        $this->assertEquals(3, $room->participants()->count());
        $this->assertEquals(3, $room->tracks()->count());
        
        // Each track should have 2 votes (from the other 2 participants)
        foreach ($tracks as $track) {
            $this->assertEquals(2, $track->votes()->count());
        }
        
        // Verify relationships are intact
        foreach ($participants as $participant) {
            $this->assertEquals(1, $participant->roomParticipations()->count());
            $this->assertEquals(1, $participant->uploadedTracks()->count());
            $this->assertEquals(2, $participant->trackVotes()->count());
        }
    }
}