<!---
    Lot Scraping Module - Auction Lot Scraping
    Manages NumisBids scraping and stores in unified chunks table
--->

<cfmodule template="layout.cfm" title="Lot Scraping" currentPage="lots">

<div class="fade-in">
    <!-- Header -->
    <div class="bg-white rounded-xl shadow-sm p-6 mb-6">
        <h1 class="text-3xl font-bold text-gray-800 flex items-center">
            🏷️ <span class="ml-3">Auction Lot Scraping</span>
        </h1>
        <p class="text-gray-600 mt-2">Scrape auction lots from NumisBids and manage your lot database</p>
    </div>

    <!-- Real-time Monitoring Dashboard -->
    <div id="monitoringDashboard" class="bg-white rounded-xl shadow-sm p-6 mb-6" style="display: none;">
        <h2 class="text-xl font-semibold text-gray-800 mb-4 flex items-center justify-between">
            <span>📊 <span class="ml-2">Real-time Monitoring</span></span>
            <button onclick="toggleMonitoring()" class="text-sm text-gray-500 hover:text-gray-700">Hide</button>
        </h2>
        
        <!-- Current Status -->
        <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
            <div class="bg-blue-50 rounded-lg p-4">
                <div class="text-sm text-blue-600 font-medium mb-1">Current Event ID</div>
                <div id="currentEventId" class="text-2xl font-bold text-blue-800">-</div>
            </div>
            <div class="bg-green-50 rounded-lg p-4">
                <div class="text-sm text-green-600 font-medium mb-1">Lots Scraped</div>
                <div id="lotsScraped" class="text-2xl font-bold text-green-800">0</div>
            </div>
            <div class="bg-purple-50 rounded-lg p-4">
                <div class="text-sm text-purple-600 font-medium mb-1">Lots Inserted</div>
                <div id="lotsInserted" class="text-2xl font-bold text-purple-800">0</div>
            </div>
            <div class="bg-orange-50 rounded-lg p-4">
                <div class="text-sm text-orange-600 font-medium mb-1">Current Lot</div>
                <div id="currentLotNumber" class="text-2xl font-bold text-orange-800">-</div>
            </div>
        </div>
        
        <!-- Progress Bars -->
        <div class="mb-6">
            <div class="mb-2 flex justify-between text-sm">
                <span class="font-medium text-gray-700">Event Progress</span>
                <span id="eventProgressText" class="text-gray-600">0 / 0</span>
            </div>
            <div class="w-full bg-gray-200 rounded-full h-3">
                <div id="eventProgressBar" class="bg-blue-600 h-3 rounded-full transition-all duration-300" style="width: 0%"></div>
            </div>
        </div>
        
        <div class="mb-6">
            <div class="mb-2 flex justify-between text-sm">
                <span class="font-medium text-gray-700">Overall Progress</span>
                <span id="overallProgressText" class="text-gray-600">0%</span>
            </div>
            <div class="w-full bg-gray-200 rounded-full h-3">
                <div id="overallProgressBar" class="bg-green-600 h-3 rounded-full transition-all duration-300" style="width: 0%"></div>
            </div>
        </div>
        
        <!-- Control Buttons -->
        <div class="flex space-x-3 mb-4">
            <button id="pauseBtn" onclick="pauseJob()" class="px-4 py-2 bg-yellow-600 text-white rounded-lg hover:bg-yellow-700 transition-colors" style="display: none;">
                ⏸️ Pause
            </button>
            <button id="resumeBtn" onclick="resumeJob()" class="px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors" style="display: none;">
                ▶️ Resume
            </button>
            <button id="stopBtn" onclick="stopJob()" class="px-4 py-2 bg-red-600 text-white rounded-lg hover:bg-red-700 transition-colors" style="display: none;">
                ⏹️ Stop
            </button>
        </div>
        
        <!-- Activity Log -->
        <div class="bg-gray-50 rounded-lg p-4">
            <h3 class="text-sm font-semibold text-gray-700 mb-2">Recent Activity</h3>
            <div id="activityLog" class="text-xs text-gray-600 space-y-1 max-h-32 overflow-y-auto">
                <div>Waiting for activity...</div>
            </div>
        </div>
    </div>
    
    <!-- Scraping Control -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        <!-- Scraper Controls -->
        <div class="bg-white rounded-xl shadow-sm p-6">
            <h2 class="text-xl font-semibold text-gray-800 mb-4 flex items-center">
                🎮 <span class="ml-2">Scraper Control</span>
            </h2>
            
            <!-- Show Monitoring Button -->
            <div class="mb-4">
                <button onclick="toggleMonitoring()" class="w-full px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 transition-colors text-sm">
                    📊 Show Real-time Monitoring
                </button>
            </div>
            
            <!-- Quick Actions -->
            <div class="grid grid-cols-2 gap-3 mb-6">
                <!-- Hidden: All scrape UI removed per request -->
                <!--
                <a href="tasks/run_scraper.cfm" 
                   class="step-card bg-gradient-to-r from-blue-500 to-blue-600 text-white p-4 rounded-lg text-center hover:from-blue-600 hover:to-blue-700 transition-colors">
                    <div class="text-2xl mb-2">▶️</div>
                    <div class="font-semibold">Start Scraping</div>
                    <div class="text-sm opacity-90">Begin lot collection</div>
                </a>
                
                <a href="tasks/run_scraper.cfm?action=status" 
                   class="step-card bg-gradient-to-r from-green-500 to-green-600 text-white p-4 rounded-lg text-center hover:from-green-600 hover:to-green-700 transition-colors">
                    <div class="text-2xl mb-2">📊</div>
                    <div class="font-semibold">View Status</div>
                    <div class="text-sm opacity-90">Check progress</div>
                </a>
                
                <a href="tasks/run_scraper.cfm?action=pause" 
                   class="step-card bg-gradient-to-r from-yellow-500 to-yellow-600 text-white p-4 rounded-lg text-center hover:from-yellow-600 hover:to-yellow-700 transition-colors">
                    <div class="text-2xl mb-2">⏸️</div>
                    <div class="font-semibold">Pause</div>
                    <div class="text-sm opacity-90">Pause scraping</div>
                </a>
                
                <a href="tasks/run_scraper.cfm?action=stop" 
                   class="step-card bg-gradient-to-r from-red-500 to-red-600 text-white p-4 rounded-lg text-center hover:from-red-600 hover:to-red-700 transition-colors">
                    <div class="text-2xl mb-2">⏹️</div>
                    <div class="font-semibold">Stop</div>
                    <div class="text-sm opacity-90">Stop scraping</div>
                </a>
                -->
            </div>
            
            <!-- Advanced Options -->
            <div class="border-t pt-4">
                <h3 class="font-semibold text-gray-700 mb-3">Advanced Options</h3>
                <form action="tasks/run_scraper.cfm" method="post" class="space-y-3">
                    <div class="grid grid-cols-2 gap-3">
                        <div>
                            <label class="block text-sm font-medium text-gray-700 mb-1">Mode</label>
                            <select name="runMode" class="w-full border border-gray-300 rounded px-3 py-2 text-sm">
                                <option value="all">All Available</option>
                                <option value="max">Limited Count</option>
                                <option value="one">Specific Event</option>
                            </select>
                        </div>
                        <div>
                            <label class="block text-sm font-medium text-gray-700 mb-1">Limit/Event ID</label>
                            <input 
                                type="text" 
                                name="targetValue" 
                                placeholder="5 or event123"
                                class="w-full border border-gray-300 rounded px-3 py-2 text-sm"
                            />
                        </div>
                    </div>
                    <button 
                        type="submit" 
                        class="w-full bg-indigo-600 text-white py-2 px-4 rounded hover:bg-indigo-700 transition-colors text-sm"
                    >
                        🎯 Start Custom Scraping
                    </button>
                </form>
            </div>
        </div>

        <!-- Scraping Process -->
        <div class="bg-white rounded-xl shadow-sm p-6">
            <h2 class="text-xl font-semibold text-gray-800 mb-4 flex items-center">
                📋 <span class="ml-2">Scraping Process</span>
            </h2>
            
            <div class="space-y-3">
                <div class="flex items-center space-x-3 p-3 bg-gray-50 rounded-lg">
                    <div class="w-8 h-8 bg-blue-500 text-white rounded-full flex items-center justify-center text-sm font-bold">1</div>
                    <div>
                        <p class="font-medium text-gray-800">Discover Events</p>
                        <p class="text-sm text-gray-600">Find auction events on NumisBids</p>
                    </div>
                </div>
                
                <div class="flex items-center space-x-3 p-3 bg-gray-50 rounded-lg">
                    <div class="w-8 h-8 bg-green-500 text-white rounded-full flex items-center justify-center text-sm font-bold">2</div>
                    <div>
                        <p class="font-medium text-gray-800">Scrape Lot Data</p>
                        <p class="text-sm text-gray-600">Extract lot details and images</p>
                    </div>
                </div>
                
                <div class="flex items-center space-x-3 p-3 bg-gray-50 rounded-lg">
                    <div class="w-8 h-8 bg-purple-500 text-white rounded-full flex items-center justify-center text-sm font-bold">3</div>
                    <div>
                        <p class="font-medium text-gray-800">Process Data</p>
                        <p class="text-sm text-gray-600">Insert lots into database</p>
                    </div>
                </div>
                
                <div class="flex items-center space-x-3 p-3 bg-gray-50 rounded-lg">
                    <div class="w-8 h-8 bg-orange-500 text-white rounded-full flex items-center justify-center text-sm font-bold">4</div>
                    <div>
                        <p class="font-medium text-gray-800">Create Embeddings</p>
                        <p class="text-sm text-gray-600">Generate AI vectors for search</p>
                    </div>
                </div>
                
                <div class="flex items-center space-x-3 p-3 bg-gray-50 rounded-lg">
                    <div class="w-8 h-8 bg-indigo-500 text-white rounded-full flex items-center justify-center text-sm font-bold">5</div>
                    <div>
                        <p class="font-medium text-gray-800">Store in Chunks</p>
                        <p class="text-sm text-gray-600">Add to unified chunks table</p>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- Scraped Lots -->
    <div class="bg-white rounded-xl shadow-sm p-6 mb-6">
        <h2 class="text-xl font-semibold text-gray-800 mb-4 flex items-center">
            🗃️ <span class="ml-2">Scraped Auction Lots</span>
        </h2>
        
        <cfquery name="lotContent" datasource="#application.db.dsn#">
            SELECT 
                source_name,
                title,
                category,
                COUNT(*) as chunk_count,
                MAX(created_at) as last_scraped,
                metadata
            FROM chunks 
            WHERE source_type = 'lot'
            GROUP BY source_name, title, category, metadata
            ORDER BY last_scraped DESC
            LIMIT 20
        </cfquery>
        
        <cfif lotContent.recordCount GT 0>
            <div class="overflow-x-auto">
                <table class="w-full table-auto">
                    <thead class="bg-gray-50">
                        <tr>
                            <th class="text-left p-3 font-medium text-gray-700">Lot/Sale</th>
                            <th class="text-left p-3 font-medium text-gray-700">Category</th>
                            <th class="text-left p-3 font-medium text-gray-700">Chunks</th>
                            <th class="text-left p-3 font-medium text-gray-700">Last Scraped</th>
                            <th class="text-left p-3 font-medium text-gray-700">Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        <cfoutput>
                        <cfloop query="lotContent">
                            <tr class="border-t border-gray-200 hover:bg-gray-50">
                                <td class="p-3">
                                    <div class="font-medium text-gray-900">#source_name#</div>
                                    <cfif len(title) AND title NEQ source_name>
                                        <div class="text-sm text-gray-500">#left(title, 50)#...</div>
                                    </cfif>
                                </td>
                                <td class="p-3">
                                    <cfif len(category)>
                                        <span class="inline-block bg-purple-100 text-purple-800 px-2 py-1 rounded text-xs">
                                            #category#
                                        </span>
                                    </cfif>
                                </td>
                                <td class="p-3 text-gray-600">#chunk_count#</td>
                                <td class="p-3 text-gray-600">#dateFormat(last_scraped, "mm/dd/yy")#</td>
                                <td class="p-3">
                                    <div class="flex space-x-2">
                                        <a href="chatbox.cfm?q=#urlEncodedFormat('lot ' & source_name)#" 
                                           class="text-blue-600 hover:text-blue-800 text-sm">
                                            Search
                                        </a>
                                        <a href="view_chunks.cfm?source=#urlEncodedFormat(source_name)#&type=lot" 
                                           class="text-green-600 hover:text-green-800 text-sm">
                                            View
                                        </a>
                                    </div>
                                </td>
                            </tr>
                        </cfloop>
                        </cfoutput>
                    </tbody>
                </table>
            </div>
        <cfelse>
            <div class="text-center py-8 text-gray-500">
                <div class="text-4xl mb-4">🏷️</div>
                <p class="text-lg font-medium">No auction lots scraped yet</p>
                <p class="text-sm">Start the scraper to collect auction data!</p>
            </div>
        </cfif>
    </div>

    <!-- Scraping Statistics -->
    <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <cfquery name="lotStats" datasource="#application.db.dsn#">
            SELECT 
                COUNT(DISTINCT source_name) as unique_lots,
                COUNT(*) as total_chunks,
                COUNT(DISTINCT category) as categories,
                MAX(created_at) as last_activity
            FROM chunks 
            WHERE source_type = 'lot'
        </cfquery>
        
        <cfoutput>
        <div class="bg-white rounded-lg shadow-sm p-4">
            <div class="flex items-center">
                <div class="w-10 h-10 bg-purple-100 rounded-lg flex items-center justify-center">
                    <span class="text-purple-600 text-lg">🏷️</span>
                </div>
                <div class="ml-3">
                    <p class="text-sm font-medium text-gray-500">Unique Lots</p>
                    <p class="text-2xl font-bold text-gray-900">#lotStats.unique_lots#</p>
                </div>
            </div>
        </div>
        
        <div class="bg-white rounded-lg shadow-sm p-4">
            <div class="flex items-center">
                <div class="w-10 h-10 bg-indigo-100 rounded-lg flex items-center justify-center">
                    <span class="text-indigo-600 text-lg">📂</span>
                </div>
                <div class="ml-3">
                    <p class="text-sm font-medium text-gray-500">Categories</p>
                    <p class="text-2xl font-bold text-gray-900">#lotStats.categories#</p>
                </div>
            </div>
        </div>
        
        <div class="bg-white rounded-lg shadow-sm p-4">
            <div class="flex items-center">
                <div class="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center">
                    <span class="text-green-600 text-lg">🕐</span>
                </div>
                <div class="ml-3">
                    <p class="text-sm font-medium text-gray-500">Last Activity</p>
                    <p class="text-lg font-bold text-gray-900">
                        <cfif isDate(lotStats.last_activity)>
                            #dateFormat(lotStats.last_activity, "mm/dd")#
                        <cfelse>
                            Never
                        </cfif>
                    </p>
                </div>
            </div>
        </div>
        </cfoutput>
    </div>
