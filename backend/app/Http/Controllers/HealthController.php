<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Redis;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Log;

class HealthController extends Controller
{
    /**
     * Comprehensive health check endpoint
     */
    public function health(Request $request): JsonResponse
    {
        if (!config('monitoring.health_checks.enabled')) {
            return response()->json(['status' => 'disabled'], 503);
        }

        $checks = config('monitoring.health_checks.checks', []);
        $timeout = config('monitoring.health_checks.timeout', 5);
        
        $results = [];
        $overallStatus = 'healthy';

        // Database health check
        if ($checks['database'] ?? false) {
            $results['database'] = $this->checkDatabase($timeout);
            if ($results['database']['status'] !== 'healthy') {
                $overallStatus = 'unhealthy';
            }
        }

        // Redis health check
        if ($checks['redis'] ?? false) {
            $results['redis'] = $this->checkRedis($timeout);
            if ($results['redis']['status'] !== 'healthy') {
                $overallStatus = 'unhealthy';
            }
        }

        // Storage health check
        if ($checks['storage'] ?? false) {
            $results['storage'] = $this->checkStorage($timeout);
            if ($results['storage']['status'] !== 'healthy') {
                $overallStatus = 'unhealthy';
            }
        }

        // WebSocket health check
        if ($checks['websocket'] ?? false) {
            $results['websocket'] = $this->checkWebSocket($timeout);
            if ($results['websocket']['status'] !== 'healthy') {
                $overallStatus = 'degraded'; // WebSocket issues are less critical
            }
        }

        // System metrics
        $results['system'] = $this->getSystemMetrics();

        $response = [
            'status' => $overallStatus,
            'timestamp' => now()->toISOString(),
            'checks' => $results,
        ];

        $statusCode = $overallStatus === 'healthy' ? 200 : 503;
        
        return response()->json($response, $statusCode);
    }

    /**
     * Simple ping endpoint for basic health checks
     */
    public function ping(): JsonResponse
    {
        return response()->json([
            'status' => 'ok',
            'timestamp' => now()->toISOString(),
        ]);
    }

    /**
     * Metrics endpoint for monitoring systems
     */
    public function metrics(Request $request): JsonResponse
    {
        if (!config('monitoring.metrics.enabled')) {
            return response()->json(['error' => 'Metrics disabled'], 503);
        }

        $metrics = $this->collectMetrics();

        return response()->json([
            'timestamp' => now()->toISOString(),
            'metrics' => $metrics,
        ]);
    }

    /**
     * Check database connectivity and performance
     */
    private function checkDatabase(int $timeout): array
    {
        try {
            $start = microtime(true);
            
            // Test basic connectivity
            DB::connection()->getPdo();
            
            // Test query performance
            $result = DB::select('SELECT 1 as test');
            
            $responseTime = (microtime(true) - $start) * 1000;

            return [
                'status' => 'healthy',
                'response_time' => round($responseTime, 2),
                'connection' => 'active',
                'driver' => DB::getDriverName(),
            ];

        } catch (\Exception $e) {
            Log::error('Database health check failed', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);

            return [
                'status' => 'unhealthy',
                'error' => $e->getMessage(),
                'connection' => 'failed',
            ];
        }
    }

    /**
     * Check Redis connectivity and performance
     */
    private function checkRedis(int $timeout): array
    {
        try {
            $start = microtime(true);
            
            // Test basic connectivity
            $redis = Redis::connection();
            $result = $redis->ping();
            
            // Test read/write operations
            $testKey = 'health_check_' . time();
            $redis->set($testKey, 'test', 'EX', 10);
            $value = $redis->get($testKey);
            $redis->del($testKey);
            
            $responseTime = (microtime(true) - $start) * 1000;

            return [
                'status' => 'healthy',
                'response_time' => round($responseTime, 2),
                'connection' => 'active',
                'ping_result' => $result,
                'read_write' => $value === 'test' ? 'ok' : 'failed',
            ];

        } catch (\Exception $e) {
            Log::error('Redis health check failed', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);

            return [
                'status' => 'unhealthy',
                'error' => $e->getMessage(),
                'connection' => 'failed',
            ];
        }
    }

