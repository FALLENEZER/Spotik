<?php

namespace App\Events;

use App\Models\Track;
use App\Models\Room;
use Illuminate\Broadcasting\Channel;
use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PresenceChannel;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcast;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class TrackSkipped implements ShouldBroadcast
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public $skippedTrack;
    public $nextTrack;
    public $room;

    /**
     * Create a new event instance.
     */
    public function __construct(Track $skippedTrack, Room $room, Track $nextTrack = null)
    {
        $this->skippedTrack = $skippedTrack;
        $this->nextTrack = $nextTrack;
        $this->room = $room;
    }

    /**
     * Get the channels the event should broadcast on.
     *
     * @return array<int, \Illuminate\Broadcasting\Channel>
     */
    public function broadcastOn(): array
    {
        return [
            new PrivateChannel('room.' . $this->room->id),
        ];
    }

    /**
     * The event's broadcast name.
     */
    public function broadcastAs(): string
    {
        return 'track.skipped';
    }

    /**
     * Get the data to broadcast.
     */
    public function broadcastWith(): array
    {
        $data = [
            'skipped_track' => [
                'id' => $this->skippedTrack->id,
                'filename' => $this->skippedTrack->filename,
                'original_name' => $this->skippedTrack->original_name,
            ],
            'room_id' => $this->room->id,
            'timestamp' => now()->toISOString(),
        ];

        if ($this->nextTrack) {
            $data['next_track'] = [
                'id' => $this->nextTrack->id,
                'filename' => $this->nextTrack->filename,
                'original_name' => $this->nextTrack->original_name,
                'duration_seconds' => $this->nextTrack->duration_seconds,
                'file_path' => $this->nextTrack->file_path,
            ];
        }

        return $data;
    }
}