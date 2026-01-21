<?php

namespace Database\Factories;

use App\Models\Room;
use App\Models\User;
use App\Models\Track;
use Illuminate\Database\Eloquent\Factories\Factory;

class RoomFactory extends Factory
{
    protected $model = Room::class;

    public function definition(): array
    {
        return [
            'name' => $this->faker->words(3, true),
            'administrator_id' => User::factory(),
            'current_track_id' => null,
            'playback_started_at' => null,
            'playback_paused_at' => null,
            'is_playing' => false,
        ];
    }

    /**
     * Create a room with a specific administrator
     */
    public function withAdministrator(User $user): static
    {
        return $this->state(fn (array $attributes) => [
            'administrator_id' => $user->id,
        ]);
    }

    /**
     * Create a room with a specific name
     */
    public function withName(string $name): static
    {
        return $this->state(fn (array $attributes) => [
            'name' => $name,
        ]);
    }

    /**
     * Create a room that is currently playing
     */
    public function playing(): static
    {
        return $this->state(fn (array $attributes) => [
            'is_playing' => true,
            'playback_started_at' => now()->subMinutes($this->faker->numberBetween(1, 10)),
        ]);
    }

    /**
     * Create a room that is paused
     */
    public function paused(): static
    {
        return $this->state(fn (array $attributes) => [
            'is_playing' => false,
            'playback_started_at' => now()->subMinutes($this->faker->numberBetween(5, 15)),
            'playback_paused_at' => now()->subMinutes($this->faker->numberBetween(1, 5)),
        ]);
    }

    /**
     * Create a room with a current track
     */
    public function withCurrentTrack(?Track $track = null): static
    {
        return $this->state(fn (array $attributes) => [
            'current_track_id' => $track ? $track->id : Track::factory()->create()->id,
        ]);
    }

    /**
     * Create a room with participants
     */
    public function withParticipants(int $count = 3): static
    {
        return $this->afterCreating(function (Room $room) use ($count) {
            $users = User::factory()->count($count)->create();
            foreach ($users as $user) {
                $room->addParticipant($user);
            }
        });
    }

    /**
     * Create a room with tracks in queue
     */
    public function withTracks(int $count = 5): static
    {
        return $this->afterCreating(function (Room $room) use ($count) {
            Track::factory()
                ->count($count)
                ->for($room)
                ->create();
        });
    }
}