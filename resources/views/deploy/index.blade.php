<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="csrf-token" content="{{ csrf_token() }}">
    <title>Laravel CI/CD Deploy Dashboard</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://unpkg.com/alpinejs@3.x.x/dist/cdn.min.js" defer></script>
</head>
<body class="bg-gray-900 text-white min-h-screen">
    <div class="container mx-auto px-4 py-8" x-data="deployApp()">
        <!-- Header -->
        <div class="text-center mb-8">
            <h1 class="text-4xl font-bold text-red-500 mb-2">Laravel CI/CD</h1>
            <p class="text-gray-400">Deployment Dashboard</p>
        </div>

        <!-- Status Cards -->
        <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
            <div class="bg-gray-800 p-4 rounded-lg">
                <h3 class="text-sm font-medium text-gray-400">App Status</h3>
                <p class="text-2xl font-bold text-green-400" x-text="status.app_status"></p>
            </div>
            <div class="bg-gray-800 p-4 rounded-lg">
                <h3 class="text-sm font-medium text-gray-400">Database</h3>
                <p class="text-2xl font-bold" :class="status.database === 'connected' ? 'text-green-400' : 'text-red-400'" x-text="status.database"></p>
            </div>
            <div class="bg-gray-800 p-4 rounded-lg">
                <h3 class="text-sm font-medium text-gray-400">Cache</h3>
                <p class="text-2xl font-bold" :class="status.cache === 'working' ? 'text-green-400' : 'text-red-400'" x-text="status.cache"></p>
            </div>
            <div class="bg-gray-800 p-4 rounded-lg">
                <h3 class="text-sm font-medium text-gray-400">Queue</h3>
                <p class="text-2xl font-bold text-blue-400" x-text="status.queue"></p>
            </div>
        </div>

        <!-- Deploy Buttons -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
            <button @click="deploy('staging')" 
                    :disabled="isDeploying"
                    class="bg-blue-600 hover:bg-blue-700 disabled:bg-gray-600 px-6 py-4 rounded-lg font-medium transition-colors">
                <span x-show="!isDeploying || deployType !== 'staging'">🚀 Deploy to Staging</span>
                <span x-show="isDeploying && deployType === 'staging'">⏳ Deploying...</span>
            </button>
            
            <button @click="deploy('production')" 
                    :disabled="isDeploying"
                    class="bg-red-600 hover:bg-red-700 disabled:bg-gray-600 px-6 py-4 rounded-lg font-medium transition-colors">
                <span x-show="!isDeploying || deployType !== 'production'">🔥 Deploy to Production</span>
                <span x-show="isDeploying && deployType === 'production'">⏳ Deploying...</span>
            </button>
            
            <button @click="deploy('rollback')" 
                    :disabled="isDeploying"
                    class="bg-yellow-600 hover:bg-yellow-700 disabled:bg-gray-600 px-6 py-4 rounded-lg font-medium transition-colors">
                <span x-show="!isDeploying || deployType !== 'rollback'">🔄 Rollback</span>
                <span x-show="isDeploying && deployType === 'rollback'">⏳ Rolling back...</span>
            </button>
        </div>

        <!-- Output Console -->
        <div class="bg-black rounded-lg p-4 mb-4" x-show="output.length > 0">
            <h3 class="text-green-400 font-mono mb-2">Deploy Output:</h3>
            <div class="font-mono text-sm space-y-1">
                <template x-for="line in output" :key="line.command">
                    <div>
                        <div class="text-yellow-400">$ <span x-text="line.command"></span></div>
                        <div class="text-gray-300 ml-2" x-text="line.output"></div>
                    </div>
                </template>
            </div>
        </div>

        <!-- Last Deployment Info -->
        <div class="bg-gray-800 rounded-lg p-4" x-show="status.last_deployment">
            <h3 class="text-lg font-medium mb-2">Last Deployment</h3>
            <div class="text-sm text-gray-400">
                <p>Time: <span x-text="status.last_deployment?.timestamp"></span></p>
                <p>Type: <span x-text="status.last_deployment?.type"></span></p>
                <p>Status: <span x-text="status.last_deployment?.status" :class="status.last_deployment?.status === 'success' ? 'text-green-400' : 'text-red-400'"></span></p>
            </div>
        </div>

        <!-- Success/Error Messages -->
        <div x-show="message" class="fixed top-4 right-4 p-4 rounded-lg shadow-lg" :class="messageType === 'success' ? 'bg-green-600' : 'bg-red-600'">
            <p x-text="message"></p>
        </div>
    </div>

    <script>
        function deployApp() {
            return {
                status: {
                    app_status: 'loading...',
                    database: 'checking...',
                    cache: 'checking...',
                    queue: 'checking...',
                    last_deployment: null
                },
                isDeploying: false,
                deployType: '',
                output: [],
                message: '',
                messageType: 'success',

                init() {
                    this.loadStatus();
                },

                async loadStatus() {
                    try {
                        const response = await fetch('/deploy/status');
                        this.status = await response.json();
                    } catch (error) {
                        console.error('Failed to load status:', error);
                    }
                },

                async deploy(type) {
                    this.isDeploying = true;
                    this.deployType = type;
                    this.output = [];
                    this.message = '';

                    try {
                        const response = await fetch('/deploy', {
                            method: 'POST',
                            headers: {
                                'Content-Type': 'application/json',
                                'X-CSRF-TOKEN': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
                            },
                            body: JSON.stringify({ type: type })
                        });

                        const result = await response.json();
                        
                        if (result.success) {
                            this.output = result.output || [];
                            this.message = result.message;
                            this.messageType = 'success';
                            this.loadStatus(); // Refresh status
                        } else {
                            this.message = result.message;
                            this.messageType = 'error';
                        }
                    } catch (error) {
                        this.message = 'Deployment failed: ' + error.message;
                        this.messageType = 'error';
                    } finally {
                        this.isDeploying = false;
                        this.deployType = '';
                        
                        // Clear message after 5 seconds
                        setTimeout(() => {
                            this.message = '';
                        }, 5000);
                    }
                }
            }
        }
    </script>
</body>
</html>
