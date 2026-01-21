-- Development database initialization for Spotik Ruby Backend
-- This script adds development-specific data and configurations

-- Create development users for testing
INSERT INTO users (id, username, email, password_hash, created_at, updated_at) VALUES
  ('dev-user-1', 'testuser1', 'test1@spotik.local', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/hL.ooqWui', NOW(), NOW()),
  ('dev-user-2', 'testuser2', 'test2@spotik.local', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/hL.ooqWui', NOW(), NOW()),
  ('dev-admin', 'admin', 'admin@spotik.local', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/hL.ooqWui', NOW(), NOW())
ON CONFLICT (id) DO NOTHING;

-- Create development rooms
INSERT INTO rooms (id, name, administrator_id, is_public, created_at, updated_at) VALUES
  ('dev-room-1', 'Development Room 1', 'dev-user-1', true, NOW(), NOW()),
  ('dev-room-2', 'Test Room 2', 'dev-user-2', true, NOW(), NOW()),
  ('dev-room-private', 'Private Test Room', 'dev-admin', false, NOW(), NOW())
ON CONFLICT (id) DO NOTHING;

-- Add users to rooms
INSERT INTO room_participants (room_id, user_id, joined_at) VALUES
  ('dev-room-1', 'dev-user-1', NOW()),
  ('dev-room-1', 'dev-user-2', NOW()),
  ('dev-room-2', 'dev-user-2', NOW()),
  ('dev-room-2', 'dev-admin', NOW()),
  ('dev-room-private', 'dev-admin', NOW())
ON CONFLICT (room_id, user_id) DO NOTHING;

-- Create development indexes for better performance
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_username_dev ON users(username);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_email_dev ON users(email);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_rooms_administrator_dev ON rooms(administrator_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_room_participants_room_dev ON room_participants(room_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_room_participants_user_dev ON room_participants(user_id);

-- Development-specific settings
-- Enable query logging for development
ALTER SYSTEM SET log_statement = 'all';
ALTER SYSTEM SET log_min_duration_statement = 0;

-- Reload configuration
SELECT pg_reload_conf();

-- Create development functions for testing
CREATE OR REPLACE FUNCTION reset_dev_data()
RETURNS void AS $$
BEGIN
  -- Reset room states
  UPDATE rooms SET 
    current_track_id = NULL,
    is_playing = false,
    playback_started_at = NULL,
    playback_paused_at = NULL
  WHERE id LIKE 'dev-%';
  
  -- Clear track votes
  DELETE FROM track_votes WHERE track_id IN (
    SELECT id FROM tracks WHERE room_id LIKE 'dev-%'
  );
  
  -- Clear tracks
  DELETE FROM tracks WHERE room_id LIKE 'dev-%';
  
  RAISE NOTICE 'Development data reset completed';
END;
$$ LANGUAGE plpgsql;

-- Create function to generate test data
CREATE OR REPLACE FUNCTION generate_test_tracks(room_id_param text, count_param integer DEFAULT 5)
RETURNS void AS $$
DECLARE
  i integer;
  track_id text;
  user_ids text[] := ARRAY['dev-user-1', 'dev-user-2', 'dev-admin'];
  track_names text[] := ARRAY['Test Song 1', 'Test Song 2', 'Test Song 3', 'Sample Track', 'Demo Audio'];
BEGIN
  FOR i IN 1..count_param LOOP
    track_id := 'test-track-' || i || '-' || extract(epoch from now())::text;
    
    INSERT INTO tracks (
      id, 
      room_id, 
      uploader_id, 
      filename, 
      original_name, 
      duration_seconds, 
      file_size_bytes,
      created_at, 
      updated_at
    ) VALUES (
      track_id,
      room_id_param,
      user_ids[1 + (i % array_length(user_ids, 1))],
      'test_' || i || '.mp3',
      track_names[1 + (i % array_length(track_names, 1))],
      180 + (i * 30), -- Varying durations
      1024 * 1024 * 3, -- 3MB file size
      NOW(),
      NOW()
    );
    
    -- Add some random votes
    IF random() > 0.5 THEN
      INSERT INTO track_votes (track_id, user_id, created_at) VALUES
        (track_id, user_ids[1 + ((i + 1) % array_length(user_ids, 1))], NOW());
    END IF;
  END LOOP;
  
  RAISE NOTICE 'Generated % test tracks for room %', count_param, room_id_param;
END;
$$ LANGUAGE plpgsql;

-- Generate some initial test data
SELECT generate_test_tracks('dev-room-1', 3);
SELECT generate_test_tracks('dev-room-2', 2);

COMMIT;