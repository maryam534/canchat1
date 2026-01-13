<!---
    Web Scraping Module - URL Content Scraping
    Scrapes web content and stores in unified chunks table
--->

<cfmodule template="layout.cfm" title="Web Scraping" currentPage="web">

<div class="fade-in">
    <!-- Header -->
    <div class="bg-white rounded-xl shadow-sm p-6 mb-6">
        <h1 class="text-3xl font-bold text-gray-800 flex items-center">
            🌐 <span class="ml-3">Web Scraping</span>
        </h1>
        <p class="text-gray-600 mt-2">Scrape web content and add to your RAG knowledge base</p>
    </div>

    <!-- Scraping Form -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        <!-- Input Form -->
        <div class="bg-white rounded-xl shadow-sm p-6">
            <h2 class="text-xl font-semibold text-gray-800 mb-4 flex items-center">
                🎯 <span class="ml-2">Scrape URLs</span>
            </h2>
            
            <form action="process_web_scraping.cfm" method="post" class="space-y-4">
                <div>
                    <label class="block text-sm font-medium text-gray-700 mb-2">URLs to Scrape</label>
                    <textarea 
                        name="urls" 
                        rows="6" 
                        placeholder="Enter URLs (one per line):&#10;https://example.com/page1&#10;https://example.com/page2&#10;&#10;Or paste a sitemap URL:&#10;https://example.com/sitemap.xml"
                        class="w-full border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                        required
                    ></textarea>
                </div>
                
                <div class="grid grid-cols-2 gap-4">
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">Category</label>
                        <input 
                            type="text" 
                            name="category" 
                            placeholder="e.g., News, Documentation"
                            class="w-full border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                        />
                    </div>
                    <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">Max Pages</label>
                        <select name="maxPages" class="w-full border border-gray-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500">
                            <option value="10">10 pages</option>
                            <option value="25">25 pages</option>
                            <option value="50">50 pages</option>
                            <option value="100">100 pages</option>
                        </select>
                    </div>
                </div>
                
                <button 
                    type="submit" 
                    class="w-full bg-gradient-to-r from-green-600 to-emerald-600 text-white py-3 px-6 rounded-lg font-semibold hover:from-green-700 hover:to-emerald-700 transition-colors"
                >
                    🚀 Start Web Scraping
                </button>
            </form>
        </div>

        <!-- Scraping Guide -->
        <div class="bg-white rounded-xl shadow-sm p-6">
            <h2 class="text-xl font-semibold text-gray-800 mb-4 flex items-center">
                📚 <span class="ml-2">Scraping Guide</span>
            </h2>
            
            <div class="space-y-4 text-sm">
                <div class="p-3 bg-blue-50 rounded-lg">
                    <h3 class="font-semibold text-blue-800 mb-2">✅ Supported URLs</h3>
                    <ul class="text-blue-700 space-y-1">
                        <li>• Individual web pages</li>
                        <li>• XML sitemaps</li>
                        <li>• RSS feeds</li>
                        <li>• Blog posts and articles</li>
                    </ul>
                </div>
                
                <div class="p-3 bg-green-50 rounded-lg">
                    <h3 class="font-semibold text-green-800 mb-2">🎯 Best Practices</h3>
                    <ul class="text-green-700 space-y-1">
                        <li>• Start with a few URLs to test</li>
                        <li>• Use categories to organize content</li>
                        <li>• Check robots.txt compliance</li>
                        <li>• Monitor processing time</li>
                    </ul>
                </div>
                
                <div class="p-3 bg-yellow-50 rounded-lg">
                    <h3 class="font-semibold text-yellow-800 mb-2">⚡ Processing Steps</h3>
                    <ol class="text-yellow-700 space-y-1">
                        <li>1. Fetch page content</li>
                        <li>2. Extract text with JSoup</li>
                        <li>3. Create text chunks</li>
                        <li>4. Generate embeddings</li>
                        <li>5. Store in unified chunks table</li>
                    </ol>
                </div>
            </div>
        </div>
    </div>

    <!-- Scraped Content -->
    <div class="bg-white rounded-xl shadow-sm p-6">
        <h2 class="text-xl font-semibold text-gray-800 mb-4 flex items-center">
            🗂️ <span class="ml-2">Scraped Web Content</span>
        </h2>
        
        <cfquery name="webContent" datasource="#application.db.dsn#">
            SELECT 
                source_name,
                title,
                category,
                COUNT(*) as chunk_count,
                MAX(created_at) as last_scraped,
                SUM(chunk_size) as total_size
            FROM chunks 
            WHERE source_type = 'web'
            GROUP BY source_name, title, category
            ORDER BY last_scraped DESC
            LIMIT 20
        </cfquery>
        
        <cfif webContent.recordCount GT 0>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                <cfoutput>
                <cfloop query="webContent">
                    <div class="border border-gray-200 rounded-lg p-4 hover:shadow-md transition-shadow">
                        <div class="flex items-start justify-between mb-2">
                            <h3 class="font-medium text-gray-900 text-sm truncate">
                                <cfif len(title)>#title#<cfelse>#source_name#</cfif>
                            </h3>
                            <span class="text-xs text-gray-500">#chunk_count# chunks</span>
                        </div>
                        
                        <p class="text-xs text-gray-600 mb-2 truncate">#source_name#</p>
                        
                        <div class="flex items-center justify-between">
                            <cfif len(category)>
                                <span class="inline-block bg-green-100 text-green-800 px-2 py-1 rounded text-xs">
                                    #category#
                                </span>
                            <cfelse>
                                <span></span>
                            </cfif>
                            <div class="flex space-x-2">
                                <a href="chatbox.cfm?q=#urlEncodedFormat('content from ' & source_name)#" 
                                   class="text-blue-600 hover:text-blue-800 text-xs">
                                    Search
                                </a>
                                <a href="view_chunks.cfm?source=#urlEncodedFormat(source_name)#&type=web" 
                                   class="text-green-600 hover:text-green-800 text-xs">
                                    View
                                </a>
                            </div>
                        </div>
                    </div>
                </cfloop>
                </cfoutput>
            </div>
        <cfelse>
            <div class="text-center py-8 text-gray-500">
                <div class="text-4xl mb-4">🌐</div>
                <p class="text-lg font-medium">No web content scraped yet</p>
                <p class="text-sm">Add some URLs above to get started!</p>
            </div>
        </cfif>
    </div>
</div>

</cfmodule>
