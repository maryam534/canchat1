# Stamp Auction ChatBot - Installation Guide

A comprehensive AI-powered chatbot system for stamp auction data with web scraping, semantic search, and RAG (Retrieval Augmented Generation) capabilities.

## 📋 System Requirements

### Software Requirements
- **ColdFusion 2023** (or compatible CFML engine like Lucee 6.2+)
- **PostgreSQL 14+** with pgvector extension
- **Node.js 18+** with npm
- **Java 8+** (for ColdFusion and document processing)

### Hardware Requirements
- **RAM:** Minimum 8GB (16GB recommended)
- **Storage:** 10GB+ free space
- **CPU:** Multi-core processor recommended

## 🗂️ Project Structure

```
stampchatbot/
├── Application.cfc              # Main application configuration
├── index.cfm                    # Main chat interface
├── chat.js                      # Frontend JavaScript
├── tables_schema.sql            # Complete database schema
├── package.json                 # Node.js dependencies
├── scrap_all_auctions_lots_data.js  # Web scraper
├── insert_lots_into_db.js       # Database importer
├── dbConfig.js                  # Database connection config
├── cfml/                        # ColdFusion components
│   ├── rag.cfm                  # RAG processing engine
│   ├── dashboard.cfm            # Admin dashboard
│   ├── upload.cfm               # File upload handler
│   ├── process_upload.cfm       # Document processing
│   ├── system_status.cfm        # System monitoring
│   ├── export_chunks.cfm        # Data export
│   ├── scrape_import.cfm        # Web scraping
│   └── config_test.cfm          # Configuration test page
├── tasks/                       # Background tasks
│   └── run_scraper.cfm          # Scraper control panel
├── libs/                        # Java libraries
│   ├── jsoup-1.20.1.jar        # HTML parsing
│   └── tika-app-3.2.3.jar      # Document text extraction
├── allAuctionLotsData_inprogress/  # Scraping work directory
├── allAuctionLotsData_final/    # Completed auction data
└── uploads/                     # Document uploads
```

## 🚀 Installation Steps

### Task 1: Database Setup

1. **Install PostgreSQL with pgvector**
   ```bash
   # Install PostgreSQL 14+ and pgvector extension
   # On Windows: Download from https://www.postgresql.org/download/windows/
   # Install pgvector: https://github.com/pgvector/pgvector#installation
   ```

2. **Create Database**
   ```sql
   CREATE DATABASE stampchatbot;
   CREATE USER stampchat_user WITH PASSWORD 'your_secure_password';
   GRANT ALL PRIVILEGES ON DATABASE stampchatbot TO stampchat_user;
   ```

3. **Run Database Schema**
   ```bash
   psql -U stampchat_user -d stampchatbot -f tables_schema.sql
   ```

### Task 2: Node.js Environment Setup

1. **Install Node.js**
   - Download from: https://nodejs.org/ (LTS version)
   - Verify installation: `node -v && npm -v`

2. **Install Dependencies**
   ```bash
   cd /path/to/stampchatbot
   npm install
   ```

3. **Install Playwright Browsers**
   ```bash
   npx playwright install
   ```

4. **Configure Environment Variables**
   Create `.env` file in project root:
   ```env
   # OpenAI Configuration
   OPENAI_API_KEY=sk-your-openai-api-key-here
   
   # Database Configuration
   DATABASE_URL=postgres://stampchat_user:your_secure_password@localhost:5432/stampchatbot

   # Web Configuration
   BASE_URL=http://localhost/canchat1
   PROCESS_URL=http://localhost/canchat1
   CHAT_VERSION=11

   # Paths
   NODE_BINARY=C:\\Program Files\\nodejs\\node.exe
   CMD_EXE=C:\\Windows\\System32\\cmd.exe
   SCRAPER_PATH=./scrap_all_auctions_lots_data.js
   INSERTER_PATH=./insert_lots_into_db.js
   UPLOADS_DIR=./uploads
   INPROGRESS_DIR=./allAuctionLotsData_inprogress
   FINAL_DIR=./allAuctionLotsData_final
   LIBS_DIR=./libs
   DEBUG_DIR=./debug

   # Processing
   TIKA_PATH=./libs/tika-app-3.2.3.jar
   JSOUP_CLASS=org.jsoup.Jsoup
   EMBED_MODEL=text-embedding-3-small
   EMBED_DIM=1536
   ```

