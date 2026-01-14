/**
 * NumisBids JSON -> Postgres (two-phase: core tx, then embeddings)
 *
 * ENV needed:
 *   OPENAI_API_KEY=sk-...
 *   EMBED_MODEL=text-embedding-3-small
 *   EMBED_DIM=1536
 *
 * DB prereqs: pgvector installed; unique indexes & lot_chunks table as noted.
 * 
 */

const fs = require('fs').promises;
const path = require('path');
try { require('dotenv').config({ path: path.join(__dirname, '.env') }); } catch (_) {}
const axios = require('axios');
const https = require('https');
const pool = require('./dbConfig'); // your pg Pool

// -------- Config --------
const folderPath = (() => {
  const envVal = process.env.FINAL_DIR;
  if (envVal) {
    return path.isAbsolute(envVal) ? envVal : path.join(__dirname, envVal);
  }
  return path.join(__dirname, 'allAuctionLotsData_final');
})();

const OPENAI_API_KEY = (process.env.OPENAI_API_KEY || '').replace(/^"|"$/g, '');
const EMBED_MODEL    = process.env.EMBED_MODEL || 'text-embedding-3-small'; // cost-effective
const EMBED_DIM      = Number(process.env.EMBED_DIM || 1536);               // must match DB (vector(1536))

// -------- Hardened HTTP client (timeout + keep-alive) --------
const http = axios.create({
  baseURL: 'https://api.openai.com/v1',
  timeout: 20000, // 20s
  headers: {
    Authorization: `Bearer ${OPENAI_API_KEY}`,
    'Content-Type': 'application/json'
  },
  httpsAgent: new https.Agent({ keepAlive: true }),
  maxContentLength: Infinity,
  maxBodyLength: Infinity
});

function sleep(ms){ return new Promise(r => setTimeout(r, ms)); }

async function withRetries(fn, tries = 3, baseDelayMs = 1200) {
  let lastErr;
  for (let i = 0; i < tries; i++) {
    try { return await fn(); }
    catch (e) {
      lastErr = e;
      const code = e.code;
      const status = e.response?.status;

      const isTransientCode = ['ECONNRESET','ETIMEDOUT','EAI_AGAIN','ECONNABORTED'].includes(code);
      const isTransientHttp = (status === 429) || (status && status >= 500);
      const transient = isTransientCode || isTransientHttp;

      const msg = e.response?.data?.error?.message || e.message;
      console.warn(`[embed retry ${i+1}/${tries}] code=${code||'-'} status=${status||'-'} msg=${msg}`);

      if (i === tries - 1 || !transient) break;

      // longer backoff on 429
      const factor = (status === 429) ? 2 : 1;
      await sleep(baseDelayMs * (i + 1) * factor);
    }
  }
  throw lastErr;
}

// -------- Utility: Embedding + Chunking --------
function buildLotChunk(lot, saleName) {
  return [
    `Lot ${lot.lotnumber || ''}: ${lot.lotname || ''}`,
    lot.shortdescription || '',
    lot.fulldescription || '',
    `Category: ${lot.category || ''}`,
    `Starting: ${lot.startingprice || ''}  Realized: ${lot.realizedprice || ''}`,
    `Sale: ${saleName || ''}`,
    `URL: ${lot.loturl || ''}`
  ].filter(Boolean).join('\n');
}

async function getEmbedding(text) {
  
  if (!OPENAI_API_KEY) throw new Error('OPENAI_API_KEY is not set');

  const res = await withRetries(
    () => http.post('/embeddings', { model: EMBED_MODEL, input: text }),
    3,
    1200
  );
  const emb = res?.data?.data?.[0]?.embedding;
  if (!Array.isArray(emb)) {
    throw new Error(`Embedding missing for model=${EMBED_MODEL}`);
  }
  if (emb.length !== EMBED_DIM) {
    throw new Error(`Embedding dim mismatch: got ${emb.length}, expected ${EMBED_DIM}`);
  }
  return emb; // array of floats
}

