<?php

namespace App\Policies;

use App\Models\Room;
use App\Models\User;

class RoomPolicy
{
    /**
     * Determine whether the user can view any rooms.
     */
    public function viewAny(User $user): bool
    {
        // All authenticated users can view rooms
        return true;
    }

    /**
     * Determine whether the user can view the room.
     */
    public function view(User $user, Room $room): bool
    {
        // All authenticated users can view room details
        return true;
    }

    /**
     * Determine whether the user can create rooms.
     */
    public function create(User $user): bool
    {
        // All authenticated users can create rooms
        return true;
    }

    /**
     * Determine whether the user can update the room.
     */
    public function update(User $user, Room $room): bool
    {
        // Only room administrator can update room
        return $room->isAdministratedBy($user);
    }

    /**
     * Determine whether the user can delete the room.
     */
    public function delete(User $user, Room $room): bool
    {
        // Only room administrator can delete room
        return $room->isAdministratedBy($user);
    }

    /**
     * Determine whether the user can join the room.
     */
    public function join(User $user, Room $room): bool
    {
        // Users can join if they're not already participants
        return !$room->hasParticipant($user);
    }

    /**
     * Determine whether the user can leave the room.
     */
    public function leave(User $user, Room $room): bool
    {
        // Users can leave if they're participants but not administrators
        return $room->hasParticipant($user) && !$room->isAdministratedBy($user);
    }

    /**
     * Determine whether the user can control playback in the room.
     */
    public function controlPlayback(User $user, Room $room): bool
    {
        // Only room administrator can control playback
        return $room->isAdministratedBy($user);
    }

    /**
     * Determine whether the user can manage tracks in the room.
     */
    public function manageTracks(User $user, Room $room): bool
    {
        // Only room administrator can manage tracks (delete, reorder)
        return $room->isAdministratedBy($user);
    }

    /**
     * Determine whether the user can upload tracks to the room.
     */
    public function uploadTracks(User $user, Room $room): bool
    {
        // All room participants can upload tracks
        return $room->hasParticipant($user);
    }

    /**
     * Determine whether the user can vote on tracks in the room.
     */
    public function vote(User $user, Room $room): bool
    {
        // All room participants can vote on tracks
        return $room->hasParticipant($user);
    }
}