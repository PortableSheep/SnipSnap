// Generate Ed25519 keypair for license signing
// Run with: npm run generate-keys

import { generateKeyPairSync, randomBytes } from 'crypto';
import { writeFileSync, existsSync } from 'fs';

// Ed25519 is the signing algorithm that matches Swift's Curve25519.Signing
const { publicKey, privateKey } = generateKeyPairSync('ed25519');

const pubRaw = publicKey.export({ type: 'spki', format: 'der' });
const privRaw = privateKey.export({ type: 'pkcs8', format: 'der' });

// Ed25519 SPKI format has a 12-byte header, raw key is 32 bytes at the end
const pubKeyRaw = pubRaw.subarray(-32);
// Ed25519 PKCS8 format has a 16-byte header, raw key is 32 bytes at the end  
const privKeyRaw = privRaw.subarray(-32);

const pubBase64 = pubKeyRaw.toString('base64');
const privBase64 = privKeyRaw.toString('base64');

console.log('\n=== SNIPSNAP LICENSE KEYS ===\n');
console.log('PUBLIC KEY (embed in app - LicenseToken.swift):');
console.log(pubBase64);
console.log('\nPRIVATE KEY (keep secret - use as SIGNING_KEY env var):');
console.log(privBase64);
console.log('\n=== ADMIN SECRET ===\n');
const adminSecret = randomBytes(32).toString('hex');
console.log('ADMIN_SECRET (for API auth):');
console.log(adminSecret);

// Save to .env file (gitignored)
const envContent = `# License server secrets - DO NOT COMMIT
SIGNING_KEY=${privBase64}
SIGNING_KEY_ID=v1
ADMIN_SECRET=${adminSecret}
`;

if (existsSync('.env')) {
  console.log('\n⚠️  .env already exists, not overwriting');
  console.log('   Manually add the keys above if needed');
} else {
  writeFileSync('.env', envContent);
  console.log('\n✓ Saved to .env (add to Railway environment variables for production)');
}

console.log('\n=== NEXT STEPS ===');
console.log('1. Copy PUBLIC KEY to Sources/Licensing/LicenseToken.swift (in publicKeys["v1"])');
console.log('2. Add SIGNING_KEY, SIGNING_KEY_ID, and ADMIN_SECRET to Railway environment variables');
console.log('3. Deploy: railway up (or connect GitHub repo)');
console.log('\n=== KEY ROTATION ===');
console.log('When you need to rotate keys:');
console.log('1. Run generate-keys again to get a new keypair');
console.log('2. Add new public key to LicenseToken.swift as "v2" (keep "v1")');
console.log('3. Ship app update with both keys');
console.log('4. Update SIGNING_KEY and set SIGNING_KEY_ID=v2 on server');
console.log('5. Old licenses (signed with v1) continue to work\n');
