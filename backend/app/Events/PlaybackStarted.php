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

class PlaybackStarted implements ShouldBroadcast
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public $track;
    public $room;
    public $startedAt;

    /**
     * Create a new event instance.
     */
    public function __construct(Track $track, Room $room, $startedAt = null)
    {
        $this->track = $track;
        $this->room = $room;
        $this->startedAt = $startedAt ?: now();
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
        return 'playback.started';
    }

    /**
     * Get the data to broadcast.
     */
    public function broadcastWith(): array
    {
        return [
            'track' => [
                'id' => $this->track->id,
                'filename' => $this->track->filename,
                'original_name' => $this->track->original_name,
                'duration_seconds' => $this->track->duration_seconds,
                'file_path' => $this->track->file_path,
            ],
            'room_id' => $this->room->id,
            'started_at' => $this->startedAt->toISOString(),
            'server_time' => now()->toISOString(),
        ];
    }
}