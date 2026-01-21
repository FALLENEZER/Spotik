<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Carbon\Carbon;

class Room extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'name',
        'administrator_id',
        'current_track_id',
        'playback_started_at',
        'playback_paused_at',
        'is_playing',
    ];

    protected $casts = [
        'playback_started_at' => 'datetime',
        'playback_paused_at' => 'datetime',
        'is_playing' => 'boolean',
    ];

    /**
     * Validation rules for room creation
     */
    public static function validationRules(): array
    {
        return [
            'name' => 'required|string|max:100',
            'administrator_id' => 'required|uuid|exists:users,id',
        ];
    }

    /**
     * Validation rules for room update
     */
    public static function updateValidationRules(): array
    {
        return [
            'name' => 'sometimes|string|max:100',
            'current_track_id' => 'sometimes|nullable|uuid|exists:tracks,id',
            'is_playing' => 'sometimes|boolean',
        ];
    }

    /**
     * Room administrator
     */
    public function administrator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'administrator_id');
    }

    /**
     * Currently playing track
     */
    public function currentTrack(): BelongsTo
    {
        return $this->belongsTo(Track::class, 'current_track_id');
    }

    /**
     * All tracks in this room
     */
    public function tracks(): HasMany
    {
        return $this->hasMany(Track::class);
    }

    /**
     * Room participants (through room_participants table)
     */
    public function participants(): HasMany
    {
        return $this->hasMany(RoomParticipant::class);
    }

    /**
     * Users participating in this room
     */
    public function users(): BelongsToMany
    {
        return $this->belongsToMany(User::class, 'room_participants')
                    ->withPivot('joined_at')
                    ->withTimestamps();
    }

    /**
     * Get track queue ordered by vote score (desc) then created_at (asc)
     */
    public function trackQueue()
    {
        return $this->hasMany(Track::class)
                    ->orderBy('vote_score', 'desc')
                    ->orderBy('created_at', 'asc');
    }

    /**
     * Get the next track in queue
     */
    public function getNextTrack(): ?Track
    {
        return $this->trackQueue()->first();
    }

    /**
     * Calculate current playback position in seconds
     */
    public function getCurrentPlaybackPosition(): int
    {
        if (!$this->is_playing || !$this->playback_started_at) {
            return 0;
        }

        $elapsed = Carbon::now()->diffInSeconds($this->playback_started_at);
        
        // If there was a pause, subtract the paused duration
        if ($this->playback_paused_at && $this->playback_paused_at->greaterThan($this->playback_started_at)) {
            $pausedDuration = Carbon::now()->diffInSeconds($this->playback_paused_at);
            $elapsed -= $pausedDuration;
        }

        return max(0, $elapsed);
    }

    /**
     * Start playing a track
     */
    public function startTrack(Track $track): void
    {
        $this->update([
            'current_track_id' => $track->id,
            'playback_started_at' => Carbon::now(),
            'playback_paused_at' => null,
            'is_playing' => true,
        ]);
    }

    /**
     * Pause current playback
     */
    public function pausePlayback(): void
    {
        $this->update([
            'playback_paused_at' => Carbon::now(),
            'is_playing' => false,
        ]);
    }

    /**
     * Resume paused playback
     */
    public function resumePlayback(): void
    {
        if ($this->playback_paused_at) {
            $pausedDuration = Carbon::now()->diffInSeconds($this->playback_paused_at);
            $newStartTime = $this->playback_started_at->addSeconds($pausedDuration);
            
            $this->update([
                'playback_started_at' => $newStartTime,
                'playback_paused_at' => null,
                'is_playing' => true,
            ]);
        }
    }

    /**
     * Stop playback
     */
    public function stopPlayback(): void
    {
        $this->update([
            'current_track_id' => null,
            'playback_started_at' => null,
            'playback_paused_at' => null,
            'is_playing' => false,
        ]);
    }

    /**
     * Skip to next track
     */
    public function skipToNext(): ?Track
    {
        $nextTrack = $this->getNextTrack();
        
        if ($nextTrack) {
            $this->startTrack($nextTrack);
        } else {
            $this->stopPlayback();
        }
        
        return $nextTrack;
    }

    /**
     * Add user to room
     */
    public function addParticipant(User $user): RoomParticipant
    {
        return $this->participants()->firstOrCreate([
            'user_id' => $user->id,
        ], [
            'joined_at' => Carbon::now(),
        ]);
    }

    /**
     * Remove user from room
     */
    public function removeParticipant(User $user): bool
    {
        return $this->participants()
                    ->where('user_id', $user->id)
                    ->delete() > 0;
    }

    /**
     * Check if user is administrator
     */
    public function isAdministratedBy(User $user): bool
    {
        return $this->administrator_id === $user->id;
    }

    /**
     * Check if user is participant
     */
    public function hasParticipant(User $user): bool
    {
        return $this->participants()
                    ->where('user_id', $user->id)
                    ->exists();
    }
}