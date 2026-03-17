#!/bin/bash
# generate-release-cert.sh — Create a self-signed code signing certificate
# for LOCAL DEVELOPMENT builds.
#
# NOTE: CI release builds now use a real Apple Developer ID certificate.
# See docs/SIGNING.md for the CI/CD signing setup.
#
# This certificate is for local development so that macOS TCC recognises
# rebuilds as the same app and preserves granted permissions (Screen
# Recording, Accessibility, Input Monitoring).
#
# Usage:
#   ./scripts/generate-release-cert.sh [--name "Cert Name"] [--output dir]

set -euo pipefail

CERT_NAME=""
OUTPUT_DIR="."

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      CERT_NAME="$2"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

# Defaults
CERT_NAME="${CERT_NAME:-SnipSnap Release}"
P12_PASSWORD=$(uuidgen | tr -d '-')
P12_FILE="${OUTPUT_DIR}/${CERT_NAME// /-}.p12"
TEMP_KEYCHAIN="snipsnap-cert-gen-$$.keychain-db"
TEMP_KEYCHAIN_PASSWORD=$(uuidgen)

echo "🔐 Generating self-signed code signing certificate: \"${CERT_NAME}\""
echo ""

cleanup() {
  security delete-keychain "$TEMP_KEYCHAIN" 2>/dev/null || true
}
trap cleanup EXIT

# Create a temporary keychain to avoid polluting the user's login keychain
security create-keychain -p "$TEMP_KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"
security set-keychain-settings -lut 3600 "$TEMP_KEYCHAIN"
security unlock-keychain -p "$TEMP_KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"

# Generate the certificate using the Security framework via a signing request.
# We use `certtool` which ships with macOS to create a self-signed cert
# directly in the keychain.

# Create certificate configuration
CERT_CONFIG=$(mktemp)
cat > "$CERT_CONFIG" << EOF
[ req ]
distinguished_name = req_dn
x509_extensions    = codesign
prompt             = no

[ req_dn ]
CN = ${CERT_NAME}

[ codesign ]
keyUsage               = critical, digitalSignature
extendedKeyUsage       = critical, codeSigning
basicConstraints       = critical, CA:false
EOF

# Generate key and self-signed certificate with OpenSSL
TEMP_DIR=$(mktemp -d)
PRIVKEY="${TEMP_DIR}/key.pem"
CERT_PEM="${TEMP_DIR}/cert.pem"

openssl req -x509 -newkey rsa:2048 \
  -keyout "$PRIVKEY" \
  -out "$CERT_PEM" \
  -days 3650 \
  -nodes \
  -config "$CERT_CONFIG" \
  2>/dev/null

# Detect OpenSSL 3.x+ and add -legacy flag so macOS `security import` can read the .p12
LEGACY_FLAG=""
if openssl version 2>/dev/null | grep -q '^OpenSSL 3\.'; then
  LEGACY_FLAG="-legacy"
fi

# Export as .p12
openssl pkcs12 -export \
  -inkey "$PRIVKEY" \
  -in "$CERT_PEM" \
  -out "$P12_FILE" \
  -passout "pass:${P12_PASSWORD}" \
  -name "$CERT_NAME" \
  $LEGACY_FLAG \
  2>/dev/null

# Clean up temp files
rm -rf "$TEMP_DIR" "$CERT_CONFIG"

# Base64-encode the .p12 for GitHub secrets
P12_BASE64=$(base64 < "$P12_FILE")

echo "✅ Certificate created: ${P12_FILE}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Add these as GitHub repository secrets:"
echo "  Settings → Secrets and variables → Actions → New repository secret"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Secret: SIGNING_CERTIFICATE_PASSWORD"
echo "Value:  ${P12_PASSWORD}"
echo ""
echo "Secret: SIGNING_CERTIFICATE_P12"
echo "Value:  (contents of the base64 file below)"
echo ""

# Write base64 to a file for easy copy
B64_FILE="${OUTPUT_DIR}/${CERT_NAME// /-}.p12.b64"
echo -n "$P12_BASE64" > "$B64_FILE"
echo "📄 Base64-encoded .p12 saved to: ${B64_FILE}"
echo "   Copy its contents into the SIGNING_CERTIFICATE_P12 secret."
echo ""
echo "⚠️  Keep these files safe and do NOT commit them to the repository."
echo "   Add to .gitignore: *.p12 *.p12.b64"
echo ""
echo "🔑 To verify the certificate locally:"
echo "   security import \"${P12_FILE}\" -P \"${P12_PASSWORD}\" -T /usr/bin/codesign"
echo "   codesign -s \"${CERT_NAME}\" --force /path/to/SnipSnap.app"
echo "   codesign -dvv /path/to/SnipSnap.app"
