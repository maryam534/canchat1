// dbConfig.js
const path = require('path');

// Load .env early. This looks for .env in the SAME folder as this file.
// If your .env is at the project root and this file is in a subfolder,
// change the path to join(__dirname, '..', '.env').
require('dotenv').config({ path: path.join(__dirname, '.env') });

const { Pool } = require('pg');

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  throw new Error('DATABASE_URL is missing. Add it to your .env file.');
}

const pool = new Pool({ connectionString });

// Optional: help catch idle client errors
pool.on('error', (err) => {
  console.error('[pg pool] unexpected error:', err.message);
});

module.exports = pool;
