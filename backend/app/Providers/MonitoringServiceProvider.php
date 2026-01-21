<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Redis;
use Illuminate\Database\Events\QueryExecuted;

class MonitoringServiceProvider extends ServiceProvider
{
    /**
     * Register services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap services.
     */
    public function boot(): void
    {
        if (!config('monitoring.enabled')) {
            return;
        }

        $this->setupDatabaseMonitoring();
        $this->setupRedisMonitoring();
    }

    /**
     * Setup database query monitoring
     */
    private function setupDatabaseMonitoring(): void
    {
        if (!config('monitoring.database.enabled')) {
            return;
        }

        DB::listen(function (QueryExecuted $query) {
            $executionTime = $query->time;
            $slowQueryThreshold = config('monitoring.database.slow_query_threshold', 1000);

            $logData = [
                'sql' => $query->sql,
                'bindings' => $query->bindings,
                'execution_time' => $executionTime,
                'connection' => $query->connectionName,
            ];

            // Log all queries if enabled
            if (config('monitoring.database.log_queries')) {
                Log::debug('Database Query', $logData);
            }

            // Log slow queries
            if (config('monitoring.database.log_slow_queries') && $executionTime > $slowQueryThreshold) {
                Log::warning('Slow Database Query', array_merge($logData, [
                    'threshold' => $slowQueryThreshold,
                    'exceeded_by' => $executionTime - $slowQueryThreshold,
                ]));
            }

            // Store query metrics
            $this->storeQueryMetrics($query, $executionTime);
        });
    }

    /**
     * Setup Redis command monitoring
     */
    private function setupRedisMonitoring(): void
    {
        if (!config('monitoring.redis.enabled')) {
            return;
        }

        // Note: Redis command monitoring would require a custom Redis client
        // or using Redis MONITOR command, which is not practical in production
        // This is a placeholder for future implementation
    }

    /**
     * Store query metrics for analysis
     */
    private function storeQueryMetrics(QueryExecuted $query, float $executionTime): void
    {
        if (!config('monitoring.metrics.enabled')) {
            return;
        }

        try {
            $cacheKey = 'db_metrics:' . date('Y-m-d-H');
            $metrics = cache()->get($cacheKey, []);

            $metrics[] = [
                'timestamp' => time(),
                'execution_time' => $executionTime,
                'connection' => $query->connectionName,
                'query_type' => $this->getQueryType($query->sql),
                'table' => $this->extractTableName($query->sql),
            ];

            // Keep only last 1000 entries per hour
            if (count($metrics) > 1000) {
                $metrics = array_slice($metrics, -1000);
            }

            cache()->put($cacheKey, $metrics, 3600);

        } catch (\Exception $e) {
            Log::error('Failed to store query metrics', [
                'error' => $e->getMessage(),
                'query' => $query->sql,
            ]);
        }
    }

    /**
     * Extract query type from SQL
     */
    private function getQueryType(string $sql): string
    {
        $sql = trim(strtoupper($sql));
        
        if (str_starts_with($sql, 'SELECT')) return 'SELECT';
        if (str_starts_with($sql, 'INSERT')) return 'INSERT';
        if (str_starts_with($sql, 'UPDATE')) return 'UPDATE';
        if (str_starts_with($sql, 'DELETE')) return 'DELETE';
        if (str_starts_with($sql, 'CREATE')) return 'CREATE';
        if (str_starts_with($sql, 'ALTER')) return 'ALTER';
        if (str_starts_with($sql, 'DROP')) return 'DROP';
        
        return 'OTHER';
    }

    /**
     * Extract table name from SQL query
     */
    private function extractTableName(string $sql): string
    {
        $sql = trim(strtoupper($sql));
        
        // Simple regex patterns for common queries
        $patterns = [
            '/SELECT.*?FROM\s+`?(\w+)`?/i',
            '/INSERT\s+INTO\s+`?(\w+)`?/i',
            '/UPDATE\s+`?(\w+)`?/i',
            '/DELETE\s+FROM\s+`?(\w+)`?/i',
        ];
        
        foreach ($patterns as $pattern) {
            if (preg_match($pattern, $sql, $matches)) {
                return strtolower($matches[1]);
            }
        }
        
        return 'unknown';
    }
}