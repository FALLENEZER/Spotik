<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Genre extends Model
{
    use HasFactory;

    protected $fillable = [
        'name',
        'description',
        'color',
    ];

    /**
     * Tracks belonging to this genre
     */
    public function tracks(): HasMany
    {
        return $this->hasMany(Track::class);
    }

    /**
     * Get tracks count for this genre
     */
    public function getTracksCountAttribute(): int
    {
        return $this->tracks()->count();
    }

    /**
     * Scope to get popular genres (with most tracks)
     */
    public function scopePopular($query, int $limit = 10)
    {
        return $query->withCount('tracks')
                    ->orderBy('tracks_count', 'desc')
                    ->limit($limit);
    }
}