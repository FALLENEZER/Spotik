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
        Schema::table('rooms', function (Blueprint $table) {
            // Add foreign key constraint for current_track_id
            $table->foreign('current_track_id')->references('id')->on('tracks')->onDelete('set null');
            
            // Add index for current_track_id
            $table->index('current_track_id');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('rooms', function (Blueprint $table) {
            $table->dropForeign(['current_track_id']);
            $table->dropIndex(['current_track_id']);
        });
    }
};