<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;
use Tymon\JWTAuth\Facades\JWTAuth;

/**
 * Property-Based Test for JWT Token Management
 * 
 * **Feature: spotik, Property 3: JWT Token Management**
 * **Validates: Requirements 1.4, 1.5**
 * 
 * This test validates that for any successful authentication, the system should 
 * return a valid JWT token that can be used for subsequent authenticated requests 
 * until expiration.
 */
class JWTTokenManagementPropertyTest extends TestCase
{
    use RefreshDatabase;

    /** @test */
    public function it_returns_valid_jwt_tokens_for_successful_authentication()
    {
        // Property: For any successful authentication, the system should return a valid JWT token
        
        // Test with registration
        $registrationData = [
            'username' => fake()->unique()->userName(),
            'email' => fake()->unique()->safeEmail(),
            'password' => fake()->password(8, 20),
            'password_confirmation' => null,
        ];
        $registrationData['password_confirmation'] = $registrationData['password'];

        $registerResponse = $this->postJson('/api/auth/register', $registrationData);
        $registerResponse->assertStatus(201);

        $registrationToken = $registerResponse->json('data.token');
        $this->assertNotNull($registrationToken);
        $this->assertIsString($registrationToken);
        $this->assertGreaterThan(10, strlen($registrationToken)); // JWT tokens are long strings

        // Verify token structure (JWT has 3 parts separated by dots)
        $tokenParts = explode('.', $registrationToken);
        $this->assertCount(3, $tokenParts, 'JWT token should have 3 parts (header.payload.signature)');
        
        foreach ($tokenParts as $part) {
            $this->assertNotEmpty($part, 'Each JWT token part should not be empty');
        }

        // Test with login
        $loginResponse = $this->postJson('/api/auth/login', [
            'email' => $registrationData['email'],
            'password' => $registrationData['password'],
        ]);
        $loginResponse->assertStatus(200);

        $loginToken = $loginResponse->json('data.token');
        $this->assertNotNull($loginToken);
        $this->assertIsString($loginToken);
        $this->assertGreaterThan(10, strlen($loginToken));

        // Verify login token structure
        $loginTokenParts = explode('.', $loginToken);
        $this->assertCount(3, $loginTokenParts);
        
        // Tokens should be different (new token generated each time)
        $this->assertNotEquals($registrationToken, $loginToken);

        // Both tokens should be valid for authentication
        $this->assertTokenIsValidForAuthentication($registrationToken);
        $this->assertTokenIsValidForAuthentication($loginToken);
    }

    /** @test */
    public function it_allows_tokens_to_be_used_for_authenticated_requests_until_expiration()
    {
        // Property: Tokens can be used for authenticated requests until expiration
        
        $user = User::factory()->create([
            'password_hash' => Hash::make('password123'),
        ]);

        // Generate token
        $token = JWTAuth::fromUser($user);
        $this->assertNotNull($token);

        // Test GET /api/auth/me endpoint
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->getJson('/api/auth/me');

        $response->assertStatus(200)
                ->assertJson([
                    'success' => true,
                    'data' => [
                        'user' => [
                            'id' => $user->id,
                            'username' => $user->username,
                            'email' => $user->email,
                        ]
                    ]
                ]);

        // Test that token works for multiple requests
        for ($i = 0; $i < 3; $i++) {
            $response = $this->withHeaders([
                'Authorization' => 'Bearer ' . $token,
            ])->getJson('/api/auth/me');

            $response->assertStatus(200)
                    ->assertJson([
                        'success' => true,
                        'data' => [
                            'user' => [
                                'id' => $user->id,
                                'username' => $user->username,
                                'email' => $user->email,
                            ]
                        ]
                    ]);
        }
    }

