<?php

require __DIR__ . '/vendor/autoload.php';

$client = new \GuzzleHttp\Client(['base_uri' => 'http://localhost:8000/api/']);

try {
    // 1. Login/Register
    $email = 'test_' . time() . rand(1000,9999) . '@example.com';
    $password = 'password123';
    
    echo "Registering user $email...\n";
    try {
        $response = $client->post('auth/register', [
            'json' => [
                'username' => 'User_' . rand(1000,9999),
                'email' => $email,
                'password' => $password,
                'password_confirmation' => $password,
            ]
        ]);
        
        // If registration returns token directly, use it
        $data = json_decode($response->getBody(), true);
        if (isset($data['data']['token'])) {
             $token = $data['data']['token'];
             echo "Got token from registration: " . substr($token, 0, 20) . "...\n";
        }
        
    } catch (\GuzzleHttp\Exception\ClientException $e) {
        echo "Registration failed: " . $e->getResponse()->getBody()->getContents() . "\n";
        // Maybe user exists, try login
        echo "Trying login...\n";
    }

    if (!isset($token)) {
        echo "Logging in...\n";
        $response = $client->post('auth/login', [
            'json' => [
                'email' => $email,
                'password' => $password,
            ]
        ]);
        
        $data = json_decode($response->getBody(), true);
        $token = $data['data']['token'] ?? $data['access_token'] ?? null;
    }
    
    if (!$token) {
        die("Failed to get token\n");
    }
    
    echo "Got token: " . substr($token, 0, 20) . "...\n";
    
    // 2. Call broadcasting/auth
    echo "Calling broadcasting/auth...\n";
    
    // Create a room first to have a valid UUID
    $response = $client->post('rooms', [
        'headers' => ['Authorization' => 'Bearer ' . $token],
        'json' => ['name' => 'Test Room']
    ]);
    $roomData = json_decode($response->getBody(), true);
    $roomId = $roomData['data']['id'] ?? $roomData['id'] ?? 'invalid-id';
    echo "Created room: $roomId\n";
    
    // Ensure user is participant (creator usually is, but let's be sure)
    // Actually, usually creator is admin and participant.
    
    $socketId = '1234.5678';
    $channelName = "private-room.$roomId";
    
    echo "Authenticating for channel: $channelName\n";
    
    $response = $client->post('broadcasting/auth', [
        'headers' => [
            'Authorization' => 'Bearer ' . $token,
            'Accept' => 'application/json',
        ],
        'form_params' => [
            'socket_id' => $socketId,
            'channel_name' => $channelName,
        ]
    ]);
    
    echo "Response status: " . $response->getStatusCode() . "\n";
    echo "Response body: " . $response->getBody() . "\n";

} catch (\GuzzleHttp\Exception\ServerException $e) {
    echo "Server Error: " . $e->getResponse()->getStatusCode() . "\n";
    echo "Body: " . $e->getResponse()->getBody()->getContents() . "\n";
} catch (\Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}
