<cfmodule template="layout.cfm" title="Single Event Scraper" currentPage="single">

<div class="fade-in max-w-2xl mx-auto">
    <div class="bg-white rounded-xl shadow-sm p-6 mb-6">
        <h1 class="text-2xl font-bold text-gray-800 mb-2">🎯 Run Single Event Scrape</h1>
        <p class="text-gray-600">Enter a NumisBids event ID and run the single-event scraper.</p>
    </div>

    <div class="bg-white rounded-xl shadow-sm p-6">
        <form action="scrape_single_event.cfm" method="get" class="space-y-4">
            <div>
                <label class="block text-sm font-medium text-gray-700 mb-1" for="eventid">Event ID</label>
                <input id="eventid" name="eventid" type="text" placeholder="e.g., 9780" class="w-full border border-gray-300 rounded px-3 py-2 text-sm" required />
            </div>
            <button type="submit" class="w-full bg-indigo-600 text-white py-2 px-4 rounded hover:bg-indigo-700 transition-colors text-sm">
                ▶️ Run Scraper
            </button>
        </form>
    </div>
</div>

</cfmodule>


