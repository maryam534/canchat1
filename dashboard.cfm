<cfquery name="q" datasource="#application.db.dsn#">
  SELECT file_name, status, created_at FROM uploaded_files
  ORDER BY created_at DESC
</cfquery>

<html>
<head>
  <title>NumisBids Scraper Dashboard</title>
  <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
  <style>
    .gradient-bg {
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    }
    .card {
      background: white;
      border-radius: 12px;
      box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
      padding: 1.5rem;
      margin-bottom: 1.5rem;
    }
    .status-indicator {
      width: 12px;
      height: 12px;
      border-radius: 50%;
      display: inline-block;
      margin-right: 8px;
    }
    .status-done { background: #10b981; }
    .status-processing { background: #f59e0b; }
    .status-error { background: #ef4444; }
  </style>
</head>
<body class="bg-gray-50">
  <div class="gradient-bg text-white p-6">
    <div class="max-w-7xl mx-auto">
      <h1 class="text-3xl font-bold mb-2">NumisBids Scraper Dashboard</h1>
      <p class="text-blue-100">Complete auction data management and scraping control</p>
    </div>
  </div>

  <div class="max-w-7xl mx-auto p-6">
    <!-- Quick Actions -->
    <div class="card">
      <h2 class="text-xl font-semibold mb-4 text-gray-800">&#128640; Quick Actions</h2>
      <div class="grid grid-cols-1 md:grid-cols-4 gap-4">
                  <a href="tasks/run_scraper.cfm" class="bg-blue-600 text-white p-4 rounded-lg text-center hover:bg-blue-700 transition-colors">
            <div class="text-2xl mb-2">&#9881;&#65039;</div>
            <div class="font-semibold">Scraper Control Panel</div>
            <div class="text-sm opacity-90">Manage scraping processes</div>
          </a>
          <a href="upload.cfm" class="bg-green-600 text-white p-4 rounded-lg text-center hover:bg-green-700 transition-colors">
            <div class="text-2xl mb-2">&#128193;</div>
            <div class="font-semibold">Upload Files</div>
            <div class="text-sm opacity-90">Upload auction data files</div>
          </a>
          <a href="rag.cfm" class="bg-purple-600 text-white p-4 rounded-lg text-center hover:bg-purple-700 transition-colors">
            <div class="text-2xl mb-2">&#128269;</div>
            <div class="font-semibold">RAG Search</div>
            <div class="text-sm opacity-90">Search auction data</div>
          </a>
          <a href="system_status.cfm" class="bg-indigo-600 text-white p-4 rounded-lg text-center hover:bg-indigo-700 transition-colors">
            <div class="text-2xl mb-2">&#128202;</div>
            <div class="font-semibold">System Status</div>
            <div class="text-sm opacity-90">Monitor system health</div>
          </a>
      </div>
    </div>

    <!-- Export Controls -->
    <div class="card">
      <h2 class="text-xl font-semibold mb-4 text-gray-800">&#128202; Export Data</h2>
      <form action="export_chunks.cfm" method="post" class="grid grid-cols-1 md:grid-cols-4 gap-4 items-end">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Start Date</label>
          <input type="date" name="startDate" class="w-full border border-gray-300 rounded-lg px-3 py-2 focus:ring-2 focus:ring-blue-500 focus:border-transparent" />
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">End Date</label>
          <input type="date" name="endDate" class="w-full border border-gray-300 rounded-lg px-3 py-2 focus:ring-2 focus:ring-blue-500 focus:border-transparent" />
        </div>
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Source Type</label>
          <select name="sourceType" class="w-full border border-gray-300 rounded-lg px-3 py-2 focus:ring-2 focus:ring-blue-500 focus:border-transparent">
            <option value="">All Sources</option>
            <option value="pdf">PDF</option>
            <option value="doc">DOC</option>
            <option value="web">Web</option>
            <option value="sql">SQL</option>
          </select>
        </div>
        <div>
          <button type="submit" class="w-full bg-indigo-600 text-white px-4 py-2 rounded-lg hover:bg-indigo-700 transition-colors font-medium">
            Export Filtered Data
          </button>
        </div>
      </form>
    </div>

    <!-- Web Scraping -->
    <div class="card">
      <h2 class="text-xl font-semibold mb-4 text-gray-800">&#127760; Web Scraping</h2>
      <form action="scrape_import.cfm" method="post">
        <label class="block text-sm font-medium text-gray-700 mb-2">Scrape from URLs or Sitemap:</label>
        <textarea name="inputURLs" rows="4" class="w-full border border-gray-300 rounded-lg p-3 focus:ring-2 focus:ring-blue-500 focus:border-transparent" placeholder="https://example.com/"></textarea>
        <button type="submit" class="mt-3 bg-blue-600 text-white px-6 py-2 rounded-lg hover:bg-blue-700 transition-colors font-medium">
          Scrape & Import
        </button>
      </form>
    </div>

    <!-- File Status Table -->
    <div class="card">
      <h2 class="text-xl font-semibold mb-4 text-gray-800">&#128203; Uploaded Files Status</h2>
      <cfoutput>
      <div class="overflow-x-auto">
        <table class="w-full table-auto">
          <thead class="bg-gray-100">
            <tr>
              <th class="text-left p-3 font-medium text-gray-700">File Name</th>
              <th class="text-left p-3 font-medium text-gray-700">Status</th>
              <th class="text-left p-3 font-medium text-gray-700">Uploaded At</th>
              <th class="text-left p-3 font-medium text-gray-700">Actions</th>
            </tr>
          </thead>
          <tbody>
            <cfloop query="q">
              <tr class="border-t border-gray-200 hover:bg-gray-50">
                <td class="p-3 text-gray-900 font-mono text-sm">#q.file_name#</td>
                <td class="p-3">
                  <cfif q.status EQ 'Done'>
                    <span class="status-indicator status-done"></span>
                    <span class="text-green-600 font-semibold">Done</span>
                  <cfelseif q.status EQ 'Processing'>
                    <span class="status-indicator status-processing"></span>
                    <span class="text-yellow-600 font-semibold">Processing</span>
                  <cfelse>
                    <span class="status-indicator status-error"></span>
                    <span class="text-red-600 font-semibold">Error</span>
                  </cfif>
                </td>
                <td class="p-3 text-gray-600">#dateFormat(q.created_at, 'yyyy-mm-dd')# #timeFormat(q.created_at, 'HH:mm:ss')#</td>
                <td class="p-3">
                  <cfif q.status EQ 'Done'>
                    <button class="bg-blue-100 text-blue-700 px-3 py-1 rounded text-sm hover:bg-blue-200 transition-colors">
                      View Data
                    </button>
                  <cfelseif q.status EQ 'Processing'>
                    <button class="bg-yellow-100 text-yellow-700 px-3 py-1 rounded text-sm" disabled>
                      In Progress
                    </button>
                  <cfelse>
                    <button class="bg-red-100 text-red-700 px-3 py-1 rounded text-sm hover:bg-red-200 transition-colors">
                      Retry
                    </button>
                  </cfif>
                </td>
              </tr>
            </cfloop>
          </tbody>
        </table>
      </div>
      </cfoutput>
    </div>

    <!-- System Status -->
    <div class="card">
      <h2 class="text-xl font-semibold mb-4 text-gray-800">&#128200; System Status</h2>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div class="bg-blue-50 p-4 rounded-lg">
          <div class="text-2xl font-bold text-blue-600" id="totalFiles">0</div>
          <div class="text-sm text-blue-700">Total Files</div>
        </div>
        <div class="bg-green-50 p-4 rounded-lg">
          <div class="text-2xl font-bold text-green-600" id="completedFiles">0</div>
          <div class="text-sm text-green-700">Completed</div>
        </div>
        <div class="bg-yellow-50 p-4 rounded-lg">
          <div class="text-2xl font-bold text-yellow-600" id="processingFiles">0</div>
          <div class="text-sm text-yellow-700">Processing</div>
        </div>
      </div>
    </div>

    <div class="mt-6 text-center">
      <a href="index.cfm" class="text-blue-600 hover:text-blue-800 underline">← Back to Chat Interface</a>
    </div>
  </div>

  <script>
    // Update system status counts
    document.addEventListener('DOMContentLoaded', function() {
      const rows = document.querySelectorAll('tbody tr');
      let total = rows.length;
      let completed = 0;
      let processing = 0;
      
      rows.forEach(row => {
        const status = row.querySelector('td:nth-child(2)').textContent.trim();
        if (status.includes('Done')) completed++;
        else if (status.includes('Processing')) processing++;
      });
      
      document.getElementById('totalFiles').textContent = total;
      document.getElementById('completedFiles').textContent = completed;
      document.getElementById('processingFiles').textContent = processing;
    });
  </script>
</body>
</html>
