/**
 * Converts plain text with lists to formatted HTML
 * Handles numbered lists, bullet points, and lot-specific formatting
 * @param {string} text - The plain text to convert
 * @returns {string} - Formatted HTML string
 */
function convertPlainListToHtml(text) {
    // Remove HTML comments
    text = text.replace(/<!--[\s\S]*?-->/g, '');

    // Try to find a "note:" at the end
    let note = '';
    let mainText = text;
    const noteMatch = text.match(/(note[:]?.*)$/i);
    
    if (noteMatch) {
        note = noteMatch[1];
        mainText = text.replace(note, '').trim();
    }

    // Split into lines, filtering out empty lines
    let lines = mainText.split('\n')
        .map(line => line.trim())
        .filter(line => line.length > 0);

    // If only one line, try to split by numbered or dash patterns
    if (lines.length === 1) {
        let numbered = lines[0].split(/\s(?=\d+\.\s)/);
        
        if (numbered.length > 1) {
            lines = numbered;
        } else {
            let dashed = lines[0].split(/\s(?=-\s)/);
            
            if (dashed.length > 1) {
                lines = dashed;
            } else {
                let lots = lines[0].split(/(?=Lots?\s*\()/i);
                
                if (lots.length > 1) {
                    lines = lots.map((l, i) => (i === 0 ? l : 'Lots ' + l));
                }
            }
        }
    }

    // Find the first list item
    const firstListIdx = lines.findIndex(line =>
        /^(-\s+|\d+\.\s+|Lots?\s*\(|Lots?\s+\d+|Lot\s+\d+)/i.test(line)
    );

    if (firstListIdx !== -1) {
        const intro = lines.slice(0, firstListIdx).join(' ');
        const listItems = [];
        
        // Extract list items
        for (let i = firstListIdx; i < lines.length; i++) {
            if (!/^(-\s+|\d+\.\s+|Lots?\s*\(|Lots?\s+\d+|Lot\s+\d+)/i.test(lines[i])) {
                break;
            }
            
            const cleanItem = lines[i]
                .replace(/^(-\s+|\d+\.\s+|Lots?\s*\(|Lots?\s+|Lot\s+)/i, '')
                .replace(/\)$/, '');
            listItems.push(cleanItem);
        }
        
        // Determine list type and styling
        const isNumbered = lines[firstListIdx].match(/^\d+\.\s+/);
        const listTag = isNumbered ? 'ol' : 'ul';
        const listClass = isNumbered
            ? 'list-decimal list-inside space-y-1'
            : 'list-disc list-inside space-y-1';

        return `
            ${intro ? `<div class="mb-2">${escapeHtml(intro)}</div>` : ''}
            <${listTag} class="${listClass}">
                ${listItems.map(item => `<li>${escapeHtml(item.trim())}</li>`).join('\n')}
            </${listTag}>
            ${note ? `<div class="mt-2 italic text-sm text-gray-600">${escapeHtml(note)}</div>` : ''}
        `;
    }

    return `<div>${escapeHtml(text)}</div>`;
}

/**
 * Escapes HTML special characters to prevent XSS attacks
 * @param {string} text - The text to escape
 * @returns {string} - HTML-escaped text
 */
function escapeHtml(text) {
    return text
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
}

/**
 * Handles sending user messages to the RAG system
 * Creates chat bubbles and processes AI responses with loading indicator
 */
function sendMessage() {
    console.log('🚀 sendMessage() called');
    
    const inputField = document.getElementById('userInput');
    const chatWindow = document.getElementById('chatWindow');
    const sendButton = document.getElementById('sendButton');
    const userMessage = inputField.value.trim();

    console.log('📋 Elements found:', { 
        inputField: !!inputField, 
        chatWindow: !!chatWindow, 
        sendButton: !!sendButton,
        message: userMessage 
    });

    // Don't send empty messages
    if (!userMessage) {
        console.log('❌ Empty message, returning');
        return;
    }

    if (!sendButton) {
        console.error('❌ Send button not found!');
        return;
    }

    console.log('⏳ Setting loading state...');
    
    // IMMEDIATE visual feedback - change button text first
    sendButton.textContent = '⏳ Sending...';
    sendButton.style.backgroundColor = '#6B7280'; // Gray
    sendButton.style.cursor = 'not-allowed';
    sendButton.style.opacity = '0.8';
    
    // Disable input and button during processing
    inputField.disabled = true;
    sendButton.disabled = true;
    inputField.style.backgroundColor = '#F3F4F6'; // Light gray
    
    console.log('✅ Loading state applied');

    // Create and display user message bubble
    const userBubble = document.createElement('div');
    userBubble.className = 'text-right';
    userBubble.innerHTML = `
        <div class="inline-block bg-blue-100 text-blue-900 px-4 py-2 rounded-lg">
            ${userMessage}
        </div>
    `;
    chatWindow.appendChild(userBubble);

    // Create loading indicator bubble
    const loadingBubble = document.createElement('div');
    loadingBubble.className = 'text-left';
    loadingBubble.id = 'loadingBubble';
    loadingBubble.innerHTML = `
        <div class="inline-block bg-blue-50 text-blue-800 px-4 py-2 rounded-lg border border-blue-200">
            <div style="display: flex; align-items: center; gap: 8px;">
                <div class="loading-spinner" style="display: inline-block; width: 16px; height: 16px; border: 2px solid #2563eb; border-top: 2px solid transparent; border-radius: 50%;"></div>
                <span class="loading-text"><strong>AI:</strong> Analyzing your question...</span>
            </div>
        </div>
    `;
    
    console.log('Loading bubble created'); // Debug log
    chatWindow.appendChild(loadingBubble);

    // Auto-scroll to bottom and clear input
    chatWindow.scrollTop = chatWindow.scrollHeight;
    inputField.value = '';

    // Send request to RAG backend using configuration
    const ragUrl = window.appConfig ? window.appConfig.cfmlPath + '/rag.cfm' : './rag.cfm';
    const showDebug = window.appConfig ? window.appConfig.showDebugLogs : false;
    
    if (showDebug) {
        console.log('🌐 Sending request to:', ragUrl);
    }
    
    fetch(ragUrl, {
        method: 'POST',
        headers: { 
            'Content-Type': 'application/x-www-form-urlencoded' 
        },
        body: `question=${encodeURIComponent(userMessage)}`
    })
    .then(response => {
        console.log('Response received'); // Debug log
        return response.text();
    })
    .then(answer => {
        console.log('Processing response...'); // Debug log
        
        // Remove loading indicator
        const loadingElement = document.getElementById('loadingBubble');
        if (loadingElement) {
            console.log('Removing loading bubble'); // Debug log
            loadingElement.remove();
        }

        // Create and display bot response bubble
        const botBubble = document.createElement('div');
        botBubble.className = 'text-left';
        
        console.log('RAG Response:', answer);
        
        botBubble.innerHTML = `
            <div class="inline-block bg-gray-200 text-gray-900 px-4 py-2 rounded-lg">
                ${answer}
            </div>
        `;
        
        chatWindow.appendChild(botBubble);
        chatWindow.scrollTop = chatWindow.scrollHeight;
    })
    .catch(err => {
        console.error('Error communicating with RAG system:', err);
        
        // Remove loading indicator
        const loadingElement = document.getElementById('loadingBubble');
        if (loadingElement) {
            loadingElement.remove();
        }
        
        // Display error message to user
        const errorBubble = document.createElement('div');
        errorBubble.className = 'text-left';
        errorBubble.innerHTML = `
            <div class="inline-block bg-red-100 text-red-900 px-4 py-2 rounded-lg">
                <span class="inline-block w-4 h-4 bg-red-500 text-white rounded-full text-center text-xs leading-4 mr-2 font-bold">ERR</span>
                Sorry, I encountered an error processing your request. Please try again.
            </div>
        `;
        chatWindow.appendChild(errorBubble);
        chatWindow.scrollTop = chatWindow.scrollHeight;
    })
    .finally(() => {
        console.log('🔄 Resetting button state...');
        
        // Re-enable input and button
        inputField.disabled = false;
        sendButton.disabled = false;
        sendButton.style.backgroundColor = '';
        sendButton.style.opacity = '';
        sendButton.style.cursor = '';
        inputField.style.backgroundColor = '';
        sendButton.textContent = 'Send';
        inputField.focus();
        
        console.log('✅ Button reset complete');
    });
}

/**
 * Test function to verify loading indicator works
 */
function testLoading() {
    console.log('🧪 Testing loading indicator...');
    
    const sendButton = document.getElementById('sendButton');
    const inputField = document.getElementById('userInput');
    
    if (!sendButton) {
        console.error('❌ Send button not found!');
        alert('Send button not found! Check console.');
        return;
    }
    
    // Show loading state
    sendButton.textContent = 'Testing...';
    sendButton.style.backgroundColor = '#EF4444'; // Red to make it obvious
    sendButton.disabled = true;
    inputField.disabled = true;
    
    console.log('✅ Loading state set, will reset in 3 seconds...');
    
    // Reset after 3 seconds
    setTimeout(() => {
        sendButton.textContent = 'Send';
        sendButton.style.backgroundColor = '';
        sendButton.disabled = false;
        inputField.disabled = false;
        console.log('✅ Test complete - loading indicator reset');
    }, 3000);
}