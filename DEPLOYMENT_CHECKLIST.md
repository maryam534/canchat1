# 🚀 Deployment Checklist

## Pre-Deployment Verification

### ✅ Task 1: Environment Setup
- [ ] PostgreSQL 14+ installed with pgvector extension
- [ ] ColdFusion 2023 or Lucee 6.2+ running
- [ ] Node.js 18+ installed
- [ ] Java 8+ available for ColdFusion

### ✅ Task 2: Database Configuration
- [ ] Database `stampchatbot` created
- [ ] User `stampchat_user` created with proper permissions
- [ ] `tables_schema.sql` executed successfully
- [ ] pgvector extension enabled
- [ ] ColdFusion datasource `ragdb` configured

### ✅ Task 3: Application Configuration
- [ ] `.env` file created with all required variables
- [ ] `OPENAI_API_KEY` set and valid
- [ ] `DATABASE_URL` configured correctly
- [ ] Directory permissions set for uploads and data folders

### ✅ Task 4: Dependencies
- [ ] `npm install` completed successfully
- [ ] `npx playwright install` completed
- [ ] Java libraries in `libs/` folder accessible
- [ ] All required directories created

## Deployment Steps

### ✅ Task 5: Initial Testing
- [ ] Visit `/cfml/config_test.cfm` - all settings show correctly
- [ ] Test database connection - no errors
- [ ] Test OpenAI API connection - embeddings work
- [ ] Upload test document - processing succeeds

### ✅ Task 6: Core Functionality
- [ ] Chat interface loads at `/index.cfm`
- [ ] Can send messages and receive responses
- [ ] Lot number queries work ("show me lot 100")
- [ ] General searches return relevant results

### ✅ Task 7: Admin Features
- [ ] Dashboard accessible at `/cfml/dashboard.cfm`
- [ ] System status page shows correct information
- [ ] File upload functionality works
- [ ] Scraper control panel accessible

### ✅ Task 8: Performance
- [ ] Response times under 10 seconds for chat queries
- [ ] Database queries execute efficiently
- [ ] File uploads process without timeout
- [ ] System resources within acceptable limits

## Production Checklist

### ✅ Task 9: Security
- [ ] OpenAI API key secured (not in source code)
- [ ] Database credentials secured
- [ ] File upload restrictions in place
- [ ] Error messages don't expose sensitive information

### ✅ Task 10: Monitoring
- [ ] System status dashboard functional
- [ ] Log files accessible and rotating
- [ ] Performance metrics being tracked
- [ ] Error alerting configured

### ✅ Task 11: Backup & Recovery
- [ ] Database backup strategy in place
- [ ] Auction data files backed up
- [ ] Configuration files version controlled
- [ ] Recovery procedures documented

## Post-Deployment

### ✅ Task 12: User Training
- [ ] Admin users trained on dashboard
- [ ] Chat interface usage documented
- [ ] Troubleshooting guide available
- [ ] Support contacts established

### ✅ Task 13: Maintenance
- [ ] Regular backup schedule active
- [ ] System monitoring alerts configured
- [ ] Update procedures documented
- [ ] Performance baselines established

---

## Quick Verification Commands

```bash
# Test Node.js setup
node --version
npm --version

# Test database connection
psql -U stampchat_user -d stampchatbot -c "SELECT version();"

# Test OpenAI API
curl -H "Authorization: Bearer $OPENAI_API_KEY" https://api.openai.com/v1/models

# Test application
curl http://your-server/stampchatbot/cfml/config_test.cfm
```

## Emergency Contacts

- **Database Issues:** Check PostgreSQL logs
- **API Issues:** Verify OpenAI API key and usage
- **Scraping Issues:** Check system status dashboard
- **Performance Issues:** Monitor system resources

---

**Complete this checklist before going live!** ✅
