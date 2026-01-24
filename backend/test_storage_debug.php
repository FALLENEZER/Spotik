<?php

require __DIR__ . '/vendor/autoload.php';

$app = require_once __DIR__ . '/bootstrap/app.php';

$kernel = $app->make(Illuminate\Contracts\Console\Kernel::class);
$kernel->bootstrap();

use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Log;

echo "Testing Storage public disk...\n";

try {
    $disk = Storage::disk('public');
    echo "Disk root: " . $disk->path('') . "\n";
    
    $path = 'room_covers/a0ea6030-68e3-4354-9db7-e97764aa3bba.png';
    echo "Checking existence of: $path\n";
    
    if ($disk->exists($path)) {
        echo "File exists.\n";
    } else {
        echo "File does not exist (This is expected if ls failed).\n";
    }
    
    // Check if we can write and read
    $testFile = 'test_debug.txt';
    $disk->put($testFile, 'Hello World');
    echo "Wrote test file to: " . $disk->path($testFile) . "\n";
    
    if ($disk->exists($testFile)) {
        echo "Test file verified.\n";
        $disk->delete($testFile);
        echo "Test file deleted.\n";
    } else {
        echo "FAILED to verify test file.\n";
    }

} catch (\Exception $e) {
    echo "EXCEPTION caught: " . $e->getMessage() . "\n";
    echo $e->getTraceAsString();
}
