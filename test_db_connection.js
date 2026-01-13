/**
 * PostgreSQL Connection Test Script
 * Tests database connection using .env variables
 * 
 * Usage: node test_db_connection.js
 * 
 * Required .env variables:
 *   DATABASE_URL=postgresql://user:password@host:port/database
 *   OR individual variables:
 *   DB_HOST=localhost
 *   DB_PORT=5432
 *   DB_NAME=ragdb
 *   DB_USER=postgres
 *   DB_PASSWORD=password
 */

const path = require('path');
const pg = require('pg');
const Pool = pg.Pool;

// Load .env file
try {
  require('dotenv').config({ path: path.join(__dirname, '.env') });
  console.log('✓ .env file loaded\n');
} catch (err) {
  console.warn('⚠ Warning: Could not load .env file:', err.message);
  console.log('   Continuing with system environment variables...\n');
}

// Get connection configuration
function getConnectionConfig() {
  // Try DATABASE_URL first (full connection string)
  if (process.env.DATABASE_URL) {
    console.log('📋 Using DATABASE_URL from .env');
    return {
      connectionString: process.env.DATABASE_URL,
      ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false
    };
  }

  // Fall back to individual connection parameters
  const config = {
    host: process.env.DB_HOST || process.env.PGHOST || 'localhost',
    port: parseInt(process.env.DB_PORT || process.env.PGPORT || '5432', 10),
    database: process.env.DB_NAME || process.env.PGDATABASE || 'ragdb',
    user: process.env.DB_USER || process.env.PGUSER || 'postgres',
    password: process.env.DB_PASSWORD || process.env.PGPASSWORD || '',
    ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false
  };

  console.log('📋 Using individual connection parameters:');
  console.log(`   Host: ${config.host}`);
  console.log(`   Port: ${config.port}`);
  console.log(`   Database: ${config.database}`);
  console.log(`   User: ${config.user}`);
  console.log(`   Password: ${config.password ? '***' : '(not set)'}`);
  console.log(`   SSL: ${config.ssl ? 'enabled' : 'disabled'}\n`);

  return config;
}

// Test connection
async function testConnection() {
  console.log('🔌 Testing PostgreSQL Connection...\n');
  
  const config = getConnectionConfig();
  const pool = new Pool(config);

  // Set up error handler
  pool.on('error', (err) => {
    console.error('❌ Pool error:', err.message);
  });

  let client;
  try {
    // Test 1: Acquire connection
    console.log('1️⃣ Acquiring database connection...');
    client = await pool.connect();
    console.log('   ✓ Connection acquired successfully\n');

    // Test 2: Check PostgreSQL version
    console.log('2️⃣ Checking PostgreSQL version...');
    const versionResult = await client.query('SELECT version()');
    const version = versionResult.rows[0].version;
    console.log(`   ✓ PostgreSQL version: ${version.split(',')[0]}\n`);

    // Test 3: Check current database
    console.log('3️⃣ Checking current database...');
    const dbResult = await client.query('SELECT current_database(), current_user');
    console.log(`   ✓ Current database: ${dbResult.rows[0].current_database}`);
    console.log(`   ✓ Current user: ${dbResult.rows[0].current_user}\n`);

    // Test 4: Check pgvector extension
    console.log('4️⃣ Checking pgvector extension...');
    try {
      const vectorResult = await client.query(`
        SELECT EXISTS(
          SELECT 1 FROM pg_extension WHERE extname = 'vector'
        ) as has_vector
      `);
      if (vectorResult.rows[0].has_vector) {
        console.log('   ✓ pgvector extension is installed\n');
      } else {
        console.log('   ⚠ pgvector extension is NOT installed\n');
      }
    } catch (err) {
      console.log(`   ⚠ Could not check pgvector: ${err.message}\n`);
    }

    // Test 5: Check for key tables
    console.log('5️⃣ Checking for key tables...');
    const tablesResult = await client.query(`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public' 
      AND table_name IN ('chunks', 'lots', 'lot_chunks', 'categories')
      ORDER BY table_name
    `);
    
    if (tablesResult.rows.length > 0) {
      console.log('   ✓ Found tables:');
      tablesResult.rows.forEach(row => {
        console.log(`      - ${row.table_name}`);
      });
    } else {
      console.log('   ⚠ No expected tables found');
    }
    console.log('');

    // Test 6: Test a simple query on chunks table (if exists)
    console.log('6️⃣ Testing query on chunks table...');
    try {
      const countResult = await client.query('SELECT COUNT(*) as count FROM chunks');
      console.log(`   ✓ Chunks table accessible: ${countResult.rows[0].count} rows\n`);
    } catch (err) {
      if (err.code === '42P01') {
        console.log('   ⚠ Chunks table does not exist\n');
      } else {
        console.log(`   ⚠ Error querying chunks: ${err.message}\n`);
      }
    }

    // Test 7: Test vector operations (if pgvector is available)
    console.log('7️⃣ Testing vector operations...');
    try {
      const vectorTest = await client.query(`
        SELECT 
          COUNT(*) as total_chunks,
          COUNT(embedding) as chunks_with_embeddings
        FROM chunks
        WHERE embedding IS NOT NULL
      `);
      if (vectorTest.rows.length > 0) {
        console.log(`   ✓ Vector operations working:`);
        console.log(`      - Total chunks: ${vectorTest.rows[0].total_chunks || 0}`);
        console.log(`      - Chunks with embeddings: ${vectorTest.rows[0].chunks_with_embeddings || 0}\n`);
      }
    } catch (err) {
      console.log(`   ⚠ Could not test vector operations: ${err.message}\n`);
    }

    console.log('✅ All connection tests passed!\n');
    return true;

  } catch (err) {
    console.error('\n❌ Connection test failed!\n');
    console.error('Error details:');
    console.error(`   Code: ${err.code || 'N/A'}`);
    console.error(`   Message: ${err.message}`);
    
    if (err.code === 'ECONNREFUSED') {
      console.error('\n💡 Troubleshooting:');
      console.error('   - Check if PostgreSQL server is running');
      console.error('   - Verify host and port in .env file');
      console.error('   - Check firewall settings');
    } else if (err.code === '28P01') {
      console.error('\n💡 Troubleshooting:');
      console.error('   - Check username and password in .env file');
      console.error('   - Verify user has access to the database');
    } else if (err.code === '3D000') {
      console.error('\n💡 Troubleshooting:');
      console.error('   - Database does not exist');
      console.error('   - Check DB_NAME in .env file');
      console.error('   - Create the database if needed');
    }
    
    return false;
  } finally {
    if (client) {
      client.release();
      console.log('🔌 Connection released');
    }
    await pool.end();
    console.log('🔌 Pool closed\n');
  }
}

// Run the test
(async () => {
  console.log('═══════════════════════════════════════════════════════════');
  console.log('  PostgreSQL Connection Test');
  console.log('═══════════════════════════════════════════════════════════\n');
  
  const success = await testConnection();
  
  if (success) {
    console.log('🎉 Connection test completed successfully!');
    process.exit(0);
  } else {
    console.log('💥 Connection test failed. Please check the errors above.');
    process.exit(1);
  }
})();

