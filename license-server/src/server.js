// Express server for license generation
// Deploy to Railway or any Node.js host

import 'dotenv/config';
import express from 'express';
import { sign, createPrivateKey } from 'crypto';

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3000;
const SIGNING_KEY = process.env.SIGNING_KEY;
const ADMIN_SECRET = process.env.ADMIN_SECRET;

// Health check
app.get('/health', (req, res) => {
  res.send('ok');
});

// Create license endpoint
app.post('/api/create-license', (req, res) => {
  // Verify admin secret
  const authHeader = req.headers.authorization;
  if (!authHeader || authHeader !== `Bearer ${ADMIN_SECRET}`) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!SIGNING_KEY) {
    return res.status(500).json({ error: 'SIGNING_KEY not configured' });
  }

  const { email, features } = req.body;
  if (!email) {
    return res.status(400).json({ error: 'Missing email' });
  }

  try {
    // Build payload
    const payload = {
      product: 'snipsnap-pro',
      email: email,
      issuedAt: Math.floor(Date.now() / 1000),
      features: features || ['all']
    };

    const payloadJson = JSON.stringify(payload);
    const payloadBytes = Buffer.from(payloadJson, 'utf-8');

    // Sign with Ed25519
    const privKeyRaw = Buffer.from(SIGNING_KEY, 'base64');
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

    res.json({
      token,
      payload,
      activationUrl: `snipsnap://activate?token=${encodeURIComponent(token)}`
    });
  } catch (error) {
    console.error('License creation failed:', error);
    res.status(500).json({ error: 'Failed to create license' });
  }
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Not found' });
});

app.listen(PORT, () => {
  console.log(`License server running on port ${PORT}`);
  if (!SIGNING_KEY) console.warn('⚠️  SIGNING_KEY not set');
  if (!ADMIN_SECRET) console.warn('⚠️  ADMIN_SECRET not set');
});
