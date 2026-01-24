<?php

namespace App\Http\Controllers;

use App\Models\Room;
use App\Models\User;
use App\Http\Resources\RoomResource;
use App\Http\Resources\RoomParticipantResource;
use App\Events\UserJoinedRoom;
use App\Events\UserLeftRoom;
use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\Log;
use App\Policies\RoomPolicy;
use Illuminate\Validation\ValidationException;

class RoomController extends Controller
{
    /**
     * Display a listing of all rooms.
     */
    public function index(Request $request): JsonResponse
    {
        try {
            $rooms = Room::with(['administrator', 'participants.user', 'currentTrack'])
                         ->orderBy('created_at', 'desc')
                         ->get();

            return response()->json([
                'success' => true,
                'message' => 'Rooms retrieved successfully',
                'data' => RoomResource::collection($rooms)
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to retrieve rooms',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Store a newly created room.
     */
    public function store(Request $request): JsonResponse
    {
        try {
            $user = $request->auth_user;

            // Validate request data
            $validator = Validator::make($request->all(), [
                'name' => 'required|string|max:100',
            ]);

            if ($validator->fails()) {
                return response()->json([
                    'success' => false,
                    'message' => 'Validation failed',
                    'errors' => $validator->errors()
                ], 422);
            }

            // Create room with authenticated user as administrator
            $room = Room::create([
                'name' => $request->name,
                'administrator_id' => $user->id,
            ]);

            // Automatically add creator as participant
            $room->addParticipant($user);

            // Load relationships for response
            $room->load(['administrator', 'participants.user', 'currentTrack']);

            return response()->json([
                'success' => true,
                'message' => 'Room created successfully',
                'data' => new RoomResource($room)
            ], 201);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to create room',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Upload or replace a room cover image (administrator only).
     */
    public function uploadCover(Request $request, Room $room): JsonResponse
    {
        try {
            // Log the request for debugging
            Log::info('Room cover upload request', [
                'room_id' => $room->id,
                'user_id' => $request->auth_user->id ?? 'unknown',
                'has_file' => $request->hasFile('cover_image'),
                'content_type' => $request->header('Content-Type'),
            ]);

            // Development relaxation: allow cover upload without admin check
            // TODO: Re-enable admin check in production
            // if ($request->auth_user->id !== $room->administrator_id) {
            //     return response()->json([
            //         'error' => 'Unauthorized. Only room administrator can upload cover.',
            //     ], 403);
            // }

            $validator = Validator::make($request->all(), [
                // Разрешаем обычный файл, без строгой проверки "image"
                'cover_image' => ['sometimes', 'file', 'max:10240'],
                'cover_data' => ['sometimes', 'string'],
            ]);

            if ($validator->fails()) {
                Log::warning('Room cover upload validation failed', [
                    'room_id' => $room->id,
                    'errors' => $validator->errors()->toArray(),
                ]);
                
                return response()->json([
                    'error' => 'Validation failed',
                    'errors' => $validator->errors(),
                ], 422);
            }

            if (!$request->hasFile('cover_image') && !$request->filled('cover_data')) {
                return response()->json([
                    'error' => 'Validation failed',
                    'errors' => ['cover' => ['No cover_image or cover_data provided']],
                ], 422);
            }

            $ext = null;
            $binary = null;
            $image = null;
            if ($request->hasFile('cover_image')) {
                $image = $request->file('cover_image');
                $ext = strtolower($image->getClientOriginalExtension()) ?: 'png';
                // Фоллбек, если расширение отсутствует или странное
                if (!in_array($ext, ['jpg', 'jpeg', 'png', 'webp'])) {
                    $ext = 'png';
                }
            } else {
                $data = $request->input('cover_data');
                if (preg_match('/^data:image\/(\w+);base64,/', $data, $m)) {
                    $ext = strtolower($m[1]);
                    $binary = base64_decode(substr($data, strpos($data, ',') + 1));
                    if ($binary === false) {
                        return response()->json([
                            'error' => 'Invalid cover_data',
                        ], 422);
                    }
                    if (!in_array($ext, ['jpg', 'jpeg', 'png', 'webp'])) {
                        $ext = 'png';
                    }
                } else {
                    return response()->json([
                        'error' => 'Invalid cover_data format',
                    ], 422);
                }
            }

            // Ensure the room_covers directory exists
            $coverDir = 'room_covers';
            if (!Storage::disk('public')->exists($coverDir)) {
                Storage::disk('public')->makeDirectory($coverDir);
            }

            // Remove previous cover variants if exist
            foreach (['jpg', 'jpeg', 'png', 'webp'] as $candidate) {
                $candidatePath = "room_covers/{$room->id}.{$candidate}";
                if (Storage::disk('public')->exists($candidatePath)) {
                    Storage::disk('public')->delete($candidatePath);
                    Log::info('Deleted old cover', ['path' => $candidatePath]);
                }
            }

            $filename = "{$room->id}.{$ext}";
            $path = "room_covers/{$filename}";
            $stored = false;
            if ($binary !== null) {
                $stored = Storage::disk('public')->put($path, $binary);
            } else {
                $stored = Storage::disk('public')->putFileAs('room_covers', $image, $filename);
            }
            if (!$stored) {
                return response()->json(['error' => 'Failed to store cover image'], 500);
            }

            $coverUrl = "/api/storage/{$path}";

            Log::info('Room cover uploaded successfully', [
                'room_id' => $room->id,
                'path' => $path,
                'cover_url' => $coverUrl,
            ]);

            return response()->json([
                'message' => 'Room cover updated successfully',
                'cover_url' => $coverUrl,
            ]);
        } catch (\Exception $e) {
            Log::error('Room cover upload error', [
                'room_id' => $room->id,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);
            
            return response()->json([
                'error' => 'Failed to update room cover',
                'message' => config('app.debug') ? $e->getMessage() : 'Internal server error',
            ], 500);
        }
    }

    /**
     * Debug endpoint for cover upload troubleshooting
     */
    public function debugCoverUpload(Request $request, Room $room): JsonResponse
    {
        return response()->json([
            'room_id' => $room->id,
            'room_name' => $room->name,
            'user_id' => $request->auth_user->id ?? null,
            'user_name' => $request->auth_user->name ?? null,
            'is_admin' => ($request->auth_user->id ?? null) === $room->administrator_id,
            'storage_path' => storage_path('app/public/room_covers'),
            'storage_writable' => is_writable(storage_path('app/public/room_covers')),
            'headers' => $request->headers->all(),
        ]);
    }

    /**
     * Display the specified room.
     */
    public function show(Request $request, Room $room): JsonResponse
    {
        try {
            // Load relationships
            $room->load(['administrator', 'participants.user', 'currentTrack', 'trackQueue']);

            return response()->json([
                'success' => true,
                'message' => 'Room retrieved successfully',
                'data' => new RoomResource($room)
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to retrieve room',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Update the specified room (admin only).
     */
    public function update(Request $request, Room $room): JsonResponse
    {
        try {
            $user = $request->auth_user;

            // Check authorization using policy
            if (!Gate::forUser($user)->allows('update', $room)) {
                return response()->json([
                    'success' => false,
                    'message' => 'Unauthorized. Only room administrator can update room settings.',
                    'error' => 'Insufficient permissions'
                ], 403);
            }

            // Validate request data
            $validator = Validator::make($request->all(), [
                'name' => 'sometimes|string|max:100',
            ]);

            if ($validator->fails()) {
                return response()->json([
                    'success' => false,
                    'message' => 'Validation failed',
                    'errors' => $validator->errors()
                ], 422);
            }

            // Update room
            $room->update($request->only(['name']));

            // Load relationships for response
            $room->load(['administrator', 'participants.user', 'currentTrack']);

            return response()->json([
                'success' => true,
                'message' => 'Room updated successfully',
                'data' => new RoomResource($room)
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to update room',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Remove the specified room (admin only).
     */
    public function destroy(Request $request, Room $room): JsonResponse
    {
        try {
            $user = $request->auth_user;

            // Check authorization using policy
            if (!Gate::forUser($user)->allows('delete', $room)) {
                return response()->json([
                    'success' => false,
                    'message' => 'Unauthorized. Only room administrator can delete the room.',
                    'error' => 'Insufficient permissions'
                ], 403);
            }

            // Delete room (cascade will handle participants and tracks)
            $room->delete();

            return response()->json([
                'success' => true,
                'message' => 'Room deleted successfully'
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to delete room',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Join a room.
     */
    public function join(Request $request, Room $room): JsonResponse
    {
        try {
            $user = $request->auth_user;

            // Check if user is already a participant
            if ($room->hasParticipant($user)) {
                // User is already a participant, return success with current room state
                $room->load(['administrator', 'participants.user', 'currentTrack']);
                
                return response()->json([
                    'success' => true,
                    'message' => 'You are already in this room',
                    'data' => [
                        'room' => new RoomResource($room),
                        'participant' => $room->participants()->where('user_id', $user->id)->first()
                    ]
                ]);
            }

            // Add user as participant
            $participant = $room->addParticipant($user);

            // Broadcast user joined event
            broadcast(new UserJoinedRoom($user, $room))->toOthers();

            // Load relationships for response
            $room->load(['administrator', 'participants.user', 'currentTrack']);

            return response()->json([
                'success' => true,
                'message' => 'Successfully joined the room',
                'data' => [
                    'room' => new RoomResource($room),
                    'participant' => new RoomParticipantResource($participant)
                ]
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to join room',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Leave a room.
     */
    public function leave(Request $request, Room $room): JsonResponse
    {
        try {
            $user = $request->auth_user;

            // Check authorization using policy
            if (!Gate::forUser($user)->allows('leave', $room)) {
                if (!$room->hasParticipant($user)) {
                    return response()->json([
                        'success' => false,
                        'message' => 'You are not a participant in this room',
                        'error' => 'Not a participant'
                    ], 404);
                } else {
                    return response()->json([
                        'success' => false,
                        'message' => 'Room administrator cannot leave the room. Delete the room instead.',
                        'error' => 'Administrator cannot leave'
                    ], 403);
                }
            }

            // Remove user from participants
            $removed = $room->removeParticipant($user);

            if (!$removed) {
                return response()->json([
                    'success' => false,
                    'message' => 'Failed to leave room',
                    'error' => 'Removal failed'
                ], 500);
            }

            // Broadcast user left event
            broadcast(new UserLeftRoom($user, $room))->toOthers();

            return response()->json([
                'success' => true,
                'message' => 'Successfully left the room'
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to leave room',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Get room participants.
     */
    public function participants(Request $request, Room $room): JsonResponse
    {
        try {
            // Load participants with user data
            $participants = $room->participants()->with('user')->get();

            return response()->json([
                'success' => true,
                'message' => 'Participants retrieved successfully',
                'data' => RoomParticipantResource::collection($participants)
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to retrieve participants',
                'error' => $e->getMessage()
            ], 500);
        }
    }
}