    /**
     * Check storage accessibility
     */
    private function checkStorage(int $timeout): array
    {
        try {
            $start = microtime(true);
            
            // Test default disk
            $defaultDisk = Storage::disk();
            $testFile = 'health_check_' . time() . '.txt';
            $testContent = 'health check test';
            
            // Test write operation
            $defaultDisk->put($testFile, $testContent);
            
            // Test read operation
            $readContent = $defaultDisk->get($testFile);
            
            // Test delete operation
            $defaultDisk->delete($testFile);
            
            $responseTime = (microtime(true) - $start) * 1000;

            // Test audio disk if configured
            $audioDiskStatus = 'not_configured';
            try {
                $audioDisk = Storage::disk('audio');
                $audioDisk->exists(''); // Test accessibility
                $audioDiskStatus = 'accessible';
            } catch (\Exception $e) {
                $audioDiskStatus = 'error: ' . $e->getMessage();
            }

            return [
                'status' => 'healthy',
                'response_time' => round($responseTime, 2),
                'default_disk' => 'accessible',
                'audio_disk' => $audioDiskStatus,
                'read_write' => $readContent === $testContent ? 'ok' : 'failed',
            ];

        } catch (\Exception $e) {
            Log::error('Storage health check failed', [
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);

            return [
                'status' => 'unhealthy',
                'error' => $e->getMessage(),
                'default_disk' => 'failed',
            ];
        }
    }

    /**
     * Check WebSocket server status
     */
    private function checkWebSocket(int $timeout): array
    {
        try {
            $reverbConfig = config('reverb.servers.reverb', []);
            $reverbHost = $reverbConfig['host'] ?? 'localhost';
            $reverbPort = $reverbConfig['port'] ?? 8080;
            $reverbScheme = 'http'; // Always HTTP for health checks
            
            $url = "{$reverbScheme}://{$reverbHost}:{$reverbPort}";
            
            $start = microtime(true);
            
            // Use cURL instead of file_get_contents for better control
            $ch = curl_init();
            curl_setopt($ch, CURLOPT_URL, $url);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_TIMEOUT, $timeout);
            curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, $timeout);
            curl_setopt($ch, CURLOPT_FOLLOWLOCATION, false);
            curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
            curl_setopt($ch, CURLOPT_FAILONERROR, false); // Don't fail on HTTP errors
            
            $result = curl_exec($ch);
            $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            $curlError = curl_error($ch);
            curl_close($ch);
            
            $responseTime = (microtime(true) - $start) * 1000;
            
            // Consider it healthy if we got any HTTP response (including 404)
            $isHealthy = $result !== false && $httpCode > 0 && empty($curlError);

            return [
                'status' => $isHealthy ? 'healthy' : 'unhealthy',
                'response_time' => round($responseTime, 2),
                'url' => $url,
                'connection' => $isHealthy ? 'active' : 'failed',
                'http_code' => $httpCode,
                'error' => $curlError ?: null,
            ];

        } catch (\Exception $e) {
            return [
                'status' => 'unhealthy',
                'error' => $e->getMessage(),
                'connection' => 'failed',
            ];
        }
    }

    /**
     * Get system metrics
     */
    private function getSystemMetrics(): array
    {
        return [
            'memory_usage' => [
                'current' => memory_get_usage(true),
                'peak' => memory_get_peak_usage(true),
                'formatted_current' => $this->formatBytes(memory_get_usage(true)),
                'formatted_peak' => $this->formatBytes(memory_get_peak_usage(true)),
            ],
            'disk_usage' => $this->getDiskUsage(),
            'load_average' => $this->getLoadAverage(),
            'uptime' => $this->getUptime(),
        ];
    }

    /**
     * Collect application metrics
     */
    private function collectMetrics(): array
    {
        $metrics = [];

        // Get cached metrics from the last hour
        $currentHour = date('Y-m-d-H');
        $metricsData = Cache::get("metrics:{$currentHour}", []);

        if (!empty($metricsData)) {
            $metrics['requests'] = [
                'total' => count($metricsData),
                'avg_response_time' => $this->calculateAverage($metricsData, 'execution_time'),
                'max_response_time' => $this->calculateMax($metricsData, 'execution_time'),
                'avg_memory_usage' => $this->calculateAverage($metricsData, 'memory_usage'),
                'max_memory_usage' => $this->calculateMax($metricsData, 'memory_usage'),
            ];

            // Status code distribution
            $statusCodes = array_count_values(array_column($metricsData, 'status_code'));
            $metrics['status_codes'] = $statusCodes;

            // Route performance
            $routeMetrics = [];
            foreach ($metricsData as $data) {
                $route = $data['route'] ?? 'unknown';
                if (!isset($routeMetrics[$route])) {
                    $routeMetrics[$route] = [];
                }
                $routeMetrics[$route][] = $data['execution_time'];
            }

            foreach ($routeMetrics as $route => $times) {
                $metrics['routes'][$route] = [
                    'count' => count($times),
                    'avg_time' => array_sum($times) / count($times),
                    'max_time' => max($times),
                ];
            }
        }

        return $metrics;
    }

    /**
     * Get disk usage information
     */
    private function getDiskUsage(): array
    {
        $storagePath = storage_path();
        
        if (function_exists('disk_free_space') && function_exists('disk_total_space')) {
            $freeBytes = disk_free_space($storagePath);
            $totalBytes = disk_total_space($storagePath);
            $usedBytes = $totalBytes - $freeBytes;
            $usagePercent = ($usedBytes / $totalBytes) * 100;

            return [
                'total' => $totalBytes,
                'used' => $usedBytes,
                'free' => $freeBytes,
                'usage_percent' => round($usagePercent, 2),
                'formatted_total' => $this->formatBytes($totalBytes),
                'formatted_used' => $this->formatBytes($usedBytes),
                'formatted_free' => $this->formatBytes($freeBytes),
            ];
        }

        return ['error' => 'Disk usage functions not available'];
    }

    /**
     * Get system load average
     */
    private function getLoadAverage(): array
    {
        if (function_exists('sys_getloadavg')) {
            $load = sys_getloadavg();
            return [
                '1min' => $load[0],
                '5min' => $load[1],
                '15min' => $load[2],
            ];
        }

        return ['error' => 'Load average not available'];
    }

    /**
     * Get system uptime
     */
    private function getUptime(): array
    {
        if (file_exists('/proc/uptime')) {
            $uptime = file_get_contents('/proc/uptime');
            $uptimeSeconds = (float) explode(' ', $uptime)[0];
            
            return [
                'seconds' => $uptimeSeconds,
                'formatted' => $this->formatUptime($uptimeSeconds),
            ];
        }

        return ['error' => 'Uptime not available'];
    }

    /**
     * Calculate average from array of data
     */
    private function calculateAverage(array $data, string $key): float
    {
        $values = array_column($data, $key);
        return count($values) > 0 ? array_sum($values) / count($values) : 0;
    }

    /**
     * Calculate maximum from array of data
     */
    private function calculateMax(array $data, string $key): float
    {
        $values = array_column($data, $key);
        return count($values) > 0 ? max($values) : 0;
    }

    /**
     * Format bytes to human readable format
     */
    private function formatBytes(int $bytes): string
    {
        $units = ['B', 'KB', 'MB', 'GB', 'TB'];
        $bytes = max($bytes, 0);
        $pow = floor(($bytes ? log($bytes) : 0) / log(1024));
        $pow = min($pow, count($units) - 1);
        
        $bytes /= (1 << (10 * $pow));
        
        return round($bytes, 2) . ' ' . $units[$pow];
    }

    /**
     * Format uptime seconds to human readable format
     */
    private function formatUptime(float $seconds): string
    {
        $days = floor($seconds / 86400);
        $hours = floor(($seconds % 86400) / 3600);
        $minutes = floor(($seconds % 3600) / 60);
        
        return "{$days}d {$hours}h {$minutes}m";
    }
}