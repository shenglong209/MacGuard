#!/bin/bash
# setup-certificate.sh - Create a self-signed certificate for MacGuard code signing
#
# This creates a consistent signing identity so that TCC (accessibility permissions)
# persists across app updates. Without a consistent identity, macOS treats each
# update as a new app and requires re-granting accessibility permission.
#
# Usage: ./scripts/setup-certificate.sh
#
# The certificate will be stored in your Keychain and can be exported for CI/CD.

set -e

CERT_NAME="MacGuard Developer"
CERT_EMAIL="macguard@localhost"
KEYCHAIN="login.keychain"

echo "=== MacGuard Certificate Setup ==="
echo ""

# Check if certificate already exists
if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "Certificate '$CERT_NAME' already exists in keychain."
    echo ""
    security find-identity -v -p codesigning | grep "$CERT_NAME"
    echo ""
    read -p "Delete and recreate? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Delete existing certificate
        security delete-certificate -c "$CERT_NAME" "$KEYCHAIN" 2>/dev/null || true
    else
        echo "Keeping existing certificate."
        exit 0
    fi
fi

# Create a self-signed certificate for code signing
echo "Creating self-signed certificate: $CERT_NAME"

# Create certificate request config
TEMP_DIR=$(mktemp -d)
CSR_CONFIG="$TEMP_DIR/csr.conf"
cat > "$CSR_CONFIG" << EOF
[req]
distinguished_name = req_distinguished_name
prompt = no
[req_distinguished_name]
CN = $CERT_NAME
emailAddress = $CERT_EMAIL
EOF

# Generate key and certificate
openssl genrsa -out "$TEMP_DIR/key.pem" 2048 2>/dev/null
openssl req -new -key "$TEMP_DIR/key.pem" -out "$TEMP_DIR/csr.pem" -config "$CSR_CONFIG" 2>/dev/null

# Create self-signed certificate with code signing extension
CERT_CONFIG="$TEMP_DIR/cert.conf"
cat > "$CERT_CONFIG" << EOF
[v3_req]
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = CA:FALSE
EOF

openssl x509 -req -days 3650 -in "$TEMP_DIR/csr.pem" -signkey "$TEMP_DIR/key.pem" \
    -out "$TEMP_DIR/cert.pem" -extfile "$CERT_CONFIG" -extensions v3_req 2>/dev/null

# Create PKCS12 bundle (use legacy format for macOS compatibility)
P12_PASSWORD="macguard"
openssl pkcs12 -export -out "$TEMP_DIR/cert.p12" \
    -inkey "$TEMP_DIR/key.pem" -in "$TEMP_DIR/cert.pem" \
    -name "$CERT_NAME" -passout pass:$P12_PASSWORD -legacy

# Import to keychain with trust for code signing
echo "Importing certificate to keychain..."
security import "$TEMP_DIR/cert.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign

# Set certificate to always be trusted for code signing
echo "Setting certificate trust (you may be prompted for password)..."
security add-trusted-cert -d -r trustAsRoot -p codeSign -k "$KEYCHAIN" "$TEMP_DIR/cert.pem" 2>/dev/null || {
    echo ""
    echo "Note: Could not automatically trust certificate. You may need to manually trust it:"
    echo "  1. Open Keychain Access"
    echo "  2. Find '$CERT_NAME' certificate"
    echo "  3. Double-click and set 'Code Signing' to 'Always Trust'"
}

# Export certificate for CI/CD (base64 encoded p12)
EXPORT_PATH="$HOME/.macguard-signing"
mkdir -p "$EXPORT_PATH"
cp "$TEMP_DIR/cert.p12" "$EXPORT_PATH/macguard-signing.p12"
base64 -i "$TEMP_DIR/cert.p12" > "$EXPORT_PATH/macguard-signing.p12.base64"

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
echo "=== Certificate Created Successfully ==="
echo ""
echo "Certificate name: $CERT_NAME"
echo "P12 password: $P12_PASSWORD"
echo "Valid for: 10 years"
echo ""
echo "For local builds, the certificate is now in your keychain."
echo ""
echo "For GitHub Actions CI/CD:"
echo "  1. Copy the base64-encoded certificate:"
echo "     cat ~/.macguard-signing/macguard-signing.p12.base64"
echo ""
echo "  2. Add as GitHub secrets:"
echo "     - SIGNING_CERTIFICATE_P12_BASE64: (the base64 content)"
echo "     - SIGNING_CERTIFICATE_PASSWORD: $P12_PASSWORD"
echo ""
echo "Verify certificate is available:"
security find-identity -v -p codesigning | grep "$CERT_NAME"
