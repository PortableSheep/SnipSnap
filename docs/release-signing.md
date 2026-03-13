# Release Code Signing

macOS ties permissions (Screen Recording, Accessibility, Input Monitoring) to an app's **code signature**. Without a stable signing identity, every update forces users to re-grant all permissions.

SnipSnap release builds are signed with a self-signed certificate stored as a GitHub secret. This gives each release the same identity so macOS TCC preserves permissions across updates.

## One-Time Setup

### 1. Generate the certificate

```bash
./scripts/generate-release-cert.sh
```

This creates:
- `SnipSnap-Release.p12` — the certificate file
- `SnipSnap-Release.p12.b64` — base64-encoded version for GitHub

### 2. Add GitHub secrets

Go to **Settings → Secrets and variables → Actions → New repository secret** and add:

| Secret | Value |
|--------|-------|
| `SIGNING_CERTIFICATE_P12` | Contents of `SnipSnap-Release.p12.b64` |
| `SIGNING_CERTIFICATE_PASSWORD` | Password printed by the script |

### 3. Verify

Push a tag or trigger the release workflow. The build log should show:
```
✅ Signing certificate imported.
```

To verify a built artifact locally:
```bash
codesign -dvv SnipSnap.app
# Should show: Authority=SnipSnap Release
```

## How It Works

The CI workflow (`.github/workflows/release.yml`):

1. Decodes the `.p12` from the `SIGNING_CERTIFICATE_P12` secret
2. Creates a temporary keychain and imports the certificate
3. Builds with `CODE_SIGN_IDENTITY="SnipSnap Release"`
4. Cleans up the keychain after the build

If no certificate secret is configured (e.g., in forks), the build falls back to unsigned — the same behavior as before.

## Impact on Existing Users

After updating to the **first signed release**, users will need to re-grant permissions one final time. After that, permissions persist across all future updates.

## Rotating the Certificate

If the certificate needs to be replaced (expired, compromised):

1. Run `./scripts/generate-release-cert.sh` to create a new one
2. Update both GitHub secrets
3. Users will need to re-grant permissions once after the next update

## Local Development

Local dev builds use the separate `SnipSnap Local Dev` certificate (see main README). The release certificate is only used in CI.
