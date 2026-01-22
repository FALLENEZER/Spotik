<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Facades\Storage;

class RoomResource extends JsonResource
{
    /**
     * Transform the resource into an array.
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'is_playing' => $this->is_playing,
            'playback_started_at' => $this->playback_started_at?->toISOString(),
            'playback_paused_at' => $this->playback_paused_at?->toISOString(),
            'current_playback_position' => $this->getCurrentPlaybackPosition(),
            'created_at' => $this->created_at->toISOString(),
            'updated_at' => $this->updated_at->toISOString(),
            
            // Relationships
            'administrator' => new UserResource($this->whenLoaded('administrator')),
            'current_track' => new TrackResource($this->whenLoaded('currentTrack')),
            'participants' => RoomParticipantResource::collection($this->whenLoaded('participants')),
            'track_queue' => TrackResource::collection($this->whenLoaded('trackQueue')),
            
            // Computed fields
            'participant_count' => $this->when(
                $this->relationLoaded('participants'),
                fn() => $this->participants->count()
            ),
            'cover_url' => (function () {
                foreach (['jpg', 'jpeg', 'png', 'webp'] as $ext) {
                    $path = "room_covers/{$this->id}.{$ext}";
                    if (Storage::disk('public')->exists($path)) {
                        return "/api/storage/{$path}";
                    }
                }
                return null;
            })(),
            'is_administrator' => $this->when(
                $request->auth_user,
                fn() => $this->isAdministratedBy($request->auth_user)
            ),
            'is_participant' => $this->when(
                $request->auth_user,
                fn() => $this->hasParticipant($request->auth_user)
            ),
        ];
    }
}
