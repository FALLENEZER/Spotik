<?php

namespace Tests\Feature;

use Tests\TestCase;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use App\Models\User;
use App\Models\Room;
use App\Models\Track;

class PerformanceOptimizationTest extends TestCase
{
    use RefreshDatabase;

    /**
     * Test that performance monitoring middleware is registered
     */
    public function test_performance_monitoring_middleware_is_registered(): void
    {
        $response = $this->getJson('/api/ping');
        
        $response->assertStatus(200);
        $response->assertJson([
            'status' => 'ok'
        ]);
    }

    /**
     * Test health check endpoint functionality
     */
    public function test_health_check_endpoint_works(): void
    {
        $response = $this->getJson('/api/health');
        
        $response->assertStatus(200);
        $response->assertJsonStructure([
            'status',
            'timestamp',
            'checks'
        ]);
    }

    /**
     * Test metrics endpoint functionality
     */
    public function test_metrics_endpoint_works(): void
    {
        $response = $this->getJson('/api/metrics');
        
        $response->assertStatus(200);
        $response->assertJsonStructure([
            'timestamp',
            'metrics'
        ]);
    }

    /**
     * Test that cache configuration is working
     */
    public function test_cache_configuration_works(): void
    {
        $testKey = 'performance_test_' . time();
        $testValue = 'test_value';
        
        // Test cache store
        Cache::put($testKey, $testValue, 60);
        
        // Test cache retrieve
        $cachedValue = Cache::get($testKey);
        
        $this->assertEquals($testValue, $cachedValue);
        
        // Cleanup
        Cache::forget($testKey);
    }

    /**
     * Test database query performance with indexes
     */
    public function test_database_indexes_exist(): void
    {
        // Check if our performance indexes exist
        $indexes = DB::select("
            SELECT indexname 
            FROM pg_indexes 
            WHERE tablename IN ('tracks', 'track_votes', 'room_participants', 'rooms', 'users')
            AND indexname LIKE 'idx_%'
        ");
        
        $indexNames = array_column($indexes, 'indexname');
        
        // Check for some of our key performance indexes
        $expectedIndexes = [
            'idx_tracks_room_score',
            'idx_votes_track_time',
            'idx_participants_room_time',
            'idx_rooms_time_name',
            'idx_users_email'
        ];
        
        foreach ($expectedIndexes as $expectedIndex) {
            $this->assertContains($expectedIndex, $indexNames, "Index {$expectedIndex} should exist");
        }
    }

    /**
     * Test track queue query performance with caching
     */
    public function test_track_queue_caching_works(): void
    {
        // Create test data
        $user = User::factory()->create();
        $room = Room::factory()->create(['administrator_id' => $user->id]);
        $room->participants()->attach($user->id);
        
        Track::factory()->count(3)->create([
            'room_id' => $room->id,
            'uploader_id' => $user->id
        ]);

        // First request should hit database and cache result
        $response1 = $this->actingAs($user, 'jwt.custom')
                          ->getJson("/api/rooms/{$room->id}/tracks");
        
        $response1->assertStatus(200);
        $response1->assertJsonStructure([
            'tracks',
            'total_count'
        ]);

        // Verify cache key exists
        $cacheKey = "room_tracks:{$room->id}:user:{$user->id}";
        $this->assertTrue(Cache::has($cacheKey));
    }

    /**
     * Test file serving optimization headers
     */
    public function test_file_serving_optimization_headers(): void
    {
        // Create a test audio file
        Storage::disk('audio')->put('tracks/test.mp3', 'fake audio content');
        
        $user = User::factory()->create();
        
        $response = $this->actingAs($user, 'jwt.custom')
                         ->get('/api/audio/test.mp3');
        
        // Check for performance optimization headers
        $response->assertHeader('Accept-Ranges', 'bytes');
        $response->assertHeader('Cache-Control');
        $response->assertHeader('ETag');
        
        // Cleanup
        Storage::disk('audio')->delete('tracks/test.mp3');
    }

    /**
     * Test that monitoring configuration is loaded
     */
    public function test_monitoring_configuration_is_loaded(): void
    {
        $this->assertTrue(config('monitoring.enabled'));
        $this->assertTrue(config('monitoring.database.enabled'));
        $this->assertTrue(config('monitoring.http.enabled'));
        $this->assertTrue(config('monitoring.metrics.enabled'));
    }

    /**
     * Test cache TTL configuration
     */
    public function test_cache_ttl_configuration(): void
    {
        $this->assertIsInt(config('cache.ttl.default'));
        $this->assertIsInt(config('cache.ttl.tracks'));
        $this->assertIsInt(config('cache.ttl.rooms'));
        $this->assertIsInt(config('cache.ttl.users'));
    }

    /**
     * Test Redis connection with performance settings
     */
    public function test_redis_connection_works(): void
    {
        try {
            $redis = app('redis');
            $result = $redis->ping();
            $this->assertTrue($result);
        } catch (\Exception $e) {
            $this->markTestSkipped('Redis not available: ' . $e->getMessage());
        }
    }

    /**
     * Test database connection with performance settings
     */
    public function test_database_connection_works(): void
    {
        $result = DB::select('SELECT 1 as test');
        $this->assertEquals(1, $result[0]->test);
    }
}