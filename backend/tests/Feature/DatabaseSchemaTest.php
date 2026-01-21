<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Schema;
use Tests\TestCase;

class DatabaseSchemaTest extends TestCase
{
    use RefreshDatabase;

    /**
     * Test that all required tables exist after migration.
     */
    public function test_all_tables_exist(): void
    {
        $expectedTables = [
            'users',
            'rooms',
            'tracks',
            'room_participants',
            'track_votes'
        ];

        foreach ($expectedTables as $table) {
            $this->assertTrue(
                Schema::hasTable($table),
                "Table '{$table}' does not exist"
            );
        }
    }

    /**
     * Test users table structure.
     */
    public function test_users_table_structure(): void
    {
        $this->assertTrue(Schema::hasTable('users'));
        
        $expectedColumns = [
            'id', 'username', 'email', 'password_hash', 
            'created_at', 'updated_at'
        ];
        
        foreach ($expectedColumns as $column) {
            $this->assertTrue(
                Schema::hasColumn('users', $column),
                "Column '{$column}' does not exist in users table"
            );
        }
    }

    /**
     * Test rooms table structure.
     */
    public function test_rooms_table_structure(): void
    {
        $this->assertTrue(Schema::hasTable('rooms'));
        
        $expectedColumns = [
            'id', 'name', 'administrator_id', 'current_track_id',
            'playback_started_at', 'playback_paused_at', 'is_playing',
            'created_at', 'updated_at'
        ];
        
        foreach ($expectedColumns as $column) {
            $this->assertTrue(
                Schema::hasColumn('rooms', $column),
                "Column '{$column}' does not exist in rooms table"
            );
        }
    }

    /**
     * Test tracks table structure.
     */
    public function test_tracks_table_structure(): void
    {
        $this->assertTrue(Schema::hasTable('tracks'));
        
        $expectedColumns = [
            'id', 'room_id', 'uploader_id', 'filename', 'original_name',
            'file_path', 'duration_seconds', 'file_size_bytes', 'mime_type',
            'vote_score', 'created_at', 'updated_at'
        ];
        
        foreach ($expectedColumns as $column) {
            $this->assertTrue(
                Schema::hasColumn('tracks', $column),
                "Column '{$column}' does not exist in tracks table"
            );
        }
    }

    /**
     * Test room_participants table structure.
     */
    public function test_room_participants_table_structure(): void
    {
        $this->assertTrue(Schema::hasTable('room_participants'));
        
        $expectedColumns = [
            'id', 'room_id', 'user_id', 'joined_at'
        ];
        
        foreach ($expectedColumns as $column) {
            $this->assertTrue(
                Schema::hasColumn('room_participants', $column),
                "Column '{$column}' does not exist in room_participants table"
            );
        }
    }

    /**
     * Test track_votes table structure.
     */
    public function test_track_votes_table_structure(): void
    {
        $this->assertTrue(Schema::hasTable('track_votes'));
        
        $expectedColumns = [
            'id', 'track_id', 'user_id', 'created_at'
        ];
        
        foreach ($expectedColumns as $column) {
            $this->assertTrue(
                Schema::hasColumn('track_votes', $column),
                "Column '{$column}' does not exist in track_votes table"
            );
        }
    }
}