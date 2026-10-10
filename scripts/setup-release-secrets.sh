#!/bin/zsh
# Puts the release signing + notarization credentials into the GitHub repository secrets used by
# .github/workflows/release.yml. Re-run it to rotate the certificate or the API key.
#
#   scripts/setup-release-secrets.sh <issuer-id> <path/to/AuthKey_KEYID.p8> [repo]
#
# - Exports ONLY the "Developer ID Application" identity from the login keychain (macOS asks to allow
#   the export), repacks it with a random password and verifies it imports into a throwaway keychain.
# - Validates the App Store Connect API key against the notary service (read-only history call).
# - Uploads MACOS_CERT_P12, MACOS_CERT_PASSWORD, NOTARY_KEY_P8, NOTARY_KEY_ID, NOTARY_ISSUER.
# Secret values are never printed; temp files live in a 0700 dir and are shredded on exit.
set -euo pipefail
ISSUER=${1:?usage: setup-release-secrets.sh <issuer-id> <AuthKey_KEYID.p8> [repo]}
P8=${2:?path to AuthKey_KEYID.p8 required}
REPO=${3:-waldo1001/waldo.Claunes}
OPENSSL=/usr/bin/openssl   # LibreSSL: writes 3DES/SHA1 PKCS#12, which `security import` reliably reads

[[ -f $P8 ]] || { echo "no such file: $P8"; exit 1; }
KEY_ID=${${P8:t:r}#AuthKey_}
[[ $KEY_ID =~ '^[A-Z0-9]{10}$' ]] || { echo "cannot read key id from file name ${P8:t}"; exit 1; }
[[ $ISSUER =~ '^[0-9a-fA-F-]{36}$' ]] || { echo "issuer id must be a UUID"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh is not logged in"; exit 1; }

IDENTITY=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')
[[ -n $IDENTITY ]] || { echo "no Developer ID Application identity in the keychain"; exit 1; }
echo "==> identity: $IDENTITY"
echo "==> API key:  $KEY_ID"

TMP=$(mktemp -d); chmod 700 "$TMP"
TMPKC="$TMP/verify.keychain-db"
cleanup() {
  security delete-keychain "$TMPKC" 2>/dev/null || true
  find "$TMP" -type f -exec rm -P {} + 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "==> validate API key with the notary service"
xcrun notarytool history --key "$P8" --key-id "$KEY_ID" --issuer "$ISSUER" >/dev/null \
  || { echo "notarytool rejected the API key (wrong issuer id, revoked key, or another team?)"; exit 1; }

echo "==> export identities from the login keychain (approve the macOS prompt)"
EXPORT_PASS=$(uuidgen)
security export -k login.keychain-db -t identities -f pkcs12 -P "$EXPORT_PASS" -o "$TMP/all.p12" >/dev/null

# Split everything out, then keep only the Developer ID certificate and the key that matches it.
$OPENSSL pkcs12 -in "$TMP/all.p12" -passin "pass:$EXPORT_PASS" -nokeys -out "$TMP/certs.pem" 2>/dev/null
$OPENSSL pkcs12 -in "$TMP/all.p12" -passin "pass:$EXPORT_PASS" -nocerts -nodes -out "$TMP/keys.pem" 2>/dev/null
awk -v d="$TMP" '/-----BEGIN CERTIFICATE-----/{n++; f=d"/cert"n".pem"} f{print > f} /-----END CERTIFICATE-----/{f=""}' "$TMP/certs.pem"
awk -v d="$TMP" '/-----BEGIN .*PRIVATE KEY-----/{n++; f=d"/key"n".pem"} f{print > f} /-----END .*PRIVATE KEY-----/{f=""}' "$TMP/keys.pem"

CERT=""
for c in "$TMP"/cert*.pem(N); do
  if $OPENSSL x509 -in "$c" -noout -subject | grep -q "Developer ID Application"; then CERT=$c; break; fi
done
[[ -n $CERT ]] || { echo "Developer ID certificate not found in the export"; exit 1; }
CERT_PUB=$($OPENSSL x509 -in "$CERT" -noout -pubkey)
KEY=""
for k in "$TMP"/key*.pem(N); do
  if [[ $($OPENSSL pkey -in "$k" -pubout 2>/dev/null) == "$CERT_PUB" ]]; then KEY=$k; break; fi
done
[[ -n $KEY ]] || { echo "private key for the Developer ID certificate not found (exported without key?)"; exit 1; }

P12_PASS=$(uuidgen)
$OPENSSL pkcs12 -export -in "$CERT" -inkey "$KEY" -name "$IDENTITY" -passout "pass:$P12_PASS" -out "$TMP/devid.p12"

echo "==> verify the p12 imports like CI does"
security create-keychain -p x "$TMPKC" >/dev/null
security import "$TMP/devid.p12" -k "$TMPKC" -P "$P12_PASS" -f pkcs12 >/dev/null
COUNT=$(security find-identity -v -p codesigning "$TMPKC" | grep -c '"Developer ID Application:' || true)
[[ $COUNT == 1 ]] || { echo "verification failed: $COUNT Developer ID identities in the p12"; exit 1; }
security delete-keychain "$TMPKC"

echo "==> upload secrets to $REPO"
base64 -i "$TMP/devid.p12" | gh secret set MACOS_CERT_P12 -R "$REPO"
print -rn -- "$P12_PASS"     | gh secret set MACOS_CERT_PASSWORD -R "$REPO"
base64 -i "$P8"              | gh secret set NOTARY_KEY_P8 -R "$REPO"
print -rn -- "$KEY_ID"       | gh secret set NOTARY_KEY_ID -R "$REPO"
print -rn -- "$ISSUER"       | gh secret set NOTARY_ISSUER -R "$REPO"

echo "==> done"
gh secret list -R "$REPO"
