<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class TrackResource extends JsonResource
{
    /**
     * Transform the resource into an array.
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'filename' => $this->filename,
            'original_name' => $this->original_name,
            'duration_seconds' => $this->duration_seconds,
            'file_size_bytes' => $this->file_size_bytes,
            'mime_type' => $this->mime_type,
            'vote_score' => $this->vote_score,
            'created_at' => $this->created_at->toISOString(),
            'updated_at' => $this->updated_at->toISOString(),
            
            // Relationships
            'uploader' => new UserResource($this->whenLoaded('uploader')),
            'room' => new RoomResource($this->whenLoaded('room')),
            
            // Computed fields
            'has_voted' => $this->when(
                $request->auth_user,
                fn() => $this->votes()->where('user_id', $request->auth_user->id)->exists()
            ),
        ];
    }
}