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
        Schema::create('rooms', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('name', 100);
            $table->uuid('administrator_id');
            $table->uuid('current_track_id')->nullable();
            $table->timestamp('playback_started_at')->nullable();
            $table->timestamp('playback_paused_at')->nullable();
            $table->boolean('is_playing')->default(false);
            $table->timestamps();
            
            // Foreign key constraints
            $table->foreign('administrator_id')->references('id')->on('users')->onDelete('cascade');
            
            // Indexes for performance
            $table->index('administrator_id');
            $table->index('name');
            $table->index('is_playing');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('rooms');
    }
};