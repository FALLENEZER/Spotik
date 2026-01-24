<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use App\Models\Genre;

class GenreSeeder extends Seeder
{
    /**
     * Run the database seeds.
     */
    public function run(): void
    {
        $genres = [
            [
                'name' => 'Pop',
                'description' => 'Popular music with catchy melodies and mainstream appeal',
                'color' => '#ff6b6b'
            ],
            [
                'name' => 'Rock',
                'description' => 'Guitar-driven music with strong rhythms',
                'color' => '#4ecdc4'
            ],
            [
                'name' => 'Hip Hop',
                'description' => 'Rhythmic spoken lyrics over beats',
                'color' => '#45b7d1'
            ],
            [
                'name' => 'Electronic',
                'description' => 'Music created using electronic instruments and technology',
                'color' => '#96ceb4'
            ],
            [
                'name' => 'Jazz',
                'description' => 'Improvisational music with complex harmonies',
                'color' => '#feca57'
            ],
            [
                'name' => 'Classical',
                'description' => 'Traditional orchestral and chamber music',
                'color' => '#ff9ff3'
            ],
            [
                'name' => 'R&B',
                'description' => 'Rhythm and blues with soulful vocals',
                'color' => '#54a0ff'
            ],
            [
                'name' => 'Country',
                'description' => 'American folk music with storytelling lyrics',
                'color' => '#5f27cd'
            ],
            [
                'name' => 'Reggae',
                'description' => 'Jamaican music with distinctive rhythm',
                'color' => '#00d2d3'
            ],
            [
                'name' => 'Alternative',
                'description' => 'Non-mainstream music with experimental elements',
                'color' => '#ff6348'
            ]
        ];

        foreach ($genres as $genre) {
            Genre::firstOrCreate(
                ['name' => $genre['name']],
                $genre
            );
        }
    }
}