require('dotenv').config();
const { Pool } = require('pg');
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

async function check() {
    try {
        // Check full chunk content for lot 23006
        const lot = await pool.query(`
            SELECT chunk_text, metadata FROM chunks 
            WHERE source_type='lot' AND chunk_text ILIKE '%23006%' LIMIT 1
        `);
        if (lot.rows[0]) {
            console.log('=== CHUNK TEXT ===');
            console.log(lot.rows[0].chunk_text);
            console.log('\n=== METADATA ===');
            console.log(lot.rows[0].metadata);
        }
    } catch (e) {
        console.error(e.message);
    } finally {
        pool.end();
    }
}
check();
