<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\Room;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tymon\JWTAuth\Facades\JWTAuth;

class RoomApiIntegrationTest extends TestCase
{
    use RefreshDatabase;

    /** @test */
    public function it_can_perform_complete_room_workflow()
    {
        // Create test users
        $admin = User::factory()->create([
            'username' => 'admin_user',
            'email' => 'admin@example.com',
        ]);
        
        $user = User::factory()->create([
            'username' => 'regular_user',
            'email' => 'user@example.com',
        ]);
        
        // Generate JWT tokens
        $adminToken = JWTAuth::fromUser($admin);
        $userToken = JWTAuth::fromUser($user);

        // 1. Admin creates a room
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->postJson('/api/rooms', [
            'name' => 'Integration Test Room'
        ]);

        $response->assertStatus(201)
                ->assertJsonPath('data.name', 'Integration Test Room')
                ->assertJsonPath('data.administrator.id', $admin->id);

        $roomId = $response->json('data.id');

        // 2. List all rooms
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->getJson('/api/rooms');

        $response->assertStatus(200)
                ->assertJsonCount(1, 'data');

        // 3. User joins the room
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $userToken,
        ])->postJson("/api/rooms/{$roomId}/join");

        $response->assertStatus(200)
                ->assertJsonPath('data.room.id', $roomId);

        // 4. Get room participants
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->getJson("/api/rooms/{$roomId}/participants");

        $response->assertStatus(200)
                ->assertJsonCount(2, 'data'); // Admin + User

        // 5. Admin updates room name
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->putJson("/api/rooms/{$roomId}", [
            'name' => 'Updated Room Name'
        ]);

        $response->assertStatus(200)
                ->assertJsonPath('data.name', 'Updated Room Name');

        // 6. User leaves the room
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $userToken,
        ])->postJson("/api/rooms/{$roomId}/leave");

        $response->assertStatus(200);

        // 7. Verify user is no longer a participant
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->getJson("/api/rooms/{$roomId}/participants");

        $response->assertStatus(200)
                ->assertJsonCount(1, 'data'); // Only admin

        // 8. Admin deletes the room
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->deleteJson("/api/rooms/{$roomId}");

        $response->assertStatus(200);

        // 9. Verify room is deleted
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $adminToken,
        ])->getJson('/api/rooms');

        $response->assertStatus(200)
                ->assertJsonCount(0, 'data');
    }

    /** @test */
    public function it_handles_room_not_found_errors()
    {
        $user = User::factory()->create();
        $token = JWTAuth::fromUser($user);

        $nonExistentRoomId = '550e8400-e29b-41d4-a716-446655440000';

        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->getJson("/api/rooms/{$nonExistentRoomId}");

        $response->assertStatus(404);
    }

    /** @test */
    public function it_validates_room_data_properly()
    {
        $user = User::factory()->create();
        $token = JWTAuth::fromUser($user);

        // Test empty name
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->postJson('/api/rooms', [
            'name' => ''
        ]);

        $response->assertStatus(422)
                ->assertJsonValidationErrors(['name']);

        // Test name too long
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->postJson('/api/rooms', [
            'name' => str_repeat('a', 101) // 101 characters, max is 100
        ]);

        $response->assertStatus(422)
                ->assertJsonValidationErrors(['name']);
    }
}