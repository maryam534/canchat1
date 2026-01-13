# 🎯 Stamp Auction ChatBot

An intelligent AI-powered chatbot system for stamp auction data with web scraping, semantic search, and natural language querying capabilities.

## ✨ Features

- **🤖 AI Chat Interface** - Natural language queries about stamp auctions
- **🔍 Semantic Search** - Vector-based similarity search using OpenAI embeddings  
- **🕷️ Web Scraping** - Automated data collection from NumisBids.com
- **📄 Document Processing** - PDF/DOC upload with text extraction
- **📊 Admin Dashboard** - Complete system management interface
- **⚡ Real-time Monitoring** - System status and performance tracking

## 🚀 Quick Start

1. **Follow Installation Guide**
   ```bash
   # See INSTALLATION_GUIDE.md for complete setup instructions
   ```

2. **Start the Application**
   ```
   http://your-server/stampchatbot/index.cfm
   ```

3. **Try Sample Queries**
   - "show me lot 100"
   - "stamps from Germany"
   - "what sold for over $500?"

## 🏗️ Architecture

- **Frontend:** ColdFusion + JavaScript + Tailwind CSS
- **Backend:** PostgreSQL with pgvector + Node.js scraping
- **AI:** OpenAI GPT-4 + text-embedding-3-small
- **Processing:** Apache Tika + Jsoup

## 📁 Core Files

- `Application.cfc` - Centralized configuration
- `index.cfm` - Main chat interface  
- `chat.js` - Frontend interactions
- `tables_schema.sql` - Complete database schema
- `rag.cfm` - AI processing engine
- `scrap_all_auctions_lots_data.js` - Web scraper

## 🔧 Configuration

All settings are centralized in `Application.cfc`:
- File paths and directories
- AI model settings and API keys
- Database connections and limits
- Processing parameters
- UI preferences

Create a `.env` file at the project root (see `.env.example`) with keys like:

- `OPENAI_API_KEY`, `DATABASE_URL`
- `BASE_URL`, `PROCESS_URL`
- `NODE_BINARY`, `CMD_EXE`
- `SCRAPER_PATH`, `INSERTER_PATH`
- `UPLOADS_DIR`, `INPROGRESS_DIR`, `FINAL_DIR`
- `TIKA_PATH`, `JSOUP_CLASS`, `CHAT_VERSION`

## 📖 Documentation

- **Installation:** See `INSTALLATION_GUIDE.md`
- **Configuration Test:** Visit `/config_test.cfm`
- **Admin Dashboard:** Visit `/dashboard.cfm`

## 🎯 Usage Examples

```
User: "show me lot 100"
Bot: Returns specific lot 100 with image, price, and details

User: "stamps from Cuba"  
Bot: Shows relevant Cuban stamp lots with similarity matching

User: "what sold for over 100 EUR?"
Bot: Finds lots with realized prices above 100 EUR
```

## 🔗 Quick Links

- **Chat Interface:** `/index.cfm`
- **Admin Dashboard:** `/dashboard.cfm` 
- **System Status:** `/system_status.cfm`
- **Configuration Test:** `/config_test.cfm`

---

**Built with ❤️ for stamp collectors and auction enthusiasts**
