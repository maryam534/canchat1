<!---
    ChatBox Module - Unified RAG Chat Interface
    Searches across ALL content types in the unified chunks table
--->

<cfmodule template="layout.cfm" title="ChatBox" currentPage="chatbox">

<style>
/* RAG Response Styling */
.rag-response h2 {
    font-size: 1.25rem;
    font-weight: bold;
    margin: 1rem 0 0.5rem 0;
    color: #1f2937;
}
.rag-response h3 {
    font-size: 1.125rem;
    font-weight: bold;
    margin: 0.75rem 0 0.5rem 0;
    color: #374151;
}
.rag-response h4 {
    font-size: 1rem;
    font-weight: bold;
    margin: 0.5rem 0 0.25rem 0;
    color: #4b5563;
}
.rag-response p {
    margin: 0.5rem 0;
    line-height: 1.6;
}
.rag-response ul, .rag-response ol {
    margin: 0.5rem 0;
    padding-left: 1.5rem;
}
.rag-response li {
    margin: 0.25rem 0;
    line-height: 1.5;
}
.rag-response strong {
    font-weight: bold;
    color: #1f2937;
}
.rag-response em {
    font-style: italic;
    color: #4b5563;
}
.rag-response br {
    line-height: 1.5;
}
</style>

<div class="fade-in">
    <!-- Header -->
    <div class="bg-white rounded-xl shadow-sm p-6 mb-6">
        <div class="flex items-center justify-between">
            <div>
                <h1 class="text-3xl font-bold text-gray-800 flex items-center">
                    🗣️ <span class="ml-3">AI ChatBox</span>
                </h1>
                <p class="text-gray-600 mt-2">Ask questions about documents, lots, web content, and more!</p>
            </div>
            <div class="text-right">
                <cfquery name="contentTypes" datasource="#application.db.dsn#">
                    SELECT 
                        source_type,
                        COUNT(*) as chunk_count,
                        COUNT(DISTINCT source_name) as source_count
                    FROM chunks
                    WHERE embedding IS NOT NULL
                    GROUP BY source_type
                    ORDER BY chunk_count DESC
                </cfquery>
                
                <div class="text-sm text-gray-500">
                    <p class="font-medium">Available Content:</p>
                    <cfoutput>
                    <cfloop query="contentTypes">
                        <span class="inline-block bg-gray-100 px-2 py-1 rounded text-xs mr-1 mt-1">
                            #source_type#: #chunk_count# chunks
                        </span>
                    </cfloop>
                    </cfoutput>
                </div>
            </div>
        </div>
    </div>

    <!-- Chat Interface -->
    <div class="bg-white rounded-xl shadow-sm overflow-hidden" x-data="chatInterface()">
        <!-- Chat Messages -->
        <div id="chatWindow" class="h-96 overflow-y-auto p-6 space-y-4 bg-gray-50">
            <!-- Welcome Message (AI on left) -->
            <div class="flex items-start justify-start space-x-3 mb-4">
                <div class="w-8 h-8 bg-green-500 rounded-full flex items-center justify-center text-white text-sm font-bold">
                    AI
                </div>
                <div class="bg-gray-100 rounded-lg p-4 shadow-sm max-w-2xl">
                    <p class="text-gray-800">
                        👋 Welcome! I can help you search across all your content:
                        <strong>documents</strong>, <strong>auction lots</strong>, <strong>web content</strong>, and more.
                    </p>
                    <p class="text-gray-600 text-sm mt-2">
                        Try asking: "show me lot 100", "documents about storytelling", "web content about fundraising"
                    </p>
                </div>
            </div>
            
            <!-- Chat Messages Container -->
            <div id="chatMessages">
                <!-- Messages will be added here dynamically -->
            </div>
        </div>

        <!-- Input Area -->
        <div class="p-6 bg-white border-t">
            <div class="flex space-x-4">
                <input 
                    type="text" 
                    id="messageInput"
                    placeholder="Ask about any content in your RAG system..."
                    class="flex-1 border border-gray-300 rounded-lg px-4 py-3 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                    x-model="currentMessage"
                    @keydown.enter="sendMessage"
                    :disabled="isLoading"
                />
                <button 
                    @click="sendMessage"
                    class="bg-blue-600 text-white px-6 py-3 rounded-lg hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                    :disabled="!currentMessage.trim() || isLoading"
                >
                    <span x-show="!isLoading">Send</span>
                    <span x-show="isLoading" class="flex items-center">
                        <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-white" fill="none" viewBox="0 0 24 24">
                            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                        </svg>
                        Thinking...
                    </span>
                </button>
            </div>
            
            <!-- Quick Actions -->
            <div class="mt-4 flex flex-wrap gap-2">
                <button @click="setMessage('show me recent documents')" class="text-xs bg-gray-100 hover:bg-gray-200 px-3 py-1 rounded-full text-gray-700 transition-colors">
                    Recent Documents
                </button>
                <button @click="setMessage('find auction lots under $100')" class="text-xs bg-gray-100 hover:bg-gray-200 px-3 py-1 rounded-full text-gray-700 transition-colors">
                    Affordable Lots
                </button>
                <button @click="setMessage('web content about stamps')" class="text-xs bg-gray-100 hover:bg-gray-200 px-3 py-1 rounded-full text-gray-700 transition-colors">
                    Web Content
                </button>
                <button @click="setMessage('summarize uploaded PDFs')" class="text-xs bg-gray-100 hover:bg-gray-200 px-3 py-1 rounded-full text-gray-700 transition-colors">
                    PDF Summary
                </button>
            </div>
        </div>
    </div>

    <!-- Content Statistics -->
    <div class="mt-6 grid grid-cols-1 md:grid-cols-4 gap-4">
        <cfquery name="stats" datasource="#application.db.dsn#">
            SELECT 
                COUNT(*) as total_chunks,
                COUNT(DISTINCT source_name) as unique_sources,
                COUNT(*) FILTER (WHERE source_type = 'document') as document_chunks,
                COUNT(*) FILTER (WHERE source_type = 'lot') as lot_chunks,
                COUNT(*) FILTER (WHERE source_type = 'web') as web_chunks,
                COUNT(*) FILTER (WHERE embedding IS NOT NULL) as embedded_chunks
            FROM chunks
        </cfquery>
        
        <cfoutput>
        <div class="bg-white rounded-lg shadow-sm p-4">
            <div class="flex items-center">
                <div class="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
                    <span class="text-blue-600 text-lg">📊</span>
                </div>
                <div class="ml-3">
                    <p class="text-sm font-medium text-gray-500">Total Chunks</p>
                    <p class="text-2xl font-bold text-gray-900">#stats.total_chunks#</p>
                </div>
            </div>
        </div>
        
        <div class="bg-white rounded-lg shadow-sm p-4">
            <div class="flex items-center">
                <div class="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center">
                    <span class="text-green-600 text-lg">📁</span>
                </div>
                <div class="ml-3">
                    <p class="text-sm font-medium text-gray-500">Documents</p>
                    <p class="text-2xl font-bold text-gray-900">#stats.document_chunks#</p>
                </div>
            </div>
        </div>
        
        <div class="bg-white rounded-lg shadow-sm p-4">
            <div class="flex items-center">
                <div class="w-10 h-10 bg-purple-100 rounded-lg flex items-center justify-center">
                    <span class="text-purple-600 text-lg">🏷️</span>
                </div>
                <div class="ml-3">
                    <p class="text-sm font-medium text-gray-500">Auction Lots</p>
                    <p class="text-2xl font-bold text-gray-900">#stats.lot_chunks#</p>
                </div>
            </div>
        </div>
        
        <div class="bg-white rounded-lg shadow-sm p-4">
            <div class="flex items-center">
                <div class="w-10 h-10 bg-orange-100 rounded-lg flex items-center justify-center">
                    <span class="text-orange-600 text-lg">🌐</span>
                </div>
                <div class="ml-3">
                    <p class="text-sm font-medium text-gray-500">Web Content</p>
                    <p class="text-2xl font-bold text-gray-900">#stats.web_chunks#</p>
                </div>
            </div>
        </div>
        </cfoutput>
    </div>
