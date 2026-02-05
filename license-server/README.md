# SnipSnap License Server

Express server for generating signed license tokens. Deploy to Railway or any Node.js host.

## Setup

```bash
cd license-server
npm install
```

## Generate Keys (one-time)

```bash
npm run generate-keys
```

This outputs:
- **Public key** → add to `Sources/Licensing/LicenseToken.swift`
- **Private key** → saved to `.env`, add to Railway environment variables
- **Admin secret** → saved to `.env`, add to Railway environment variables

## Local Development

```bash
npm run dev
```

Server runs at `http://localhost:3000`

## Local License Generation

```bash
npm run create-license -- user@example.com
```

## Deploy to Railway

1. Create a new project on [railway.app](https://railway.app)
2. Connect your GitHub repo or use `railway up`
3. Add environment variables in Railway dashboard:
   - `SIGNING_KEY` - your private key (from generate-keys)
   - `SIGNING_KEY_ID` - key version, e.g. `v1` (for key rotation)
   - `ADMIN_SECRET` - your admin secret (from generate-keys)
4. Railway auto-detects Node.js and runs `npm start`

Your server will be live at `https://your-project.up.railway.app`

## API Usage

**Create License**

```bash
curl -X POST https://your-project.up.railway.app/api/create-license \
  -H "Authorization: Bearer YOUR_ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com"}'
```

Response:
```json
{
  "token": "eyJwcm9k...signature",
  "payload": {
    "kid": "v1",
    "product": "snipsnap-pro",
    "email": "user@example.com",
    "issuedAt": 1707091200,
    "features": ["all"]
  },
  "activationUrl": "snipsnap://activate?token=..."
}
```

## Security

- Private key stored securely in Railway environment variables
- Admin secret required for all license creation
- Licenses are validated offline in the app (no network calls needed)
- All communication over HTTPS (Railway provides SSL automatically)

## Key Rotation

Tokens include a `kid` (key ID) field that enables key rotation without invalidating existing licenses.

**To rotate keys:**

1. Generate a new keypair:
   ```bash
   npm run generate-keys
   ```

2. Add the new public key to `Sources/Licensing/LicenseToken.swift`:
   ```swift
   private static let publicKeys: [String: String] = [
     "v1": "old-public-key-base64",  // Keep existing key
     "v2": "new-public-key-base64"   // Add new key
   ]
   ```

3. Ship an app update with both keys

4. Update Railway environment variables:
   - `SIGNING_KEY` = new private key
   - `SIGNING_KEY_ID` = `v2`

5. New licenses will use v2, old licenses (v1) continue to work
