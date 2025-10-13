#!/usr/bin/env node

/**
 * Supabase Key Generator
 *
 * This script generates all required keys for Supabase configuration.
 * Run with: node generate-keys.js
 */

const crypto = require('crypto');
const jwt = require('jsonwebtoken');

console.log('\n🔐 Supabase Key Generator\n');
console.log('Generating secure keys for your Supabase deployment...\n');

// 1. Generate JWT Secret
const jwtSecret = crypto.randomBytes(32).toString('base64');
console.log('✅ JWT Secret generated');
console.log(`SUPABASE_JWT_SECRET=${jwtSecret}\n`);

// 2. Generate Database Password
const dbPassword = crypto.randomBytes(24).toString('base64');
console.log('✅ Database Password generated');
console.log(`POSTGRES_PASSWORD=${dbPassword}`);
console.log(`SUPABASE_DB_PASSWORD=${dbPassword}\n`);

// 3. Generate Anonymous Key
const anonKey = jwt.sign(
  {
    role: 'anon',
    iss: 'supabase',
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + (10 * 365 * 24 * 60 * 60) // 10 years
  },
  jwtSecret
);
console.log('✅ Anonymous Key generated (public API access with RLS)');
console.log(`SUPABASE_ANON_KEY=${anonKey}`);
console.log(`PUBLIC_ANON_KEY=${anonKey}\n`);

// 4. Generate Service Role Key
const serviceRoleKey = jwt.sign(
  {
    role: 'service_role',
    iss: 'supabase',
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + (10 * 365 * 24 * 60 * 60) // 10 years
  },
  jwtSecret
);
console.log('✅ Service Role Key generated (bypasses RLS - keep secure!)');
console.log(`SUPABASE_SERVICE_ROLE_KEY=${serviceRoleKey}\n`);

console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
console.log('📋 Complete .env Configuration:');
console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

const envContent = `# Security Keys (Generated: ${new Date().toISOString()})
SUPABASE_JWT_SECRET=${jwtSecret}
SUPABASE_ANON_KEY=${anonKey}
SUPABASE_SERVICE_ROLE_KEY=${serviceRoleKey}
PUBLIC_ANON_KEY=${anonKey}

# Database
POSTGRES_PASSWORD=${dbPassword}
SUPABASE_DB_PASSWORD=${dbPassword}
`;

console.log(envContent);
console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
console.log('💡 Next Steps:');
console.log('1. Copy the configuration above');
console.log('2. Paste into your .env file');
console.log('3. Add remaining configuration (S3, APIs, etc.)');
console.log('4. Run: docker-compose up -d\n');

console.log('⚠️  Security Reminders:');
console.log('• Never commit .env to version control');
console.log('• Use different keys for development and production');
console.log('• Keep service_role key secure (server-side only)');
console.log('• Rotate keys periodically in production\n');
