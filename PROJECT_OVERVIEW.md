# 📋 Project Overview - Stamp Auction ChatBot

## 🎯 System Architecture

### Core Components

#### **1. Frontend (User Interface)**
- **`index.cfm`** - Main chat interface with Tailwind CSS styling
- **`chat.js`** - JavaScript handling user interactions and API calls
- **Loading indicators** and **real-time feedback**

#### **2. Backend (ColdFusion)**
- **`Application.cfc`** - Centralized configuration management
- **`cfml/rag.cfm`** - RAG processing engine with vector search
- **`cfml/dashboard.cfm`** - Administrative dashboard
- **`cfml/upload.cfm`** - File upload handler
- **`cfml/process_upload.cfm`** - Document text extraction and embedding

#### **3. Data Processing (Node.js)**
- **`scrap_all_auctions_lots_data.js`** - Web scraper for NumisBids.com
- **`insert_lots_into_db.js`** - Database import with embeddings
- **`dbConfig.js`** - Database connection configuration

#### **4. Database (PostgreSQL + pgvector)**
- **`tables_schema.sql`** - Complete database schema
- **Vector embeddings** for semantic search
- **Auction data storage** with relationships

#### **5. Automation & Control**
- **`tasks/run_scraper.cfm`** - Scraper control panel
- **`cfml/system_status.cfm`** - System monitoring

## 🔄 Data Flow

### **1. Web Scraping Process**
```
NumisBids.com → Playwright Scraper → JSON Files → Database Import → Vector Embeddings
```

### **2. Document Upload Process**
```
PDF Upload → Apache Tika → Text Extraction → Chunking → OpenAI Embeddings → Database
```

### **3. Chat Query Process**
```
User Query → OpenAI Embedding → Vector Search → Context Retrieval → GPT-4 → Response
```

## 🗂️ File Organization

### **Essential Files (DO NOT DELETE)**
```
stampchatbot/
├── Application.cfc              # ⚙️ Core configuration
├── index.cfm                    # 🏠 Main interface  
├── chat.js                      # 💬 Frontend logic
├── tables_schema.sql            # 🗄️ Database schema
├── package.json                 # 📦 Dependencies
├── scrap_all_auctions_lots_data.js  # 🕷️ Web scraper
├── insert_lots_into_db.js       # 📥 Data importer
└── dbConfig.js                  # 🔗 DB connection
```

### **CFML Components**
```
cfml/
├── rag.cfm                      # 🤖 AI processing
├── dashboard.cfm                # 📊 Admin panel
├── upload.cfm                   # 📤 File uploads
├── process_upload.cfm           # 📄 Document processing
├── system_status.cfm            # 📈 Monitoring
├── export_chunks.cfm            # 📋 Data export
├── scrape_import.cfm            # 🌐 Web scraping
└── config_test.cfm              # 🧪 Config verification
```

### **Supporting Files**
```
├── libs/                        # Java libraries
├── tasks/run_scraper.cfm        # Scraper control
├── allAuctionLotsData_*/        # Data directories
├── uploads/                     # Upload directory
├── setup.js                     # Setup script
├── INSTALLATION_GUIDE.md        # Setup instructions
└── DEPLOYMENT_CHECKLIST.md      # Deployment guide
```

## 🎨 Key Features

### **1. Intelligent Chat**
- **Natural Language Processing** with GPT-4
- **Lot-specific queries** ("show me lot 100")
- **Semantic search** across auction data
- **Real-time loading indicators**

### **2. Web Scraping**
- **Automated data collection** from NumisBids.com
- **Resume/pause/stop** functionality
- **Progress monitoring** and logging
- **Error handling** and recovery

### **3. Document Processing**
- **PDF/DOC upload** support
- **Text extraction** with Apache Tika
- **Automatic chunking** and embedding
- **Integration** with chat search

### **4. Administration**
- **System monitoring** dashboard
- **Performance metrics** tracking
- **Data export** capabilities
- **Configuration management**

## 🔧 Configuration Management

### **Centralized in Application.cfc**
- **File Paths:** All directories and executables
- **AI Settings:** Models, timeouts, limits
- **Database:** Connections and query limits  
- **Processing:** Chunk sizes, retries
- **UI:** Display options and debug settings

### **Environment Variables**
- **`OPENAI_API_KEY`** - Required for AI functionality
- **`DATABASE_URL`** - PostgreSQL connection string
- **`BASE_URL`** - Application base URL
- **`PROCESS_URL`** - Processing server URL

## 🚀 Deployment

### **Development Environment**
1. Run `npm run setup` for interactive configuration
2. Start ColdFusion server
3. Access `http://localhost/stampchatbot/index.cfm`

### **Production Environment**
1. Follow `INSTALLATION_GUIDE.md` completely
2. Complete `DEPLOYMENT_CHECKLIST.md` verification
3. Monitor via system status dashboard

## 🎯 Usage Patterns

### **End Users**
- **Chat Interface:** Ask natural language questions
- **Lot Queries:** Search specific lot numbers
- **Category Searches:** Find stamps by country/type

### **Administrators**
- **Dashboard:** Monitor system health
- **Scraper Control:** Manage data collection
- **File Management:** Upload and process documents

## 📊 Performance Expectations

- **Chat Response:** 3-10 seconds
- **Lot Queries:** 1-5 seconds  
- **Document Upload:** 30-120 seconds
- **Scraping:** 10-60 minutes per auction

---

**This system provides a complete AI-powered solution for stamp auction data management and querying.** 🎯
