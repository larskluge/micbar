#!/usr/bin/env bash
#
# Creates a stable self-signed code-signing identity for MicBar in a dedicated
# keychain. macOS pins TCC permissions (Automation / Microphone / Accessibility)
# to an app's code signature; ad-hoc signing (`codesign -s -`) mints a new cdhash
# on every build, silently invalidating all granted permissions each `make install`.
# A stable cert gives a cdhash-independent designated requirement, so grants persist.
#
# Run once:  make setup-signing
# Safe to re-run (recreates the keychain + cert).
set -euo pipefail

KC="$HOME/Library/Keychains/micbar-signing.keychain-db"
KC_PW="micbar-local"   # guards only this throwaway keychain (a local self-signed cert)
CN="MicBar Local Signing"

if security find-identity -p codesigning "$KC" 2>/dev/null | grep -q "$CN"; then
  echo "Signing identity '$CN' already present in $KC — nothing to do."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $CN
[v3]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -days 3650 -config "$WORK/cert.conf"
# macOS `security import` only accepts legacy PKCS#12 PBE/MAC algorithms.
openssl pkcs12 -export -out "$WORK/id.p12" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -passout pass:p12pass -name "$CN" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg SHA1

security delete-keychain "$KC" 2>/dev/null || true
security create-keychain -p "$KC_PW" "$KC"
security set-keychain-settings "$KC"                       # no auto-lock timeout
security unlock-keychain -p "$KC_PW" "$KC"
# Append to the user search list, preserving existing keychains.
security list-keychains -d user -s $(security list-keychains -d user | sed 's/"//g') "$KC"
security import "$WORK/id.p12" -k "$KC" -P p12pass -T /usr/bin/codesign -A
# Allow codesign to use the key without a GUI prompt.
security set-key-partition-list -S apple-tool:,apple:,unsigned: -s -k "$KC_PW" "$KC" >/dev/null

echo "Created signing identity:"
security find-identity -p codesigning "$KC" | grep "$CN"
