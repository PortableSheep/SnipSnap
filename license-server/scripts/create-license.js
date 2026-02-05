// Create a license locally for testing
// Run with: npm run create-license -- email@example.com

import { sign, createPrivateKey } from 'crypto';
import { readFileSync, existsSync } from 'fs';
import { config } from 'dotenv';

config(); // Load .env

const email = process.argv[2];
if (!email) {
  console.error('Usage: npm run create-license -- email@example.com');
  process.exit(1);
}

const signingKey = process.env.SIGNING_KEY;
if (!signingKey) {
  console.error('Missing SIGNING_KEY in .env - run npm run generate-keys first');
  process.exit(1);
}

const signingKeyId = process.env.SIGNING_KEY_ID || 'v1';

// Build payload with key ID for rotation support
const payload = {
  kid: signingKeyId,
  product: 'snipsnap-pro',
  email: email,
  issuedAt: Math.floor(Date.now() / 1000),
  features: ['all']
};

const payloadJson = JSON.stringify(payload);
const payloadBytes = Buffer.from(payloadJson, 'utf-8');

// Sign with Ed25519
const privKeyRaw = Buffer.from(signingKey, 'base64');
const privateKey = createPrivateKey({
  key: Buffer.concat([
    // PKCS8 header for Ed25519
    Buffer.from('302e020100300506032b657004220420', 'hex'),
    privKeyRaw
  ]),
  format: 'der',
  type: 'pkcs8'
});

const signature = sign(null, payloadBytes, privateKey);

// Base64url encode
const payloadB64 = payloadBytes.toString('base64url');
const sigB64 = signature.toString('base64url');

const token = `${payloadB64}.${sigB64}`;

console.log('\n=== LICENSE TOKEN ===\n');
console.log(token);
console.log('\n=== PAYLOAD ===\n');
console.log(JSON.stringify(payload, null, 2));
console.log('\nActivate in SnipSnap with this token.\n');
