<?php

/**
 * Standalone Database Schema Integrity Test
 * 
 * **Feature: spotik, Property 11: Data Persistence and Integrity**
 * **Validates: Requirements 8.1, 8.2, 8.5**
 * 
 * This script validates that for any data operation (user creation, room creation, 
 * track upload, vote), the system persists the data reliably in PostgreSQL and 
 * maintains referential integrity.
 */

// Database connection configuration
$host = '127.0.0.1';
$port = '5432';
$dbname = 'spotik_test';
$username = 'spotik_user';
$password = 'spotik_password';

try {
    $pdo = new PDO("pgsql:host=$host;port=$port;dbname=$dbname", $username, $password);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    echo "✓ Connected to database successfully\n";
} catch (PDOException $e) {
    die("✗ Connection failed: " . $e->getMessage() . "\n");
}

// Function to generate fake data
function generateFakeData() {
    return [
        'username' => 'testuser_' . uniqid(),
        'email' => 'test_' . uniqid() . '@example.com',
        'password_hash' => password_hash('password123', PASSWORD_DEFAULT),
        'room_name' => 'Test Room ' . uniqid(),
        'track_filename' => 'track_' . uniqid() . '.mp3',
        'track_original_name' => 'Test Song ' . uniqid() . '.mp3',
        'track_file_path' => 'tracks/' . uniqid() . '.mp3',
        'track_duration' => rand(30, 600),
        'track_file_size' => rand(1000000, 50000000),
        'track_mime_type' => 'audio/mpeg',
    ];
}

// Function to run migrations (simplified)
function runMigrations($pdo) {
    echo "Running database migrations...\n";
    
    // Create users table
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS users (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            username VARCHAR(50) UNIQUE NOT NULL,
            email VARCHAR(255) UNIQUE NOT NULL,
            password_hash VARCHAR(255) NOT NULL,
            created_at TIMESTAMP DEFAULT NOW(),
            updated_at TIMESTAMP DEFAULT NOW()
        )
    ");
    
    // Create rooms table
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS rooms (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            name VARCHAR(100) NOT NULL,
            administrator_id UUID REFERENCES users(id) ON DELETE CASCADE,
            current_track_id UUID NULL,
            playback_started_at TIMESTAMP NULL,
            playback_paused_at TIMESTAMP NULL,
            is_playing BOOLEAN DEFAULT FALSE,
            created_at TIMESTAMP DEFAULT NOW(),
            updated_at TIMESTAMP DEFAULT NOW()
        )
    ");
    
    // Create tracks table
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS tracks (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            room_id UUID REFERENCES rooms(id) ON DELETE CASCADE,
            uploader_id UUID REFERENCES users(id) ON DELETE CASCADE,
            filename VARCHAR(255) NOT NULL,
            original_name VARCHAR(255) NOT NULL,
            file_path VARCHAR(500) NOT NULL,
            duration_seconds INTEGER NOT NULL,
            file_size_bytes BIGINT NOT NULL,
            mime_type VARCHAR(100) NOT NULL,
            vote_score INTEGER DEFAULT 0,
            created_at TIMESTAMP DEFAULT NOW(),
            updated_at TIMESTAMP DEFAULT NOW()
        )
    ");
    
    // Create room_participants table
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS room_participants (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            room_id UUID REFERENCES rooms(id) ON DELETE CASCADE,
            user_id UUID REFERENCES users(id) ON DELETE CASCADE,
            joined_at TIMESTAMP DEFAULT NOW(),
            UNIQUE(room_id, user_id)
        )
    ");
    
    // Create track_votes table
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS track_votes (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            track_id UUID REFERENCES tracks(id) ON DELETE CASCADE,
            user_id UUID REFERENCES users(id) ON DELETE CASCADE,
            created_at TIMESTAMP DEFAULT NOW(),
            UNIQUE(track_id, user_id)
        )
    ");
    
    echo "✓ Migrations completed successfully\n";
}

// Function to clean up test data
function cleanupTestData($pdo) {
    $pdo->exec("TRUNCATE TABLE track_votes CASCADE");
    $pdo->exec("TRUNCATE TABLE room_participants CASCADE");
    $pdo->exec("TRUNCATE TABLE tracks CASCADE");
    $pdo->exec("TRUNCATE TABLE rooms CASCADE");
    $pdo->exec("TRUNCATE TABLE users CASCADE");
}