function extractPriceAndCurrency(priceStr) {
  if (!priceStr) return { price: null, currency: null };
  priceStr = String(priceStr).replace(/starting price:/i, '').trim();
  const parts = priceStr.split(/\s+/);
  const currency = parts.pop();
  const price = parseFloat(parts.join('').replace(/,/g, ''));
  return { price: isNaN(price) ? null : price, currency: currency || null };
}

function parseEventDate(eventDateStr) {
  if (!eventDateStr) return { startDate: null, endDate: null };
  eventDateStr = String(eventDateStr).replace(/^Auction date:\s*/i, '').trim();
  const parts = eventDateStr.split(' ');
  if (parts[0]?.includes('-')) {
    const [startDay, endDay] = parts[0].split('-');
    const month = parts[1];
    const year  = parts[2];
    return {
      startDate: new Date(`${startDay} ${month} ${year}`),
      endDate:   new Date(`${endDay} ${month} ${year}`)
    };
  } else {
    const [day, month, year] = parts;
    const dt = new Date(`${day} ${month} ${year}`);
    return { startDate: dt, endDate: dt };
  }
}

// -------- File bookkeeping (use client inside tx) --------
// Skip **only** if status='Completed'. If you prefer skip-on-any-row, just return result.rowCount > 0.
async function fileAlreadyProcessedTx(client, fileName) {
  const result = await client.query(
    `SELECT status FROM uploaded_files WHERE file_name = $1 LIMIT 1`,
    [fileName]
  );
  if (!result.rowCount) return false;
  return result.rows[0].status === 'Completed';
}

// Upsert with status & processed_at; needs UNIQUE on file_name
async function markFileAsProcessedTx(client, fileName, relativeFilePath, status = 'Completed') {
  await client.query(
    `INSERT INTO uploaded_files (file_name, file_path, status, processed_at)
     VALUES ($1, $2, $3, now())
     ON CONFLICT (file_name) DO UPDATE
     SET file_path = EXCLUDED.file_path,
         status = EXCLUDED.status,
         processed_at = now()`,
    [fileName, relativeFilePath, status]
  );
}

// -------- Upsert helpers (transaction-aware) --------
async function upsertAuctionHouseFromJsonTx(client, jsonData) {
  const firmId = jsonData.auctionid;
  const name   = jsonData.auctionname || 'Unknown Auction House';

  // Extract contact info from jsonData.contact or use defaults
  const contact = jsonData.contact || {};
  const addressLines = (contact.address || '')
    .split(',').map(l => l.trim()).filter(Boolean);
  const [addr1 = '', addr2 = '', addr3 = '', addr4 = ''] = addressLines;

  const phone = contact.phone || '';
  const fax   = contact.fax || '';
  const s_email   = contact.email || '';
  const s_webpage = contact.website || '';
  const last_update = new Date();

  console.log(`Upserting Auction House: firmId=${firmId}, name=${name}`);

  await client.query(`
    INSERT INTO auction_houses (
      firm_id, name, addr1, addr2, addr3, addr4,
      phone, fax, s_email, s_webpage, last_update
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
    ON CONFLICT (firm_id) DO UPDATE SET
      name = EXCLUDED.name,
      addr1 = EXCLUDED.addr1, addr2 = EXCLUDED.addr2, addr3 = EXCLUDED.addr3, addr4 = EXCLUDED.addr4,
      phone = EXCLUDED.phone, fax = EXCLUDED.fax,
      s_email = EXCLUDED.s_email, s_webpage = EXCLUDED.s_webpage,
      last_update = EXCLUDED.last_update
  `, [firmId, name, addr1, addr2, addr3, addr4, phone, fax, s_email, s_webpage, last_update]);
}

async function getFirmPkTx(client, firmId) {
  const r = await client.query(
    `SELECT firm_pk FROM auction_houses WHERE firm_id = $1`,
    [firmId]
  );
  return r.rowCount ? r.rows[0].firm_pk : null;
}

