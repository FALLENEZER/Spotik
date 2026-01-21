<?php

namespace Database\Factories;

use App\Models\TrackVote;
use App\Models\Track;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

class TrackVoteFactory extends Factory
{
    protected $model = TrackVote::class;

    public function definition(): array
    {
        return [
            'track_id' => Track::factory(),
            'user_id' => User::factory(),
            'created_at' => $this->faker->dateTimeBetween('-1 week', 'now'),
        ];
    }

    /**
     * Create a vote for a specific track
     */
    public function forTrack(Track $track): static
    {
        return $this->state(fn (array $attributes) => [
            'track_id' => $track->id,
        ]);
    }

    /**
     * Create a vote by a specific user
     */
    public function byUser(User $user): static
    {
        return $this->state(fn (array $attributes) => [
            'user_id' => $user->id,
        ]);
    }

    /**
     * Create a vote that was just cast
     */
    public function justCast(): static
    {
        return $this->state(fn (array $attributes) => [
            'created_at' => now(),
        ]);
    }

    /**
     * Create a vote cast recently (within last hour)
     */
    public function recentlyCast(): static
    {
        return $this->state(fn (array $attributes) => [
            'created_at' => $this->faker->dateTimeBetween('-1 hour', 'now'),
        ]);
    }

    /**
     * Create an old vote
     */
    public function old(): static
    {
        return $this->state(fn (array $attributes) => [
            'created_at' => $this->faker->dateTimeBetween('-1 month', '-1 week'),
        ]);
    }

    /**
     * Create a vote by the track uploader (self-vote)
     */
    public function selfVote(): static
    {
        return $this->afterMaking(function (TrackVote $vote) {
            // Ensure the voter is the same as the track uploader
            $vote->user_id = $vote->track->uploader_id;
        });
    }

    /**
     * Create multiple votes for the same track
     */
    public function forSameTrack(Track $track, int $count): static
    {
        return $this->count($count)->state(fn (array $attributes) => [
            'track_id' => $track->id,
        ]);
    }
}