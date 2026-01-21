<?php

namespace Database\Factories;

use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

class UserFactory extends Factory
{
    protected $model = User::class;

    public function definition(): array
    {
        return [
            'username' => 'user_' . $this->faker->randomNumber(6),
            'email' => 'user' . $this->faker->randomNumber(6) . '@example.com',
            'password_hash' => password_hash('password', PASSWORD_DEFAULT),
        ];
    }

    /**
     * Create a user with a specific password
     */
    public function withPassword(string $password): static
    {
        return $this->state(fn (array $attributes) => [
            'password_hash' => password_hash($password, PASSWORD_DEFAULT),
        ]);
    }

    /**
     * Create a user with a specific username
     */
    public function withUsername(string $username): static
    {
        return $this->state(fn (array $attributes) => [
            'username' => $username,
        ]);
    }

    /**
     * Create a user with a specific email
     */
    public function withEmail(string $email): static
    {
        return $this->state(fn (array $attributes) => [
            'email' => $email,
        ]);
    }

    /**
     * Create a user that will be a room administrator
     */
    public function administrator(): static
    {
        return $this->state(fn (array $attributes) => [
            'username' => 'admin_' . $this->faker->randomNumber(4),
        ]);
    }
}