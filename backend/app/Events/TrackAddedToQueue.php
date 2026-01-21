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

class TrackAddedToQueue implements ShouldBroadcast
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public $track;
    public $room;

    /**
     * Create a new event instance.
     */
    public function __construct(Track $track, Room $room)
    {
        $this->track = $track;
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
        return 'track.added';
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
                'vote_score' => $this->track->vote_score,
                'uploader' => [
                    'id' => $this->track->uploader->id,
                    'username' => $this->track->uploader->username,
                ],
            ],
            'room_id' => $this->room->id,
            'timestamp' => now()->toISOString(),
        ];
    }
}