<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Performance Monitoring Configuration
    |--------------------------------------------------------------------------
    */

    'enabled' => env('MONITORING_ENABLED', true),

    /*
    |--------------------------------------------------------------------------
    | Database Query Monitoring
    |--------------------------------------------------------------------------
    */

    'database' => [
        'enabled' => env('DB_MONITORING_ENABLED', true),
        'slow_query_threshold' => env('DB_SLOW_QUERY_THRESHOLD', 1000), // milliseconds
        'log_queries' => env('DB_LOG_QUERIES', false),
        'log_slow_queries' => env('DB_LOG_SLOW_QUERIES', true),
    ],

    /*
    |--------------------------------------------------------------------------
    | Redis Monitoring
    |--------------------------------------------------------------------------
    */

    'redis' => [
        'enabled' => env('REDIS_MONITORING_ENABLED', true),
        'slow_command_threshold' => env('REDIS_SLOW_COMMAND_THRESHOLD', 100), // milliseconds
        'log_commands' => env('REDIS_LOG_COMMANDS', false),
        'log_slow_commands' => env('REDIS_LOG_SLOW_COMMANDS', true),
    ],

    /*
    |--------------------------------------------------------------------------
    | HTTP Request Monitoring
    |--------------------------------------------------------------------------
    */

    'http' => [
        'enabled' => env('HTTP_MONITORING_ENABLED', true),
        'slow_request_threshold' => env('HTTP_SLOW_REQUEST_THRESHOLD', 2000), // milliseconds
        'log_requests' => env('HTTP_LOG_REQUESTS', false),
        'log_slow_requests' => env('HTTP_LOG_SLOW_REQUESTS', true),
        'exclude_paths' => [
            '/ping',
            '/health',
            '/metrics',
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Memory Usage Monitoring
    |--------------------------------------------------------------------------
    */

    'memory' => [
        'enabled' => env('MEMORY_MONITORING_ENABLED', true),
        'threshold' => env('MEMORY_THRESHOLD', 128), // MB
        'log_high_usage' => env('MEMORY_LOG_HIGH_USAGE', true),
    ],

    /*
    |--------------------------------------------------------------------------
    | File Upload Monitoring
    |--------------------------------------------------------------------------
    */

    'file_uploads' => [
        'enabled' => env('FILE_UPLOAD_MONITORING_ENABLED', true),
        'log_uploads' => env('FILE_UPLOAD_LOG_UPLOADS', true),
        'log_failures' => env('FILE_UPLOAD_LOG_FAILURES', true),
        'track_sizes' => env('FILE_UPLOAD_TRACK_SIZES', true),
    ],

    /*
    |--------------------------------------------------------------------------
    | WebSocket Monitoring
    |--------------------------------------------------------------------------
    */

    'websocket' => [
        'enabled' => env('WEBSOCKET_MONITORING_ENABLED', true),
        'log_connections' => env('WEBSOCKET_LOG_CONNECTIONS', true),
        'log_disconnections' => env('WEBSOCKET_LOG_DISCONNECTIONS', true),
        'log_messages' => env('WEBSOCKET_LOG_MESSAGES', false),
        'connection_threshold' => env('WEBSOCKET_CONNECTION_THRESHOLD', 100),
    ],

    /*
    |--------------------------------------------------------------------------
    | Audio Streaming Monitoring
    |--------------------------------------------------------------------------
    */

    'audio_streaming' => [
        'enabled' => env('AUDIO_STREAMING_MONITORING_ENABLED', true),
        'log_streams' => env('AUDIO_STREAMING_LOG_STREAMS', true),
        'log_range_requests' => env('AUDIO_STREAMING_LOG_RANGE_REQUESTS', false),
        'track_bandwidth' => env('AUDIO_STREAMING_TRACK_BANDWIDTH', true),
    ],

    /*
    |--------------------------------------------------------------------------
    | Error Tracking
    |--------------------------------------------------------------------------
    */

    'error_tracking' => [
        'enabled' => env('ERROR_TRACKING_ENABLED', true),
        'log_level' => env('ERROR_TRACKING_LOG_LEVEL', 'error'),
        'include_context' => env('ERROR_TRACKING_INCLUDE_CONTEXT', true),
        'include_stack_trace' => env('ERROR_TRACKING_INCLUDE_STACK_TRACE', true),
        'exclude_exceptions' => [
            'Illuminate\Auth\AuthenticationException',
            'Illuminate\Validation\ValidationException',
            'Symfony\Component\HttpKernel\Exception\NotFoundHttpException',
        ],
    ],

    /*
    |--------------------------------------------------------------------------
    | Metrics Collection
    |--------------------------------------------------------------------------
    */

    'metrics' => [
        'enabled' => env('METRICS_ENABLED', true),
        'endpoint' => env('METRICS_ENDPOINT', '/metrics'),
        'collect_system_metrics' => env('METRICS_COLLECT_SYSTEM', true),
        'collect_app_metrics' => env('METRICS_COLLECT_APP', true),
        'retention_days' => env('METRICS_RETENTION_DAYS', 30),
    ],

    /*
    |--------------------------------------------------------------------------
    | Health Checks
    |--------------------------------------------------------------------------
    */

    'health_checks' => [
        'enabled' => env('HEALTH_CHECKS_ENABLED', true),
        'endpoint' => env('HEALTH_CHECKS_ENDPOINT', '/health'),
        'checks' => [
            'database' => true,
            'redis' => true,
            'storage' => true,
            'websocket' => true,
        ],
        'timeout' => env('HEALTH_CHECKS_TIMEOUT', 5), // seconds
    ],

    /*
    |--------------------------------------------------------------------------
    | Alerting Configuration
    |--------------------------------------------------------------------------
    */

    'alerts' => [
        'enabled' => env('ALERTS_ENABLED', false),
        'channels' => [
            'log' => true,
            'email' => env('ALERTS_EMAIL_ENABLED', false),
            'slack' => env('ALERTS_SLACK_ENABLED', false),
        ],
        'thresholds' => [
            'error_rate' => env('ALERT_ERROR_RATE_THRESHOLD', 5), // errors per minute
            'response_time' => env('ALERT_RESPONSE_TIME_THRESHOLD', 5000), // milliseconds
            'memory_usage' => env('ALERT_MEMORY_USAGE_THRESHOLD', 80), // percentage
            'disk_usage' => env('ALERT_DISK_USAGE_THRESHOLD', 85), // percentage
        ],
    ],

];