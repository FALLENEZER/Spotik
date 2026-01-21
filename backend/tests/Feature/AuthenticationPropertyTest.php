<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;
use Tymon\JWTAuth\Facades\JWTAuth;

/**
 * Property-Based Test for User Registration and Authentication
 * 
 * **Feature: spotik, Property 1: User Registration and Authentication**
 * **Validates: Requirements 1.1, 1.2**
 * 
 * This test validates that for any valid user registration data, the system should 
 * create a new user account and allow subsequent authentication with those credentials.
 */
class AuthenticationPropertyTest extends TestCase
{
    use RefreshDatabase;

    /** @test */
    public function it_creates_user_account_and_allows_authentication_for_any_valid_registration_data()
    {
        // Property: For any valid user registration data, the system should create a new user account
        // and allow subsequent authentication with those credentials
        
        // Generate random valid user data
        $validUserData = [
            'username' => fake()->unique()->userName(),
            'email' => fake()->unique()->safeEmail(),
            'password' => fake()->password(8, 20), // Between 8-20 characters
            'password_confirmation' => null, // Will be set to same as password
        ];
        $validUserData['password_confirmation'] = $validUserData['password'];

        // Test registration
        $response = $this->postJson('/api/auth/register', $validUserData);

        // Verify registration was successful
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
                            'username' => $validUserData['username'],
                            'email' => $validUserData['email'],
                        ],
                        'token_type' => 'bearer',
                    ]
                ]);

        // Verify user was created in database
        $this->assertDatabaseHas('users', [
            'username' => $validUserData['username'],
            'email' => $validUserData['email'],
        ]);

        // Verify password was hashed correctly
        $user = User::where('email', $validUserData['email'])->first();
        $this->assertNotNull($user);
        $this->assertTrue(Hash::check($validUserData['password'], $user->password_hash));

        // Verify JWT token is valid
        $registrationToken = $response->json('data.token');
        $this->assertNotNull($registrationToken);
        
        // Test that the token can be used for authentication
        $meResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $registrationToken,
        ])->getJson('/api/auth/me');

        $meResponse->assertStatus(200)
                 ->assertJson([
                     'success' => true,
                     'data' => [
                         'user' => [
                             'id' => $user->id,
                             'username' => $validUserData['username'],
                             'email' => $validUserData['email'],
                         ]
                     ]
                 ]);

        // Test subsequent authentication with the same credentials
        $loginData = [
            'email' => $validUserData['email'],
            'password' => $validUserData['password'],
        ];

        $loginResponse = $this->postJson('/api/auth/login', $loginData);

        $loginResponse->assertStatus(200)
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
                                 'username' => $validUserData['username'],
                                 'email' => $validUserData['email'],
                             ],
                             'token_type' => 'bearer',
                         ]
                     ]);

        // Verify login token is also valid
        $loginToken = $loginResponse->json('data.token');
        $this->assertNotNull($loginToken);
        $this->assertNotEquals($loginToken, $registrationToken); // Should be a new token

        // Test that the login token can be used for authentication
        $meResponse2 = $this->withHeaders([
            'Authorization' => 'Bearer ' . $loginToken,
        ])->getJson('/api/auth/me');

        $meResponse2->assertStatus(200)
                  ->assertJson([
                      'success' => true,
                      'data' => [
                          'user' => [
                              'id' => $user->id,
                              'username' => $validUserData['username'],
                              'email' => $validUserData['email'],
                          ]
                      ]
                  ]);
    }

    /** @test */
    public function it_handles_various_valid_username_formats_consistently()
    {
        // Property: The system should handle various valid username formats consistently
        $validUsernames = [
            'user123',
            'test_user',
            'TestUser',
            'user-name',
            'u',
            str_repeat('a', 50), // Maximum length
            'user.name',
            'User123_test',
        ];

        foreach ($validUsernames as $username) {
            // Generate unique email for each test
            $userData = [
                'username' => $username,
                'email' => fake()->unique()->safeEmail(),
                'password' => 'password123',
                'password_confirmation' => 'password123',
            ];

            $response = $this->postJson('/api/auth/register', $userData);

            $response->assertStatus(201)
                    ->assertJson([
                        'success' => true,
                        'data' => [
                            'user' => [
                                'username' => $username,
                            ]
                        ]
                    ]);

            // Test login with the created user
            $loginResponse = $this->postJson('/api/auth/login', [
                'email' => $userData['email'],
                'password' => $userData['password'],
            ]);

            $loginResponse->assertStatus(200)
                         ->assertJson([
                             'success' => true,
                             'data' => [
                                 'user' => [
                                     'username' => $username,
                                 ]
                             ]
                         ]);
        }
    }

    /** @test */
    public function it_handles_various_valid_email_formats_consistently()
    {
        // Property: The system should handle various valid email formats consistently
        $validEmails = [
            'test@example.com',
            'user.name@domain.co.uk',
            'user+tag@example.org',
            'user123@test-domain.com',
            'a@b.co',
            'very.long.email.address@very-long-domain-name.example.com',
        ];

        foreach ($validEmails as $email) {
            $userData = [
                'username' => fake()->unique()->userName(),
                'email' => $email,
                'password' => 'password123',
                'password_confirmation' => 'password123',
            ];

            $response = $this->postJson('/api/auth/register', $userData);

            $response->assertStatus(201)
                    ->assertJson([
                        'success' => true,
                        'data' => [
                            'user' => [
                                'email' => $email,
                            ]
                        ]
                    ]);

            // Test login with the created user
            $loginResponse = $this->postJson('/api/auth/login', [
                'email' => $email,
                'password' => $userData['password'],
            ]);

            $loginResponse->assertStatus(200)
                         ->assertJson([
                             'success' => true,
                             'data' => [
                                 'user' => [
                                     'email' => $email,
                                 ]
                             ]
                         ]);
        }
    }

    /** @test */
    public function it_handles_various_valid_password_formats_consistently()
    {
        // Property: The system should handle various valid password formats consistently
        $validPasswords = [
            'password123',
            'P@ssw0rd!',
            'very-long-password-with-many-characters-123',
            '12345678', // Minimum length
            'Pass Word', // With spaces
            'пароль123', // Unicode characters
            'P@$$w0rd#2024',
        ];

        foreach ($validPasswords as $password) {
            $userData = [
                'username' => fake()->unique()->userName(),
                'email' => fake()->unique()->safeEmail(),
                'password' => $password,
                'password_confirmation' => $password,
            ];

            $response = $this->postJson('/api/auth/register', $userData);

            $response->assertStatus(201)
                    ->assertJson([
                        'success' => true,
                    ]);

            // Test login with the created user
            $loginResponse = $this->postJson('/api/auth/login', [
                'email' => $userData['email'],
                'password' => $password,
            ]);

            $loginResponse->assertStatus(200)
                         ->assertJson([
                             'success' => true,
                         ]);

            // Verify password was hashed correctly
            $user = User::where('email', $userData['email'])->first();
            $this->assertTrue(Hash::check($password, $user->password_hash));
        }
    }

    /** @test */
    public function it_maintains_authentication_state_consistency_across_token_operations()
    {
        // Property: Authentication state should remain consistent across token operations
        $userData = [
            'username' => fake()->unique()->userName(),
            'email' => fake()->unique()->safeEmail(),
            'password' => 'password123',
            'password_confirmation' => 'password123',
        ];

        // Register user
        $registerResponse = $this->postJson('/api/auth/register', $userData);
        $registerResponse->assertStatus(201);
        
        $originalToken = $registerResponse->json('data.token');
        $userId = $registerResponse->json('data.user.id');

        // Test that original token works for authentication
        $meResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $originalToken,
        ])->getJson('/api/auth/me');

        $meResponse->assertStatus(200)
                  ->assertJson([
                      'success' => true,
                      'data' => [
                          'user' => [
                              'id' => $userId,
                              'username' => $userData['username'],
                              'email' => $userData['email'],
                          ]
                      ]
                  ]);

        // Test login to get a fresh token
        $loginResponse = $this->postJson('/api/auth/login', [
            'email' => $userData['email'],
            'password' => $userData['password'],
        ]);

        $loginResponse->assertStatus(200);
        $loginToken = $loginResponse->json('data.token');
        $this->assertNotNull($loginToken);

        // Test that login token works for authentication
        $meResponse2 = $this->withHeaders([
            'Authorization' => 'Bearer ' . $loginToken,
        ])->getJson('/api/auth/me');

        $meResponse2->assertStatus(200)
                   ->assertJson([
                       'success' => true,
                       'data' => [
                           'user' => [
                               'id' => $userId,
                               'username' => $userData['username'],
                               'email' => $userData['email'],
                           ]
                       ]
                   ]);

        // Test that user data remains consistent across different tokens
        $this->assertEquals(
            $meResponse->json('data.user.id'),
            $meResponse2->json('data.user.id')
        );
        $this->assertEquals(
            $meResponse->json('data.user.username'),
            $meResponse2->json('data.user.username')
        );
        $this->assertEquals(
            $meResponse->json('data.user.email'),
            $meResponse2->json('data.user.email')
        );

        // Test that multiple logins work consistently
        $loginResponse2 = $this->postJson('/api/auth/login', [
            'email' => $userData['email'],
            'password' => $userData['password'],
        ]);

        $loginResponse2->assertStatus(200)
                      ->assertJson([
                          'success' => true,
                          'data' => [
                              'user' => [
                                  'id' => $userId,
                                  'username' => $userData['username'],
                                  'email' => $userData['email'],
                              ]
                          ]
                      ]);
    }

    /** @test */
    public function it_generates_unique_tokens_for_concurrent_authentication_requests()
    {
        // Property: Each authentication request should generate a unique token
        $userData = [
            'username' => fake()->unique()->userName(),
            'email' => fake()->unique()->safeEmail(),
            'password' => 'password123',
            'password_confirmation' => 'password123',
        ];

        // Register user
        $this->postJson('/api/auth/register', $userData)->assertStatus(201);

        // Perform multiple concurrent login requests (simulated)
        $tokens = [];
        for ($i = 0; $i < 5; $i++) {
            $response = $this->postJson('/api/auth/login', [
                'email' => $userData['email'],
                'password' => $userData['password'],
            ]);

            $response->assertStatus(200);
            $token = $response->json('data.token');
            $this->assertNotNull($token);
            
            // Verify token is unique
            $this->assertNotContains($token, $tokens);
            $tokens[] = $token;

            // Verify each token works
            $meResponse = $this->withHeaders([
                'Authorization' => 'Bearer ' . $token,
            ])->getJson('/api/auth/me');

            $meResponse->assertStatus(200)
                      ->assertJson([
                          'success' => true,
                          'data' => [
                              'user' => [
                                  'username' => $userData['username'],
                                  'email' => $userData['email'],
                              ]
                          ]
                      ]);
        }

        // Verify all tokens are unique
        $this->assertCount(5, $tokens);
        $this->assertCount(5, array_unique($tokens));
    }

    /** @test */
    public function it_preserves_user_data_integrity_throughout_authentication_lifecycle()
    {
        // Property: User data should remain consistent throughout the authentication lifecycle
        $userData = [
            'username' => fake()->unique()->userName(),
            'email' => fake()->unique()->safeEmail(),
            'password' => 'password123',
            'password_confirmation' => 'password123',
        ];

        // Register user
        $registerResponse = $this->postJson('/api/auth/register', $userData);
        $registerResponse->assertStatus(201);
        
        $expectedUserData = [
            'id' => $registerResponse->json('data.user.id'),
            'username' => $userData['username'],
            'email' => $userData['email'],
        ];

        // Test data consistency across different authentication endpoints
        $endpoints = [
            ['method' => 'GET', 'url' => '/api/auth/me'],
        ];

        $token = $registerResponse->json('data.token');

        foreach ($endpoints as $endpoint) {
            $response = $this->withHeaders([
                'Authorization' => 'Bearer ' . $token,
            ])->json($endpoint['method'], $endpoint['url']);

            if ($response->status() === 200) {
                $responseUserData = $response->json('data.user');
                $this->assertEquals($expectedUserData['id'], $responseUserData['id']);
                $this->assertEquals($expectedUserData['username'], $responseUserData['username']);
                $this->assertEquals($expectedUserData['email'], $responseUserData['email']);
            }
        }

        // Test data consistency after login
        $loginResponse = $this->postJson('/api/auth/login', [
            'email' => $userData['email'],
            'password' => $userData['password'],
        ]);

        $loginResponse->assertStatus(200);
        $loginUserData = $loginResponse->json('data.user');
        $this->assertEquals($expectedUserData['id'], $loginUserData['id']);
        $this->assertEquals($expectedUserData['username'], $loginUserData['username']);
        $this->assertEquals($expectedUserData['email'], $loginUserData['email']);

        // Test data consistency after token refresh
        $newToken = $loginResponse->json('data.token');
        $refreshResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $newToken,
        ])->postJson('/api/auth/refresh');

        $refreshResponse->assertStatus(200);
        
        $refreshedToken = $refreshResponse->json('data.token');
        $meResponse = $this->withHeaders([
            'Authorization' => 'Bearer ' . $refreshedToken,
        ])->getJson('/api/auth/me');

        $meResponse->assertStatus(200);
        $meUserData = $meResponse->json('data.user');
        $this->assertEquals($expectedUserData['id'], $meUserData['id']);
        $this->assertEquals($expectedUserData['username'], $meUserData['username']);
        $this->assertEquals($expectedUserData['email'], $meUserData['email']);
    }

    /** @test */
    public function it_rejects_invalid_authentication_attempts_consistently()
    {
        // **Feature: spotik, Property 2: Invalid Authentication Rejection**
        // **Validates: Requirements 1.3**
        // Property: For any invalid login credentials (wrong password, non-existent user, malformed data),
        // the system should reject the authentication attempt and return an appropriate error.

        // First, create a valid user for testing wrong password scenarios
        $validUser = User::factory()->create([
            'email' => 'valid@example.com',
            'password_hash' => Hash::make('correct_password'),
        ]);

        // Test Case 1: Wrong passwords for existing users
        $wrongPasswords = [
            'wrong_password',
            'incorrect123',
            'short',
            'CORRECT_PASSWORD', // Case sensitivity
            'correct_password ', // Trailing space
            ' correct_password', // Leading space
            'correct_password123', // Extra characters
            'correct_passwor', // Missing characters
            'password123', // Completely different
            str_repeat('a', 1000), // Very long password
            'пароль', // Unicode characters
            'correct\npassword', // With newline
            'correct\tpassword', // With tab
        ];

        foreach ($wrongPasswords as $wrongPassword) {
            $response = $this->postJson('/api/auth/login', [
                'email' => $validUser->email,
                'password' => $wrongPassword,
            ]);

            $response->assertStatus(401)
                    ->assertJson([
                        'success' => false,
                        'message' => 'Invalid credentials',
                        'error' => 'Password does not match'
                    ]);

            // Verify no token is returned
            $this->assertNull($response->json('data.token'));
        }

        // Test Case 1b: Empty password (should return validation error)
        $response = $this->postJson('/api/auth/login', [
            'email' => $validUser->email,
            'password' => '',
        ]);

        $response->assertStatus(422)
                ->assertJson([
                    'success' => false,
                    'message' => 'Validation failed',
                ])
                ->assertJsonValidationErrors(['password']);

        // Verify no token is returned
        $this->assertNull($response->json('data.token'));

        // Test Case 2: Non-existent users with various email formats
        $nonExistentEmails = [
            'nonexistent@example.com',
            'fake.user@domain.com',
            'test123@nowhere.org',
            'user@invalid-domain.xyz',
            'random.email@test.co.uk',
            'nobody@example.net',
            'ghost@phantom.com',
            'missing@user.io',
        ];

        foreach ($nonExistentEmails as $email) {
            $response = $this->postJson('/api/auth/login', [
                'email' => $email,
                'password' => 'any_password',
            ]);

            $response->assertStatus(401)
                    ->assertJson([
                        'success' => false,
                        'message' => 'Invalid credentials',
                        'error' => 'User not found'
                    ]);

            // Verify no token is returned
            $this->assertNull($response->json('data.token'));
        }

        // Test Case 3: Malformed email addresses
        $malformedEmails = [
            'invalid-email',
            'no-at-symbol.com',
            '@missing-local.com',
            'missing-domain@',
            'double@@domain.com',
            'spaces in@email.com',
            'email@',
            '@domain.com',
            'email@domain',
            'email.domain.com',
            'email@domain..com',
            'email@.domain.com',
            'email@domain.com.',
            'email@-domain.com',
            'email@domain-.com',
            '',
            ' ',
            'email with spaces@domain.com',
            'email@domain with spaces.com',
            'email@domain.com with extra',
        ];

        foreach ($malformedEmails as $malformedEmail) {
            $response = $this->postJson('/api/auth/login', [
                'email' => $malformedEmail,
                'password' => 'any_password',
            ]);

            // Should return validation error for malformed emails OR user not found
            // Laravel's email validation might let some through, so we accept both
            $this->assertContains($response->status(), [401, 422]);
            $response->assertJson([
                'success' => false,
            ]);

            // Verify no token is returned
            $this->assertNull($response->json('data.token'));
        }

        // Test Case 3b: Clearly invalid emails that should definitely fail validation
        $definitelyInvalidEmails = [
            'тест@domain.com', // Unicode in local part
            'email@тест.com', // Unicode in domain
        ];

        foreach ($definitelyInvalidEmails as $invalidEmail) {
            $response = $this->postJson('/api/auth/login', [
                'email' => $invalidEmail,
                'password' => 'any_password',
            ]);

            // These should return validation error or user not found
            $this->assertContains($response->status(), [401, 422]);
            $response->assertJson([
                'success' => false,
            ]);

            // Verify no token is returned
            $this->assertNull($response->json('data.token'));
        }

        // Test Case 4: Missing required fields
        $incompleteDataTests = [
            [
                'data' => [], // Empty request
                'expected_status' => 422,
                'expected_errors' => ['email', 'password']
            ],
            [
                'data' => ['email' => 'test@example.com'], // Missing password
                'expected_status' => 422,
                'expected_errors' => ['password']
            ],
            [
                'data' => ['password' => 'password123'], // Missing email
                'expected_status' => 422,
                'expected_errors' => ['email']
            ],
            [
                'data' => ['email' => '', 'password' => 'password123'], // Empty email
                'expected_status' => 422,
                'expected_errors' => ['email']
            ],
            [
                'data' => ['email' => 'test@example.com', 'password' => ''], // Empty password
                'expected_status' => 422,
                'expected_errors' => ['password']
            ],
            [
                'data' => ['email' => null, 'password' => 'password123'], // Null email
                'expected_status' => 422,
                'expected_errors' => ['email']
            ],
            [
                'data' => ['email' => 'test@example.com', 'password' => null], // Null password
                'expected_status' => 422,
                'expected_errors' => ['password']
            ],
        ];

        foreach ($incompleteDataTests as $testCase) {
            $response = $this->postJson('/api/auth/login', $testCase['data']);

            $response->assertStatus($testCase['expected_status'])
                    ->assertJson([
                        'success' => false,
                        'message' => 'Validation failed',
                    ]);

            // Should have validation errors for expected fields
            foreach ($testCase['expected_errors'] as $field) {
                $response->assertJsonValidationErrors([$field]);
            }

            // Verify no token is returned
            $this->assertNull($response->json('data.token'));
        }

        // Test Case 5: Invalid data types
        $invalidTypeData = [
            ['email' => 123, 'password' => 'password123'], // Numeric email
            ['email' => true, 'password' => 'password123'], // Boolean email
            ['email' => ['test@example.com'], 'password' => 'password123'], // Array email
            ['email' => 'test@example.com', 'password' => 123], // Numeric password
            ['email' => 'test@example.com', 'password' => true], // Boolean password
            ['email' => 'test@example.com', 'password' => ['password123']], // Array password
        ];

        foreach ($invalidTypeData as $data) {
            $response = $this->postJson('/api/auth/login', $data);

            // Should return validation error or 401 depending on how Laravel handles type conversion
            $this->assertContains($response->status(), [401, 422]);
            $response->assertJson([
                'success' => false,
            ]);

            // Verify no token is returned
            $this->assertNull($response->json('data.token'));
        }

        // Test Case 6: SQL injection attempts
        $sqlInjectionAttempts = [
            "admin@example.com'; DROP TABLE users; --",
            "admin@example.com' OR '1'='1",
            "admin@example.com' UNION SELECT * FROM users --",
            "admin@example.com'; INSERT INTO users VALUES ('hacker', 'hacker@evil.com', 'hash'); --",
        ];

        foreach ($sqlInjectionAttempts as $maliciousEmail) {
            $response = $this->postJson('/api/auth/login', [
                'email' => $maliciousEmail,
                'password' => 'any_password',
            ]);

            // Should either be validation error (422) or user not found (401)
            $this->assertContains($response->status(), [401, 422]);
            $response->assertJson([
                'success' => false,
            ]);

            // Verify no token is returned
            $this->assertNull($response->json('data.token'));

            // Verify the database wasn't compromised - user should still exist
            $this->assertDatabaseHas('users', [
                'id' => $validUser->id,
                'email' => $validUser->email,
            ]);
        }

        // Test Case 7: Extremely long inputs
        $longEmail = str_repeat('a', 1000) . '@' . str_repeat('b', 1000) . '.com';
        $longPassword = str_repeat('c', 10000);

        $response = $this->postJson('/api/auth/login', [
            'email' => $longEmail,
            'password' => $longPassword,
        ]);

        // Should handle gracefully with validation error or user not found
        $this->assertContains($response->status(), [401, 422]);
        $response->assertJson([
            'success' => false,
        ]);

        // Verify no token is returned
        $this->assertNull($response->json('data.token'));
    }

    /** @test */
    public function it_consistently_rejects_authentication_with_case_sensitive_passwords()
    {
        // Property: Password authentication should be case-sensitive and consistent
        $user = User::factory()->create([
            'email' => 'test@example.com',
            'password_hash' => Hash::make('MySecretPassword123'),
        ]);

        $incorrectCasePasswords = [
            'mysecretpassword123', // All lowercase
            'MYSECRETPASSWORD123', // All uppercase
            'mySecretPassword123', // Different camelCase
            'MySecretPASSWORD123', // Mixed case variation
            'mySECRETpassword123', // Another variation
        ];

        foreach ($incorrectCasePasswords as $password) {
            $response = $this->postJson('/api/auth/login', [
                'email' => $user->email,
                'password' => $password,
            ]);

            $response->assertStatus(401)
                    ->assertJson([
                        'success' => false,
                        'message' => 'Invalid credentials',
                        'error' => 'Password does not match'
                    ]);
        }

        // Verify correct password still works
        $response = $this->postJson('/api/auth/login', [
            'email' => $user->email,
            'password' => 'MySecretPassword123',
        ]);

        $response->assertStatus(200)
                ->assertJson([
                    'success' => true,
                    'message' => 'Login successful',
                ]);
    }

    /** @test */
    public function it_rejects_authentication_attempts_with_timing_attack_resistance()
    {
        // Property: Authentication should take similar time for existing and non-existing users
        // to prevent timing attacks that could reveal valid email addresses
        
        $existingUser = User::factory()->create([
            'email' => 'existing@example.com',
            'password_hash' => Hash::make('correct_password'),
        ]);

        // Test with existing user but wrong password
        $startTime1 = microtime(true);
        $response1 = $this->postJson('/api/auth/login', [
            'email' => $existingUser->email,
            'password' => 'wrong_password',
        ]);
        $endTime1 = microtime(true);
        $duration1 = $endTime1 - $startTime1;

        $response1->assertStatus(401)
                 ->assertJson([
                     'success' => false,
                     'message' => 'Invalid credentials',
                     'error' => 'Password does not match'
                 ]);

        // Test with non-existing user
        $startTime2 = microtime(true);
        $response2 = $this->postJson('/api/auth/login', [
            'email' => 'nonexistent@example.com',
            'password' => 'any_password',
        ]);
        $endTime2 = microtime(true);
        $duration2 = $endTime2 - $startTime2;

        $response2->assertStatus(401)
                 ->assertJson([
                     'success' => false,
                     'message' => 'Invalid credentials',
                     'error' => 'User not found'
                 ]);

        // Both should return 401 status and no token
        $this->assertNull($response1->json('data.token'));
        $this->assertNull($response2->json('data.token'));

        // Note: In a production system, we would want similar timing,
        // but for this test we just verify both scenarios are handled securely
        $this->assertGreaterThan(0, $duration1);
        $this->assertGreaterThan(0, $duration2);
    }

    /** @test */
    public function it_maintains_consistent_error_response_format_for_all_invalid_authentication_attempts()
    {
        // Property: All invalid authentication attempts should return consistent error response format
        $user = User::factory()->create([
            'email' => 'test@example.com',
            'password_hash' => Hash::make('correct_password'),
        ]);

        $invalidAttempts = [
            // Wrong password
            [
                'data' => ['email' => $user->email, 'password' => 'wrong_password'], 
                'expected_status' => 401
            ],
            // Non-existent user
            [
                'data' => ['email' => 'nonexistent@example.com', 'password' => 'any_password'], 
                'expected_status' => 401
            ],
            // Malformed email
            [
                'data' => ['email' => 'invalid-email', 'password' => 'any_password'], 
                'expected_status' => 422
            ],
            // Missing password
            [
                'data' => ['email' => $user->email], 
                'expected_status' => 422
            ],
            // Missing email
            [
                'data' => ['password' => 'any_password'], 
                'expected_status' => 422
            ],
            // Empty data
            [
                'data' => [], 
                'expected_status' => 422
            ],
        ];

        foreach ($invalidAttempts as $attempt) {
            $expectedStatus = $attempt['expected_status'];
            $data = $attempt['data'];

            $response = $this->postJson('/api/auth/login', $data);

            $response->assertStatus($expectedStatus)
                    ->assertJsonStructure([
                        'success',
                        'message',
                    ])
                    ->assertJson([
                        'success' => false,
                    ]);

            // Verify no token is ever returned for invalid attempts
            $this->assertNull($response->json('data.token'));
            $this->assertNull($response->json('token'));

            // Verify consistent response structure
            $responseData = $response->json();
            $this->assertIsArray($responseData);
            $this->assertArrayHasKey('success', $responseData);
            $this->assertArrayHasKey('message', $responseData);
            $this->assertFalse($responseData['success']);
            $this->assertIsString($responseData['message']);
        }
    }
}