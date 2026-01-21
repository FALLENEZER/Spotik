<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class RoomParticipantResource extends JsonResource
{
    /**
     * Transform the resource into an array.
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'joined_at' => $this->joined_at->toISOString(),
            'duration_in_room' => $this->getDurationInRoom(),
            'is_administrator' => $this->isAdministrator(),
            
            // User relationship
            'user' => new UserResource($this->whenLoaded('user')),
        ];
    }
}