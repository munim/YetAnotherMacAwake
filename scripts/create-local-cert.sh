#!/bin/bash
# Create a persistent self-signed codesigning identity so Accessibility survives rebuilds.
# Usage: ./scripts/create-local-cert.sh
set -euo pipefail
NAME="YetAnotherMacAwake Local"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if security find-certificate -c "$NAME" -a 2>/dev/null | grep -q "BEGIN CERTIFICATE"; then
    echo "Already exists: $NAME"
    security find-certificate -a -c "$NAME" 2>&1 | head -5
    exit 0
fi
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cat > "$TMPDIR/openssl.cnf" <<EOF
[req]
distinguished_name=dn
x509_extensions=v3
prompt=no
default_bits=2048
[dn]
CN=$NAME
[v3]
basicConstraints=CA:TRUE
keyUsage=critical,digitalSignature,keyCertSign,cRLSign
extendedKeyUsage=codeSigning
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer
EOF
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$TMPDIR/key.pem" -out "$TMPDIR/cert.pem" -config "$TMPDIR/openssl.cnf" -extensions v3 2>/dev/null
openssl pkcs12 -export -out "$TMPDIR/cert.p12" -inkey "$TMPDIR/key.pem" -in "$TMPDIR/cert.pem" -passout pass:test123 -name "$NAME" 2>/dev/null
security import "$TMPDIR/cert.p12" -k "$KEYCHAIN" -P test123 -T /usr/bin/codesign -T /usr/bin/security 2>&1 | grep -v "already exists" || true
echo "Created identity: $NAME"
security find-certificate -a -c "$NAME" 2>&1 | head -5
echo "Next: ./build.sh will auto-use it. Re-grant Accessibility once after the next build."
