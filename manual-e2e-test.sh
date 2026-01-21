#!/bin/bash

# Manual End-to-End Testing Script for Spotik
# This script provides a comprehensive manual testing guide

echo "🎵 Spotik End-to-End Testing Script"
echo "=================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print test step
print_step() {
    echo -e "${BLUE}📋 $1${NC}"
}

# Function to print success
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Function to print warning
print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Function to print error
print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to wait for user input
wait_for_user() {
    echo -e "${YELLOW}Press Enter to continue...${NC}"
    read
}

echo "This script will guide you through comprehensive end-to-end testing of Spotik."
echo "Make sure the application is running before proceeding."
echo ""

# Check if Docker is running
print_step "Checking Docker status..."
if docker ps > /dev/null 2>&1; then
    print_success "Docker is running"
else
    print_error "Docker is not running. Please start Docker first."
    exit 1
fi

# Check if application containers are running
print_step "Checking application containers..."
if docker-compose ps | grep -q "Up"; then
    print_success "Application containers are running"
else
    print_warning "Some containers may not be running. Starting application..."
    docker-compose up -d
    sleep 10
fi

echo ""
echo "🧪 MANUAL TESTING CHECKLIST"
echo "=========================="
echo ""

# Test 1: User Registration and Authentication
print_step "TEST 1: User Registration and Authentication"
echo "1. Open browser and navigate to http://localhost:3000"
echo "2. Click 'Register' or navigate to registration page"
echo "3. Fill in registration form:"
echo "   - Username: testuser1"
echo "   - Email: test1@example.com"
echo "   - Password: SecurePass123!"
echo "4. Submit registration form"
echo "5. Verify successful registration message"
echo "6. Login with the same credentials"
echo "7. Verify successful login and redirect to dashboard"
wait_for_user

# Test 2: Room Creation and Management
print_step "TEST 2: Room Creation and Management"
echo "1. From dashboard, click 'Create Room'"
echo "2. Enter room name: 'Test Collaborative Room'"
echo "3. Submit room creation form"
echo "4. Verify redirect to room interface"
echo "5. Verify you are shown as room administrator"
echo "6. Note the room ID/URL for later use"
wait_for_user

# Test 3: File Upload and Validation
print_step "TEST 3: File Upload and Validation"
echo "1. In the room interface, locate file upload area"
echo "2. Try uploading an invalid file (e.g., .txt file)"
echo "3. Verify error message for invalid file type"
echo "4. Upload a valid audio file (MP3, WAV, or M4A)"
echo "5. Verify file appears in track queue"
echo "6. Verify file information is displayed correctly"
wait_for_user

# Test 4: Multi-User Testing (Second Browser/Incognito)
print_step "TEST 4: Multi-User Testing"
echo "1. Open a second browser window or incognito mode"
echo "2. Navigate to http://localhost:3000"
echo "3. Register a second user:"
echo "   - Username: testuser2"
echo "   - Email: test2@example.com"
echo "   - Password: SecurePass456!"
echo "4. Login with second user credentials"
echo "5. Join the room created by first user (use room URL/ID)"
echo "6. Verify both users appear in participant list"
echo "7. Upload a different audio file from second user"
echo "8. Verify both tracks appear in queue"
wait_for_user

# Test 5: Track Voting System
print_step "TEST 5: Track Voting System"
echo "1. From second user, vote for first user's track"
echo "2. From first user, vote for second user's track"
echo "3. Verify vote counts update in real-time"
echo "4. Verify track queue reorders by vote score"
echo "5. Try removing a vote and verify count decreases"
wait_for_user

# Test 6: WebSocket Real-Time Events
print_step "TEST 6: WebSocket Real-Time Events"
echo "1. Keep both browser windows visible side by side"
echo "2. From one user, upload a new track"
echo "3. Verify the track appears immediately in other user's queue"
echo "4. From one user, vote for a track"
echo "5. Verify vote count updates immediately for other user"
echo "6. Have one user leave the room"
echo "7. Verify participant list updates for remaining user"
wait_for_user

