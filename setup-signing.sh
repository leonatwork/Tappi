#!/usr/bin/env bash
# Creates a local code signing identity so that granted permissions survive rebuilds.
#
# macOS ties Accessibility and Screen Recording grants to an app's code signature.
# An ad-hoc signature is identified by the hash of the binary itself, so every
# rebuild produces a new identity and silently invalidates the grants — the
# checkbox stays ticked but no longer applies to the running app.
#
# Signing with a certificate instead anchors the identity to the certificate:
#   ad-hoc      designated => cdhash H"..."              (changes every build)
#   certificate designated => certificate leaf = H"..."  (stable)
#
# The certificate does not need to be trusted by the system — codesign accepts an
# untrusted self-signed identity for local signing, so no admin password is needed.
set -euo pipefail

NAME="${1:-Tappi Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -q "$NAME"; then
  echo "==> identity '$NAME' already exists — nothing to do"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> generating a self-signed code signing certificate"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# Apple's keychain cannot read OpenSSL 3's default PKCS#12 algorithms.
openssl pkcs12 -export -out "$WORK/id.p12" \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -passout pass:tappi -name "$NAME" \
  -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES 2>/dev/null

echo "==> importing into the login keychain"
security import "$WORK/id.p12" -k "$KEYCHAIN" -P tappi -T /usr/bin/codesign -A >/dev/null

echo "==> done. './build.sh --install' will now use it automatically."
echo "    Grant the permissions once more; they will survive every rebuild after that."
