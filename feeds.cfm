<!---
    Feeds Module - RSS/Atom Feed Processing
    Processes feeds and stores content in unified chunks table
--->

<cfmodule template="layout.cfm" title="Content Feeds" currentPage="feeds">

<div class="fade-in">
    <!-- Header -->
    <div class="bg-white rounded-xl shadow-sm p-6 mb-6">
        <h1 class="text-3xl font-bold text-gray-800 flex items-center">
            📡 <span class="ml-3">Content Feeds</span>
        </h1>
        <p class="text-gray-600 mt-2">Monitor RSS feeds and automatically add new content to your RAG system</p>
    </div>

    <!-- Add Feed Section -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        <!-- Add New Feed -->
        <div class="bg-white rounded-xl shadow-sm p-6">
            <h2 class="text-xl font-semibold text-gray-800 mb-4 flex items-center">
                ➕ <span class="ml-2">Add New Feed</span>
            </h2>
            
            <form action="process_feed.cfm" method="post" class="space-y-4">
                <div>
                    <label class="block text-sm font-medium text-gray-700 mb-2">Feed URL</label>
                    <input 
                        type="url" 
                        name="feedUrl" 
                        placeholder="https://example.com/rss.xml"
                        class="w-full border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                        required
                    />
                </div>
                
                <div class="grid grid-cols-2 gap-3">
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">Category</label>
                        <input 
                            type="text" 
                            name="category" 
                            placeholder="News, Blog, etc."
                            class="w-full border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                        />
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">Update Frequency</label>
                        <select name="frequency" class="w-full border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500">
                            <option value="manual">Manual</option>
                            <option value="hourly">Hourly</option>
                            <option value="daily">Daily</option>
                            <option value="weekly">Weekly</option>
                        </select>
                    </div>
                </div>
                
                <button 
                    type="submit" 
                    class="w-full bg-gradient-to-r from-emerald-600 to-green-600 text-white py-3 px-6 rounded-lg font-semibold hover:from-emerald-700 hover:to-green-700 transition-colors"
                >
                    📡 Add & Process Feed
                </button>
            </form>
        </div>

        <!-- Feed Processing Steps -->
        <div class="bg-white rounded-xl shadow-sm p-6">
            <h2 class="text-xl font-semibold text-gray-800 mb-4 flex items-center">
                🔄 <span class="ml-2">Processing Steps</span>
            </h2>
            
            <div class="space-y-3">
                <div class="flex items-center space-x-3 p-3 bg-gray-50 rounded-lg">
                    <div class="w-8 h-8 bg-blue-500 text-white rounded-full flex items-center justify-center text-sm font-bold">1</div>
                    <div>
                        <p class="font-medium text-gray-800">Fetch Feed</p>
                        <p class="text-sm text-gray-600">Download RSS/Atom XML</p>
                    </div>
                </div>
                
                <div class="flex items-center space-x-3 p-3 bg-gray-50 rounded-lg">
                    <div class="w-8 h-8 bg-green-500 text-white rounded-full flex items-center justify-center text-sm font-bold">2</div>
                    <div>
                        <p class="font-medium text-gray-800">Parse Entries</p>
                        <p class="text-sm text-gray-600">Extract articles and metadata</p>
                    </div>
                </div>
                
                <div class="flex items-center space-x-3 p-3 bg-gray-50 rounded-lg">
                    <div class="w-8 h-8 bg-purple-500 text-white rounded-full flex items-center justify-center text-sm font-bold">3</div>
                    <div>
                        <p class="font-medium text-gray-800">Fetch Content</p>
                        <p class="text-sm text-gray-600">Download full article text</p>
                    </div>
                </div>
                
                <div class="flex items-center space-x-3 p-3 bg-gray-50 rounded-lg">
                    <div class="w-8 h-8 bg-orange-500 text-white rounded-full flex items-center justify-center text-sm font-bold">4</div>
                    <div>
                        <p class="font-medium text-gray-800">Create Embeddings</p>
                        <p class="text-sm text-gray-600">Generate AI vectors</p>
                    </div>
                </div>
                
                <div class="flex items-center space-x-3 p-3 bg-gray-50 rounded-lg">
                    <div class="w-8 h-8 bg-indigo-500 text-white rounded-full flex items-center justify-center text-sm font-bold">5</div>
                    <div>
                        <p class="font-medium text-gray-800">Store Content</p>
                        <p class="text-sm text-gray-600">Add to unified chunks table</p>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- Active Feeds -->
    <div class="bg-white rounded-xl shadow-sm p-6">
        <h2 class="text-xl font-semibold text-gray-800 mb-4 flex items-center">
            📰 <span class="ml-2">Active Feeds</span>
        </h2>
        
        <cfquery name="feedContent" datasource="#application.db.dsn#">
            SELECT 
                source_name,
                title,
                category,
                COUNT(*) as article_count,
                MAX(created_at) as last_updated,
                MIN(created_at) as first_added
            FROM chunks 
            WHERE source_type = 'feed'
            GROUP BY source_name, title, category
            ORDER BY last_updated DESC
        </cfquery>
        
        <cfif feedContent.recordCount GT 0>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <cfoutput>
                <cfloop query="feedContent">
                    <div class="border border-gray-200 rounded-lg p-4 hover:shadow-md transition-shadow">
                        <div class="flex items-start justify-between mb-2">
                            <h3 class="font-medium text-gray-900 text-sm">
                                <cfif len(title)>#title#<cfelse>#source_name#</cfif>
                            </h3>
                            <span class="text-xs text-gray-500">#article_count# articles</span>
                        </div>
                        
                        <p class="text-xs text-gray-600 mb-2">#source_name#</p>
                        
                        <div class="flex items-center justify-between">
                            <cfif len(category)>
                                <span class="inline-block bg-emerald-100 text-emerald-800 px-2 py-1 rounded text-xs">
                                    #category#
                                </span>
                            <cfelse>
                                <span></span>
                            </cfif>
                            <div class="flex space-x-2">
                                <a href="chatbox.cfm?q=#urlEncodedFormat('articles from ' & source_name)#" 
                                   class="text-blue-600 hover:text-blue-800 text-xs">
                                    Search
                                </a>
                                <a href="refresh_feed.cfm?source=#urlEncodedFormat(source_name)#" 
                                   class="text-green-600 hover:text-green-800 text-xs">
                                    Refresh
                                </a>
                            </div>
                        </div>
                    </div>
                </cfloop>
                </cfoutput>
            </div>
        <cfelse>
            <div class="text-center py-8 text-gray-500">
                <div class="text-4xl mb-4">📡</div>
                <p class="text-lg font-medium">No feeds configured yet</p>
                <p class="text-sm">Add your first RSS feed above!</p>
            </div>
        </cfif>
    </div>
</div>

</cfmodule>
