<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| API Routes
|--------------------------------------------------------------------------
*/

// Health check and monitoring endpoints
Route::get('/ping', [App\Http\Controllers\HealthController::class, 'ping']);
Route::get('/health', [App\Http\Controllers\HealthController::class, 'health']);
Route::get('/metrics', [App\Http\Controllers\HealthController::class, 'metrics']);

// Time synchronization endpoint
Route::get('/time', function () {
    return response()->json([
        'timestamp' => now()->toISOString(),
        'unix_timestamp' => now()->timestamp,
        'timezone' => config('app.timezone')
    ]);
});

// Public routes (no authentication required)
Route::prefix('auth')->group(function () {
    Route::post('/register', [App\Http\Controllers\AuthController::class, 'register']);
    Route::post('/login', [App\Http\Controllers\AuthController::class, 'login']);
    Route::post('/refresh', [App\Http\Controllers\AuthController::class, 'refresh']);
    Route::post('/logout', [App\Http\Controllers\AuthController::class, 'logout']);
});

// Protected routes (authentication required)
Route::middleware(['jwt.custom', 'performance.monitoring'])->group(function () {
    
    // Authentication routes
    Route::prefix('auth')->group(function () {
        Route::get('/me', [App\Http\Controllers\AuthController::class, 'me']);
    });

    // Room management routes
    Route::prefix('rooms')->group(function () {
        Route::get('/', [App\Http\Controllers\RoomController::class, 'index']);
        Route::post('/', [App\Http\Controllers\RoomController::class, 'store']);
        Route::get('/{room}', [App\Http\Controllers\RoomController::class, 'show']);
        Route::put('/{room}', [App\Http\Controllers\RoomController::class, 'update']);
        Route::delete('/{room}', [App\Http\Controllers\RoomController::class, 'destroy']);
        
        // Room participation
        Route::post('/{room}/join', [App\Http\Controllers\RoomController::class, 'join']);
        Route::post('/{room}/leave', [App\Http\Controllers\RoomController::class, 'leave']);
        Route::get('/{room}/participants', [App\Http\Controllers\RoomController::class, 'participants']);
        
        // Track management within rooms
        Route::get('/{room}/tracks', [App\Http\Controllers\TrackController::class, 'index']);
        Route::post('/{room}/tracks', [App\Http\Controllers\TrackController::class, 'store']);
        Route::delete('/{room}/tracks/{track}', [App\Http\Controllers\TrackController::class, 'destroy']);
        
        // Track voting
        Route::post('/{room}/tracks/{track}/vote', [App\Http\Controllers\VoteController::class, 'vote']);
        Route::delete('/{room}/tracks/{track}/vote', [App\Http\Controllers\VoteController::class, 'unvote']);
        
        // Playback control (admin only)
        Route::post('/{room}/tracks/{track}/play', [App\Http\Controllers\PlaybackController::class, 'start']);
        Route::post('/{room}/playback/pause', [App\Http\Controllers\PlaybackController::class, 'pause']);
        Route::post('/{room}/playback/resume', [App\Http\Controllers\PlaybackController::class, 'resume']);
        Route::post('/{room}/playback/skip', [App\Http\Controllers\PlaybackController::class, 'skip']);
        Route::post('/{room}/playback/stop', [App\Http\Controllers\PlaybackController::class, 'stop']);
        Route::get('/{room}/playback/status', [App\Http\Controllers\PlaybackController::class, 'status']);
    });

    // File serving routes (optimized for performance)
    Route::get('/audio/{filename}', [App\Http\Controllers\FileController::class, 'serve'])
        ->where('filename', '.*');
    Route::get('/audio/{filename}/metadata', [App\Http\Controllers\FileController::class, 'metadata'])
        ->where('filename', '.*');
    
    // Track streaming routes
    Route::get('/tracks/{track}/stream', [App\Http\Controllers\TrackController::class, 'stream']);
});

// WebSocket broadcasting routes
Route::middleware(['jwt.custom'])->prefix('broadcasting')->group(function () {
    Route::post('/auth', [App\Http\Controllers\BroadcastController::class, 'authenticate']);
});