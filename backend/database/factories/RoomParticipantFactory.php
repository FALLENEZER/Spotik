<?php

namespace Database\Factories;

use App\Models\RoomParticipant;
use App\Models\Room;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

class RoomParticipantFactory extends Factory
{
    protected $model = RoomParticipant::class;

    public function definition(): array
    {
        return [
            'room_id' => Room::factory(),
            'user_id' => User::factory(),
            'joined_at' => $this->faker->dateTimeBetween('-1 week', 'now'),
        ];
    }

    /**
     * Create a participant for a specific room
     */
    public function forRoom(Room $room): static
    {
        return $this->state(fn (array $attributes) => [
            'room_id' => $room->id,
        ]);
    }

    /**
     * Create a participant for a specific user
     */
    public function forUser(User $user): static
    {
        return $this->state(fn (array $attributes) => [
            'user_id' => $user->id,
        ]);
    }

    /**
     * Create a participant who just joined
     */
    public function justJoined(): static
    {
        return $this->state(fn (array $attributes) => [
            'joined_at' => now(),
        ]);
    }

    /**
     * Create a participant who joined recently (within last hour)
     */
    public function recentlyJoined(): static
    {
        return $this->state(fn (array $attributes) => [
            'joined_at' => $this->faker->dateTimeBetween('-1 hour', 'now'),
        ]);
    }

    /**
     * Create a participant who joined a while ago
     */
    public function longTimeParticipant(): static
    {
        return $this->state(fn (array $attributes) => [
            'joined_at' => $this->faker->dateTimeBetween('-1 month', '-1 week'),
        ]);
    }

    /**
     * Create a participant who is also the room administrator
     */
    public function administrator(): static
    {
        return $this->afterCreating(function (RoomParticipant $participant) {
            $participant->room->update([
                'administrator_id' => $participant->user_id,
            ]);
        });
    }
}