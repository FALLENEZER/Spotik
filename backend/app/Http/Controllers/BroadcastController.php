<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Broadcast;

class BroadcastController extends Controller
{
    /**
     * Authenticate the request for broadcasting.
     */
    public function authenticate(Request $request)
    {
        try {
            $user = $request->auth_user;
            
            if (!$user) {
                return response()->json([
                    'success' => false,
                    'message' => 'Unauthenticated'
                ], 401);
            }

            // Use Laravel's built-in broadcast authentication
            if (!$request->user()) {
                $request->setUserResolver(function () use ($user) {
                    return $user;
                });
            }
            return Broadcast::auth($request);

        } catch (\Exception $e) {
            \Illuminate\Support\Facades\Log::error('Broadcast auth error: ' . $e->getMessage());
            \Illuminate\Support\Facades\Log::error($e->getTraceAsString());
            
            return response()->json([
                'success' => false,
                'message' => 'Failed to authenticate for broadcasting',
                'error' => $e->getMessage()
            ], 500);
        }
    }
}