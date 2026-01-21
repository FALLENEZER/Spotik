<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\Room;
use App\Models\RoomParticipant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tymon\JWTAuth\Facades\JWTAuth;
use Illuminate\Support\Facades\Gate;

/**
 * Property-Based Test for Room Creation and Administration
 * 
 * **Feature: spotik, Property 4: Room Creation and Administration**
 * **Validates: Requirements 2.1, 6.4**
 * 
 * This test validates that for any authenticated user creating a room, the system should:
 * - Create a new room with that user as Room_Administrator
 * - Provide them with exclusive rights to manage playback
 */
class RoomCreationAdministrationPropertyTest extends TestCase
{
    use RefreshDatabase;

    /** @test */
    public function it_creates_room_with_user_as_administrator_for_any_authenticated_user()
    {
        // **Property 4: Room Creation and Administration**
        // **Validates: Requirements 2.1, 6.4**
        // Property: For any authenticated user creating a room, the system should establish 
        // a new room with that user as Room_Administrator and grant exclusive playback control privileges

        // Run property test with multiple iterations
        for ($iteration = 0; $iteration < 100; $iteration++) {
            // Generate random authenticated user data
            $user = User::factory()->create([
                'username' => fake()->unique()->userName(),
                'email' => fake()->unique()->safeEmail(),
            ]);

            // Generate JWT token for authentication
            $token = JWTAuth::fromUser($user);

            // Generate random valid room data
            $roomData = [
                'name' => $this->generateValidRoomName(),
            ];

            // Test room creation
            $response = $this->withHeaders([
                'Authorization' => 'Bearer ' . $token,
            ])->postJson('/api/rooms', $roomData);

            // Verify room creation was successful
            $response->assertStatus(201)
                    ->assertJsonStructure([
                        'success',
                        'message',
                        'data' => [
                            'id',
                            'name',
                            'administrator' => ['id', 'username', 'email'],
                            'participants',
                            'is_playing',
                            'playback_started_at',
                            'playback_paused_at',
                            'current_playback_position',
                            'created_at',
                            'updated_at'
                        ]
                    ])
                    ->assertJson([
                        'success' => true,
                        'message' => 'Room created successfully',
                        'data' => [
                            'name' => $roomData['name'],
                            'administrator' => [
                                'id' => $user->id,
                                'username' => $user->username,
                                'email' => $user->email,
                            ],
                            'is_playing' => false,
                        ]
                    ]);

            // Extract room ID from response
            $roomId = $response->json('data.id');
            $this->assertNotNull($roomId);

            // **Requirement 2.1 Validation**: Verify room was created with user as administrator
            $this->assertDatabaseHas('rooms', [
                'id' => $roomId,
                'name' => $roomData['name'],
                'administrator_id' => $user->id,
                'is_playing' => false,
            ]);

            // Verify creator was automatically added as participant
            $this->assertDatabaseHas('room_participants', [
                'room_id' => $roomId,
                'user_id' => $user->id,
            ]);

            // Load the created room for further testing
            $room = Room::find($roomId);
            $this->assertNotNull($room);

            // Verify room administrator relationship
            $this->assertTrue($room->isAdministratedBy($user));
            $this->assertEquals($user->id, $room->administrator_id);
            $this->assertEquals($user->id, $room->administrator->id);

            // Verify creator is also a participant
            $this->assertTrue($room->hasParticipant($user));

            // **Requirement 6.4 Validation**: Verify administrator has exclusive playback control privileges
            $this->assertTrue(Gate::forUser($user)->allows('controlPlayback', $room));
            $this->assertTrue(Gate::forUser($user)->allows('update', $room));
            $this->assertTrue(Gate::forUser($user)->allows('delete', $room));
            $this->assertTrue(Gate::forUser($user)->allows('manageTracks', $room));

            // Create another user to verify non-administrators don't have playback control
            $otherUser = User::factory()->create([
                'username' => fake()->unique()->userName(),
                'email' => fake()->unique()->safeEmail(),
            ]);

            // Verify other users don't have playback control privileges
            $this->assertFalse(Gate::forUser($otherUser)->allows('controlPlayback', $room));
            $this->assertFalse(Gate::forUser($otherUser)->allows('update', $room));
            $this->assertFalse(Gate::forUser($otherUser)->allows('delete', $room));
            $this->assertFalse(Gate::forUser($otherUser)->allows('manageTracks', $room));

            // Test that other users can join but cannot control playback
            $otherToken = JWTAuth::fromUser($otherUser);
            
            $joinResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $otherToken,
            ])->postJson("/api/rooms/{$roomId}/join");

            $joinResponse->assertStatus(200)
                        ->assertJson([
                            'success' => true,
                            'message' => 'Successfully joined the room'
                        ]);