async function upsertSaleTx(client, jsonData, firmPk) {
  const saleNo     = jsonData.auctionid || '';
  const salename   = jsonData.auctiontitle || 'Unknown Sale';
  const { startDate, endDate } = parseEventDate(jsonData.eventdate || '');
  const salelogo   = jsonData.saleInfo?.saleLogo || '';
  const salesource = jsonData.contact?.website || '';

  console.log(`Upserting Sale: saleNo=${saleNo}, salename=${salename}, startDate=${startDate}, endDate=${endDate}`);

  const r = await client.query(`
    INSERT INTO sales (
      sale_firm_fk, sale_no, salename, date1, date2, salelogo, salesource
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7)
    ON CONFLICT (sale_firm_fk, sale_no) DO UPDATE SET
      salename   = EXCLUDED.salename,
      date1      = EXCLUDED.date1,
      date2      = EXCLUDED.date2,
      salelogo   = EXCLUDED.salelogo,
      salesource = EXCLUDED.salesource
    RETURNING sale_pk
  `, [firmPk, saleNo, salename, startDate, endDate, salelogo, salesource]);

  return { salePk: r.rows[0].sale_pk, saleEndDate: endDate || null };
}

async function upsertLotTx(client, lot, jsonData, firmPk, salePk) {
  const lastEdit   = new Date();
  const auctionId  = jsonData.auctionid || '';
  const saleNumber = jsonData.auctionid || ''; // Use auctionid as sale number
  const lot_no     = lot.lotnumber || null;

  const majgroup   = lot.category || null;
  const catdescr   = lot.shortdescription || lot.lotname || null;
  const title      = lot.fulldescription || null;
  const image_url  = lot.imagepath || null;
  const lot_url    = lot.loturl || null;
  const { startDate, endDate } = parseEventDate(jsonData.eventdate || '');

  const { price: opening,  currency } = extractPriceAndCurrency(lot.startingprice);
  const { price: realized }           = extractPriceAndCurrency(lot.realizedprice);

  const primarykey = `${auctionId}-${saleNumber}-${lot_no}`;
  const lotCloseDate = endDate || null;

  console.log(`Upserting Lot: lot_no=${lot_no}, majgroup=${majgroup}, opening=${opening}, realized=${realized}`);

  const r = await client.query(`
    INSERT INTO lots (
      lot_firm_fk, lot_sale_fk, lot_no, majgroup, catdescr,
      title, image_url, lot_url, close_date, opening, realized, currency, last_edit, primarykey
    )
    VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
    ON CONFLICT (primarykey) DO UPDATE SET
      majgroup   = EXCLUDED.majgroup,
      catdescr   = EXCLUDED.catdescr,
      title      = EXCLUDED.title,
      image_url  = EXCLUDED.image_url,
      lot_url    = EXCLUDED.lot_url,
      close_date = COALESCE(EXCLUDED.close_date, lots.close_date),
      opening    = EXCLUDED.opening,
      realized   = EXCLUDED.realized,
      currency   = EXCLUDED.currency,
      last_edit  = EXCLUDED.last_edit
    RETURNING lot_pk
  `, [
    firmPk, salePk, lot_no, majgroup, catdescr,
    title, image_url, lot_url, lotCloseDate, opening, realized, currency, lastEdit, primarykey
  ]);

  return r.rows[0].lot_pk;
}

// -------- Real-time single-lot insertion (for scraper integration) --------
/**
 * Insert a single lot to database in real-time mode
 * This function handles auction house, sale, and lot insertion for a single lot
 * @param {Object} lot - Lot data object
 * @param {Object} eventData - Event data containing auctionid, auctionname, auctiontitle, eventdate, contact, saleInfo, extractedSaleName
 * @returns {Promise<Object>} - { success: boolean, lotPk: number|null, error: string|null }
 */
async function insertSingleLot(lot, eventData) {
  const client = await pool.connect();
  let lotPk = null;
  
  try {
    await client.query('BEGIN');
    
    const auctionId = eventData.auctionid || '';
    if (!auctionId) {
      throw new Error('Missing auctionid in eventData');
    }
    
    // 1) Upsert Auction House
    await upsertAuctionHouseFromJsonTx(client, eventData);
    
    // 2) Get firm_pk
    const firmPk = await getFirmPkTx(client, auctionId);
    if (!firmPk) {
      throw new Error(`firm_pk not found for firmId ${auctionId}`);
    }
    
    // 3) Upsert Sale
    const { salePk } = await upsertSaleTx(client, eventData, firmPk);
    
    // 4) Insert Lot
    lotPk = await upsertLotTx(client, lot, eventData, firmPk, salePk);
    
    // 5) Insert category if present
    if (lot.category) {
      await client.query(
        `INSERT INTO categories (name) VALUES ($1)
         ON CONFLICT (name) DO NOTHING`,
        [lot.category.trim()]
      );
    }
    
    await client.query('COMMIT');
    
    return { success: true, lotPk, error: null };
  } catch (err) {
    await client.query('ROLLBACK');
    console.error(`[insertSingleLot Error] ${err.message}`);
    return { success: false, lotPk: null, error: err.message };
  } finally {
    client.release();
  }
}