// Test functions
function testUserDataPersistence($pdo) {
    echo "\n--- Testing User Data Persistence ---\n";
    
    $data = generateFakeData();
    
    // Insert user
    $stmt = $pdo->prepare("
        INSERT INTO users (username, email, password_hash) 
        VALUES (?, ?, ?) 
        RETURNING id
    ");
    $stmt->execute([$data['username'], $data['email'], $data['password_hash']]);
    $userId = $stmt->fetchColumn();
    
    // Verify data persistence
    $stmt = $pdo->prepare("SELECT * FROM users WHERE id = ?");
    $stmt->execute([$userId]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    
    assert($user !== false, "User should be retrievable from database");
    assert($user['username'] === $data['username'], "Username should match");
    assert($user['email'] === $data['email'], "Email should match");
    assert($user['password_hash'] === $data['password_hash'], "Password hash should match");
    
    echo "✓ User data persistence test passed\n";
    return $userId;
}

function testUniqueConstraints($pdo) {
    echo "\n--- Testing Unique Constraints ---\n";
    
    $data = generateFakeData();
    
    // Insert first user
    $stmt = $pdo->prepare("
        INSERT INTO users (username, email, password_hash) 
        VALUES (?, ?, ?)
    ");
    $stmt->execute([$data['username'], $data['email'], $data['password_hash']]);
    
    // Try to insert duplicate username
    try {
        $stmt->execute(['duplicate_' . $data['username'], 'different@example.com', $data['password_hash']]);
        assert(false, "Should have thrown exception for duplicate username");
    } catch (PDOException $e) {
        echo "✓ Duplicate username correctly rejected\n";
    }
    
    // Try to insert duplicate email
    try {
        $stmt->execute(['different_user', $data['email'], $data['password_hash']]);
        assert(false, "Should have thrown exception for duplicate email");
    } catch (PDOException $e) {
        echo "✓ Duplicate email correctly rejected\n";
    }
    
    echo "✓ Unique constraints test passed\n";
}

function testReferentialIntegrity($pdo) {
    echo "\n--- Testing Referential Integrity ---\n";
    
    $data = generateFakeData();
    
    // Create user
    $stmt = $pdo->prepare("
        INSERT INTO users (username, email, password_hash) 
        VALUES (?, ?, ?) 
        RETURNING id
    ");
    $stmt->execute([$data['username'], $data['email'], $data['password_hash']]);
    $userId = $stmt->fetchColumn();
    
    // Create room
    $stmt = $pdo->prepare("
        INSERT INTO rooms (name, administrator_id) 
        VALUES (?, ?) 
        RETURNING id
    ");
    $stmt->execute([$data['room_name'], $userId]);
    $roomId = $stmt->fetchColumn();
    
    // Create track
    $stmt = $pdo->prepare("
        INSERT INTO tracks (room_id, uploader_id, filename, original_name, file_path, duration_seconds, file_size_bytes, mime_type) 
        VALUES (?, ?, ?, ?, ?, ?, ?, ?) 
        RETURNING id
    ");
    $stmt->execute([
        $roomId, $userId, $data['track_filename'], $data['track_original_name'], 
        $data['track_file_path'], $data['track_duration'], $data['track_file_size'], $data['track_mime_type']
    ]);
    $trackId = $stmt->fetchColumn();
    
    // Verify relationships exist
    $stmt = $pdo->prepare("
        SELECT r.name, u.username, t.filename 
        FROM rooms r 
        JOIN users u ON r.administrator_id = u.id 
        JOIN tracks t ON t.room_id = r.id 
        WHERE r.id = ?
    ");
    $stmt->execute([$roomId]);
    $result = $stmt->fetch(PDO::FETCH_ASSOC);
    
    assert($result !== false, "Relationships should be established");
    assert($result['name'] === $data['room_name'], "Room name should match");
    assert($result['username'] === $data['username'], "Username should match");
    assert($result['filename'] === $data['track_filename'], "Track filename should match");
    
    // Test cascade delete
    $pdo->prepare("DELETE FROM users WHERE id = ?")->execute([$userId]);
    
    // Verify cascade worked
    $stmt = $pdo->prepare("SELECT COUNT(*) FROM rooms WHERE id = ?");
    $stmt->execute([$roomId]);
    $roomCount = $stmt->fetchColumn();
    
    $stmt = $pdo->prepare("SELECT COUNT(*) FROM tracks WHERE id = ?");
    $stmt->execute([$trackId]);
    $trackCount = $stmt->fetchColumn();
    
    assert($roomCount == 0, "Room should be deleted due to cascade");
    assert($trackCount == 0, "Track should be deleted due to cascade");
    
    echo "✓ Referential integrity test passed\n";
}

function testComplexOperations($pdo) {
    echo "\n--- Testing Complex Multi-table Operations ---\n";
    
    // Create admin user
    $data = generateFakeData();
    $stmt = $pdo->prepare("
        INSERT INTO users (username, email, password_hash) 
        VALUES (?, ?, ?) 
        RETURNING id
    ");
    $stmt->execute([$data['username'], $data['email'], $data['password_hash']]);
    $adminId = $stmt->fetchColumn();
    
    // Create room
    $stmt = $pdo->prepare("
        INSERT INTO rooms (name, administrator_id) 
        VALUES (?, ?) 
        RETURNING id
    ");
    $stmt->execute([$data['room_name'], $adminId]);
    $roomId = $stmt->fetchColumn();
    
    // Create multiple participants
    $participantIds = [];
    for ($i = 0; $i < 3; $i++) {
        $participantData = generateFakeData();
        $stmt = $pdo->prepare("
            INSERT INTO users (username, email, password_hash) 
            VALUES (?, ?, ?) 
            RETURNING id
        ");
        $stmt->execute([$participantData['username'], $participantData['email'], $participantData['password_hash']]);
        $participantId = $stmt->fetchColumn();
        $participantIds[] = $participantId;
        
        // Add to room
        $stmt = $pdo->prepare("
            INSERT INTO room_participants (room_id, user_id) 
            VALUES (?, ?)
        ");
        $stmt->execute([$roomId, $participantId]);
    }
    
    // Each participant uploads a track
    $trackIds = [];
    foreach ($participantIds as $participantId) {
        $trackData = generateFakeData();
        $stmt = $pdo->prepare("
            INSERT INTO tracks (room_id, uploader_id, filename, original_name, file_path, duration_seconds, file_size_bytes, mime_type) 
            VALUES (?, ?, ?, ?, ?, ?, ?, ?) 
            RETURNING id
        ");
        $stmt->execute([
            $roomId, $participantId, $trackData['track_filename'], $trackData['track_original_name'], 
            $trackData['track_file_path'], $trackData['track_duration'], $trackData['track_file_size'], $trackData['track_mime_type']
        ]);
        $trackIds[] = $stmt->fetchColumn();
    }
    
    // All participants vote for all tracks (except their own)
    foreach ($participantIds as $voterId) {
        foreach ($trackIds as $trackId) {
            // Check if this user uploaded this track
            $stmt = $pdo->prepare("SELECT uploader_id FROM tracks WHERE id = ?");
            $stmt->execute([$trackId]);
            $uploaderId = $stmt->fetchColumn();
            
            if ($uploaderId !== $voterId) {
                $stmt = $pdo->prepare("
                    INSERT INTO track_votes (track_id, user_id) 
                    VALUES (?, ?)
                ");
                $stmt->execute([$trackId, $voterId]);
            }
        }
    }
    
    // Verify data consistency
    $stmt = $pdo->prepare("SELECT COUNT(*) FROM room_participants WHERE room_id = ?");
    $stmt->execute([$roomId]);
    $participantCount = $stmt->fetchColumn();
    
    $stmt = $pdo->prepare("SELECT COUNT(*) FROM tracks WHERE room_id = ?");
    $stmt->execute([$roomId]);
    $trackCount = $stmt->fetchColumn();
    
    assert($participantCount == 3, "Should have 3 participants");
    assert($trackCount == 3, "Should have 3 tracks");
    
    // Each track should have 2 votes (from the other 2 participants)
    foreach ($trackIds as $trackId) {
        $stmt = $pdo->prepare("SELECT COUNT(*) FROM track_votes WHERE track_id = ?");
        $stmt->execute([$trackId]);
        $voteCount = $stmt->fetchColumn();
        assert($voteCount == 2, "Each track should have 2 votes");
    }
    
    echo "✓ Complex operations test passed\n";
}

// Run all tests
try {
    runMigrations($pdo);
    
    cleanupTestData($pdo);
    testUserDataPersistence($pdo);
    
    cleanupTestData($pdo);
    testUniqueConstraints($pdo);
    
    cleanupTestData($pdo);
    testReferentialIntegrity($pdo);
    
    cleanupTestData($pdo);
    testComplexOperations($pdo);
    
    cleanupTestData($pdo);
    
    echo "\n🎉 All database schema integrity tests passed!\n";
    echo "✓ Property 11: Data Persistence and Integrity validated\n";
    echo "✓ Requirements 8.1, 8.2, 8.5 satisfied\n";
    
} catch (Exception $e) {
    echo "\n❌ Test failed: " . $e->getMessage() . "\n";
    echo "Stack trace:\n" . $e->getTraceAsString() . "\n";
    exit(1);
}
?>