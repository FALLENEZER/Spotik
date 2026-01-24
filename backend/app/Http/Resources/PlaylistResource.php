<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class PlaylistResource extends JsonResource
{
    /**
     * Transform the resource into an array.
     *
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $user = $request->user();
        
        return [
            'id' => $this->id,
            'name' => $this->name,
            'description' => $this->description,
            'is_public' => $this->is_public,
            'is_owner' => $user && $this->user_id === $user->id,
            'user' => new UserResource($this->whenLoaded('user')),
            'tracks_count' => $this->when(
                $this->relationLoaded('tracks') || isset($this->tracks_count),
                $this->tracks_count ?? $this->tracks->count()
            ),
            'total_duration' => $this->when(
                $this->relationLoaded('tracks'),
                $this->total_duration
            ),
            'tracks' => TrackResource::collection($this->whenLoaded('tracks')),
            'created_at' => $this->created_at,
            'updated_at' => $this->updated_at,
        ];
    }
}