</div>

<script>
function chatInterface() {
    return {
        currentMessage: '',
        isLoading: false,
        messages: [],
        
        init() {
            // Focus input on load
            this.$nextTick(() => {
                document.getElementById('messageInput')?.focus();
            });
        },
        
        setMessage(text) {
            this.currentMessage = text;
            this.$nextTick(() => {
                document.getElementById('messageInput')?.focus();
            });
        },
        
        async sendMessage() {
            if (!this.currentMessage.trim() || this.isLoading) return;
            
            const userMessage = this.currentMessage.trim();
            this.currentMessage = '';
            this.isLoading = true;
            
            // Add user message to chat
            this.addMessage('user', userMessage);
            
            // Add thinking indicator
            const thinkingId = this.addMessage('ai', '', true);
            
            try {
                // Send request to RAG backend
                const formData = new FormData();
                formData.append('question', userMessage);
                
                const response = await fetch('rag.cfm', {
                    method: 'POST',
                    body: formData
                });
                
                if (!response.ok) {
                    throw new Error(`HTTP ${response.status}: ${response.statusText}`);
                }
                
                const result = await response.text();
                
                // Remove thinking indicator
                this.removeMessage(thinkingId);
                
                // Parse and display AI response
                this.parseAndDisplayResponse(result);
                
            } catch (error) {
                console.error('Chat error:', error);
                
                // Remove thinking indicator
                this.removeMessage(thinkingId);
                
                // Show error message
                this.addMessage('ai', `❌ Sorry, I encountered an error: ${error.message}`);
            } finally {
                this.isLoading = false;
                this.scrollToBottom();
            }
        },
        
        addMessage(type, content, isThinking = false, customThinkingText = '🤔 Thinking...') {
            const messageId = Date.now() + Math.random();
            const messageElement = document.createElement('div');
            messageElement.className = 'fade-in mb-4';
            messageElement.id = `message-${messageId}`;
            
            if (type === 'user') {
                // User messages on the right (WhatsApp style)
                messageElement.innerHTML = `
                    <div class="flex items-start justify-end space-x-3">
                        <div class="bg-blue-500 text-white rounded-lg p-4 shadow-sm max-w-2xl">
                            <p>${this.escapeHtml(content)}</p>
                        </div>
                        <div class="w-8 h-8 bg-gray-600 rounded-full flex items-center justify-center text-white text-sm font-bold">
                            U
                        </div>
                    </div>
                `;
            } else {
                // AI responses on the left (WhatsApp style)
                messageElement.innerHTML = `
                    <div class="flex items-start justify-start space-x-3">
                        <div class="w-8 h-8 bg-green-500 rounded-full flex items-center justify-center text-white text-sm font-bold">
                            AI
                        </div>
                        <div class="bg-gray-100 rounded-lg p-4 shadow-sm max-w-2xl">
                            ${isThinking ? 
                                `<div class="flex items-center text-gray-500">
                                    <div class="animate-pulse mr-2">${customThinkingText}</div>
                                    <div class="flex space-x-1">
                                        <div class="w-2 h-2 bg-gray-400 rounded-full animate-bounce"></div>
                                        <div class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 0.1s"></div>
                                        <div class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 0.2s"></div>
                                    </div>
                                </div>` : 
                                `<div class="text-gray-800 rag-response">${content}</div>`
                            }
                        </div>
                    </div>
                `;
            }
            
            document.getElementById('chatMessages').appendChild(messageElement);
            return messageId;
        },
        
        removeMessage(messageId) {
            const element = document.getElementById(`message-${messageId}`);
            if (element) {
                element.remove();
            }
        },
        
        parseAndDisplayResponse(htmlResponse) {
            // Show typing indicator first
            const typingId = this.addMessage('ai', '', true, '✍️ AI is responding...');
            
            // Simulate typing delay for better UX
            setTimeout(() => {
                this.removeMessage(typingId);
                
                try {
                    console.log('RAG Response:', htmlResponse);
                    
                    // Check if response contains .answer-box div
                    const tempDiv = document.createElement('div');
                    tempDiv.innerHTML = htmlResponse;
                    const answerBox = tempDiv.querySelector('.answer-box');
                    
                    let content = answerBox ? answerBox.innerHTML : htmlResponse;
                    
                    // Convert markdown image syntax to HTML img tags
                    content = content.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<img src="$2" alt="$1" style="max-width:300px; border-radius:8px; margin:10px 0;">');
                    
                    // Also handle plain image URLs in the response
                    content = content.replace(/(Image URL:\s*)(https?:\/\/[^\s<]+\.(jpg|jpeg|png|gif|webp))/gi, 
                        '$1<br><img src="$2" alt="Lot Image" style="max-width:300px; border-radius:8px; margin:10px 0;">');
                    
                    this.addMessage('ai', content);
                    
                } catch (error) {
                    console.error('Response parsing error:', error);
                    this.addMessage('ai', '❌ Sorry, I had trouble processing the response. Please try again.');
                }
            }, 800); // Small delay for typing effect
        },
        
        extractTextResponse(htmlResponse) {
            // Legacy text extraction fallback (not used in new flow)
            const tempDiv = document.createElement('div');
            tempDiv.innerHTML = htmlResponse;
            const scripts = tempDiv.querySelectorAll('script, style, nav, footer');
            scripts.forEach(el => el.remove());
            let textContent = tempDiv.textContent || tempDiv.innerText || '';
            textContent = textContent.replace(/\s+/g, ' ').trim();
            if (textContent.length > 0) {
                this.addMessage('ai', this.escapeHtml(textContent));
            } else {
                this.addMessage('ai', '🤔 I received a response but couldn\'t find a clear answer. Could you try rephrasing your question?');
            }
        },
        
        scrollToBottom() {
            this.$nextTick(() => {
                const chatWindow = document.getElementById('chatWindow');
                if (chatWindow) {
                    chatWindow.scrollTop = chatWindow.scrollHeight;
                }
            });
        },
        
        escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }
    }
}
</script>

</cfmodule>
