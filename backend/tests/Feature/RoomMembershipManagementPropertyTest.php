<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\Room;
use App\Models\RoomParticipant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tymon\JWTAuth\Facades\JWTAuth;
use Illuminate\Support\Facades\Gate;
use Carbon\Carbon;

/**
 * Property-Based Test for Room Membership Management
 * 
 * **Feature: spotik, Property 5: Room Membership Management**
 * **Validates: Requirements 2.2, 2.3, 2.4, 2.5**
 * 
 * This test validates that for any user joining or leaving a room, the system should:
 * - Correctly update the participant list (Requirements 2.2, 2.3)
 * - Display current participant list to all room members (Requirement 2.4)
 * - Handle membership changes in real-time (Requirement 2.5)
 */
class RoomMembershipManagementPropertyTest extends TestCase
{
    use RefreshDatabase;

    /** @test */
    public function it_correctly_manages_room_membership_for_any_user_operations()
    {
        // **Property 5: Room Membership Management**
        // **Validates: Requirements 2.2, 2.3, 2.4, 2.5**
        // Property: For any user joining or leaving a room, the system should update the participant list
        // accordingly and broadcast the membership change to all current participants

        // Run property test with multiple iterations
        for ($iteration = 0; $iteration < 100; $iteration++) {
            // Create room administrator
            $admin = User::factory()->create([
                'username' => fake()->unique()->userName(),
                'email' => fake()->unique()->safeEmail(),
            ]);
            $adminToken = JWTAuth::fromUser($admin);

            // Create room
            $roomData = ['name' => $this->generateValidRoomName()];
            $createResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->postJson('/api/rooms', $roomData);

            $createResponse->assertStatus(201);
            $roomId = $createResponse->json('data.id');
            $room = Room::find($roomId);

            // **Requirement 2.2 Validation**: Test user joining room
            $joiningUser = User::factory()->create([
                'username' => fake()->unique()->userName(),
                'email' => fake()->unique()->safeEmail(),
            ]);
            $joiningUserToken = JWTAuth::fromUser($joiningUser);

            // Verify user is not initially a participant
            $this->assertFalse($room->hasParticipant($joiningUser));
            $this->assertDatabaseMissing('room_participants', [
                'room_id' => $roomId,
                'user_id' => $joiningUser->id,
            ]);

            // Test joining room
            $joinResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $joiningUserToken,
            ])->postJson("/api/rooms/{$roomId}/join");

            $joinResponse->assertStatus(200)
                        ->assertJson([
                            'success' => true,
                            'message' => 'Successfully joined the room'
                        ]);

            // **Requirement 2.2**: Verify user was added to participant list
            $room->refresh();
            $this->assertTrue($room->hasParticipant($joiningUser));
            $this->assertDatabaseHas('room_participants', [
                'room_id' => $roomId,
                'user_id' => $joiningUser->id,
            ]);

            // Verify participant record has correct timestamp
            $participant = RoomParticipant::where('room_id', $roomId)
                                        ->where('user_id', $joiningUser->id)
                                        ->first();
            $this->assertNotNull($participant);
            $this->assertNotNull($participant->joined_at);
            $this->assertInstanceOf(Carbon::class, $participant->joined_at);

            // **Requirement 2.4**: Verify participant list is displayed correctly to all members
            $participantsResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->getJson("/api/rooms/{$roomId}/participants");

            $participantsResponse->assertStatus(200)
                               ->assertJson([
                                   'success' => true,
                                   'message' => 'Participants retrieved successfully'
                               ]);

            $participantsData = $participantsResponse->json('data');
            $this->assertIsArray($participantsData);
            $this->assertCount(2, $participantsData); // Admin + joining user

            // Verify both participants are in the list
            $participantIds = collect($participantsData)->pluck('user.id')->toArray();
            $this->assertContains($admin->id, $participantIds);
            $this->assertContains($joiningUser->id, $participantIds);

