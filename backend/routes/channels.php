<?php

use Illuminate\Support\Facades\Broadcast;
use App\Models\Room;
use App\Models\User;

/*
|--------------------------------------------------------------------------
| Broadcast Channels
|--------------------------------------------------------------------------
|
| Here you may register all of the event broadcasting channels that your
| application supports. The given channel authorization callbacks are
| used to check if an authenticated user can listen to the channel.
|
*/

Broadcast::channel('App.Models.User.{id}', function ($user, $id) {
    return (int) $user->id === (int) $id;
});

// Room channel authorization - only room participants can listen
Broadcast::channel('room.{roomId}', function (User $user, string $roomId) {
    try {
        \Illuminate\Support\Facades\Log::info("Authorizing room channel for user: {$user->id}, room: {$roomId}");
        
        $room = Room::find($roomId);
        
        if (!$room) {
            \Illuminate\Support\Facades\Log::warning("Room not found: {$roomId}");
            return false;
        }
        
        // Check if user is a participant in the room
        $isParticipant = $room->participants()->where('user_id', $user->id)->exists();
        \Illuminate\Support\Facades\Log::info("Is participant: " . ($isParticipant ? 'yes' : 'no'));
        
        return $isParticipant;
    } catch (\Exception $e) {
        \Illuminate\Support\Facades\Log::error("Error in room channel auth: " . $e->getMessage());
        return false;
    }
});