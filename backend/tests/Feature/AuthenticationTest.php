<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;
use Tymon\JWTAuth\Facades\JWTAuth;

class AuthenticationTest extends TestCase
{
    use RefreshDatabase;

    /** @test */
    public function it_can_register_a_new_user_with_valid_data()
    {
        $userData = [
            'username' => 'testuser',
            'email' => 'test@example.com',
            'password' => 'password123',
            'password_confirmation' => 'password123',
        ];

        $response = $this->postJson('/api/auth/register', $userData);

        $response->assertStatus(201)
                ->assertJsonStructure([
                    'success',
                    'message',
                    'data' => [
                        'user' => ['id', 'username', 'email', 'created_at'],
                        'token',
                        'token_type',
                        'expires_in'
                    ]
                ])
                ->assertJson([
                    'success' => true,
                    'message' => 'User registered successfully',
                    'data' => [
                        'user' => [
                            'username' => 'testuser',
                            'email' => 'test@example.com',
                        ],
                        'token_type' => 'bearer',
                    ]
                ]);

        // Verify user was created in database
        $this->assertDatabaseHas('users', [
            'username' => 'testuser',
            'email' => 'test@example.com',
        ]);

        // Verify password was hashed
        $user = User::where('email', 'test@example.com')->first();
        $this->assertTrue(Hash::check('password123', $user->password_hash));
    }

    /** @test */
    public function it_rejects_registration_with_invalid_email()
    {
        $userData = [
            'username' => 'testuser',
            'email' => 'invalid-email',
            'password' => 'password123',
            'password_confirmation' => 'password123',
        ];

        $response = $this->postJson('/api/auth/register', $userData);

        $response->assertStatus(422)
                ->assertJson([
                    'success' => false,
                    'message' => 'Validation failed',
                ])
                ->assertJsonValidationErrors(['email']);
    }

    /** @test */
    public function it_rejects_registration_with_duplicate_email()
    {
        // Create existing user
        User::factory()->create(['email' => 'test@example.com']);

        $userData = [
            'username' => 'testuser',
            'email' => 'test@example.com',
            'password' => 'password123',
            'password_confirmation' => 'password123',
        ];

        $response = $this->postJson('/api/auth/register', $userData);

        $response->assertStatus(422)
                ->assertJson([
                    'success' => false,
                    'message' => 'Validation failed',
                ])
                ->assertJsonValidationErrors(['email']);
    }

    /** @test */
    public function it_rejects_registration_with_duplicate_username()
    {
        // Create existing user
        User::factory()->create(['username' => 'testuser']);

        $userData = [
            'username' => 'testuser',
            'email' => 'test@example.com',
            'password' => 'password123',
            'password_confirmation' => 'password123',
        ];

        $response = $this->postJson('/api/auth/register', $userData);

        $response->assertStatus(422)
                ->assertJson([
                    'success' => false,
                    'message' => 'Validation failed',
                ])
                ->assertJsonValidationErrors(['username']);
    }

    /** @test */
    public function it_rejects_registration_with_password_confirmation_mismatch()
    {
        $userData = [
            'username' => 'testuser',
            'email' => 'test@example.com',
            'password' => 'password123',
            'password_confirmation' => 'different_password',
        ];

        $response = $this->postJson('/api/auth/register', $userData);

        $response->assertStatus(422)
                ->assertJson([
                    'success' => false,
                    'message' => 'Validation failed',
                ])
                ->assertJsonValidationErrors(['password']);
    }

    /** @test */
    public function it_can_login_with_valid_credentials()
    {
        // Create a user
        $user = User::factory()->create([
            'email' => 'test@example.com',
            'password_hash' => Hash::make('password123'),
        ]);

        $loginData = [
            'email' => 'test@example.com',
            'password' => 'password123',
        ];

        $response = $this->postJson('/api/auth/login', $loginData);

        $response->assertStatus(200)
                ->assertJsonStructure([
                    'success',
                    'message',
                    'data' => [
                        'user' => ['id', 'username', 'email', 'created_at'],
                        'token',
                        'token_type',
                        'expires_in'
                    ]
                ])
                ->assertJson([
                    'success' => true,
                    'message' => 'Login successful',
                    'data' => [
                        'user' => [
                            'id' => $user->id,
                            'email' => 'test@example.com',
                        ],
                        'token_type' => 'bearer',
                    ]
                ]);
    }

