<?php

namespace App\Http\Controllers;

use App\Models\Room;
use App\Models\Track;
use App\Events\PlaybackStarted;
use App\Events\PlaybackPaused;
use App\Events\PlaybackResumed;
use App\Events\TrackSkipped;
use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Gate;

class PlaybackController extends Controller
{
    /**
     * Start playing a track
     */
    public function start(Request $request, Room $room, Track $track): JsonResponse
    {
        try {
            $user = $request->auth_user;

            // Check if user is room administrator
            if (!$room->isAdministratedBy($user)) {
                return response()->json([
                    'success' => false,
                    'message' => 'Only room administrator can control playback',
                    'error' => 'Insufficient permissions'
                ], 403);
            }

            // Check if track belongs to the room
            if ($track->room_id !== $room->id) {
                return response()->json([
                    'success' => false,
                    'message' => 'Track does not belong to this room',
                    'error' => 'Invalid track'
                ], 404);
            }

            // Start playback
            $startedAt = now();
            $room->update([
                'current_track_id' => $track->id,
                'playback_started_at' => $startedAt,
                'playback_paused_at' => null,
                'is_playing' => true,
            ]);

            // Broadcast playback started event
            broadcast(new PlaybackStarted($track, $room, $startedAt));

            return response()->json([
                'success' => true,
                'message' => 'Playback started successfully',
                'data' => [
                    'track_id' => $track->id,
                    'started_at' => $startedAt->toISOString(),
                    'server_time' => now()->toISOString(),
                ]
            ]);

        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to start playback',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Pause current playback
     */
    public function pause(Request $request, Room $room): JsonResponse
    {
        try {
            $user = $request->auth_user;

            // Check if user is room administrator
            if (!$room->isAdministratedBy($user)) {
                return response()->json([
                    'success' => false,
                    'message' => 'Only room administrator can control playback',
                    'error' => 'Insufficient permissions'
                ], 403);
            }

            // Check if there's a current track playing
            if (!$room->current_track_id || !$room->is_playing) {
                return response()->json([
                    'success' => false,
                    'message' => 'No track is currently playing',
                    'error' => 'No active playback'
                ], 400);
            }

            $currentTrack = $room->currentTrack;
            $pausedAt = now();
            
            // Calculate current position
            $position = null;
            if ($room->playback_started_at) {
                $position = $room->playback_started_at->diffInSeconds($pausedAt);
            }

            // Pause playback
            $room->update([
                'playback_paused_at' => $pausedAt,
                'is_playing' => false,
            ]);

            // Broadcast playback paused event
            broadcast(new PlaybackPaused($currentTrack, $room, $pausedAt, $position));

            return response()->json([
                'success' => true,
                'message' => 'Playback paused successfully',
                'data' => [
                    'track_id' => $currentTrack->id,
                    'paused_at' => $pausedAt->toISOString(),
                    'position' => $position,
                    'server_time' => now()->toISOString(),
                ]
            ]);

        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to pause playback',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Resume paused playback
     */
    public function resume(Request $request, Room $room): JsonResponse
    {
        try {
            $user = $request->auth_user;

            // Check if user is room administrator
            if (!$room->isAdministratedBy($user)) {
                return response()->json([
                    'success' => false,
                    'message' => 'Only room administrator can control playback',
                    'error' => 'Insufficient permissions'
                ], 403);
            }

            // Check if there's a paused track
            if (!$room->current_track_id || $room->is_playing || !$room->playback_paused_at) {
                return response()->json([
                    'success' => false,
                    'message' => 'No track is currently paused',
                    'error' => 'No paused playback'
                ], 400);
            }

            $currentTrack = $room->currentTrack;
            $resumedAt = now();
            
            // Calculate pause duration and adjust start time
            $pauseDuration = $resumedAt->diffInSeconds($room->playback_paused_at);
            $newStartTime = $room->playback_started_at->addSeconds($pauseDuration);
            
            // Calculate current position
            $position = $room->playback_started_at->diffInSeconds($room->playback_paused_at);

            // Resume playback
            $room->update([
                'playback_started_at' => $newStartTime,
                'playback_paused_at' => null,
                'is_playing' => true,
            ]);

            // Broadcast playback resumed event
            broadcast(new PlaybackResumed($currentTrack, $room, $resumedAt, $position));

            return response()->json([
                'success' => true,
                'message' => 'Playback resumed successfully',
                'data' => [
                    'track_id' => $currentTrack->id,
                    'resumed_at' => $resumedAt->toISOString(),
                    'position' => $position,
                    'server_time' => now()->toISOString(),
                ]
            ]);

        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to resume playback',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Skip to next track
     */
    public function skip(Request $request, Room $room): JsonResponse
    {
        try {
            $user = $request->auth_user;

            // Check if user is room administrator
            if (!$room->isAdministratedBy($user)) {
                return response()->json([
                    'success' => false,
                    'message' => 'Only room administrator can control playback',
                    'error' => 'Insufficient permissions'
                ], 403);
            }

            // Check if there's a current track
            if (!$room->current_track_id) {
                return response()->json([
                    'success' => false,
                    'message' => 'No track is currently playing',
                    'error' => 'No active track'
                ], 400);
            }

            $currentTrack = $room->currentTrack;
            
            // Get next track in queue
            $nextTrack = $room->trackQueue()
                             ->where('id', '!=', $currentTrack->id)
                             ->first();

            // Stop current playback
            $room->update([
                'current_track_id' => $nextTrack ? $nextTrack->id : null,
                'playback_started_at' => $nextTrack ? now() : null,
                'playback_paused_at' => null,
                'is_playing' => $nextTrack ? true : false,
            ]);

            // Broadcast track skipped event
            broadcast(new TrackSkipped($currentTrack, $room, $nextTrack));

            // If there's a next track, also broadcast playback started
            if ($nextTrack) {
                broadcast(new PlaybackStarted($nextTrack, $room));
            }

            return response()->json([
                'success' => true,
                'message' => 'Track skipped successfully',
                'data' => [
                    'skipped_track_id' => $currentTrack->id,
                    'next_track_id' => $nextTrack ? $nextTrack->id : null,
                    'server_time' => now()->toISOString(),
                ]
            ]);

        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to skip track',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Stop playback
     */
    public function stop(Request $request, Room $room): JsonResponse
    {
        try {
            $user = $request->auth_user;

            // Check if user is room administrator
            if (!$room->isAdministratedBy($user)) {
                return response()->json([
                    'success' => false,
                    'message' => 'Only room administrator can control playback',
                    'error' => 'Insufficient permissions'
                ], 403);
            }

            $currentTrack = $room->currentTrack;

            // Stop playback
            $room->update([
                'current_track_id' => null,
                'playback_started_at' => null,
                'playback_paused_at' => null,
                'is_playing' => false,
            ]);

            // If there was a current track, broadcast paused event
            if ($currentTrack) {
                broadcast(new PlaybackPaused($currentTrack, $room));
            }

            return response()->json([
                'success' => true,
                'message' => 'Playback stopped successfully',
                'data' => [
                    'server_time' => now()->toISOString(),
                ]
            ]);

        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to stop playback',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Get current playback status
     */
    public function status(Request $request, Room $room): JsonResponse
    {
        try {
            $user = $request->auth_user;

            // Check if user is participant of the room
            if (!$room->hasParticipant($user)) {
                return response()->json([
                    'success' => false,
                    'message' => 'You must be a participant of this room to view playback status',
                    'error' => 'Not a participant'
                ], 403);
            }

            $currentTrack = $room->currentTrack;
            $position = null;

            // Calculate current position if playing
            if ($room->is_playing && $room->playback_started_at) {
                $position = $room->playback_started_at->diffInSeconds(now());
            } elseif (!$room->is_playing && $room->playback_paused_at && $room->playback_started_at) {
                $position = $room->playback_started_at->diffInSeconds($room->playback_paused_at);
            }

            return response()->json([
                'success' => true,
                'message' => 'Playback status retrieved successfully',
                'data' => [
                    'is_playing' => $room->is_playing,
                    'current_track' => $currentTrack ? [
                        'id' => $currentTrack->id,
                        'filename' => $currentTrack->filename,
                        'original_name' => $currentTrack->original_name,
                        'duration_seconds' => $currentTrack->duration_seconds,
                        'file_path' => $currentTrack->file_path,
                    ] : null,
                    'position' => $position,
                    'started_at' => $room->playback_started_at?->toISOString(),
                    'paused_at' => $room->playback_paused_at?->toISOString(),
                    'server_time' => now()->toISOString(),
                ]
            ]);

        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to get playback status',
                'error' => $e->getMessage()
            ], 500);
        }
    }
}