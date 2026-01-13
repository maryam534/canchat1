-- =====================================================================
-- Extensions
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS vector;  -- for pgvector (semantic search)

-- =====================================================================
-- Table: uploaded_files
-- Tracks processed files from your scraper/inserter pipeline
-- =====================================================================
CREATE TABLE uploaded_files (
  id SERIAL PRIMARY KEY,
  file_name TEXT,
  file_path TEXT,
  status TEXT DEFAULT 'Pending',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS uploaded_files_file_name_key ON uploaded_files(file_name);
  
ALTER TABLE uploaded_files
ADD COLUMN IF NOT EXISTS processed_at TIMESTAMPTZ DEFAULT now();

-- =====================================================================
-- Table: auction_houses  (formerly [dbo].[AuctionHouses])
-- Adds uniqueness on firm_id for safe upserts
-- =====================================================================
CREATE TABLE auction_houses (
  firm_pk   SERIAL PRIMARY KEY,
  firm_id   VARCHAR(50) NOT NULL,
  name      VARCHAR(80),
  addr1     VARCHAR(50),
  addr2     VARCHAR(50),
  addr3     VARCHAR(50),
  addr4     VARCHAR(50),
  phone     VARCHAR(100),
  fax       VARCHAR(100),
  s_email   VARCHAR(50),
  s_webpage VARCHAR(120),
  username  VARCHAR(50),
  password  VARCHAR(50),
  last_update TIMESTAMP,
  san_type    VARCHAR(1),
  reg_type    CHAR(1),
  email_bids  CHAR(1),
  wwchannel   CHAR(2),
  buyerspremium NUMERIC(8, 4),
  buyerspremium_mail NUMERIC(8, 2),
  pts  CHAR(20),
  asda CHAR(10),
  aps  CHAR(10),
  ipda CHAR(10),
  CONSTRAINT u_auction_houses_firm_id UNIQUE (firm_id)
);

-- =====================================================================
-- Table: sales (formerly [dbo].[SALES])
-- Adds keyword_categories array + uniqueness per house (sale_firm_fk, sale_no)
-- =====================================================================
CREATE TABLE sales (
  sale_pk       SERIAL PRIMARY KEY,
  sale_firm_fk  INT NOT NULL REFERENCES auction_houses(firm_pk) ON DELETE CASCADE,
  sale_no       VARCHAR(10) NOT NULL,
  salename      VARCHAR(200),
  date1         TIMESTAMP,
  date2         TIMESTAMP,
  summary       TEXT,
  location      TEXT,
  livebid       VARCHAR(1),
  saletype      VARCHAR(1),
  net_price     VARCHAR(1),
  unsolds       CHAR(1),
  web_toc       VARCHAR(120),
  boldtext      VARCHAR(200),
  uscalendar    VARCHAR(1),
  europecal     VARCHAR(1),
  worldwide     VARCHAR(1),
  linkonly      VARCHAR(1),
  alt_title     VARCHAR(200),
  link_html     VARCHAR(200),
  featuretext   TEXT,
  categorystamps VARCHAR(1),
  categorycoins  VARCHAR(1),
  salelogo       VARCHAR(200),
  salesource     VARCHAR(50),

  -- New: store unique categories per sale (collected from its lots)
  keyword_categories TEXT[] DEFAULT '{}',

  CONSTRAINT u_sales_house_sale_no UNIQUE (sale_firm_fk, sale_no)
);

-- =====================================================================
-- Table: lots (formerly [dbo].[LOTS])
-- Adds uniqueness (lot_sale_fk, lot_no) and on primarykey
-- =====================================================================
CREATE TABLE lots (
  lot_pk      SERIAL PRIMARY KEY,
  lot_firm_fk INT NOT NULL REFERENCES auction_houses(firm_pk) ON DELETE CASCADE,
  lot_sale_fk INT NOT NULL REFERENCES sales(sale_pk) ON DELETE CASCADE,

  lot_no    VARCHAR(10) NOT NULL,
  majgroup  VARCHAR(50),
  catdescr  TEXT,
  subgroup  VARCHAR(50),
  scountry  VARCHAR(50),
  year      VARCHAR(10),
  stamp     VARCHAR(1),
  coin      VARCHAR(1),
  "order"   VARCHAR(25),
  symbol    VARCHAR(5),
  "condition" VARCHAR(8),
  gum       VARCHAR(5),
  title     TEXT,
  htmltext  TEXT,
  htmlfile  VARCHAR(30),
  image_url TEXT,
  video_url TEXT,
  lot_url   TEXT,
  est_low   FLOAT,
  est_real  FLOAT,
  opening   FLOAT,
  realized  FLOAT,
  reserve   FLOAT,
  grade     TEXT,
  certifying_agency TEXT,
  currency  VARCHAR(10),
  last_edit TIMESTAMP,
  last_time VARCHAR(6),
  close_date TIMESTAMP,

  -- Surrogate composite identity you already use
  primarykey VARCHAR(100) NOT NULL,

  slot_no  VARCHAR(50),
  sorder   VARCHAR(50),

  CONSTRAINT u_lots_sale_lot_no UNIQUE (lot_sale_fk, lot_no),
  CONSTRAINT u_lots_primarykey UNIQUE (primarykey)
);

-- =====================================================================
-- Table: categories (global, unique list)
-- =====================================================================
CREATE TABLE categories (
  id BIGSERIAL PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- =====================================================================
-- Table: lot_chunks (RAG vector store for lots)
--  - One chunk per lot (you can expand to multi-chunk later if needed)
--  - VECTOR(1536) for nomic-embed-text-v1; change if your model differs
-- =====================================================================
CREATE TABLE lot_chunks (
  id BIGSERIAL PRIMARY KEY,
  lot_fk   INT NOT NULL UNIQUE REFERENCES lots(lot_pk) ON DELETE CASCADE,
  chunk    TEXT NOT NULL,
  embedding VECTOR(1536)
);

-- Approximate nearest neighbor (ANN) index for cosine similarity
CREATE INDEX lot_chunks_embedding_idx
  ON lot_chunks USING ivfflat (embedding vector_cosine_ops)
  WITH (lists = 100);

-- Database setup for NumisBids Scraper Job Management System

-- Table for tracking scraper jobs
CREATE TABLE IF NOT EXISTS scraper_jobs (
    id SERIAL PRIMARY KEY,
    job_name VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'queued', -- queued, running, paused, stopped, completed, error
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP NULL,
    paused_at TIMESTAMP NULL,
    stopped_at TIMESTAMP NULL,
    completed_at TIMESTAMP NULL,
    process_id VARCHAR(50) NULL,
    max_sales INTEGER NULL,
    target_event_id VARCHAR(50) NULL,
    run_mode VARCHAR(20) DEFAULT 'all', -- all, one, max
    parameters JSONB NULL,
    error_message TEXT NULL,
    created_by VARCHAR(100) DEFAULT 'system',
    rag_processed_at TIMESTAMP NULL -- Track when RAG processing completed
);

-- Table for detailed scraping logs
CREATE TABLE IF NOT EXISTS scrape_logs (
    id SERIAL PRIMARY KEY,
    job_id INTEGER REFERENCES scraper_jobs(id) ON DELETE CASCADE,
    log_level VARCHAR(20) NOT NULL, -- info, warning, error, debug
    message TEXT NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    source VARCHAR(100) DEFAULT 'scraper', -- scraper, system, user
    metadata JSONB NULL
);

-- Table for job statistics
CREATE TABLE IF NOT EXISTS job_statistics (
    id SERIAL PRIMARY KEY,
    job_id INTEGER REFERENCES scraper_jobs(id) ON DELETE CASCADE,
    total_events INTEGER DEFAULT 0,
    processed_events INTEGER DEFAULT 0,
    total_lots INTEGER DEFAULT 0,
    processed_lots INTEGER DEFAULT 0,
    files_created INTEGER DEFAULT 0,
    files_completed INTEGER DEFAULT 0,
    start_time TIMESTAMP NULL,
    end_time TIMESTAMP NULL,
    duration_seconds INTEGER DEFAULT 0,
    last_update TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for better performance
CREATE INDEX IF NOT EXISTS idx_scraper_jobs_status ON scraper_jobs(status);
CREATE INDEX IF NOT EXISTS idx_scraper_jobs_created_at ON scraper_jobs(created_at);
CREATE INDEX IF NOT EXISTS idx_scraper_jobs_status_created ON scraper_jobs(status, created_at);
CREATE INDEX IF NOT EXISTS idx_scrape_logs_job_id ON scrape_logs(job_id);
CREATE INDEX IF NOT EXISTS idx_scrape_logs_timestamp ON scrape_logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_job_statistics_job_id ON job_statistics(job_id);

-- Insert initial system job if needed
INSERT INTO scraper_jobs (job_name, status, created_by) 
VALUES ('System Initialization', 'completed', 'system')
ON CONFLICT DO NOTHING; 