<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

// Health check endpoint for load balancer
Route::get('/health', function () {
    return response()->json([
        'status' => 'ok',
        'timestamp' => now()->toISOString(),
        'environment' => app()->environment(),
        'version' => config('app.version', '1.0.0')
    ]);
});

// Deploy routes
Route::get('/deploy', [App\Http\Controllers\DeployController::class, 'index'])->name('deploy.index');
Route::post('/deploy', [App\Http\Controllers\DeployController::class, 'deploy'])->name('deploy.execute');
Route::get('/deploy/status', [App\Http\Controllers\DeployController::class, 'status'])->name('deploy.status');
