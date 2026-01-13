# ⚡ Quick Start Guide

## 🚀 Get Running in 10 Minutes

### Task 1: Prerequisites (2 minutes)
```bash
# Verify you have:
node --version    # Should be 18+
java -version     # Should be 8+
psql --version    # Should be 14+
```

### Task 2: Database Setup (3 minutes)
```sql
-- Create database and user
CREATE DATABASE stampchatbot;
CREATE USER stampchat_user WITH PASSWORD 'your_password';
GRANT ALL PRIVILEGES ON DATABASE stampchatbot TO stampchat_user;

-- Install pgvector extension
CREATE EXTENSION vector;

-- Run schema
\i tables_schema.sql
```

### Task 3: Configuration (2 minutes)
```bash
# Run interactive setup
npm run setup

# Or manually create .env:
echo "OPENAI_API_KEY=sk-your-key" > .env
echo "DATABASE_URL=postgres://stampchat_user:password@localhost:5432/stampchatbot" >> .env
```

### Task 4: Install Dependencies (2 minutes)
```bash
npm install
npm run install-browsers
```

### Task 5: Start Application (1 minute)
1. **Start ColdFusion server**
2. **Configure datasource:** Name: `ragdb`, PostgreSQL connection
3. **Access:** `http://localhost/stampchatbot/index.cfm`

## ✅ Verification

### Test These URLs:
- **Chat:** `/index.cfm` - Should load chat interface
- **Config:** `/cfml/config_test.cfm` - Should show all settings
- **Dashboard:** `/cfml/dashboard.cfm` - Should load admin panel

### Test These Queries:
- **"hello"** - Should get welcome response
- **"show me lot 100"** - Should find specific lot (if data exists)
- **Upload a PDF** - Should process and create embeddings

## 🔧 Troubleshooting

### Common Issues:

#### **"Datasource not found"**
- Configure ColdFusion datasource named `ragdb`
- Test database connection in CF Admin

#### **"OpenAI API Error"**
- Check `OPENAI_API_KEY` in environment
- Verify API key is valid and has credits

#### **"No results found"**
- Import sample data: `npm run import`
- Or scrape new data: `npm run scrape`

#### **"Loading indicator not showing"**
- Check browser console for JavaScript errors
- Verify `chat.js` is loading correctly

## 📞 Need Help?

1. **Check configuration:** `/cfml/config_test.cfm`
2. **Review logs:** ColdFusion application logs
3. **Test components:** Use deployment checklist
4. **Verify setup:** Follow installation guide

---

**You should be chatting with your stamp auction assistant in under 10 minutes!** 🎯
