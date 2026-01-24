<?php

namespace App\Http\Controllers;

use App\Models\Playlist;
use App\Models\Track;
use App\Http\Resources\PlaylistResource;
use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Validator;

class PlaylistController extends Controller
{
    /**
     * Display a listing of playlists.
     */
    public function index(Request $request): JsonResponse
    {
        try {
            $user = $request->user();
            
            // Get user's playlists and public playlists
            $playlists = Playlist::with(['user', 'tracks'])
                               ->where(function($query) use ($user) {
                                   $query->where('user_id', $user->id)
                                         ->orWhere('is_public', true);
                               })
                               ->withCount('tracks')
                               ->orderBy('created_at', 'desc')
                               ->get();

            return response()->json([
                'success' => true,
                'message' => 'Playlists retrieved successfully',
                'data' => PlaylistResource::collection($playlists)
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to retrieve playlists',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Store a newly created playlist.
     */
    public function store(Request $request): JsonResponse
    {
        try {
            $user = $request->user();

            $validator = Validator::make($request->all(), [
                'name' => 'required|string|max:100',
                'description' => 'nullable|string|max:1000',
                'is_public' => 'boolean',
            ]);

            if ($validator->fails()) {
                return response()->json([
                    'success' => false,
                    'message' => 'Validation failed',
                    'errors' => $validator->errors()
                ], 422);
            }

            $playlist = Playlist::create([
                'name' => $request->name,
                'description' => $request->description,
                'is_public' => $request->get('is_public', false),
                'user_id' => $user->id,
            ]);

            $playlist->load(['user', 'tracks']);
            $playlist->loadCount('tracks');

            return response()->json([
                'success' => true,
                'message' => 'Playlist created successfully',
                'data' => new PlaylistResource($playlist)
            ], 201);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to create playlist',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Display the specified playlist.
     */
    public function show(Request $request, Playlist $playlist): JsonResponse
    {
        try {
            $user = $request->user();

            // Check if user can view this playlist
            if (!$playlist->is_public && $playlist->user_id !== $user->id) {
                return response()->json([
                    'success' => false,
                    'message' => 'Unauthorized to view this playlist',
                    'error' => 'Access denied'
                ], 403);
            }

            $playlist->load(['user', 'tracks.uploader', 'tracks.genre']);
            $playlist->loadCount('tracks');

            return response()->json([
                'success' => true,
                'message' => 'Playlist retrieved successfully',
                'data' => new PlaylistResource($playlist)
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to retrieve playlist',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Update the specified playlist.
     */
    public function update(Request $request, Playlist $playlist): JsonResponse
    {
        try {
            $user = $request->user();

            // Check if user owns this playlist
            if ($playlist->user_id !== $user->id) {
                return response()->json([
                    'success' => false,
                    'message' => 'Unauthorized to update this playlist',
                    'error' => 'Access denied'
                ], 403);
            }

            $validator = Validator::make($request->all(), [
                'name' => 'sometimes|string|max:100',
                'description' => 'nullable|string|max:1000',
                'is_public' => 'boolean',
            ]);

            if ($validator->fails()) {
                return response()->json([
                    'success' => false,
                    'message' => 'Validation failed',
                    'errors' => $validator->errors()
                ], 422);
            }

            $playlist->update($request->only(['name', 'description', 'is_public']));
            $playlist->load(['user', 'tracks']);

            return response()->json([
                'success' => true,
                'message' => 'Playlist updated successfully',
                'data' => new PlaylistResource($playlist)
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to update playlist',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Remove the specified playlist.
     */
    public function destroy(Request $request, Playlist $playlist): JsonResponse
    {
        try {
            $user = $request->user();

            // Check if user owns this playlist
            if ($playlist->user_id !== $user->id) {
                return response()->json([
                    'success' => false,
                    'message' => 'Unauthorized to delete this playlist',
                    'error' => 'Access denied'
                ], 403);
            }

            $playlist->delete();

            return response()->json([
                'success' => true,
                'message' => 'Playlist deleted successfully'
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to delete playlist',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Add track to playlist
     */
    public function addTrack(Request $request, Playlist $playlist): JsonResponse
    {
        try {
            $user = $request->user();

            // Check if user owns this playlist
            if ($playlist->user_id !== $user->id) {
                return response()->json([
                    'success' => false,
                    'message' => 'Unauthorized to modify this playlist',
                    'error' => 'Access denied'
                ], 403);
            }

            $validator = Validator::make($request->all(), [
                'track_id' => 'required|uuid|exists:tracks,id',
                'position' => 'nullable|integer|min:0',
            ]);

            if ($validator->fails()) {
                return response()->json([
                    'success' => false,
                    'message' => 'Validation failed',
                    'errors' => $validator->errors()
                ], 422);
            }

            $track = Track::findOrFail($request->track_id);

            // Check if track is already in playlist
            if ($playlist->tracks()->where('track_id', $track->id)->exists()) {
                return response()->json([
                    'success' => false,
                    'message' => 'Track is already in playlist',
                    'error' => 'Duplicate track'
                ], 409);
            }

            $playlist->addTrack($track, $request->position);

            return response()->json([
                'success' => true,
                'message' => 'Track added to playlist successfully'
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to add track to playlist',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Remove track from playlist
     */
    public function removeTrack(Request $request, Playlist $playlist, Track $track): JsonResponse
    {
        try {
            $user = $request->user();

            // Check if user owns this playlist
            if ($playlist->user_id !== $user->id) {
                return response()->json([
                    'success' => false,
                    'message' => 'Unauthorized to modify this playlist',
                    'error' => 'Access denied'
                ], 403);
            }

            $removed = $playlist->removeTrack($track);

            if (!$removed) {
                return response()->json([
                    'success' => false,
                    'message' => 'Track not found in playlist',
                    'error' => 'Track not in playlist'
                ], 404);
            }

            return response()->json([
                'success' => true,
                'message' => 'Track removed from playlist successfully'
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to remove track from playlist',
                'error' => $e->getMessage()
            ], 500);
        }
    }
}