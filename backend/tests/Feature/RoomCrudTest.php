<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\Room;
use App\Models\RoomParticipant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;
use Tymon\JWTAuth\Facades\JWTAuth;

class RoomCrudTest extends TestCase
{
    use RefreshDatabase;

    protected $admin;
    protected $user;
    protected $adminToken;
    protected $userToken;

    protected function setUp(): void
    {
        parent::setUp();
        
        // Create test users
        $this->admin = User::factory()->create([
            'username' => 'admin_user',
            'email' => 'admin@example.com',
        ]);
        
        $this->user = User::factory()->create([
            'username' => 'regular_user',
            'email' => 'user@example.com',
        ]);
        
        // Generate JWT tokens
        $this->adminToken = JWTAuth::fromUser($this->admin);
        $this->userToken = JWTAuth::fromUser($this->user);
    }

    /** @test */
    public function it_can_list_all_rooms()
    {
        // Create some test rooms
        $room1 = Room::factory()->create(['administrator_id' => $this->admin->id]);
        $room2 = Room::factory()->create(['administrator_id' => $this->user->id]);
        
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->adminToken,
        ])->getJson('/api/rooms');
        
        $response->assertStatus(200)
                ->assertJson([
                    'success' => true,
                    'message' => 'Rooms retrieved successfully'
                ])
                ->assertJsonCount(2, 'data');
    }

    /** @test */
    public function it_can_create_a_new_room()
    {
        $roomData = [
            'name' => 'Test Room'
        ];
        
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->adminToken,
        ])->postJson('/api/rooms', $roomData);
        
        $response->assertStatus(201)
                ->assertJson([
                    'success' => true,
                    'message' => 'Room created successfully'
                ])
                ->assertJsonPath('data.name', 'Test Room')
                ->assertJsonPath('data.administrator.id', $this->admin->id);
        
        // Verify room was created in database
        $this->assertDatabaseHas('rooms', [
            'name' => 'Test Room',
            'administrator_id' => $this->admin->id
        ]);
        
        // Verify creator was added as participant
        $room = Room::where('name', 'Test Room')->first();
        $this->assertDatabaseHas('room_participants', [
            'room_id' => $room->id,
            'user_id' => $this->admin->id
        ]);
    }

    /** @test */
    public function it_validates_room_creation_data()
    {
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->adminToken,
        ])->postJson('/api/rooms', []);
        
        $response->assertStatus(422)
                ->assertJson([
                    'success' => false,
                    'message' => 'Validation failed'
                ])
                ->assertJsonValidationErrors(['name']);
    }

    /** @test */
    public function it_can_show_a_specific_room()
    {
        $room = Room::factory()->create(['administrator_id' => $this->admin->id]);
        
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->adminToken,
        ])->getJson("/api/rooms/{$room->id}");
        
        $response->assertStatus(200)
                ->assertJson([
                    'success' => true,
                    'message' => 'Room retrieved successfully'
                ])
                ->assertJsonPath('data.id', $room->id)
                ->assertJsonPath('data.name', $room->name);
    }

    /** @test */
    public function it_can_update_room_as_administrator()
    {
        $room = Room::factory()->create(['administrator_id' => $this->admin->id]);
        
        $updateData = ['name' => 'Updated Room Name'];
        
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->adminToken,
        ])->putJson("/api/rooms/{$room->id}", $updateData);
        
        $response->assertStatus(200)
                ->assertJson([
                    'success' => true,
                    'message' => 'Room updated successfully'
                ])
                ->assertJsonPath('data.name', 'Updated Room Name');
        
        // Verify database was updated
        $this->assertDatabaseHas('rooms', [
            'id' => $room->id,
            'name' => 'Updated Room Name'
        ]);
    }

    /** @test */
    public function it_cannot_update_room_as_non_administrator()
    {
        $room = Room::factory()->create(['administrator_id' => $this->admin->id]);
        
        $updateData = ['name' => 'Unauthorized Update'];
        
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->userToken,
        ])->putJson("/api/rooms/{$room->id}", $updateData);
        
        $response->assertStatus(403)
                ->assertJson([
                    'success' => false,
                    'message' => 'Unauthorized. Only room administrator can update room settings.'
                ]);
    }

    /** @test */
    public function it_can_delete_room_as_administrator()
    {
        $room = Room::factory()->create(['administrator_id' => $this->admin->id]);
        
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->adminToken,
        ])->deleteJson("/api/rooms/{$room->id}");
        
        $response->assertStatus(200)
                ->assertJson([
                    'success' => true,
                    'message' => 'Room deleted successfully'
                ]);
        
        // Verify room was deleted
        $this->assertDatabaseMissing('rooms', ['id' => $room->id]);
    }

    /** @test */
    public function it_cannot_delete_room_as_non_administrator()
    {
        $room = Room::factory()->create(['administrator_id' => $this->admin->id]);
        
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->userToken,
        ])->deleteJson("/api/rooms/{$room->id}");
        
        $response->assertStatus(403)
                ->assertJson([
                    'success' => false,
                    'message' => 'Unauthorized. Only room administrator can delete the room.'
                ]);
    }

    /** @test */
    public function it_can_join_a_room()
    {
        $room = Room::factory()->create(['administrator_id' => $this->admin->id]);
        
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->userToken,
        ])->postJson("/api/rooms/{$room->id}/join");
        
        $response->assertStatus(200)
                ->assertJson([
                    'success' => true,
                    'message' => 'Successfully joined the room'
                ]);
        
        // Verify participant was added
        $this->assertDatabaseHas('room_participants', [
            'room_id' => $room->id,
            'user_id' => $this->user->id
        ]);
    }

    /** @test */
    public function it_cannot_join_room_twice()
    {
        $room = Room::factory()->create(['administrator_id' => $this->admin->id]);
        $room->addParticipant($this->user);
        
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->userToken,
        ])->postJson("/api/rooms/{$room->id}/join");
        
        $response->assertStatus(409)
                ->assertJson([
                    'success' => false,
                    'message' => 'You are already a participant in this room'
                ]);
    }

    /** @test */
    public function it_can_leave_a_room()
    {
        $room = Room::factory()->create(['administrator_id' => $this->admin->id]);
        $room->addParticipant($this->user);
        
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->userToken,
        ])->postJson("/api/rooms/{$room->id}/leave");
        
        $response->assertStatus(200)
                ->assertJson([
                    'success' => true,
                    'message' => 'Successfully left the room'
                ]);
        
        // Verify participant was removed
        $this->assertDatabaseMissing('room_participants', [
            'room_id' => $room->id,
            'user_id' => $this->user->id
        ]);
    }

    /** @test */
    public function it_cannot_leave_room_if_not_a_participant()
    {
        $room = Room::factory()->create(['administrator_id' => $this->admin->id]);
        
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->userToken,
        ])->postJson("/api/rooms/{$room->id}/leave");
        
        $response->assertStatus(404)
                ->assertJson([
                    'success' => false,
                    'message' => 'You are not a participant in this room'
                ]);
    }

    /** @test */
    public function it_administrator_cannot_leave_room()
    {
        $room = Room::factory()->create(['administrator_id' => $this->admin->id]);
        $room->addParticipant($this->admin);
        
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->adminToken,
        ])->postJson("/api/rooms/{$room->id}/leave");
        
        $response->assertStatus(403)
                ->assertJson([
                    'success' => false,
                    'message' => 'Room administrator cannot leave the room. Delete the room instead.'
                ]);
    }

    /** @test */
    public function it_can_get_room_participants()
    {
        $room = Room::factory()->create(['administrator_id' => $this->admin->id]);
        $room->addParticipant($this->admin);
        $room->addParticipant($this->user);
        
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $this->adminToken,
        ])->getJson("/api/rooms/{$room->id}/participants");
        
        $response->assertStatus(200)
                ->assertJson([
                    'success' => true,
                    'message' => 'Participants retrieved successfully'
                ])
                ->assertJsonCount(2, 'data');
    }

    /** @test */
    public function it_requires_authentication_for_all_room_endpoints()
    {
        $room = Room::factory()->create(['administrator_id' => $this->admin->id]);
        
        // Test all endpoints without authentication
        $endpoints = [
            ['GET', '/api/rooms'],
            ['POST', '/api/rooms'],
            ['GET', "/api/rooms/{$room->id}"],
            ['PUT', "/api/rooms/{$room->id}"],
            ['DELETE', "/api/rooms/{$room->id}"],
            ['POST', "/api/rooms/{$room->id}/join"],
            ['POST', "/api/rooms/{$room->id}/leave"],
            ['GET', "/api/rooms/{$room->id}/participants"],
        ];
        
        foreach ($endpoints as [$method, $url]) {
            $response = $this->json($method, $url);
            $response->assertStatus(401);
        }
    }
}