<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Support\Facades\Storage;

class Track extends Model
{
    use HasFactory, HasUuids;

    protected $fillable = [
        'room_id',
        'uploader_id',
        'filename',
        'original_name',
        'file_path',
        'duration_seconds',
        'file_size_bytes',
        'mime_type',
        'vote_score',
    ];

    protected $casts = [
        'duration_seconds' => 'integer',
        'file_size_bytes' => 'integer',
        'vote_score' => 'integer',
    ];

    /**
     * Supported audio MIME types
     */
    public const SUPPORTED_MIME_TYPES = [
        'audio/mpeg',     // MP3
        'audio/wav',      // WAV
        'audio/mp4',      // M4A
        'audio/x-m4a',    // M4A alternative
    ];

    /**
     * Supported file extensions
     */
    public const SUPPORTED_EXTENSIONS = ['mp3', 'wav', 'm4a'];

    /**
     * Maximum file size in bytes (50MB)
     */
    public const MAX_FILE_SIZE = 50 * 1024 * 1024;

    /**
     * Validation rules for track upload
     */
    public static function validationRules(): array
    {
        $maxSize = self::MAX_FILE_SIZE / 1024; // Convert to KB for validation
        $mimeTypes = implode(',', self::SUPPORTED_MIME_TYPES);
        $extensions = implode(',', self::SUPPORTED_EXTENSIONS);
        
        return [
            'room_id' => 'required|uuid|exists:rooms,id',
            'uploader_id' => 'required|uuid|exists:users,id',
            'audio_file' => "required|file|mimes:{$extensions}|mimetypes:{$mimeTypes}|max:{$maxSize}",
            'original_name' => 'sometimes|string|max:255',
        ];
    }

    /**
     * Validation rules for track update
     */
    public static function updateValidationRules(): array
    {
        return [
            'original_name' => 'sometimes|string|max:255',
            'vote_score' => 'sometimes|integer|min:0',
        ];
    }

    /**
     * Room this track belongs to
     */
    public function room(): BelongsTo
    {
        return $this->belongsTo(Room::class);
    }

    /**
     * User who uploaded this track
     */
    public function uploader(): BelongsTo
    {
        return $this->belongsTo(User::class, 'uploader_id');
    }

    /**
     * Votes for this track
     */
    public function votes(): HasMany
    {
        return $this->hasMany(TrackVote::class);
    }

    /**
     * Users who voted for this track
     */
    public function voters(): BelongsToMany
    {
        return $this->belongsToMany(User::class, 'track_votes')
                    ->withTimestamps();
    }

    /**
     * Get the file URL for streaming
     */
    public function getFileUrl(): string
    {
        return "/api/tracks/{$this->id}/stream";
    }

    /**
     * Get formatted duration (MM:SS)
     */
    public function getFormattedDuration(): string
    {
        $minutes = floor($this->duration_seconds / 60);
        $seconds = $this->duration_seconds % 60;
        return sprintf('%d:%02d', $minutes, $seconds);
    }

    /**
     * Get formatted file size
     */
    public function getFormattedFileSize(): string
    {
        $bytes = $this->file_size_bytes;
        $units = ['B', 'KB', 'MB', 'GB'];
        
        for ($i = 0; $bytes > 1024 && $i < count($units) - 1; $i++) {
            $bytes /= 1024;
        }
        
        return round($bytes, 2) . ' ' . $units[$i];
    }

    /**
     * Add a vote from a user
     */
    public function addVote(User $user): TrackVote
    {
        $vote = $this->votes()->firstOrCreate([
            'user_id' => $user->id,
        ]);

        return $vote;
    }

    /**
     * Remove a vote from a user
     */
    public function removeVote(User $user): bool
    {
        $vote = $this->votes()->where('user_id', $user->id)->first();
        
        if ($vote) {
            $vote->delete();
            return true;
        }

        return false;
    }

    /**
     * Toggle vote for a user
     */
    public function toggleVote(User $user): bool
    {
        if ($this->hasVoteFrom($user)) {
            $this->removeVote($user);
            return false; // Vote removed
        } else {
            $this->addVote($user);
            return true; // Vote added
        }
    }

    /**
     * Check if user has voted for this track
     */
    public function hasVoteFrom(User $user): bool
    {
        return $this->votes()
                    ->where('user_id', $user->id)
                    ->exists();
    }

    /**
     * Recalculate vote score from actual votes
     */
    public function recalculateVoteScore(): void
    {
        $actualScore = $this->votes()->count();
        $this->update(['vote_score' => $actualScore]);
    }

    /**
     * Check if file exists in storage
     */
    public function fileExists(): bool
    {
        return Storage::exists($this->file_path);
    }

    /**
     * Delete the audio file from storage
     */
    public function deleteFile(): bool
    {
        if ($this->fileExists()) {
            return Storage::delete($this->file_path);
        }
        return true;
    }

    /**
     * Check if this is a supported audio format
     */
    public static function isSupportedMimeType(string $mimeType): bool
    {
        return in_array($mimeType, self::SUPPORTED_MIME_TYPES);
    }

    /**
     * Check if this is a supported file extension
     */
    public static function isSupportedExtension(string $extension): bool
    {
        return in_array(strtolower($extension), self::SUPPORTED_EXTENSIONS);
    }

    /**
     * Boot method to handle model events
     */
    protected static function boot()
    {
        parent::boot();

        // When a track is deleted, also delete the file
        static::deleting(function ($track) {
            $track->deleteFile();
        });
    }
}