# Test 7: Playback Controls (Admin Only)
print_step "TEST 7: Playback Controls"
echo "1. From first user (room admin), start playback of a track"
echo "2. Verify playback controls are visible for admin"
echo "3. Verify playback controls are disabled/hidden for second user"
echo "4. From admin, pause the track"
echo "5. Verify pause state updates for both users"
echo "6. From admin, resume playback"
echo "7. Verify resume state updates for both users"
echo "8. From admin, skip to next track"
echo "9. Verify track change for both users"
wait_for_user

# Test 8: Audio Synchronization
print_step "TEST 8: Audio Synchronization"
echo "1. Start playback from admin user"
echo "2. Listen to audio from both browser windows"
echo "3. Verify audio is synchronized (no echo/delay)"
echo "4. Pause and resume from admin"
echo "5. Verify both users pause/resume simultaneously"
echo "6. Check playback position consistency"
wait_for_user

# Test 9: Error Handling
print_step "TEST 9: Error Handling"
echo "1. Try accessing admin controls from non-admin user"
echo "2. Verify appropriate error message"
echo "3. Try uploading oversized file (if size limits exist)"
echo "4. Try joining non-existent room"
echo "5. Verify graceful error handling in all cases"
wait_for_user

# Test 10: Connection Resilience
print_step "TEST 10: Connection Resilience"
echo "1. Temporarily disconnect internet on one client"
echo "2. Perform actions on connected client"
echo "3. Reconnect internet on disconnected client"
echo "4. Verify client reconnects and syncs state"
echo "5. Test WebSocket reconnection behavior"
wait_for_user

# Test 11: Performance and Load
print_step "TEST 11: Performance Testing"
echo "1. Upload multiple large audio files"
echo "2. Have multiple users join the same room"
echo "3. Perform rapid voting actions"
echo "4. Monitor browser console for errors"
echo "5. Check network tab for failed requests"
echo "6. Verify responsive UI during heavy operations"
wait_for_user

# Test 12: Cross-Browser Compatibility
print_step "TEST 12: Cross-Browser Testing"
echo "1. Test in Chrome, Firefox, Safari, Edge"
echo "2. Verify audio playback works in all browsers"
echo "3. Verify WebSocket connections work"
echo "4. Check for browser-specific issues"
echo "5. Test on mobile browsers if possible"
wait_for_user

# Test 13: Data Persistence
print_step "TEST 13: Data Persistence"
echo "1. Create room and upload tracks"
echo "2. Refresh browser page"
echo "3. Verify room state persists"
echo "4. Verify track queue persists"
echo "5. Verify user session persists"
echo "6. Test logout and re-login"
wait_for_user

echo ""
echo "🏁 TESTING COMPLETE"
echo "=================="
echo ""

print_step "Final Verification Checklist:"
echo "□ User registration and authentication working"
echo "□ Room creation and management functional"
echo "□ File upload with validation working"
echo "□ Multi-user collaboration tested"
echo "□ Real-time WebSocket events working"
echo "□ Track voting system functional"
echo "□ Admin playback controls working"
echo "□ Audio synchronization verified"
echo "□ Error handling graceful"
echo "□ Connection resilience tested"
echo "□ Performance acceptable"
echo "□ Cross-browser compatibility checked"
echo "□ Data persistence verified"

echo ""
print_step "Automated Test Execution:"
echo "Run the following commands to execute automated tests:"
echo ""
echo "Frontend Tests:"
echo "cd frontend && npm test"
echo ""
echo "Backend Tests:"
echo "cd backend && php artisan test"
echo ""

print_step "Log Analysis:"
echo "Check the following logs for any errors:"
echo "- Browser Developer Console"
echo "- Docker container logs: docker-compose logs"
echo "- Laravel logs: backend/storage/logs/laravel.log"
echo ""

if [ "$1" = "--run-automated" ]; then
    print_step "Running automated tests..."
    
    echo "Running frontend tests..."
    cd frontend
    npm test -- --run
    cd ..
    
    echo "Running backend tests..."
    cd backend
    php artisan test
    cd ..
    
    print_success "Automated tests completed!"
fi

print_success "End-to-end testing guide completed!"
print_step "Document any issues found and verify all critical functionality works as expected."

echo ""
echo "For detailed test results, see: END_TO_END_TEST_RESULTS.md"
echo ""