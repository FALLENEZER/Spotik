<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    /**
     * Seed the application's database.
     */
    public function run(): void
    {
        // Seed genres first
        $this->call([
            GenreSeeder::class,
        ]);
        
        // Add other seeders here when needed
        // $this->call([
        //     UserSeeder::class,
        //     RoomSeeder::class,
        // ]);
    }
}