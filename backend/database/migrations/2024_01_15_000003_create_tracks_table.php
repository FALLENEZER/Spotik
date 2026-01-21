<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('tracks', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('room_id');
            $table->uuid('uploader_id');
            $table->string('filename', 255);
            $table->string('original_name', 255);
            $table->string('file_path', 500);
            $table->integer('duration_seconds');
            $table->bigInteger('file_size_bytes');
            $table->string('mime_type', 100);
            $table->integer('vote_score')->default(0);
            $table->timestamps();
            
            // Foreign key constraints
            $table->foreign('room_id')->references('id')->on('rooms')->onDelete('cascade');
            $table->foreign('uploader_id')->references('id')->on('users')->onDelete('cascade');
            
            // Indexes for performance - critical for queue ordering
            $table->index(['room_id', 'vote_score', 'created_at'], 'idx_tracks_room_score');
            $table->index('room_id');
            $table->index('uploader_id');
            $table->index('vote_score');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('tracks');
    }
};