/**
 * Process lot with embedding in real-time mode
 * This is a wrapper that inserts the lot and optionally creates embedding
 * @param {Object} lot - Lot data object
 * @param {Object} eventData - Event data
 * @param {boolean} createEmbedding - Whether to create embedding (default: true)
 * @returns {Promise<Object>} - Insertion result
 */
async function processLotInRealTime(lot, eventData, createEmbedding = true) {
  const result = await insertSingleLot(lot, eventData);
  
  if (result.success && createEmbedding && result.lotPk) {
    try {
      // Create embedding for the lot
      const saleName = eventData.auctiontitle || '';
      const chunk = buildLotChunk(lot, saleName);
      const embedding = await getEmbedding(chunk);
      const vecLiteral = `[${embedding.join(',')}]`;
      
      await pool.query(
        `INSERT INTO chunks (
          chunk_text, 
          embedding, 
          source_type, 
          source_name, 
          source_id,
          chunk_index,
          chunk_size,
          content_type,
          title,
          category,
          embedding_model,
          metadata
        )
        VALUES ($1, $2::vector, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12::jsonb)
        ON CONFLICT (source_type, source_id, chunk_index) DO UPDATE
        SET chunk_text = EXCLUDED.chunk_text,
            embedding = EXCLUDED.embedding,
            title = EXCLUDED.title,
            category = EXCLUDED.category,
            metadata = EXCLUDED.metadata`,
        [
          chunk, 
          vecLiteral, 
          'lot', 
          saleName, 
          String(result.lotPk),
          1,
          chunk.length,
          'auction/lot',
          lot.lotname || '',
          lot.category || '',
          'text-embedding-3-small',
          JSON.stringify({
            lotNumber: lot.lotnumber || null,
            startingPrice: lot.startingprice || null,
            realizedPrice: lot.realizedprice || null,
            lotUrl: lot.loturl || null,
            imageUrl: lot.imagepath || null,
            saleId: eventData.salePk || null
          })
        ]
      );
    } catch (embedErr) {
      console.warn(`[Embedding Error for lot ${lot.lotnumber}]: ${embedErr.message}`);
      // Don't fail the insertion if embedding fails
    }
  }
  
  return result;
}

// Export functions for use in scraper
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    insertSingleLot,
    processLotInRealTime,
    upsertLotTx,
    upsertSaleTx,
    upsertAuctionHouseFromJsonTx,
    getFirmPkTx
  };
}

// -------- Embedding resume helper --------
async function getExistingEmbeddedLotFks(lotPkList) {
  if (!lotPkList.length) return new Set();
  const { rows } = await pool.query(
    'SELECT CAST(source_id AS INTEGER) as lot_fk FROM chunks WHERE source_type = $1 AND source_id = ANY($2)',
    ['lot', lotPkList.map(String)]
  );
  return new Set(rows.map(r => r.lot_fk));
}



