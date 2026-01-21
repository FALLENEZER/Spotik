<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class CorsMiddleware
{
    /**
     * Handle an incoming request.
     */
    public function handle(Request $request, Closure $next): Response
    {
        $response = $next($request);

        $response->headers->set('Access-Control-Allow-Origin', $this->getAllowedOrigins($request));
        $response->headers->set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
        $response->headers->set('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With, Accept, Origin');
        $response->headers->set('Access-Control-Allow-Credentials', 'true');
        $response->headers->set('Access-Control-Max-Age', '86400');

        // Handle preflight requests
        if ($request->getMethod() === 'OPTIONS') {
            $response->setStatusCode(200);
        }

        return $response;
    }

    /**
     * Get allowed origins based on environment
     */
    private function getAllowedOrigins(Request $request): string
    {
        $allowedOrigins = [
            'http://localhost:3000',
            'http://localhost:8080',
            'http://127.0.0.1:3000',
            'http://127.0.0.1:8080',
        ];

        // Add production origins from environment
        if (env('FRONTEND_URL')) {
            $allowedOrigins[] = env('FRONTEND_URL');
        }

        $origin = $request->headers->get('Origin');
        
        if (in_array($origin, $allowedOrigins)) {
            return $origin;
        }

        // Default to first allowed origin
        return $allowedOrigins[0];
    }
}