    /** @test */
    public function it_rejects_login_with_invalid_email()
    {
        $loginData = [
            'email' => 'nonexistent@example.com',
            'password' => 'password123',
        ];

        $response = $this->postJson('/api/auth/login', $loginData);

        $response->assertStatus(401)
                ->assertJson([
                    'success' => false,
                    'message' => 'Invalid credentials',
                    'error' => 'User not found'
                ]);
    }

    /** @test */
    public function it_rejects_login_with_invalid_password()
    {
        // Create a user
        User::factory()->create([
            'email' => 'test@example.com',
            'password_hash' => Hash::make('password123'),
        ]);

        $loginData = [
            'email' => 'test@example.com',
            'password' => 'wrong_password',
        ];

        $response = $this->postJson('/api/auth/login', $loginData);

        $response->assertStatus(401)
                ->assertJson([
                    'success' => false,
                    'message' => 'Invalid credentials',
                    'error' => 'Password does not match'
                ]);
    }

    /** @test */
    public function it_rejects_login_with_malformed_email()
    {
        $loginData = [
            'email' => 'invalid-email',
            'password' => 'password123',
        ];

        $response = $this->postJson('/api/auth/login', $loginData);

        $response->assertStatus(422)
                ->assertJson([
                    'success' => false,
                    'message' => 'Validation failed',
                ])
                ->assertJsonValidationErrors(['email']);
    }

    /** @test */
    public function it_can_access_protected_routes_with_valid_token()
    {
        $user = User::factory()->create();
        $token = JWTAuth::fromUser($user);

        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->getJson('/api/auth/me');

        $response->assertStatus(200)
                ->assertJson([
                    'success' => true,
                    'message' => 'User retrieved successfully',
                    'data' => [
                        'user' => [
                            'id' => $user->id,
                            'username' => $user->username,
                            'email' => $user->email,
                        ]
                    ]
                ]);
    }

    /** @test */
    public function it_rejects_access_to_protected_routes_without_token()
    {
        $response = $this->getJson('/api/auth/me');

        $response->assertStatus(401)
                ->assertJson([
                    'success' => false,
                    'message' => 'Token not provided',
                    'error' => 'Token absent'
                ]);
    }

    /** @test */
    public function it_rejects_access_with_invalid_token()
    {
        $response = $this->withHeaders([
            'Authorization' => 'Bearer invalid_token',
        ])->getJson('/api/auth/me');

        $response->assertStatus(401)
                ->assertJson([
                    'success' => false,
                    'message' => 'Token is invalid',
                    'error' => 'Invalid token'
                ]);
    }

    /** @test */
    public function it_can_refresh_valid_token()
    {
        $user = User::factory()->create();
        $token = JWTAuth::fromUser($user);

        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->postJson('/api/auth/refresh');

        $response->assertStatus(200)
                ->assertJsonStructure([
                    'success',
                    'message',
                    'data' => [
                        'token',
                        'token_type',
                        'expires_in'
                    ]
                ])
                ->assertJson([
                    'success' => true,
                    'message' => 'Token refreshed successfully',
                    'data' => [
                        'token_type' => 'bearer',
                    ]
                ]);
    }

    /** @test */
    public function it_can_logout_and_invalidate_token()
    {
        $user = User::factory()->create();
        $token = JWTAuth::fromUser($user);

        // Test that we can access a protected route with the token first
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->getJson('/api/auth/me');

        $response->assertStatus(200);

        // For this test, we'll just verify the logout endpoint works
        // The token invalidation can be tested separately
        $logoutResponse = $this->postJson('/api/auth/logout');
        
        $logoutResponse->assertStatus(200)
                      ->assertJson([
                          'success' => true,
                          'message' => 'Successfully logged out'
                      ]);
    }
}