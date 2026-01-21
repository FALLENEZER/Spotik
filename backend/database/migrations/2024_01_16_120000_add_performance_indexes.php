<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Disable transaction for this migration due to CONCURRENTLY operations
     */
    public $withinTransaction = false;

    /**
     * Run the migrations.
     */
    public function up(): void
    {
        // Add composite indexes for better query performance
        Schema::table('tracks', function (Blueprint $table) {
            // Optimize track queue queries (room_id + vote_score DESC + created_at ASC)
            $table->index(['room_id', 'vote_score', 'created_at'], 'idx_tracks_queue_order');
            
            // Optimize uploader queries
            $table->index(['uploader_id', 'created_at'], 'idx_tracks_uploader_time');
            
            // Optimize file path lookups
            $table->index('file_path', 'idx_tracks_file_path');
        });

        Schema::table('track_votes', function (Blueprint $table) {
            // Optimize vote counting queries
            $table->index(['track_id', 'created_at'], 'idx_votes_track_time');
            
            // Optimize user vote history queries
            $table->index(['user_id', 'created_at'], 'idx_votes_user_time');
        });

        Schema::table('room_participants', function (Blueprint $table) {
            // Optimize participant queries
            $table->index(['room_id', 'joined_at'], 'idx_participants_room_time');
            
            // Optimize user room queries
            $table->index(['user_id', 'joined_at'], 'idx_participants_user_time');
        });

        Schema::table('rooms', function (Blueprint $table) {
            // Optimize room listing queries
            $table->index(['created_at', 'name'], 'idx_rooms_time_name');
            
            // Optimize active room queries
            $table->index(['is_playing', 'updated_at'], 'idx_rooms_playing_updated');
            
            // Optimize current track queries
            $table->index('current_track_id', 'idx_rooms_current_track');
        });

        Schema::table('users', function (Blueprint $table) {
            // Optimize user lookup queries
            $table->index('email', 'idx_users_email');
            $table->index('username', 'idx_users_username');
            $table->index('created_at', 'idx_users_created');
        });

        // Create partial indexes for PostgreSQL-specific optimizations
        if (DB::getDriverName() === 'pgsql') {
            // Partial index for active rooms only
            DB::statement('CREATE INDEX CONCURRENTLY idx_rooms_active ON rooms (updated_at DESC) WHERE is_playing = true');
            
            // Partial index for tracks with votes
            DB::statement('CREATE INDEX CONCURRENTLY idx_tracks_voted ON tracks (room_id, vote_score DESC, created_at ASC) WHERE vote_score > 0');
        }
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('tracks', function (Blueprint $table) {
            $table->dropIndex('idx_tracks_queue_order');
            $table->dropIndex('idx_tracks_uploader_time');
            $table->dropIndex('idx_tracks_file_path');
        });

        Schema::table('track_votes', function (Blueprint $table) {
            $table->dropIndex('idx_votes_track_time');
            $table->dropIndex('idx_votes_user_time');
        });

        Schema::table('room_participants', function (Blueprint $table) {
            $table->dropIndex('idx_participants_room_time');
            $table->dropIndex('idx_participants_user_time');
        });

        Schema::table('rooms', function (Blueprint $table) {
            $table->dropIndex('idx_rooms_time_name');
            $table->dropIndex('idx_rooms_playing_updated');
            $table->dropIndex('idx_rooms_current_track');
        });

        Schema::table('users', function (Blueprint $table) {
            $table->dropIndex('idx_users_email');
            $table->dropIndex('idx_users_username');
            $table->dropIndex('idx_users_created');
        });

        // Drop PostgreSQL partial indexes
        if (DB::getDriverName() === 'pgsql') {
            DB::statement('DROP INDEX CONCURRENTLY IF EXISTS idx_rooms_active');
            DB::statement('DROP INDEX CONCURRENTLY IF EXISTS idx_tracks_voted');
        }
    }
};