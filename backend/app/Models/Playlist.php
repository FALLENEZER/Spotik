<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;

class Playlist extends Model
{
    use HasFactory;

    protected $fillable = [
        'name',
        'description',
        'is_public',
        'user_id',
    ];

    protected $casts = [
        'is_public' => 'boolean',
    ];

    /**
     * User who owns this playlist
     */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /**
     * Tracks in this playlist
     */
    public function tracks(): BelongsToMany
    {
        return $this->belongsToMany(Track::class, 'playlist_tracks')
                    ->withPivot('position')
                    ->withTimestamps()
                    ->orderBy('playlist_tracks.position');
    }

    /**
     * Add track to playlist
     */
    public function addTrack(Track $track, ?int $position = null): void
    {
        if ($position === null) {
            $position = $this->tracks()->count();
        }

        $this->tracks()->attach($track->id, [
            'position' => $position,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    /**
     * Remove track from playlist
     */
    public function removeTrack(Track $track): bool
    {
        return $this->tracks()->detach($track->id) > 0;
    }

    /**
     * Get total duration of playlist in seconds
     */
    public function getTotalDurationAttribute(): int
    {
        return $this->tracks()->sum('duration_seconds') ?? 0;
    }

    /**
     * Get tracks count
     */
    public function getTracksCountAttribute(): int
    {
        return $this->tracks()->count();
    }

    /**
     * Scope to get public playlists
     */
    public function scopePublic($query)
    {
        return $query->where('is_public', true);
    }

    /**
     * Scope to get user's playlists
     */
    public function scopeForUser($query, User $user)
    {
        return $query->where('user_id', $user->id);
    }
}