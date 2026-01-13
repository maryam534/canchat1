#!/usr/bin/env node

/**
 * Stamp ChatBot Setup Script
 * Helps configure the application after installation
 */

const fs = require('fs');
const path = require('path');
const readline = require('readline');

const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
});

console.log('🎯 Stamp Auction ChatBot Setup');
console.log('=====================================\n');

async function question(prompt) {
    return new Promise((resolve) => {
        rl.question(prompt, resolve);
    });
}

async function setup() {
    try {
        console.log('This script will help you configure your environment.\n');

        // Check if .env exists
        const envPath = path.join(__dirname, '.env');
        const envExists = fs.existsSync(envPath);

        if (envExists) {
            const overwrite = await question('⚠️  .env file already exists. Overwrite? (y/N): ');
            if (overwrite.toLowerCase() !== 'y') {
                console.log('Setup cancelled. Edit .env manually if needed.');
                rl.close();
                return;
            }
        }

        // Collect configuration
        console.log('\n📝 Configuration Setup:\n');

        const openaiKey = await question('🤖 Enter your OpenAI API Key (sk-...): ');
        if (!openaiKey.startsWith('sk-')) {
            console.log('❌ Invalid OpenAI API key format. Should start with "sk-"');
            rl.close();
            return;
        }

        const dbHost = await question('🗄️  Database Host (localhost): ') || 'localhost';
        const dbPort = await question('🗄️  Database Port (5432): ') || '5432';
        const dbName = await question('🗄️  Database Name (stampchatbot): ') || 'stampchatbot';
        const dbUser = await question('🗄️  Database User (stampchat_user): ') || 'stampchat_user';
        const dbPass = await question('🗄️  Database Password: ');

        const baseUrl = await question('🌐 Base URL (http://localhost): ') || 'http://localhost';
        const processUrl = await question('🌐 Process URL (same as base): ') || baseUrl;

        // Create .env file
        const envContent = `# Stamp ChatBot Configuration
# Generated on ${new Date().toISOString()}

# OpenAI Configuration
OPENAI_API_KEY=${openaiKey}

# Database Configuration  
DATABASE_URL=postgres://${dbUser}:${dbPass}@${dbHost}:${dbPort}/${dbName}

# Web Configuration
BASE_URL=${baseUrl}
PROCESS_URL=${processUrl}

# Optional: Embedding Configuration
EMBED_MODEL=text-embedding-3-small
EMBED_DIM=1536
`;

        fs.writeFileSync(envPath, envContent);

        console.log('\n✅ Configuration saved to .env file');
        console.log('\n🎯 Next Steps:');
        console.log('1. Start your ColdFusion server');
        console.log('2. Visit: http://your-server/stampchatbot/cfml/config_test.cfm');
        console.log('3. Test the chat interface: http://your-server/stampchatbot/index.cfm');
        console.log('4. Access admin dashboard: http://your-server/stampchatbot/cfml/dashboard.cfm');
        console.log('\n📖 See INSTALLATION_GUIDE.md for detailed instructions.');

    } catch (error) {
        console.error('❌ Setup failed:', error.message);
    } finally {
        rl.close();
    }
}

// Check Node.js version
const nodeVersion = process.version;
const majorVersion = parseInt(nodeVersion.slice(1).split('.')[0]);

if (majorVersion < 18) {
    console.log(`❌ Node.js ${nodeVersion} detected. Please upgrade to Node.js 18+ for best compatibility.`);
    process.exit(1);
}

setup();