            // Verify other user is now a participant but still not administrator
            $this->assertTrue($room->hasParticipant($otherUser));
            $this->assertFalse($room->isAdministratedBy($otherUser));
            $this->assertFalse(Gate::forUser($otherUser)->allows('controlPlayback', $room));

            // Test administrator can update room while others cannot
            $updateData = ['name' => 'Updated ' . $roomData['name']];
            
            $updateResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $token,
            ])->putJson("/api/rooms/{$roomId}", $updateData);

            $updateResponse->assertStatus(200)
                          ->assertJson([
                              'success' => true,
                              'message' => 'Room updated successfully',
                              'data' => [
                                  'name' => $updateData['name'],
                                  'administrator' => [
                                      'id' => $user->id,
                                  ]
                              ]
                          ]);

            // Verify non-administrator cannot update room
            $unauthorizedUpdateResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $otherToken,
            ])->putJson("/api/rooms/{$roomId}", ['name' => 'Unauthorized Update']);

            $unauthorizedUpdateResponse->assertStatus(403)
                                      ->assertJson([
                                          'success' => false,
                                          'message' => 'Unauthorized. Only room administrator can update room settings.'
                                      ]);

            // Test administrator can delete room while others cannot
            $deleteAttemptResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $otherToken,
            ])->deleteJson("/api/rooms/{$roomId}");

            $deleteAttemptResponse->assertStatus(403)
                                 ->assertJson([
                                     'success' => false,
                                     'message' => 'Unauthorized. Only room administrator can delete the room.'
                                 ]);

            // Verify room still exists after unauthorized delete attempt
            $this->assertDatabaseHas('rooms', ['id' => $roomId]);

            // Test administrator can successfully delete room
            $deleteResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $token,
            ])->deleteJson("/api/rooms/{$roomId}");

            $deleteResponse->assertStatus(200)
                          ->assertJson([
                              'success' => true,
                              'message' => 'Room deleted successfully'
                          ]);

            // Verify room was deleted
            $this->assertDatabaseMissing('rooms', ['id' => $roomId]);
            $this->assertDatabaseMissing('room_participants', ['room_id' => $roomId]);
        }
    }

    /** @test */
    public function it_maintains_administrator_privileges_consistency_across_room_operations()
    {
        // Property: Administrator privileges should remain consistent across all room operations
        
        for ($iteration = 0; $iteration < 10; $iteration++) {
            // Create authenticated user
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

            // Test administrator privileges are consistent across different operations
            $privilegeTests = [
                'controlPlayback' => true,
                'update' => true,
                'delete' => true,
                'manageTracks' => true,
                'uploadTracks' => true,
                'vote' => true,
            ];

            foreach ($privilegeTests as $privilege => $expectedResult) {
                $this->assertEquals(
                    $expectedResult,
                    Gate::forUser($admin)->allows($privilege, $room),
                    "Administrator should have {$privilege} privilege"
                );
            }

            // Create multiple other users and verify they don't have admin privileges
            for ($userIndex = 0; $userIndex < 3; $userIndex++) {
                $regularUser = User::factory()->create([
                    'username' => fake()->unique()->userName(),
                    'email' => fake()->unique()->safeEmail(),
                ]);

                // Test before joining room
                $this->assertFalse(Gate::forUser($regularUser)->allows('controlPlayback', $room));
                $this->assertFalse(Gate::forUser($regularUser)->allows('update', $room));
                $this->assertFalse(Gate::forUser($regularUser)->allows('delete', $room));
                $this->assertFalse(Gate::forUser($regularUser)->allows('manageTracks', $room));

                // Join room
                $room->addParticipant($regularUser);

                // Test after joining room - should still not have admin privileges
                $this->assertFalse(Gate::forUser($regularUser)->allows('controlPlayback', $room));
                $this->assertFalse(Gate::forUser($regularUser)->allows('update', $room));
                $this->assertFalse(Gate::forUser($regularUser)->allows('delete', $room));
                $this->assertFalse(Gate::forUser($regularUser)->allows('manageTracks', $room));

                // But should have participant privileges
                $this->assertTrue(Gate::forUser($regularUser)->allows('uploadTracks', $room));
                $this->assertTrue(Gate::forUser($regularUser)->allows('vote', $room));
            }

            // Verify administrator still has all privileges after other users joined
            foreach ($privilegeTests as $privilege => $expectedResult) {
                $this->assertEquals(
                    $expectedResult,
                    Gate::forUser($admin)->allows($privilege, $room),
                    "Administrator should maintain {$privilege} privilege after other users join"
                );
            }

            // Clean up
            $room->delete();
        }
    }

    /** @test */
    public function it_handles_various_valid_room_names_consistently()
    {
        // Property: The system should handle various valid room name formats consistently
        
        $validRoomNames = [
            'Simple Room',
            'Room123',
            'My Awesome Music Room',
            'R',
            str_repeat('A', 100), // Maximum length
            'Room with Numbers 123456',
            'Special-Characters_Room!',
            'Комната', // Unicode characters
            'Room with    spaces',
            'UPPERCASE ROOM',
            'lowercase room',
            'MiXeD cAsE rOoM',
            'Room with émojis 🎵🎶',
            'Room-with-dashes',
            'Room_with_underscores',
            'Room.with.dots',
            'Room (with parentheses)',
            'Room [with brackets]',
            'Room {with braces}',
        ];

        foreach ($validRoomNames as $roomName) {
            // Create user for this test
            $user = User::factory()->create([
                'username' => fake()->unique()->userName(),
                'email' => fake()->unique()->safeEmail(),
            ]);
            $token = JWTAuth::fromUser($user);

            // Test room creation with this name
            $response = $this->withHeaders([
                'Authorization' => 'Bearer ' . $token,
            ])->postJson('/api/rooms', ['name' => $roomName]);

            $response->assertStatus(201)
                    ->assertJson([
                        'success' => true,
                        'data' => [
                            'name' => $roomName,
                            'administrator' => [
                                'id' => $user->id,
                            ]
                        ]
                    ]);

            $roomId = $response->json('data.id');
            $room = Room::find($roomId);

            // Verify administrator privileges work with any room name
            $this->assertTrue($room->isAdministratedBy($user));
            $this->assertTrue(Gate::forUser($user)->allows('controlPlayback', $room));
            $this->assertTrue(Gate::forUser($user)->allows('update', $room));
            $this->assertTrue(Gate::forUser($user)->allows('delete', $room));

            // Verify database consistency
            $this->assertDatabaseHas('rooms', [
                'id' => $roomId,
                'name' => $roomName,
                'administrator_id' => $user->id,
            ]);

            // Clean up
            $room->delete();
        }
    }

    /** @test */
    public function it_preserves_administrator_identity_throughout_room_lifecycle()
    {
        // Property: Room administrator identity should remain consistent throughout the room's lifecycle
        
        for ($iteration = 0; $iteration < 5; $iteration++) {
            // Create administrator
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
            $originalAdminId = $createResponse->json('data.administrator.id');

            // Verify initial administrator
            $this->assertEquals($admin->id, $originalAdminId);

            // Perform various room operations and verify administrator remains the same
            $room = Room::find($roomId);

            // Test 1: Add multiple participants
            $participants = [];
            for ($i = 0; $i < 5; $i++) {
                $participant = User::factory()->create([
                    'username' => fake()->unique()->userName(),
                    'email' => fake()->unique()->safeEmail(),
                ]);
                $participants[] = $participant;
                
                $participantToken = JWTAuth::fromUser($participant);
                $joinResponse = $this->withHeaders([
                    'Authorization' => 'Bearer ' . $participantToken,
                ])->postJson("/api/rooms/{$roomId}/join");

                $joinResponse->assertStatus(200);

                // Verify administrator hasn't changed
                $room->refresh();
                $this->assertEquals($admin->id, $room->administrator_id);
                $this->assertTrue($room->isAdministratedBy($admin));
                $this->assertFalse($room->isAdministratedBy($participant));
            }

            // Test 2: Update room multiple times
            for ($updateIndex = 0; $updateIndex < 3; $updateIndex++) {
                $updateData = ['name' => 'Updated Room ' . $updateIndex];
                $updateResponse = $this->withHeaders([
                    'Authorization' => 'Bearer ' . $adminToken,
                ])->putJson("/api/rooms/{$roomId}", $updateData);

                $updateResponse->assertStatus(200);
                
                // Verify administrator hasn't changed
                $this->assertEquals($admin->id, $updateResponse->json('data.administrator.id'));
                $room->refresh();
                $this->assertEquals($admin->id, $room->administrator_id);
            }

            // Test 3: Participants leave and rejoin
            foreach ($participants as $participant) {
                $participantToken = JWTAuth::fromUser($participant);
                
                // Leave room
                $leaveResponse = $this->withHeaders([
                    'Authorization' => 'Bearer ' . $participantToken,
                ])->postJson("/api/rooms/{$roomId}/leave");

                $leaveResponse->assertStatus(200);

                // Verify administrator hasn't changed
                $room->refresh();
                $this->assertEquals($admin->id, $room->administrator_id);

                // Rejoin room
                $rejoinResponse = $this->withHeaders([
                    'Authorization' => 'Bearer ' . $participantToken,
                ])->postJson("/api/rooms/{$roomId}/join");

                $rejoinResponse->assertStatus(200);

                // Verify administrator still hasn't changed
                $room->refresh();
                $this->assertEquals($admin->id, $room->administrator_id);
            }

            // Test 4: Get room details multiple times
            for ($getIndex = 0; $getIndex < 3; $getIndex++) {
                $getResponse = $this->withHeaders([
                    'Authorization' => 'Bearer ' . $adminToken,
                ])->getJson("/api/rooms/{$roomId}");

                $getResponse->assertStatus(200)
                           ->assertJson([
                               'data' => [
                                   'administrator' => [
                                       'id' => $admin->id,
                                       'username' => $admin->username,
                                       'email' => $admin->email,
                                   ]
                               ]
                           ]);
            }

            // Final verification: Administrator identity is preserved
            $room->refresh();
            $this->assertEquals($admin->id, $room->administrator_id);
            $this->assertTrue($room->isAdministratedBy($admin));
            $this->assertTrue(Gate::forUser($admin)->allows('controlPlayback', $room));

            // Verify no other user has administrator privileges
            foreach ($participants as $participant) {
                $this->assertFalse($room->isAdministratedBy($participant));
                $this->assertFalse(Gate::forUser($participant)->allows('controlPlayback', $room));
            }

            // Clean up
            $room->delete();
        }
    }

    /** @test */
    public function it_enforces_exclusive_playback_control_for_administrators_only()
    {
        // Property: Only room administrators should have playback control privileges
        
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

            // Create multiple regular users
            $regularUsers = [];
            for ($i = 0; $i < 4; $i++) {
                $user = User::factory()->create([
                    'username' => fake()->unique()->userName(),
                    'email' => fake()->unique()->safeEmail(),
                ]);
                $regularUsers[] = $user;
                
                // Add as participant
                $userToken = JWTAuth::fromUser($user);
                $this->withHeaders([
                    'Authorization' => 'Bearer ' . $userToken,
                ])->postJson("/api/rooms/{$roomId}/join")->assertStatus(200);
            }

            // Test playback control privileges
            $playbackPrivileges = [
                'controlPlayback',
                'update',
                'delete',
                'manageTracks',
            ];

            // Verify administrator has all playback control privileges
            foreach ($playbackPrivileges as $privilege) {
                $this->assertTrue(
                    Gate::forUser($admin)->allows($privilege, $room),
                    "Administrator should have {$privilege} privilege"
                );
            }

            // Verify regular users don't have playback control privileges
            foreach ($regularUsers as $user) {
                foreach ($playbackPrivileges as $privilege) {
                    $this->assertFalse(
                        Gate::forUser($user)->allows($privilege, $room),
                        "Regular user should NOT have {$privilege} privilege"
                    );
                }

                // But should have participant privileges
                $this->assertTrue(Gate::forUser($user)->allows('uploadTracks', $room));
                $this->assertTrue(Gate::forUser($user)->allows('vote', $room));
            }

            // Test that even after room updates, privileges remain exclusive
            $this->withHeaders([
                'Authorization' => 'Bearer ' . $adminToken,
            ])->putJson("/api/rooms/{$roomId}", ['name' => 'Updated Room'])->assertStatus(200);

            // Re-verify privileges after update
            foreach ($playbackPrivileges as $privilege) {
                $this->assertTrue(
                    Gate::forUser($admin)->allows($privilege, $room),
                    "Administrator should maintain {$privilege} privilege after room update"
                );
            }

            foreach ($regularUsers as $user) {
                foreach ($playbackPrivileges as $privilege) {
                    $this->assertFalse(
                        Gate::forUser($user)->allows($privilege, $room),
                        "Regular user should still NOT have {$privilege} privilege after room update"
                    );
                }
            }

            // Test unauthorized attempts to perform admin actions
            foreach ($regularUsers as $user) {
                $userToken = JWTAuth::fromUser($user);

                // Attempt to update room (should fail)
                $updateResponse = $this->withHeaders([
                    'Authorization' => 'Bearer ' . $userToken,
                ])->putJson("/api/rooms/{$roomId}", ['name' => 'Unauthorized Update']);

                $updateResponse->assertStatus(403)
                              ->assertJson([
                                  'success' => false,
                                  'message' => 'Unauthorized. Only room administrator can update room settings.'
                              ]);

                // Attempt to delete room (should fail)
                $deleteResponse = $this->withHeaders([
                    'Authorization' => 'Bearer ' . $userToken,
                ])->deleteJson("/api/rooms/{$roomId}");

                $deleteResponse->assertStatus(403)
                              ->assertJson([
                                  'success' => false,
                                  'message' => 'Unauthorized. Only room administrator can delete the room.'
                              ]);
            }

            // Verify room still exists and administrator privileges are intact
            $this->assertDatabaseHas('rooms', ['id' => $roomId]);
            $room->refresh();
            $this->assertTrue($room->isAdministratedBy($admin));

            // Clean up
            $room->delete();
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