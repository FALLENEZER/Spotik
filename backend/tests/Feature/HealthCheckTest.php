<?php

namespace Tests\Feature;

use Tests\TestCase;

class HealthCheckTest extends TestCase
{
    /**
     * Test the health check endpoint.
     */
    public function test_health_check_endpoint(): void
    {
        $response = $this->get('/api/health');

        $response->assertStatus(200)
                 ->assertJson([
                     'status' => 'ok',
                     'service' => 'Spotik API',
                     'version' => '1.0.0'
                 ])
                 ->assertJsonStructure([
                     'status',
                     'timestamp',
                     'service',
                     'version'
                 ]);
    }
}