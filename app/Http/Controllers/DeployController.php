<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Process;
use Illuminate\Support\Facades\Log;

class DeployController extends Controller
{
    public function index()
    {
        return view('deploy.index');
    }

    public function deploy(Request $request)
    {
        try {
            $deployType = $request->input('type', 'staging');

            // Log deployment attempt
            Log::info("Deployment started", ['type' => $deployType, 'user' => request()->ip()]);

            $commands = [];

            switch ($deployType) {
                case 'staging':
                    $commands = [
                        'echo "🚀 Starting Staging Deployment..."',
                        'php artisan config:clear',
                        'php artisan cache:clear',
                        'php artisan route:clear',
                        'php artisan view:clear',
                        'echo "✅ Staging deployment completed!"'
                    ];
                    break;

                case 'production':
                    $commands = [
                        'echo "🚀 Starting Production Deployment..."',
                        'php artisan down --message="Deploying updates..." --retry=60',
                        'php artisan config:cache',
                        'php artisan route:cache',
                        'php artisan view:cache',
                        'php artisan migrate --force',
                        'php artisan up',
                        'echo "✅ Production deployment completed!"'
                    ];
                    break;

                case 'rollback':
                    $commands = [
                        'echo "🔄 Starting Rollback..."',
                        'php artisan migrate:rollback',
                        'php artisan config:clear',
                        'php artisan cache:clear',
                        'echo "✅ Rollback completed!"'
                    ];
                    break;
            }

            $output = [];
            foreach ($commands as $command) {
                $result = shell_exec($command . ' 2>&1');
                $output[] = [
                    'command' => $command,
                    'output' => $result
                ];
            }

            Log::info("Deployment completed", ['type' => $deployType, 'success' => true]);

            return response()->json([
                'success' => true,
                'message' => ucfirst($deployType) . ' deployment completed successfully!',
                'output' => $output,
                'timestamp' => now()->toDateTimeString()
            ]);

        } catch (\Exception $e) {
            Log::error("Deployment failed", ['error' => $e->getMessage()]);

            return response()->json([
                'success' => false,
                'message' => 'Deployment failed: ' . $e->getMessage(),
                'timestamp' => now()->toDateTimeString()
            ], 500);
        }
    }

    public function status()
    {
        $status = [
            'app_status' => 'running',
            'database' => $this->checkDatabase(),
            'cache' => $this->checkCache(),
            'queue' => $this->checkQueue(),
            'last_deployment' => $this->getLastDeployment()
        ];

        return response()->json($status);
    }

    private function checkDatabase()
    {
        try {
            \DB::connection()->getPdo();
            return 'connected';
        } catch (\Exception $e) {
            return 'disconnected';
        }
    }

    private function checkCache()
    {
        try {
            \Cache::put('health_check', 'ok', 10);
            return \Cache::get('health_check') === 'ok' ? 'working' : 'failed';
        } catch (\Exception $e) {
            return 'failed';
        }
    }

    private function checkQueue()
    {
        return config('queue.default');
    }

    private function getLastDeployment()
    {
        // This would typically come from a database or log file
        return [
            'timestamp' => now()->subHours(2)->toDateTimeString(),
            'type' => 'staging',
            'status' => 'success'
        ];
    }
}
