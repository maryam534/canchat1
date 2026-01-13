<!---
    Main Entry Point - Redirect to new unified interface
--->

<cfif structKeyExists(url, "appreset")>
    <!--- Handle app reset requests --->
    <!DOCTYPE html>
    <html>
    <head>
        <title>Application Reset</title>
        <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
    </head>
    <body class="bg-gray-100 p-6">
        <div class="max-w-md mx-auto bg-white rounded-lg shadow p-6 text-center">
            <div class="text-4xl mb-4">🔄</div>
            <h1 class="text-xl font-bold text-gray-800 mb-2">Application Reset</h1>
            <p class="text-gray-600 mb-4">Configuration reloaded successfully.</p>
            <a href="chatbox.cfm" class="inline-block bg-blue-600 text-white px-6 py-2 rounded-lg hover:bg-blue-700 transition-colors">
                → Continue to ChatBox
            </a>
        </div>
    </body>
    </html>
<cfelse>
    <!--- Redirect to new chatbox interface --->
    <cflocation url="chatbox.cfm" addToken="false">
</cfif>