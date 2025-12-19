#!/bin/bash
# export-certificate.sh - Export Apple Development certificate for GitHub Actions
#
# This exports your Apple Development certificate so that GitHub Actions can sign
# the app with the same identity, preserving accessibility permissions across updates.
#
# Usage: ./scripts/export-certificate.sh

set -e

echo "=== Export Apple Development Certificate ==="
echo ""

# Find Apple Development certificate
IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)"/\1/')

if [ -z "$IDENTITY" ]; then
    echo "❌ No Apple Development certificate found."
    echo "   You can create a self-signed certificate instead:"
    echo "   ./scripts/setup-certificate.sh"
    exit 1
fi

echo "Found certificate: $IDENTITY"
echo ""

# Export path
EXPORT_PATH="$HOME/.macguard-signing"
mkdir -p "$EXPORT_PATH"
P12_FILE="$EXPORT_PATH/apple-dev-cert.p12"

echo "You will be prompted for:"
echo "  1. Your keychain password (to access the certificate)"
echo "  2. A new password to protect the exported .p12 file"
echo ""
read -p "Continue? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Exporting certificate..."
security export -k login.keychain-db -t identities -f pkcs12 -o "$P12_FILE" -P ""

# If that fails with empty password, try interactively
if [ ! -f "$P12_FILE" ]; then
    echo "Trying interactive export..."
    security export -k login.keychain-db -t identities -f pkcs12 -o "$P12_FILE"
fi

if [ -f "$P12_FILE" ]; then
    # Base64 encode for GitHub secrets
    base64 -i "$P12_FILE" > "$P12_FILE.base64"

    echo ""
    echo "=== Certificate Exported Successfully ==="
    echo ""
    echo "Files created:"
    echo "  $P12_FILE"
    echo "  $P12_FILE.base64"
    echo ""
    echo "Add these GitHub secrets:"
    echo ""
    echo "  SIGNING_CERTIFICATE_P12_BASE64:"
    echo "    cat $P12_FILE.base64 | pbcopy"
    echo "    (This copies the content to clipboard)"
    echo ""
    echo "  SIGNING_CERTIFICATE_PASSWORD:"
    echo "    The password you set for the .p12 file"
    echo ""
    echo "Go to: https://github.com/shenglong209/MacGuard/settings/secrets/actions"
else
    echo "❌ Export failed. Try exporting manually from Keychain Access:"
    echo "   1. Open Keychain Access"
    echo "   2. Find '$IDENTITY' certificate"
    echo "   3. Right-click > Export '$IDENTITY'..."
    echo "   4. Save as .p12 file with a password"
    echo "   5. Base64 encode: base64 -i cert.p12 > cert.p12.base64"
fi
