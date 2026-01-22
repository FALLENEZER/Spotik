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
            $user = $request->user();

            if (!$room->isAdministratedBy($user)) {
                return response()->json([
                    'error' => 'Only room administrators can update the cover'
                ], 403);
            }

            $validator = Validator::make($request->all(), [
                'cover_image' => [
                    'required',
                    'image',
                    'mimes:jpg,jpeg,png,webp',
                    'max:5120', // 5 MB
                ],
            ]);

            if ($validator->fails()) {
                return response()->json([
                    'error' => 'Validation failed',
                    'errors' => $validator->errors(),
                ], 422);
            }

            $image = $request->file('cover_image');
            $ext = strtolower($image->getClientOriginalExtension());

            // Remove previous cover variants if exist
            foreach (['jpg', 'jpeg', 'png', 'webp'] as $candidate) {
                $candidatePath = "room_covers/{$room->id}.{$candidate}";
                if (Storage::disk('public')->exists($candidatePath)) {
                    Storage::disk('public')->delete($candidatePath);
                }
            }

            $path = "room_covers/{$room->id}.{$ext}";
            Storage::disk('public')->putFileAs('room_covers', $image, "{$room->id}.{$ext}");

            $coverUrl = "/api/storage/{$path}";

            return response()->json([
                'message' => 'Room cover updated successfully',
                'cover_url' => $coverUrl,
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'error' => 'Failed to update room cover',
                'message' => config('app.debug') ? $e->getMessage() : 'Internal server error',
            ], 500);
        }
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
