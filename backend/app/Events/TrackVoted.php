<?php

namespace App\Events;

use App\Models\Track;
use App\Models\User;
use App\Models\Room;
use Illuminate\Broadcasting\Channel;
use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PresenceChannel;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcast;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class TrackVoted implements ShouldBroadcast
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public $track;
    public $user;
    public $room;
    public $voteAdded;

    /**
     * Create a new event instance.
     */
    public function __construct(Track $track, User $user, Room $room, bool $voteAdded)
    {
        $this->track = $track;
        $this->user = $user;
        $this->room = $room;
        $this->voteAdded = $voteAdded;
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
        return 'track.voted';
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
                'vote_score' => $this->track->vote_score,
            ],
            'user' => [
                'id' => $this->user->id,
                'username' => $this->user->username,
            ],
            'vote_added' => $this->voteAdded,
            'room_id' => $this->room->id,
            'timestamp' => now()->toISOString(),
        ];
    }
}