    /** @test */
    public function it_handles_token_refresh_correctly()
    {
        // Property: Token refresh works correctly
        
        $user = User::factory()->create([
            'password_hash' => Hash::make('password123'),
        ]);

        // Generate initial token
        $originalToken = JWTAuth::fromUser($user);
        $this->assertNotNull($originalToken);

        // Test token refresh
        $refreshResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $originalToken,
        ])->postJson('/api/auth/refresh');

        $refreshResponse->assertStatus(200)
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

        $refreshedToken = $refreshResponse->json('data.token');
        $this->assertNotNull($refreshedToken);
        $this->assertIsString($refreshedToken);
        $this->assertNotEquals($originalToken, $refreshedToken, 'Refreshed token should be different from original');

        // Verify refreshed token structure
        $tokenParts = explode('.', $refreshedToken);
        $this->assertCount(3, $tokenParts);

        // Verify refreshed token works for authentication
        $this->assertTokenIsValidForAuthentication($refreshedToken);

        // Verify expires_in is a positive integer
        $expiresIn = $refreshResponse->json('data.expires_in');
        $this->assertIsInt($expiresIn);
        $this->assertGreaterThan(0, $expiresIn);
        
        // Should match configured TTL (in seconds)
        $expectedTtl = config('jwt.ttl') * 60; // Convert minutes to seconds
        $this->assertEquals($expectedTtl, $expiresIn);
    }

    /** @test */
    public function it_maintains_consistent_token_properties_across_operations()
    {
        // Property: Token properties should remain consistent across different operations
        
        for ($i = 0; $i < 3; $i++) {
            // Test registration token
            $registrationData = [
                'username' => fake()->unique()->userName(),
                'email' => fake()->unique()->safeEmail(),
                'password' => 'password123',
                'password_confirmation' => 'password123',
            ];

            $registerResponse = $this->postJson('/api/auth/register', $registrationData);
            $registerResponse->assertStatus(201);

            $registrationToken = $registerResponse->json('data.token');
            $registrationExpiresIn = $registerResponse->json('data.expires_in');
            $registrationTokenType = $registerResponse->json('data.token_type');

            // Test login token
            $loginResponse = $this->postJson('/api/auth/login', [
                'email' => $registrationData['email'],
                'password' => $registrationData['password'],
            ]);
            $loginResponse->assertStatus(200);

            $loginToken = $loginResponse->json('data.token');
            $loginExpiresIn = $loginResponse->json('data.expires_in');
            $loginTokenType = $loginResponse->json('data.token_type');

            // Test refresh token
            $refreshResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $loginToken,
            ])->postJson('/api/auth/refresh');
            $refreshResponse->assertStatus(200);

            $refreshToken = $refreshResponse->json('data.token');
            $refreshExpiresIn = $refreshResponse->json('data.expires_in');
            $refreshTokenType = $refreshResponse->json('data.token_type');

            // Verify consistent properties
            $this->assertEquals('bearer', $registrationTokenType);
            $this->assertEquals('bearer', $loginTokenType);
            $this->assertEquals('bearer', $refreshTokenType);

            $this->assertEquals($registrationExpiresIn, $loginExpiresIn);
            $this->assertEquals($loginExpiresIn, $refreshExpiresIn);

            // Verify all tokens have proper JWT structure
            foreach ([$registrationToken, $loginToken, $refreshToken] as $token) {
                $tokenParts = explode('.', $token);
                $this->assertCount(3, $tokenParts);
                foreach ($tokenParts as $part) {
                    $this->assertNotEmpty($part);
                }
            }

            // Verify all tokens work for authentication
            $this->assertTokenIsValidForAuthentication($registrationToken);
            $this->assertTokenIsValidForAuthentication($refreshToken);
        }
    }

    /** @test */
    public function it_handles_concurrent_token_operations_safely()
    {
        // Property: Concurrent token operations should be handled safely
        
        $user = User::factory()->create([
            'password_hash' => Hash::make('password123'),
        ]);

        // Generate multiple tokens concurrently (simulated)
        $tokens = [];
        for ($i = 0; $i < 5; $i++) {
            $token = JWTAuth::fromUser($user);
            $this->assertNotNull($token);
            $tokens[] = $token;
        }

        // All tokens should be unique
        $this->assertCount(5, array_unique($tokens), 'All generated tokens should be unique');

        // All tokens should work for authentication
        foreach ($tokens as $token) {
            $this->assertTokenIsValidForAuthentication($token);
        }

        // Test concurrent refresh operations
        $refreshedTokens = [];
        foreach (array_slice($tokens, 0, 3) as $token) { // Use first 3 tokens
            $refreshResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $token,
            ])->postJson('/api/auth/refresh');

            $refreshResponse->assertStatus(200);
            $refreshedToken = $refreshResponse->json('data.token');
            $this->assertNotNull($refreshedToken);
            $refreshedTokens[] = $refreshedToken;
        }

        // All refreshed tokens should be unique
        $this->assertCount(3, array_unique($refreshedTokens), 'All refreshed tokens should be unique');

        // All refreshed tokens should work
        foreach ($refreshedTokens as $token) {
            $this->assertTokenIsValidForAuthentication($token);
        }
    }

    /** @test */
    public function it_validates_token_format_and_structure_consistently()
    {
        // Property: All generated tokens should have consistent format and structure
        
        $user = User::factory()->create([
            'password_hash' => Hash::make('password123'),
        ]);

        // Test tokens from different sources
        $tokenSources = [
            'direct' => JWTAuth::fromUser($user),
            'login' => $this->getTokenFromLogin($user),
            'registration' => $this->getTokenFromRegistration(),
        ];

        foreach ($tokenSources as $source => $token) {
            $this->assertNotNull($token, "Token from {$source} should not be null");
            $this->assertIsString($token, "Token from {$source} should be a string");

            // Verify JWT structure (3 parts separated by dots)
            $parts = explode('.', $token);
            $this->assertCount(3, $parts, "Token from {$source} should have 3 parts");

            // Verify each part is base64url encoded (no padding, URL-safe characters)
            foreach ($parts as $index => $part) {
                $this->assertNotEmpty($part, "Part {$index} of token from {$source} should not be empty");
                $this->assertMatchesRegularExpression(
                    '/^[A-Za-z0-9_-]+$/', 
                    $part, 
                    "Part {$index} of token from {$source} should be base64url encoded"
                );
            }

            // Verify token can be parsed by JWT library
            try {
                $payload = JWTAuth::setToken($token)->getPayload();
                $this->assertNotNull($payload, "Token from {$source} should have valid payload");
                
                // Verify required claims exist
                $requiredClaims = config('jwt.required_claims', []);
                foreach ($requiredClaims as $claim) {
                    $this->assertTrue(
                        $payload->offsetExists($claim), 
                        "Token from {$source} should have required claim: {$claim}"
                    );
                }

                // Verify subject claim exists and is valid
                $this->assertTrue(
                    $payload->offsetExists('sub'), 
                    "Token from {$source} should have subject claim"
                );
                
                $subjectId = $payload->get('sub');
                $this->assertNotNull($subjectId, "Subject claim should not be null");
                $this->assertIsString($subjectId, "Subject claim should be a string");

            } catch (\Exception $e) {
                $this->fail("Token from {$source} should be parseable by JWT library: " . $e->getMessage());
            }
        }
    }

    /** @test */
    public function it_rejects_invalid_and_malformed_tokens_consistently()
    {
        // Property: Invalid tokens should be consistently rejected
        
        $invalidTokens = [
            'invalid_token',
            'not.a.jwt',
            'too.few.parts',
            'too.many.parts.here.extra',
            '',
            'Bearer token_without_bearer_prefix',
            'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.invalid_payload.invalid_signature',
            str_repeat('a', 1000), // Very long invalid token
        ];

        foreach ($invalidTokens as $invalidToken) {
            $response = $this->withHeaders([
                'Authorization' => 'Bearer ' . $invalidToken,
            ])->getJson('/api/auth/me');

            $response->assertStatus(401, "Invalid token '{$invalidToken}' should be rejected with 401");
            
            // Should have error message
            $responseData = $response->json();
            $this->assertArrayHasKey('message', $responseData, "Invalid token response should have message");
        }
    }

    /** @test */
    public function it_handles_missing_authorization_header_correctly()
    {
        // Property: Requests without authorization header should be rejected
        
        $response = $this->getJson('/api/auth/me');
        
        $response->assertStatus(401);
        
        $responseData = $response->json();
        $this->assertArrayHasKey('message', $responseData);
        $this->assertStringContainsString('token', strtolower($responseData['message']));
    }

    /** @test */
    public function it_generates_unique_tokens_for_each_authentication_request()
    {
        // Property: Each authentication request should generate a unique token
        
        $user = User::factory()->create([
            'password_hash' => Hash::make('password123'),
        ]);

        // Generate multiple tokens for the same user
        $tokens = [];
        for ($i = 0; $i < 10; $i++) {
            $response = $this->postJson('/api/auth/login', [
                'email' => $user->email,
                'password' => 'password123',
            ]);

            $response->assertStatus(200);
            $token = $response->json('data.token');
            $this->assertNotNull($token);
            
            // Verify token is unique
            $this->assertNotContains($token, $tokens, "Token should be unique");
            $tokens[] = $token;

            // Verify each token works
            $this->assertTokenIsValidForAuthentication($token);
        }

        // Verify all tokens are unique
        $this->assertCount(10, $tokens);
        $this->assertCount(10, array_unique($tokens));
    }

    /**
     * Helper method to assert that a token is valid for authentication
     */
    private function assertTokenIsValidForAuthentication(string $token): void
    {
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $token,
        ])->getJson('/api/auth/me');

        $response->assertStatus(200)
                ->assertJson([
                    'success' => true,
                ])
                ->assertJsonStructure([
                    'success',
                    'message',
                    'data' => [
                        'user' => ['id', 'username', 'email']
                    ]
                ]);
    }

    /**
     * Helper method to get token from login
     */
    private function getTokenFromLogin(User $user): string
    {
        $response = $this->postJson('/api/auth/login', [
            'email' => $user->email,
            'password' => 'password123',
        ]);

        $response->assertStatus(200);
        return $response->json('data.token');
    }

    /**
     * Helper method to get token from registration
     */
    private function getTokenFromRegistration(): string
    {
        $userData = [
            'username' => fake()->unique()->userName(),
            'email' => fake()->unique()->safeEmail(),
            'password' => 'password123',
            'password_confirmation' => 'password123',
        ];

        $response = $this->postJson('/api/auth/register', $userData);
        $response->assertStatus(201);
        return $response->json('data.token');
    }
}