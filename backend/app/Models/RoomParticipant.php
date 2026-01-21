<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Carbon\Carbon;

class RoomParticipant extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'room_id',
        'user_id',
        'joined_at',
    ];

    protected $casts = [
        'joined_at' => 'datetime',
    ];

    public $timestamps = false;

    /**
     * Validation rules for room participant
     */
    public static function validationRules(): array
    {
        return [
            'room_id' => 'required|uuid|exists:rooms,id',
            'user_id' => 'required|uuid|exists:users,id',
        ];
    }

    /**
     * Room this participation belongs to
     */
    public function room(): BelongsTo
    {
        return $this->belongsTo(Room::class);
    }

    /**
     * User participating in the room
     */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /**
     * Get how long the user has been in the room
     */
    public function getDurationInRoom(): string
    {
        $duration = Carbon::now()->diff($this->joined_at);
        
        if ($duration->days > 0) {
            return $duration->days . ' day' . ($duration->days > 1 ? 's' : '');
        } elseif ($duration->h > 0) {
            return $duration->h . ' hour' . ($duration->h > 1 ? 's' : '');
        } elseif ($duration->i > 0) {
            return $duration->i . ' minute' . ($duration->i > 1 ? 's' : '');
        } else {
            return 'Just joined';
        }
    }

    /**
     * Check if user is the room administrator
     */
    public function isAdministrator(): bool
    {
        return $this->room->administrator_id === $this->user_id;
    }

    /**
     * Boot method to handle model events
     */
    protected static function boot()
    {
        parent::boot();

        // Set joined_at timestamp when creating
        static::creating(function ($participant) {
            if (!$participant->joined_at) {
                $participant->joined_at = Carbon::now();
            }
        });
    }
}