### Task 3: ColdFusion Setup

1. **Configure ColdFusion Datasource**
   - Create datasource named: `ragdb`
   - Database: PostgreSQL
   - Server: localhost
   - Port: 5432
   - Database: stampchatbot
   - Username: stampchat_user
   - Password: your_secure_password

2. **Configure Java Libraries**
   - Ensure `libs/` folder contains:
     - `jsoup-1.20.1.jar`
     - `tika-app-3.2.3.jar`
   - Update `Application.cfc` paths if needed

3. **Set Environment Variables**
   - Set `OPENAI_API_KEY` in system environment or JVM properties
   - Example JVM: `-DOPENAI_API_KEY=sk-your-key`

### Task 4: Directory Structure

1. **Create Required Directories**
   ```bash
   mkdir allAuctionLotsData_inprogress
   mkdir allAuctionLotsData_final  
   mkdir uploads
   ```

2. **Set Permissions**
   - Ensure ColdFusion can read/write to all directories
   - Set appropriate file permissions for your OS

### Task 5: Configuration Verification

1. **Test Configuration**
   - Navigate to: `http://your-server/stampchatbot/cfml/config_test.cfm`
   - Verify all paths and settings are correct

2. **Test Database Connection**
   - Check that all tables were created successfully
   - Verify pgvector extension is installed

## 🎯 Usage Instructions

### Starting the Application

1. **Access Main Interface**
   ```
   http://your-server/stampchatbot/index.cfm
   ```

2. **Admin Dashboard**
   ```
   http://your-server/stampchatbot/cfml/dashboard.cfm
   ```

3. **System Status**
   ```
   http://your-server/stampchatbot/cfml/system_status.cfm
   ```

### Core Features

#### 1. **Chat Interface**
- Ask questions about stamp auctions
- Query specific lot numbers: "show me lot 100"
- Search by category, country, or description

#### 2. **Web Scraping**
- Automated scraping from NumisBids.com
- Manual scraper control via dashboard
- Resume/pause/stop functionality

#### 3. **Document Upload**
- Upload PDF catalogs for processing
- Automatic text extraction and embedding
- Integration with chat search

#### 4. **Data Management**
- Export filtered data as CSV
- Monitor system performance
- View processing logs

## ⚙️ Configuration Options

### Environment Variables
```env
# Required
OPENAI_API_KEY=sk-your-api-key

# Optional
BASE_URL=http://localhost
PROCESS_URL=http://your-server/stampchatbot
DATABASE_URL=postgres://user:pass@localhost:5432/dbname
```

### Application.cfc Settings

All configuration is centralized in `Application.cfc`:

- **AI Settings:** Model selection, timeouts, limits
- **File Paths:** All directory and executable paths
- **Database:** Connection and query limits
- **Processing:** Chunk sizes, timeouts, retries
- **UI:** Display options and debug settings

## 🔧 Maintenance

### Regular Tasks
1. **Monitor disk space** in data directories
2. **Check system status** via dashboard
3. **Review processing logs** for errors
4. **Update OpenAI API usage** monitoring

### Troubleshooting
1. **Check configuration:** Visit `/cfml/config_test.cfm`
2. **Review logs:** ColdFusion application logs
3. **Database health:** Monitor PostgreSQL performance
4. **API limits:** Monitor OpenAI API usage

## 🚀 Getting Started

1. **Complete installation** following all tasks above
2. **Test configuration** page
3. **Upload sample document** to test processing
4. **Try chat queries** like "show me lot 100"
5. **Access admin dashboard** for system management

## 📞 Support

- Configuration issues: Check `cfml/config_test.cfm`
- Database problems: Verify `tables_schema.sql` execution
- API errors: Check OpenAI API key and usage limits
- Scraping issues: Monitor via system status dashboard

---

**Note:** This system combines web scraping, vector databases, and AI to create an intelligent stamp auction assistant. Ensure all components are properly configured before use.
