<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Carbon\Carbon;

class TrackVote extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'track_id',
        'user_id',
        'created_at',
    ];

    protected $casts = [
        'created_at' => 'datetime',
    ];

    public $timestamps = false;

    /**
     * Validation rules for track vote
     */
    public static function validationRules(): array
    {
        return [
            'track_id' => 'required|uuid|exists:tracks,id',
            'user_id' => 'required|uuid|exists:users,id',
        ];
    }

    /**
     * Track this vote belongs to
     */
    public function track(): BelongsTo
    {
        return $this->belongsTo(Track::class);
    }

    /**
     * User who cast this vote
     */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /**
     * Get the room this vote belongs to (through track)
     */
    public function room(): BelongsTo
    {
        return $this->track()->getRelated()->room();
    }

    /**
     * Check if this vote is from the track uploader
     */
    public function isFromUploader(): bool
    {
        return $this->user_id === $this->track->uploader_id;
    }

    /**
     * Boot method to handle model events
     */
    protected static function boot()
    {
        parent::boot();

        // Set created_at timestamp when creating
        static::creating(function ($vote) {
            if (!$vote->created_at) {
                $vote->created_at = Carbon::now();
            }
        });

        // Update track vote score when vote is created
        static::created(function ($vote) {
            $vote->track->increment('vote_score');
        });

        // Update track vote score when vote is deleted
        static::deleted(function ($vote) {
            $vote->track->decrement('vote_score');
        });
    }
}