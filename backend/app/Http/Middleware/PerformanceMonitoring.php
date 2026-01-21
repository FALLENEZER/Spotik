<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Cache;
use Symfony\Component\HttpFoundation\Response;

class PerformanceMonitoring
{
    /**
     * Handle an incoming request.
     */
    public function handle(Request $request, Closure $next): Response
    {
        if (!config('monitoring.enabled') || !config('monitoring.http.enabled')) {
            return $next($request);
        }

        // Skip monitoring for excluded paths
        $excludePaths = config('monitoring.http.exclude_paths', []);
        foreach ($excludePaths as $path) {
            if ($request->is(trim($path, '/'))) {
                return $next($request);
            }
        }

        $startTime = microtime(true);
        $startMemory = memory_get_usage(true);

        // Process the request
        $response = $next($request);

        $endTime = microtime(true);
        $endMemory = memory_get_usage(true);

        $executionTime = ($endTime - $startTime) * 1000; // Convert to milliseconds
        $memoryUsage = $endMemory - $startMemory;
        $peakMemory = memory_get_peak_usage(true);

        // Log performance metrics
        $this->logPerformanceMetrics($request, $response, [
            'execution_time' => $executionTime,
            'memory_usage' => $memoryUsage,
            'peak_memory' => $peakMemory,
            'start_memory' => $startMemory,
            'end_memory' => $endMemory,
        ]);

        // Add performance headers in debug mode
        if (config('app.debug')) {
            $response->headers->set('X-Execution-Time', round($executionTime, 2) . 'ms');
            $response->headers->set('X-Memory-Usage', $this->formatBytes($memoryUsage));
            $response->headers->set('X-Peak-Memory', $this->formatBytes($peakMemory));
        }

        return $response;
    }

    /**
     * Log performance metrics
     */
    private function logPerformanceMetrics(Request $request, Response $response, array $metrics): void
    {
        $slowRequestThreshold = config('monitoring.http.slow_request_threshold', 2000);
        $memoryThreshold = config('monitoring.memory.threshold', 128) * 1024 * 1024; // Convert MB to bytes

        $logData = [
            'method' => $request->method(),
            'url' => $request->fullUrl(),
            'route' => $request->route()?->getName(),
            'status_code' => $response->getStatusCode(),
            'execution_time' => round($metrics['execution_time'], 2),
            'memory_usage' => $this->formatBytes($metrics['memory_usage']),
            'peak_memory' => $this->formatBytes($metrics['peak_memory']),
            'user_id' => $request->user()?->id,
            'ip_address' => $request->ip(),
            'user_agent' => $request->userAgent(),
        ];

        // Log all requests if enabled
        if (config('monitoring.http.log_requests')) {
            Log::info('HTTP Request', $logData);
        }

        // Log slow requests
        if (config('monitoring.http.log_slow_requests') && $metrics['execution_time'] > $slowRequestThreshold) {
            Log::warning('Slow HTTP Request', array_merge($logData, [
                'threshold' => $slowRequestThreshold,
                'exceeded_by' => round($metrics['execution_time'] - $slowRequestThreshold, 2),
            ]));
        }

        // Log high memory usage
        if (config('monitoring.memory.log_high_usage') && $metrics['peak_memory'] > $memoryThreshold) {
            Log::warning('High Memory Usage', array_merge($logData, [
                'threshold' => $this->formatBytes($memoryThreshold),
                'exceeded_by' => $this->formatBytes($metrics['peak_memory'] - $memoryThreshold),
            ]));
        }

        // Store metrics in cache for aggregation
        $this->storeMetrics($request, $response, $metrics);
    }

    /**
     * Store metrics in cache for aggregation
     */
    private function storeMetrics(Request $request, Response $response, array $metrics): void
    {
        if (!config('monitoring.metrics.enabled')) {
            return;
        }

        $cacheKey = 'metrics:' . date('Y-m-d-H'); // Hourly buckets
        $metricsData = Cache::get($cacheKey, []);

        $metricsData[] = [
            'timestamp' => time(),
            'method' => $request->method(),
            'route' => $request->route()?->getName(),
            'status_code' => $response->getStatusCode(),
            'execution_time' => $metrics['execution_time'],
            'memory_usage' => $metrics['memory_usage'],
            'peak_memory' => $metrics['peak_memory'],
        ];

        // Keep only last 1000 entries per hour to prevent memory issues
        if (count($metricsData) > 1000) {
            $metricsData = array_slice($metricsData, -1000);
        }

        Cache::put($cacheKey, $metricsData, 3600); // Store for 1 hour
    }

    /**
     * Format bytes to human readable format
     */
    private function formatBytes(int $bytes): string
    {
        $units = ['B', 'KB', 'MB', 'GB'];
        $bytes = max($bytes, 0);
        $pow = floor(($bytes ? log($bytes) : 0) / log(1024));
        $pow = min($pow, count($units) - 1);
        
        $bytes /= (1 << (10 * $pow));
        
        return round($bytes, 2) . ' ' . $units[$pow];
    }
}