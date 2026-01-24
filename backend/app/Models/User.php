<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Notifications\Notifiable;
use Tymon\JWTAuth\Contracts\JWTSubject;

class User extends Authenticatable implements JWTSubject
{
    use HasFactory, HasUuids, Notifiable;

    protected $fillable = [
        'username',
        'email',
        'password_hash',
    ];

    protected $hidden = [
        'password_hash',
        'remember_token',
    ];

    protected $casts = [
        'email_verified_at' => 'datetime',
    ];

    /**
     * Get the password for authentication.
     */
    public function getAuthPassword()
    {
        return $this->password_hash;
    }

    /**
     * Validation rules for user creation
     */
    public static function validationRules(): array
    {
        return [
            'username' => 'required|string|max:50|unique:users,username',
            'email' => 'required|string|email|max:255|unique:users,email',
            'password' => 'required|string|min:8|confirmed',
        ];
    }

    /**
     * Validation rules for user update
     */
    public static function updateValidationRules($userId): array
    {
        return [
            'username' => 'sometimes|string|max:50|unique:users,username,' . $userId,
            'email' => 'sometimes|string|email|max:255|unique:users,email,' . $userId,
            'password' => 'sometimes|string|min:8|confirmed',
        ];
    }

    /**
     * Rooms administered by this user
     */
    public function administeredRooms(): HasMany
    {
        return $this->hasMany(Room::class, 'administrator_id');
    }

    /**
     * Room participations for this user
     */
    public function roomParticipations(): HasMany
    {
        return $this->hasMany(RoomParticipant::class);
    }

    /**
     * Rooms this user is participating in (through room_participants table)
     */
    public function rooms(): BelongsToMany
    {
        return $this->belongsToMany(Room::class, 'room_participants')
                    ->withPivot('joined_at')
                    ->withTimestamps();
    }

    /**
     * Tracks uploaded by this user
     */
    public function uploadedTracks(): HasMany
    {
        return $this->hasMany(Track::class, 'uploader_id');
    }

    /**
     * Track votes by this user
     */
    public function trackVotes(): HasMany
    {
        return $this->hasMany(TrackVote::class);
    }

    /**
     * Tracks this user has voted for
     */
    public function votedTracks(): BelongsToMany
    {
        return $this->belongsToMany(Track::class, 'track_votes')
                    ->withTimestamps();
    }

    /**
     * Playlists created by this user
     */
    public function playlists(): HasMany
    {
        return $this->hasMany(Playlist::class);
    }

    /**
     * Check if user is administrator of a room
     */
    public function isAdministratorOf(Room $room): bool
    {
        return $this->id === $room->administrator_id;
    }

    /**
     * Check if user is participating in a room
     */
    public function isParticipantOf(Room $room): bool
    {
        return $this->roomParticipations()
                    ->where('room_id', $room->id)
                    ->exists();
    }

    /**
     * Check if user has voted for a track
     */
    public function hasVotedFor(Track $track): bool
    {
        return $this->trackVotes()
                    ->where('track_id', $track->id)
                    ->exists();
    }

    /**
     * Get the identifier that will be stored in the subject claim of the JWT.
     */
    public function getJWTIdentifier()
    {
        return $this->getKey();
    }

    /**
     * Return a key value array, containing any custom claims to be added to the JWT.
     */
    public function getJWTCustomClaims()
    {
        return [];
    }
}