<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

// Deploy routes
Route::get('/deploy', [App\Http\Controllers\DeployController::class, 'index'])->name('deploy.index');
Route::post('/deploy', [App\Http\Controllers\DeployController::class, 'deploy'])->name('deploy.execute');
Route::get('/deploy/status', [App\Http\Controllers\DeployController::class, 'status'])->name('deploy.status');