</div>

<script>
let monitoringInterval = null;
let isMonitoringVisible = false;

function toggleMonitoring() {
    const dashboard = document.getElementById('monitoringDashboard');
    if (dashboard.style.display === 'none') {
        dashboard.style.display = 'block';
        isMonitoringVisible = true;
        startMonitoring();
    } else {
        dashboard.style.display = 'none';
        isMonitoringVisible = false;
        stopMonitoring();
    }
}

function startMonitoring() {
    if (monitoringInterval) clearInterval(monitoringInterval);
    updateMonitoring(); // Initial update
    monitoringInterval = setInterval(updateMonitoring, 2500); // Update every 2.5 seconds
}

function stopMonitoring() {
    if (monitoringInterval) {
        clearInterval(monitoringInterval);
        monitoringInterval = null;
    }
}

function updateMonitoring() {
    fetch('tasks/run_scraper.cfm?action=status&ajax=1')
        .then(response => response.json())
        .then(data => {
            if (data.currentJob && data.currentJob.id) {
                const job = data.currentJob;
                
                // Update status fields
                document.getElementById('currentEventId').textContent = job.currentEventId || '-';
                document.getElementById('currentLotNumber').textContent = job.currentLotNumber || '-';
                
                // Update statistics
                if (job.statistics) {
                    const stats = job.statistics;
                    document.getElementById('lotsScraped').textContent = stats.processedLots || 0;
                    document.getElementById('lotsInserted').textContent = stats.processedLots || 0;
                    
                    // Update progress bars
                    if (job.totalEvents > 0) {
                        const eventProgress = ((job.currentEventIndex + 1) / job.totalEvents) * 100;
                        document.getElementById('eventProgressBar').style.width = eventProgress + '%';
                        document.getElementById('eventProgressText').textContent = 
                            (job.currentEventIndex + 1) + ' / ' + job.totalEvents;
                    }
                    
                    if (stats.totalEvents > 0) {
                        const overallProgress = (stats.processedEvents / stats.totalEvents) * 100;
                        document.getElementById('overallProgressBar').style.width = overallProgress + '%';
                        document.getElementById('overallProgressText').textContent = Math.round(overallProgress) + '%';
                    }
                }
                
                // Update button states
                if (job.status === 'running') {
                    document.getElementById('pauseBtn').style.display = 'inline-block';
                    document.getElementById('resumeBtn').style.display = 'none';
                    document.getElementById('stopBtn').style.display = 'inline-block';
                } else if (job.status === 'paused') {
                    document.getElementById('pauseBtn').style.display = 'none';
                    document.getElementById('resumeBtn').style.display = 'inline-block';
                    document.getElementById('stopBtn').style.display = 'inline-block';
                } else {
                    document.getElementById('pauseBtn').style.display = 'none';
                    document.getElementById('resumeBtn').style.display = 'none';
                    document.getElementById('stopBtn').style.display = 'none';
                }
                
                // Show dashboard if job is running or paused
                if ((job.status === 'running' || job.status === 'paused') && !isMonitoringVisible) {
                    document.getElementById('monitoringDashboard').style.display = 'block';
                    isMonitoringVisible = true;
                }
            } else {
                // No active job
                document.getElementById('pauseBtn').style.display = 'none';
                document.getElementById('resumeBtn').style.display = 'none';
                document.getElementById('stopBtn').style.display = 'none';
            }
            
            // Update activity log
            if (data.logs && data.logs.length > 0) {
                const logDiv = document.getElementById('activityLog');
                const recentLogs = data.logs.slice(-5).reverse();
                logDiv.innerHTML = recentLogs.map(log => 
                    `<div>[${log.timestamp}] ${log.message}</div>`
                ).join('');
            }
        })
        .catch(error => {
            console.error('Error fetching monitoring data:', error);
        });
}