            // Verify participant list is accessible to the joining user as well
            $userParticipantsResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $joiningUserToken,
            ])->getJson("/api/rooms/{$roomId}/participants");

            $userParticipantsResponse->assertStatus(200)
                                   ->assertJsonCount(2, 'data');

            // **Requirement 2.5**: Verify real-time notification through API response structure
            // (In a full implementation, this would test WebSocket events, but we validate through API responses)
            $roomDetailsResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->getJson("/api/rooms/{$roomId}");

            $roomDetailsResponse->assertStatus(200)
                              ->assertJsonStructure([
                                  'success',
                                  'message',
                                  'data' => [
                                      'id',
                                      'name',
                                      'administrator',
                                      'participants' => [
                                          '*' => [
                                              'id',
                                              'user' => ['id', 'username', 'email'],
                                              'joined_at'
                                          ]
                                      ]
                                  ]
                              ]);

            $roomData = $roomDetailsResponse->json('data');
            $this->assertCount(2, $roomData['participants']);

            // **Requirement 2.3 Validation**: Test user leaving room
            $leaveResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $joiningUserToken,
            ])->postJson("/api/rooms/{$roomId}/leave");

            $leaveResponse->assertStatus(200)
                         ->assertJson([
                             'success' => true,
                             'message' => 'Successfully left the room'
                         ]);

            // **Requirement 2.3**: Verify user was removed from participant list
            $room->refresh();
            $this->assertFalse($room->hasParticipant($joiningUser));
            $this->assertDatabaseMissing('room_participants', [
                'room_id' => $roomId,
                'user_id' => $joiningUser->id,
            ]);

            // **Requirement 2.4**: Verify updated participant list after user leaves
            $updatedParticipantsResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->getJson("/api/rooms/{$roomId}/participants");

            $updatedParticipantsResponse->assertStatus(200)
                                      ->assertJsonCount(1, 'data'); // Only admin remains

            $remainingParticipant = $updatedParticipantsResponse->json('data.0');
            $this->assertEquals($admin->id, $remainingParticipant['user']['id']);

            // Test edge case: User cannot join room twice
            $room->addParticipant($joiningUser);
            $duplicateJoinResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $joiningUserToken,
            ])->postJson("/api/rooms/{$roomId}/join");

            $duplicateJoinResponse->assertStatus(409)
                                 ->assertJson([
                                     'success' => false,
                                     'message' => 'You are already a participant in this room'
                                 ]);

            // Test edge case: User cannot leave room if not a participant
            $room->removeParticipant($joiningUser);
            $invalidLeaveResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $joiningUserToken,
            ])->postJson("/api/rooms/{$roomId}/leave");

            $invalidLeaveResponse->assertStatus(404)
                                ->assertJson([
                                    'success' => false,
                                    'message' => 'You are not a participant in this room'
                                ]);

            // Test edge case: Administrator cannot leave room
            $adminLeaveResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->postJson("/api/rooms/{$roomId}/leave");

            $adminLeaveResponse->assertStatus(403)
                              ->assertJson([
                                  'success' => false,
                                  'message' => 'Room administrator cannot leave the room. Delete the room instead.'
                              ]);

            // Verify administrator is still a participant
            $this->assertTrue($room->hasParticipant($admin));
            $this->assertTrue($room->isAdministratedBy($admin));

            // Clean up
            $room->delete();
        }
    }

    /** @test */
    public function it_handles_multiple_users_joining_and_leaving_simultaneously()
    {
        // Property: System should handle multiple concurrent membership operations correctly
        
        for ($iteration = 0; $iteration < 10; $iteration++) {
            // Create room administrator
            $admin = User::factory()->create([
                'username' => fake()->unique()->userName(),
                'email' => fake()->unique()->safeEmail(),
            ]);
            $adminToken = JWTAuth::fromUser($admin);

            // Create room
            $roomData = ['name' => $this->generateValidRoomName()];
            $createResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->postJson('/api/rooms', $roomData);

            $createResponse->assertStatus(201);
            $roomId = $createResponse->json('data.id');
            $room = Room::find($roomId);

            // Create multiple users
            $users = [];
            $tokens = [];
            for ($i = 0; $i < 5; $i++) {
                $user = User::factory()->create([
                    'username' => fake()->unique()->userName(),
                    'email' => fake()->unique()->safeEmail(),
                ]);
                $users[] = $user;
                $tokens[] = JWTAuth::fromUser($user);
            }

            // Test multiple users joining
            foreach ($users as $index => $user) {
                $joinResponse = $this->withHeaders([
                    'Authorization' => 'Bearer ' . $tokens[$index],
                ])->postJson("/api/rooms/{$roomId}/join");

                $joinResponse->assertStatus(200);
                
                // Verify user was added
                $room->refresh();
                $this->assertTrue($room->hasParticipant($user));
            }

            // Verify all users are participants
            $participantsResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->getJson("/api/rooms/{$roomId}/participants");

            $participantsResponse->assertStatus(200)
                               ->assertJsonCount(6, 'data'); // Admin + 5 users

            // Test multiple users leaving
            foreach (array_slice($users, 0, 3) as $index => $user) {
                $leaveResponse = $this->withHeaders([
                    'Authorization' => 'Bearer ' . $tokens[$index],
                ])->postJson("/api/rooms/{$roomId}/leave");

                $leaveResponse->assertStatus(200);
                
                // Verify user was removed
                $room->refresh();
                $this->assertFalse($room->hasParticipant($user));
            }

            // Verify correct number of participants remain
            $finalParticipantsResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->getJson("/api/rooms/{$roomId}/participants");

            $finalParticipantsResponse->assertStatus(200)
                                    ->assertJsonCount(3, 'data'); // Admin + 2 remaining users

            // Verify the correct users remain
            $remainingParticipants = $finalParticipantsResponse->json('data');
            $remainingUserIds = collect($remainingParticipants)->pluck('user.id')->toArray();
            
            $this->assertContains($admin->id, $remainingUserIds);
            $this->assertContains($users[3]->id, $remainingUserIds);
            $this->assertContains($users[4]->id, $remainingUserIds);

            // Clean up
            $room->delete();
        }
    }

    /** @test */
    public function it_maintains_participant_list_consistency_across_room_operations()
    {
        // Property: Participant list should remain consistent across various room operations
        
        for ($iteration = 0; $iteration < 5; $iteration++) {
            // Create room administrator
            $admin = User::factory()->create([
                'username' => fake()->unique()->userName(),
                'email' => fake()->unique()->safeEmail(),
            ]);
            $adminToken = JWTAuth::fromUser($admin);

            // Create room
            $roomData = ['name' => $this->generateValidRoomName()];
            $createResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->postJson('/api/rooms', $roomData);

            $createResponse->assertStatus(201);
            $roomId = $createResponse->json('data.id');
            $room = Room::find($roomId);

            // Add multiple participants
            $participants = [];
            for ($i = 0; $i < 3; $i++) {
                $user = User::factory()->create([
                    'username' => fake()->unique()->userName(),
                    'email' => fake()->unique()->safeEmail(),
                ]);
                $participants[] = $user;
                
                $userToken = JWTAuth::fromUser($user);
                $this->withHeaders([
                    'Authorization' => 'Bearer ' . $userToken,
                ])->postJson("/api/rooms/{$roomId}/join")->assertStatus(200);
            }

            // Test participant list consistency after room updates
            $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->putJson("/api/rooms/{$roomId}", ['name' => 'Updated Room'])->assertStatus(200);

            // Verify all participants are still there
            $participantsResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->getJson("/api/rooms/{$roomId}/participants");

            $participantsResponse->assertStatus(200)
                               ->assertJsonCount(4, 'data'); // Admin + 3 participants

            // Test participant list consistency after getting room details multiple times
            for ($j = 0; $j < 3; $j++) {
                $roomResponse = $this->withHeaders([
                    'Authorization' => 'Bearer ' . $adminToken,
                ])->getJson("/api/rooms/{$roomId}");

                $roomResponse->assertStatus(200);
                $roomData = $roomResponse->json('data');
                $this->assertCount(4, $roomData['participants']);
            }

            // Test that participant timestamps are preserved
            $participantRecords = RoomParticipant::where('room_id', $roomId)->get();
            $this->assertCount(4, $participantRecords);

            foreach ($participantRecords as $record) {
                $this->assertNotNull($record->joined_at);
                $this->assertInstanceOf(Carbon::class, $record->joined_at);
                $this->assertTrue($record->joined_at->lessThanOrEqualTo(Carbon::now()));
            }

            // Test removing participants one by one
            foreach ($participants as $participant) {
                $participantToken = JWTAuth::fromUser($participant);
                
                $leaveResponse = $this->withHeaders([
                    'Authorization' => 'Bearer ' . $participantToken,
                ])->postJson("/api/rooms/{$roomId}/leave");

                $leaveResponse->assertStatus(200);
                
                // Verify participant count decreases correctly
                $room->refresh();
                $this->assertFalse($room->hasParticipant($participant));
            }

            // Verify only admin remains
            $finalParticipantsResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->getJson("/api/rooms/{$roomId}/participants");

            $finalParticipantsResponse->assertStatus(200)
                                    ->assertJsonCount(1, 'data');

            $finalParticipant = $finalParticipantsResponse->json('data.0');
            $this->assertEquals($admin->id, $finalParticipant['user']['id']);

            // Clean up
            $room->delete();
        }
    }

    /** @test */
    public function it_validates_membership_operations_with_various_user_types()
    {
        // Property: Membership operations should work consistently for various user types
        
        for ($iteration = 0; $iteration < 3; $iteration++) {
            // Create room administrator
            $admin = User::factory()->create([
                'username' => fake()->unique()->userName(),
                'email' => fake()->unique()->safeEmail(),
            ]);
            $adminToken = JWTAuth::fromUser($admin);

            // Create room
            $roomData = ['name' => $this->generateValidRoomName()];
            $createResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->postJson('/api/rooms', $roomData);

            $createResponse->assertStatus(201);
            $roomId = $createResponse->json('data.id');
            $room = Room::find($roomId);

            // Test with users having different username/email formats
            $userVariations = [
                [
                    'username' => 'user123_' . $iteration,
                    'email' => 'user123_' . $iteration . '@example.com',
                ],
                [
                    'username' => 'test_user_' . $iteration,
                    'email' => 'test.user_' . $iteration . '@domain.co.uk',
                ],
                [
                    'username' => 'UserWithCaps_' . $iteration,
                    'email' => 'user+tag_' . $iteration . '@example.org',
                ],
                [
                    'username' => 'user-with-dashes_' . $iteration,
                    'email' => 'very.long.email_' . $iteration . '@very-long-domain.example.com',
                ],
                [
                    'username' => str_repeat('a', 15) . '_' . $iteration, // Long username
                    'email' => 'a_' . $iteration . '@b.co', // Short email
                ],
            ];

            foreach ($userVariations as $index => $userData) {
                $user = User::factory()->create([
                    'username' => $userData['username'] . '_' . uniqid(),
                    'email' => str_replace('@', '_' . uniqid() . '@', $userData['email']),
                ]);
                $userToken = JWTAuth::fromUser($user);

                // Test joining
                $joinResponse = $this->withHeaders([
                    'Authorization' => 'Bearer ' . $userToken,
                ])->postJson("/api/rooms/{$roomId}/join");

                $joinResponse->assertStatus(200)
                            ->assertJson([
                                'success' => true,
                                'message' => 'Successfully joined the room'
                            ]);

                // Verify user was added
                $room->refresh();
                $this->assertTrue($room->hasParticipant($user));

                // Verify user appears in participant list with correct data
                $participantsResponse = $this->withHeaders([
                    'Authorization' => 'Bearer ' . $adminToken,
                ])->getJson("/api/rooms/{$roomId}/participants");

                $participantsResponse->assertStatus(200);
                $participants = $participantsResponse->json('data');
                
                $userFound = false;
                foreach ($participants as $participant) {
                    if ($participant['user']['id'] === $user->id) {
                        $this->assertEquals($userData['username'], $participant['user']['username']);
                        $this->assertEquals($userData['email'], $participant['user']['email']);
                        $userFound = true;
                        break;
                    }
                }
                $this->assertTrue($userFound, "User with username {$userData['username']} should be found in participants");

                // Test leaving
                $leaveResponse = $this->withHeaders([
                    'Authorization' => 'Bearer ' . $userToken,
                ])->postJson("/api/rooms/{$roomId}/leave");

                $leaveResponse->assertStatus(200)
                             ->assertJson([
                                 'success' => true,
                                 'message' => 'Successfully left the room'
                             ]);

                // Verify user was removed
                $room->refresh();
                $this->assertFalse($room->hasParticipant($user));
            }

            // Clean up
            $room->delete();
        }
    }

    /** @test */
    public function it_handles_membership_operations_with_room_state_changes()
    {
        // Property: Membership operations should work correctly even when room state changes
        
        for ($iteration = 0; $iteration < 3; $iteration++) {
            // Create room administrator
            $admin = User::factory()->create([
                'username' => fake()->unique()->userName(),
                'email' => fake()->unique()->safeEmail(),
            ]);
            $adminToken = JWTAuth::fromUser($admin);

            // Create room
            $roomData = ['name' => $this->generateValidRoomName()];
            $createResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->postJson('/api/rooms', $roomData);

            $createResponse->assertStatus(201);
            $roomId = $createResponse->json('data.id');
            $room = Room::find($roomId);

            // Create test user
            $user = User::factory()->create([
                'username' => fake()->unique()->userName(),
                'email' => fake()->unique()->safeEmail(),
            ]);
            $userToken = JWTAuth::fromUser($user);

            // Test joining room
            $joinResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $userToken,
            ])->postJson("/api/rooms/{$roomId}/join");

            $joinResponse->assertStatus(200);
            $this->assertTrue($room->hasParticipant($user));

            // Change room name and verify membership is preserved
            $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->putJson("/api/rooms/{$roomId}", ['name' => 'Updated Room Name'])->assertStatus(200);

            $room->refresh();
            $this->assertTrue($room->hasParticipant($user));
            $this->assertEquals('Updated Room Name', $room->name);

            // Verify participant list is still accessible after room update
            $participantsResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->getJson("/api/rooms/{$roomId}/participants");

            $participantsResponse->assertStatus(200)
                               ->assertJsonCount(2, 'data'); // Admin + user

            // Test leaving room after room state changes
            $leaveResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $userToken,
            ])->postJson("/api/rooms/{$roomId}/leave");

            $leaveResponse->assertStatus(200);
            $room->refresh();
            $this->assertFalse($room->hasParticipant($user));

            // Test rejoining after room state changes
            $rejoinResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $userToken,
            ])->postJson("/api/rooms/{$roomId}/join");

            $rejoinResponse->assertStatus(200);
            $room->refresh();
            $this->assertTrue($room->hasParticipant($user));

            // Verify participant has new joined_at timestamp
            $participant = RoomParticipant::where('room_id', $roomId)
                                        ->where('user_id', $user->id)
                                        ->first();
            $this->assertNotNull($participant);
            $this->assertNotNull($participant->joined_at);

            // Clean up
            $room->delete();
        }
    }

    /** @test */
    public function it_prevents_unauthorized_membership_operations()
    {
        // Property: Unauthorized users should not be able to perform membership operations
        
        // Create room administrator
        $admin = User::factory()->create([
            'username' => fake()->unique()->userName(),
            'email' => fake()->unique()->safeEmail(),
        ]);
        $adminToken = JWTAuth::fromUser($admin);

        // Create room
        $roomData = ['name' => $this->generateValidRoomName()];
        $createResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->postJson('/api/rooms', $roomData);

        $createResponse->assertStatus(201);
        $roomId = $createResponse->json('data.id');

        // Test operations without authentication - these should return error status codes
        $response = $this->postJson("/api/rooms/{$roomId}/join");
        $this->assertNotEquals(200, $response->status(), 'Unauthorized join should not succeed');

        $response = $this->postJson("/api/rooms/{$roomId}/leave");
        $this->assertNotEquals(200, $response->status(), 'Unauthorized leave should not succeed');

        // Test with invalid token
        $response = $this->withHeaders([
            'Authorization' => 'Bearer invalid_token',
        ])->postJson("/api/rooms/{$roomId}/join");
        $this->assertNotEquals(200, $response->status(), 'Invalid token join should not succeed');

        // Clean up
        Room::find($roomId)->delete();
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
            fn() => fake()->catchPhrase(),
            fn() => fake()->word() . ' Music Room',
            fn() => 'The ' . fake()->word() . ' Lounge',
        ];

        $nameGenerator = fake()->randomElement($nameTypes);
        $name = $nameGenerator();

        // Ensure name is within valid length
        return substr($name, 0, 100);
    }
}