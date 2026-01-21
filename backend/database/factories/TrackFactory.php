<?php

namespace Database\Factories;

use App\Models\Track;
use App\Models\Room;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

class TrackFactory extends Factory
{
    protected $model = Track::class;

    public function definition(): array
    {
        $mimeTypes = Track::SUPPORTED_MIME_TYPES;
        $extensions = Track::SUPPORTED_EXTENSIONS;
        $extension = $this->faker->randomElement($extensions);
        $mimeType = $this->getMimeTypeForExtension($extension);
        
        return [
            'room_id' => Room::factory(),
            'uploader_id' => User::factory(),
            'filename' => $this->faker->uuid() . '.' . $extension,
            'original_name' => $this->faker->words(3, true) . '.' . $extension,
            'file_path' => 'tracks/' . $this->faker->uuid() . '.' . $extension,
            'duration_seconds' => $this->faker->numberBetween(30, 600), // 30 seconds to 10 minutes
            'file_size_bytes' => $this->faker->numberBetween(1000000, Track::MAX_FILE_SIZE), // 1MB to max size
            'mime_type' => $mimeType,
            'vote_score' => 0,
        ];
    }

    /**
     * Create a track with specific vote count
     */
    public function withVotes(?int $votes = null): static
    {
        return $this->state(fn (array $attributes) => [
            'vote_score' => $votes ?? $this->faker->numberBetween(0, 20),
        ]);
    }

    /**
     * Create a track for a specific room
     */
    public function forRoom(Room $room): static
    {
        return $this->state(fn (array $attributes) => [
            'room_id' => $room->id,
        ]);
    }

    /**
     * Create a track uploaded by a specific user
     */
    public function uploadedBy(User $user): static
    {
        return $this->state(fn (array $attributes) => [
            'uploader_id' => $user->id,
        ]);
    }

    /**
     * Create an MP3 track
     */
    public function mp3(): static
    {
        return $this->state(fn (array $attributes) => [
            'filename' => $this->faker->uuid() . '.mp3',
            'original_name' => $this->faker->words(3, true) . '.mp3',
            'file_path' => 'tracks/' . $this->faker->uuid() . '.mp3',
            'mime_type' => 'audio/mpeg',
        ]);
    }

    /**
     * Create a WAV track
     */
    public function wav(): static
    {
        return $this->state(fn (array $attributes) => [
            'filename' => $this->faker->uuid() . '.wav',
            'original_name' => $this->faker->words(3, true) . '.wav',
            'file_path' => 'tracks/' . $this->faker->uuid() . '.wav',
            'mime_type' => 'audio/wav',
            'file_size_bytes' => $this->faker->numberBetween(5000000, Track::MAX_FILE_SIZE), // WAV files are larger
        ]);
    }

    /**
     * Create an M4A track
     */
    public function m4a(): static
    {
        return $this->state(fn (array $attributes) => [
            'filename' => $this->faker->uuid() . '.m4a',
            'original_name' => $this->faker->words(3, true) . '.m4a',
            'file_path' => 'tracks/' . $this->faker->uuid() . '.m4a',
            'mime_type' => 'audio/mp4',
        ]);
    }

    /**
     * Create a short track (under 1 minute)
     */
    public function short(): static
    {
        return $this->state(fn (array $attributes) => [
            'duration_seconds' => $this->faker->numberBetween(15, 59),
        ]);
    }

    /**
     * Create a long track (over 5 minutes)
     */
    public function long(): static
    {
        return $this->state(fn (array $attributes) => [
            'duration_seconds' => $this->faker->numberBetween(300, 900), // 5-15 minutes
        ]);
    }

    /**
     * Create a popular track (high vote score)
     */
    public function popular(): static
    {
        return $this->state(fn (array $attributes) => [
            'vote_score' => $this->faker->numberBetween(10, 50),
        ]);
    }

    /**
     * Create a track with actual votes
     */
    public function withActualVotes(?int $count = null): static
    {
        $voteCount = $count ?? $this->faker->numberBetween(1, 10);
        
        return $this->afterCreating(function (Track $track) use ($voteCount) {
            $users = User::factory()->count($voteCount)->create();
            foreach ($users as $user) {
                $track->addVote($user);
            }
        });
    }

    /**
     * Get MIME type for file extension
     */
    private function getMimeTypeForExtension(string $extension): string
    {
        return match ($extension) {
            'mp3' => 'audio/mpeg',
            'wav' => 'audio/wav',
            'm4a' => 'audio/mp4',
            default => 'audio/mpeg',
        };
    }
}