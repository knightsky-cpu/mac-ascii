#!/usr/bin/env bash
set -euo pipefail

CERT_NAME="${CERT_NAME:-MacAscii Local Code Signing}"
KEYCHAIN="${KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
P12_PASSWORD="${P12_PASSWORD:-macascii-local-signing}"
WORK_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if security find-identity -v -p codesigning | grep -Fq "$CERT_NAME"; then
    echo "Code-signing identity already exists: $CERT_NAME"
    exit 0
fi

OPENSSL_CONFIG="$WORK_DIR/cert.conf"
KEY_PATH="$WORK_DIR/cert.key"
CRT_PATH="$WORK_DIR/cert.crt"
P12_PATH="$WORK_DIR/cert.p12"

cat > "$OPENSSL_CONFIG" <<CONFIG
[ req ]
distinguished_name = dn
x509_extensions = extensions
prompt = no

[ dn ]
CN = $CERT_NAME

[ extensions ]
basicConstraints = critical,CA:true
keyUsage = critical,digitalSignature,keyCertSign
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CONFIG

openssl req \
    -new \
    -newkey rsa:2048 \
    -nodes \
    -x509 \
    -days 3650 \
    -keyout "$KEY_PATH" \
    -out "$CRT_PATH" \
    -config "$OPENSSL_CONFIG" >/dev/null 2>&1

openssl pkcs12 \
    -export \
    -legacy \
    -inkey "$KEY_PATH" \
    -in "$CRT_PATH" \
    -out "$P12_PATH" \
    -name "$CERT_NAME" \
    -passout "pass:$P12_PASSWORD" >/dev/null 2>&1

security import "$P12_PATH" \
    -k "$KEYCHAIN" \
    -P "$P12_PASSWORD" \
    -T /usr/bin/codesign >/dev/null

security add-trusted-cert \
    -d \
    -r trustRoot \
    -p codeSign \
    -k "$KEYCHAIN" \
    "$CRT_PATH" >/dev/null

security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "" \
    "$KEYCHAIN" >/dev/null 2>&1 || true

security find-identity -v -p codesigning
