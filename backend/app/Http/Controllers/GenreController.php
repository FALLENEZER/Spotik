<?php

namespace App\Http\Controllers;

use App\Models\Genre;
use App\Http\Resources\GenreResource;
use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Validator;

class GenreController extends Controller
{
    /**
     * Display a listing of genres.
     */
    public function index(Request $request): JsonResponse
    {
        try {
            $genres = Genre::withCount('tracks')
                          ->orderBy('name')
                          ->get();

            return response()->json([
                'success' => true,
                'message' => 'Genres retrieved successfully',
                'data' => GenreResource::collection($genres)
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to retrieve genres',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Store a newly created genre.
     */
    public function store(Request $request): JsonResponse
    {
        try {
            $validator = Validator::make($request->all(), [
                'name' => 'required|string|max:100|unique:genres,name',
                'description' => 'nullable|string|max:500',
                'color' => 'nullable|string|regex:/^#[0-9A-Fa-f]{6}$/',
            ]);

            if ($validator->fails()) {
                return response()->json([
                    'success' => false,
                    'message' => 'Validation failed',
                    'errors' => $validator->errors()
                ], 422);
            }

            $genre = Genre::create($request->only(['name', 'description', 'color']));

            return response()->json([
                'success' => true,
                'message' => 'Genre created successfully',
                'data' => new GenreResource($genre)
            ], 201);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to create genre',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Display the specified genre.
     */
    public function show(Genre $genre): JsonResponse
    {
        try {
            $genre->load('tracks');
            $genre->loadCount('tracks');

            return response()->json([
                'success' => true,
                'message' => 'Genre retrieved successfully',
                'data' => new GenreResource($genre)
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to retrieve genre',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Update the specified genre.
     */
    public function update(Request $request, Genre $genre): JsonResponse
    {
        try {
            $validator = Validator::make($request->all(), [
                'name' => 'sometimes|string|max:100|unique:genres,name,' . $genre->id,
                'description' => 'nullable|string|max:500',
                'color' => 'nullable|string|regex:/^#[0-9A-Fa-f]{6}$/',
            ]);

            if ($validator->fails()) {
                return response()->json([
                    'success' => false,
                    'message' => 'Validation failed',
                    'errors' => $validator->errors()
                ], 422);
            }

            $genre->update($request->only(['name', 'description', 'color']));

            return response()->json([
                'success' => true,
                'message' => 'Genre updated successfully',
                'data' => new GenreResource($genre)
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to update genre',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Remove the specified genre.
     */
    public function destroy(Genre $genre): JsonResponse
    {
        try {
            // Check if genre has tracks
            if ($genre->tracks()->count() > 0) {
                return response()->json([
                    'success' => false,
                    'message' => 'Cannot delete genre with existing tracks',
                    'error' => 'Genre has associated tracks'
                ], 409);
            }

            $genre->delete();

            return response()->json([
                'success' => true,
                'message' => 'Genre deleted successfully'
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to delete genre',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Get popular genres (with most tracks)
     */
    public function popular(Request $request): JsonResponse
    {
        try {
            $limit = $request->get('limit', 10);
            
            $genres = Genre::popular($limit)->get();

            return response()->json([
                'success' => true,
                'message' => 'Popular genres retrieved successfully',
                'data' => GenreResource::collection($genres)
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Failed to retrieve popular genres',
                'error' => $e->getMessage()
            ], 500);
        }
    }
}