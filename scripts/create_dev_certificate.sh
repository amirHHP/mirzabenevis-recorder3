#!/usr/bin/env bash
set -euo pipefail

CERT_NAME="MirzaBenevisLocalSign"
PASSWORD="mirza"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

echo "=== Generating Self-Signed Code Signing Certificate ==="

# 1. Create OpenSSL config
cat > codesign.cnf <<EOF
[ req ]
default_bits = 2048
default_md = sha256
prompt = no
distinguished_name = dn
x509_extensions = v3_req

[ dn ]
CN = MirzaBenevisLocalSign

[ v3_req ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# 2. Generate private key and certificate
/opt/homebrew/bin/openssl req -x509 -config codesign.cnf -days 3650 -out codesign_cert.pem -keyout codesign_key.pem -newkey rsa:2048 -nodes

# 3. Export to PKCS#12 (.p12)
/opt/homebrew/bin/openssl pkcs12 -export -legacy -in codesign_cert.pem -inkey codesign_key.pem -out codesign_cert.p12 -name "$CERT_NAME" -password pass:"$PASSWORD"

# 4. Import into login keychain
echo "=== Importing into Keychain ==="
security import codesign_cert.p12 -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign

# 5. Clean up temporary files
rm -f codesign.cnf codesign_cert.pem codesign_key.pem codesign_cert.p12

echo "=== Verification ==="
security find-identity -p codesigning -v

echo "✅ Self-signed code signing certificate '$CERT_NAME' created and imported successfully!"