function pauseJob() {
    fetch('tasks/run_scraper.cfm?action=pause&ajax=1', { method: 'POST' })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                addActivityLog('Job paused successfully');
                updateMonitoring();
            } else {
                alert('Error pausing job: ' + (data.error || 'Unknown error'));
            }
        })
        .catch(error => {
            console.error('Error pausing job:', error);
            alert('Error pausing job');
        });
}

function resumeJob() {
    fetch('tasks/run_scraper.cfm?action=resume&ajax=1', { method: 'POST' })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                addActivityLog('Job resumed successfully');
                updateMonitoring();
            } else {
                alert('Error resuming job: ' + (data.error || 'Unknown error'));
            }
        })
        .catch(error => {
            console.error('Error resuming job:', error);
            alert('Error resuming job');
        });
}

function stopJob() {
    if (confirm('Are you sure you want to stop the job?')) {
        fetch('tasks/run_scraper.cfm?action=stop&ajax=1', { method: 'POST' })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    addActivityLog('Job stopped successfully');
                    stopMonitoring();
                    updateMonitoring();
                } else {
                    alert('Error stopping job: ' + (data.error || 'Unknown error'));
                }
            })
            .catch(error => {
                console.error('Error stopping job:', error);
                alert('Error stopping job');
            });
    }
}

function addActivityLog(message) {
    const logDiv = document.getElementById('activityLog');
    const timestamp = new Date().toLocaleTimeString();
    const logEntry = document.createElement('div');
    logEntry.textContent = `[${timestamp}] ${message}`;
    logDiv.insertBefore(logEntry, logDiv.firstChild);
    
    // Keep only last 10 entries
    while (logDiv.children.length > 10) {
        logDiv.removeChild(logDiv.lastChild);
    }
}

// Auto-start monitoring if page loads with active job
document.addEventListener('DOMContentLoaded', function() {
    setTimeout(function() {
        fetch('tasks/run_scraper.cfm?action=status&ajax=1')
            .then(response => response.json())
            .then(data => {
                if (data.currentJob && (data.currentJob.status === 'running' || data.currentJob.status === 'paused')) {
                    toggleMonitoring();
                }
            })
            .catch(error => console.error('Error checking initial status:', error));
    }, 1000);
});
</script>

</cfmodule>
