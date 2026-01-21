<?php

use Illuminate\Support\Str;

return [

    /*
    |--------------------------------------------------------------------------
    | Default Cache Store
    |--------------------------------------------------------------------------
    */

    'default' => env('CACHE_DRIVER', 'redis'),

    /*
    |--------------------------------------------------------------------------
    | Cache Stores
    |--------------------------------------------------------------------------
    */

    'stores' => [

        'array' => [
            'driver' => 'array',
            'serialize' => false,
        ],

        'database' => [
            'driver' => 'database',
            'table' => 'cache',
            'connection' => null,
            'lock_connection' => null,
        ],

        'file' => [
            'driver' => 'file',
            'path' => storage_path('framework/cache/data'),
            'lock_path' => storage_path('framework/cache/data'),
        ],

        'memcached' => [
            'driver' => 'memcached',
            'persistent_id' => env('MEMCACHED_PERSISTENT_ID'),
            'sasl' => [
                env('MEMCACHED_USERNAME'),
                env('MEMCACHED_PASSWORD'),
            ],
            'options' => [
                // Memcached::OPT_CONNECT_TIMEOUT => 2000,
            ],
            'servers' => [
                [
                    'host' => env('MEMCACHED_HOST', '127.0.0.1'),
                    'port' => env('MEMCACHED_PORT', 11211),
                    'weight' => 100,
                ],
            ],
        ],

        'redis' => [
            'driver' => 'redis',
            'connection' => env('CACHE_REDIS_CONNECTION', 'cache'),
            'lock_connection' => env('CACHE_REDIS_LOCK_CONNECTION', 'default'),
            // Performance optimizations
            'serializer' => env('CACHE_REDIS_SERIALIZER', 'php'), // php, igbinary, json
            'compression' => env('CACHE_REDIS_COMPRESSION', false),
            'prefix' => env('CACHE_PREFIX', Str::slug(env('APP_NAME', 'laravel'), '_').'_cache'),
        ],

        'dynamodb' => [
            'driver' => 'dynamodb',
            'key' => env('AWS_ACCESS_KEY_ID'),
            'secret' => env('AWS_SECRET_ACCESS_KEY'),
            'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
            'table' => env('DYNAMODB_CACHE_TABLE', 'cache'),
            'endpoint' => env('DYNAMODB_ENDPOINT'),
        ],

        'octane' => [
            'driver' => 'octane',
        ],

        // High-performance cache for frequently accessed data
        'tracks' => [
            'driver' => 'redis',
            'connection' => 'cache',
            'prefix' => 'tracks_cache',
            'serializer' => 'igbinary', // More efficient serialization
            'compression' => true,
        ],

        // Cache for room data
        'rooms' => [
            'driver' => 'redis',
            'connection' => 'cache',
            'prefix' => 'rooms_cache',
            'serializer' => 'php',
            'compression' => false, // Room data is small, skip compression
        ],

        // Cache for user sessions and auth data
        'sessions' => [
            'driver' => 'redis',
            'connection' => 'session',
            'prefix' => 'session_cache',
            'serializer' => 'php',
            'compression' => false,
        ],

    ],

    /*
    |--------------------------------------------------------------------------
    | Cache Key Prefix
    |--------------------------------------------------------------------------
    */

    'prefix' => env('CACHE_PREFIX', Str::slug(env('APP_NAME', 'laravel'), '_').'_cache'),

    /*
    |--------------------------------------------------------------------------
    | Cache Tags
    |--------------------------------------------------------------------------
    */

    'tags' => [
        'rooms' => 'rooms',
        'tracks' => 'tracks',
        'users' => 'users',
        'votes' => 'votes',
        'participants' => 'participants',
    ],

    /*
    |--------------------------------------------------------------------------
    | Cache TTL Settings
    |--------------------------------------------------------------------------
    */

    'ttl' => [
        'default' => env('CACHE_TTL', 3600), // 1 hour
        'rooms' => env('CACHE_TTL_ROOMS', 1800), // 30 minutes
        'tracks' => env('CACHE_TTL_TRACKS', 3600), // 1 hour
        'users' => env('CACHE_TTL_USERS', 7200), // 2 hours
        'votes' => env('CACHE_TTL_VOTES', 300), // 5 minutes
        'participants' => env('CACHE_TTL_PARTICIPANTS', 600), // 10 minutes
        'audio_metadata' => env('CACHE_TTL_AUDIO_METADATA', 86400), // 24 hours
    ],

];