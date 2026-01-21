<?php

namespace App\Http\Controllers;

use App\Models\Room;
use App\Models\Track;
use App\Events\TrackVoted;
use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;

class VoteController extends Controller
{
    /**
     * Vote for a track
     */
    public function vote(Request $request, Room $room, Track $track): JsonResponse
    {
        try {
            $user = $request->user();

            // Check if user is participant of the room
            if (!$room->hasParticipant($user)) {
                return response()->json([
                    'error' => 'You must be a participant of this room to vote'
                ], 403);
            }

            // Check if track belongs to the room
            if ($track->room_id !== $room->id) {
                return response()->json([
                    'error' => 'Track does not belong to this room'
                ], 404);
            }

            // Add vote (will not duplicate if already exists)
            $vote = $track->addVote($user);
            $wasNewVote = $vote->wasRecentlyCreated;

            // Broadcast vote event if it was a new vote
            if ($wasNewVote) {
                broadcast(new TrackVoted($track->fresh(), $user, $room, true))->toOthers();
            }

            return response()->json([
                'message' => $wasNewVote ? 'Vote added successfully' : 'Vote already exists',
                'vote_score' => $track->fresh()->vote_score,
                'user_has_voted' => true,
            ]);

        } catch (\Exception $e) {
            return response()->json([
                'error' => 'Failed to vote for track',
                'message' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * Remove vote for a track
     */
    public function unvote(Request $request, Room $room, Track $track): JsonResponse
    {
        try {
            $user = $request->user();

            // Check if user is participant of the room
            if (!$room->hasParticipant($user)) {
                return response()->json([
                    'error' => 'You must be a participant of this room to remove votes'
                ], 403);
            }

            // Check if track belongs to the room
            if ($track->room_id !== $room->id) {
                return response()->json([
                    'error' => 'Track does not belong to this room'
                ], 404);
            }

            // Remove vote
            $voteRemoved = $track->removeVote($user);

            // Broadcast vote event if vote was actually removed
            if ($voteRemoved) {
                broadcast(new TrackVoted($track->fresh(), $user, $room, false))->toOthers();
            }

            return response()->json([
                'message' => $voteRemoved ? 'Vote removed successfully' : 'No vote to remove',
                'vote_score' => $track->fresh()->vote_score,
                'user_has_voted' => false,
            ]);

        } catch (\Exception $e) {
            return response()->json([
                'error' => 'Failed to remove vote',
                'message' => $e->getMessage()
            ], 500);
        }
    }
}