async function processFiles() {
  try {
    const files = await fs.readdir(folderPath);
    const jsonFiles = files.filter(f => f.endsWith('.json')).sort();

    for (const file of jsonFiles) {
      const client = await pool.connect();
      let lotPkMap = [];
      let jsonData, lots, saleNameForChunk;
      let salePkForFile = null; // keep sale_pk available for embedding metadata

      try {
        await client.query('BEGIN');

        const fullPath = path.join(folderPath, file);
        const relativePath = path.relative(__dirname, fullPath).replace(/\\/g, '/');

        // ✅ Skip if already processed
        const done = await fileAlreadyProcessedTx(client, file);
        if (done) {
          await client.query('ROLLBACK');
          console.log(`↩️ Skipping ${file} (already Completed).`);
          continue;
        }

        const fileData = await fs.readFile(fullPath, 'utf8');
        jsonData = JSON.parse(fileData);

        // Normalize uppercase keys to lowercase (handle both formats)
        if (!Array.isArray(jsonData) && typeof jsonData === 'object') {
          const normalized = {};
          for (const [key, value] of Object.entries(jsonData)) {
            const lowerKey = key.toLowerCase();
            // Handle nested objects (like CONTACT, SALEINFO)
            if (value && typeof value === 'object' && !Array.isArray(value)) {
              const nestedNormalized = {};
              for (const [nestedKey, nestedValue] of Object.entries(value)) {
                nestedNormalized[nestedKey.toLowerCase()] = nestedValue;
              }
              normalized[lowerKey] = nestedNormalized;
            } 
            // Handle arrays of objects (like LOTS array)
            else if (Array.isArray(value) && value.length > 0 && typeof value[0] === 'object') {
              normalized[lowerKey] = value.map(item => {
                if (item && typeof item === 'object') {
                  const itemNormalized = {};
                  for (const [itemKey, itemValue] of Object.entries(item)) {
                    itemNormalized[itemKey.toLowerCase()] = itemValue;
                  }
                  return itemNormalized;
                }
                return item;
              });
            } else {
              normalized[lowerKey] = value;
            }
          }
          jsonData = normalized;
        }

        // Normalize: support both array-of-lots and wrapped object formats
        if (Array.isArray(jsonData)) {
          const lotsArr = jsonData;
          const first = lotsArr[0] || {};
          jsonData = {
            auctionid: first.auctionid || null,
            auctionname: first.auctionname || '',
            auctiontitle: first.auctiontitle || '',
            eventdate: first.eventdate || '',
            saleInfo: {},
            contact: {},
            lots: lotsArr
          };
          console.log(`Normalized array format: ${lotsArr.length} lots found`);
        }

        // Fallback auctionid from filename if missing
        if (!jsonData.auctionid) {
          const m = file.match(/auction_(\d+)_lots\.json$/i);
          if (m) jsonData.auctionid = m[1];
        }

        const firmId = jsonData.auctionid;
        if (!firmId) throw new Error('Missing auctionid in JSON (cannot upsert Auction House)');
        saleNameForChunk = jsonData.auctiontitle || '';

        // 1) Upsert Auction House
        console.log(`\n=== ${file} :: UPSERT Auction House (${firmId}) ===`);
        await upsertAuctionHouseFromJsonTx(client, jsonData);

        // 2) Get firm_pk
        const firmPk = await getFirmPkTx(client, firmId);
        if (!firmPk) throw new Error(`firm_pk not found for firmId ${firmId}`);

        // 3) Upsert Sale
        console.log(`=== ${file} :: UPSERT Sale ===`);
        const { salePk } = await upsertSaleTx(client, jsonData, firmPk);
        salePkForFile = salePk;

        // 4) Lots + categories
        console.log(`=== ${file} :: UPSERT Lots (Phase A) ===`);
        lots = Array.isArray(jsonData.lots) ? jsonData.lots : [];
        const catSet = new Set();

        console.log(`Processing ${lots.length} lots...`);
        
        if (lots.length === 0) {
          console.log(`⚠️ No lots found in ${file}`);
        }

        for (const lot of lots) {
          if (lot.category) catSet.add(lot.category.trim().toLowerCase());

          const lotPk = await upsertLotTx(client, lot, jsonData, firmPk, salePk);
          lotPkMap.push({ lotPk, lot });

          if (lot.category) {
            await client.query(
              `INSERT INTO categories (name) VALUES ($1)
               ON CONFLICT (name) DO NOTHING`,
              [lot.category.trim()]
            );
          }
        }

        console.log(`Processed ${lotPkMap.length} lots, ${catSet.size} categories`);

        // 5) Update sale categories
        const keywordCategories = Array.from(catSet);
        await client.query(
          `UPDATE sales SET keyword_categories = $1::text[] WHERE sale_pk = $2`,
          [keywordCategories, salePk]
        );

        // 6) Mark core phase done
        await markFileAsProcessedTx(client, file, relativePath, 'CoreCommitted');

        await client.query('COMMIT');
        console.log(`✅ Core DB writes committed for ${file}`);
      } catch (error) {
        try { await client.query('ROLLBACK'); } catch (_) {}
        console.error(`❌ Core phase failed ${file}:`, error.message);
        continue;
      } finally {
        client.release();
      }

      // -------- Phase B: Embeddings --------
      try {
        console.log(`🔎 Embedding phase for ${file}...`);
        const lotPkList = lotPkMap.map(x => x.lotPk);
        const alreadySet = await getExistingEmbeddedLotFks(lotPkList);
        const toEmbed = lotPkMap.filter(({ lotPk }) => !alreadySet.has(lotPk));

        if (alreadySet.size > 0) {
          console.log(`↩️ Skipping ${alreadySet.size} already embedded; processing ${toEmbed.length}.`);
        }
        console.log(`Total lots: ${lotPkMap.length}, Already embedded: ${alreadySet.size}, To embed: ${toEmbed.length}`);

        if (toEmbed.length === 0) {
          console.log(`⚠️ No lots to embed for ${file}`);
        } else {

        for (const { lotPk, lot } of toEmbed) {
          try {
            console.log(`   • Embedding lot ${lot.lotnumber} (pk=${lotPk})`);
            const chunk = buildLotChunk(lot, saleNameForChunk);
            const embedding = await getEmbedding(chunk);
            console.log("embedding:", embedding);
            const vecLiteral = `[${embedding.join(',')}]`;
            console.log("vecLiteral:", vecLiteral);
            
            
            await pool.query(
              `INSERT INTO chunks (
                chunk_text, 
                embedding, 
                source_type, 
                source_name, 
                source_id,
                chunk_index,
                chunk_size,
                content_type,
                title,
                category,
                embedding_model,
                metadata
              )
              VALUES ($1, $2::vector, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12::jsonb)
              ON CONFLICT (source_type, source_id, chunk_index) DO UPDATE
              SET chunk_text = EXCLUDED.chunk_text,
                  embedding = EXCLUDED.embedding,
                  title = EXCLUDED.title,
                  category = EXCLUDED.category,
                  metadata = EXCLUDED.metadata`,
              [
                chunk, 
                vecLiteral, 
                'lot', 
                saleNameForChunk, 
                String(lotPk),
                1,
                chunk.length,
                'auction/lot',
                lot.lotname || '',
                lot.category || '',
                'text-embedding-3-small',
                JSON.stringify({
                  lotNumber: lot.lotnumber || null,
                  startingPrice: lot.startingprice || null,
                  realizedPrice: lot.realizedprice || null,
                  lotUrl: lot.loturl || null,
                  imageUrl: lot.imagepath || null,
                  saleId: salePkForFile || null
                })
              ]
            );
          } catch (e) {
            console.warn(`   ⚠️ Embed skipped (lot ${lot.lotnumber}): ${e.response?.data?.error?.message || e.message}`);
          }
        }
        }
        console.log(`✅ Embedding phase completed for ${file}`);
        await pool.query(
          `UPDATE uploaded_files
           SET status = 'Completed', processed_at = now()
           WHERE file_name = $1`,
          [file]
        );
      } catch (e) {
        console.warn(`⚠️ Embedding phase error for ${file}: ${e.message}`);
        await pool.query(
          `UPDATE uploaded_files
           SET status = 'EmbeddingError', processed_at = now()
           WHERE file_name = $1`,
          [file]
        );
      }
    }

    console.log('\n🎉 All files processed.\n');
  } catch (err) {
    console.error('❌ processFiles error:', err.message);
  }
}

// Only run processFiles() if this script is executed directly (not when required as a module)
// Check if this is the main module (not required by another script)
if (require.main === module) {
  // Start
  processFiles().then(() => {
    console.log('✅ Script finished successfully');
    process.exit(0);
  }).catch(err => {
    console.error('❌ Script failed:', err);
    process.exit(1);
  });
}
