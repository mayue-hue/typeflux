#!/usr/bin/env bash
set -euo pipefail

CERT_NAME="Typeflux Dev"
KEYCHAIN_NAME="typeflux-dev.keychain-db"
KEYCHAIN_PATH="$HOME/Library/Keychains/$KEYCHAIN_NAME"
LOGIN_KEYCHAIN_PATH="$HOME/Library/Keychains/login.keychain-db"

normalize_keychain_path() {
  local keychain="$1"
  keychain="$(printf '%s' "$keychain" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')"
  printf '%s' "$keychain"
}

append_keychain_once() {
  local candidate="$1"
  local existing

  if [[ ${keychain_count:-0} -gt 0 ]]; then
    for existing in "${keychains[@]}"; do
      if [[ "$existing" == "$candidate" ]]; then
        return
      fi
    done
  fi

  keychains[$keychain_count]="$candidate"
  keychain_count=$((keychain_count + 1))
}

repair_user_keychain_search_list() {
  local -a keychains
  local keychain_count
  local keychain

  keychains=()
  keychain_count=0

  # Keep the real login keychain first. This also repairs malformed entries
  # caused by older versions of this script passing the whole list as one arg.
  if [[ -f "$LOGIN_KEYCHAIN_PATH" ]]; then
    append_keychain_once "$LOGIN_KEYCHAIN_PATH"
  fi

  while IFS= read -r keychain; do
    keychain="$(normalize_keychain_path "$keychain")"
    [[ -n "$keychain" ]] || continue
    [[ -e "$keychain" ]] || continue
    append_keychain_once "$keychain"
  done < <(security list-keychains -d user 2>/dev/null || true)

  if [[ -f "$KEYCHAIN_PATH" ]]; then
    append_keychain_once "$KEYCHAIN_PATH"
  fi

  if [[ $keychain_count -gt 0 ]]; then
    security list-keychains -d user -s "${keychains[@]}"
  fi

  if [[ -f "$LOGIN_KEYCHAIN_PATH" ]]; then
    security default-keychain -d user -s "$LOGIN_KEYCHAIN_PATH"
  fi
}

# Already set up?
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$CERT_NAME\""; then
  repair_user_keychain_search_list
  echo "Certificate '$CERT_NAME' is already a valid code-signing identity."
  exit 0
fi

echo "Creating self-signed code-signing certificate: $CERT_NAME"

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

openssl req -x509 -newkey rsa:2048 \
  -keyout "$TEMP_DIR/typeflux_dev.key" \
  -out "$TEMP_DIR/typeflux_dev.crt" \
  -days 3650 -nodes \
  -subj "/CN=$CERT_NAME" \
  -addext "keyUsage=critical,digitalSignature,keyCertSign" \
  -addext "extendedKeyUsage=critical,codeSigning"

openssl pkcs12 -export \
  -inkey "$TEMP_DIR/typeflux_dev.key" \
  -in "$TEMP_DIR/typeflux_dev.crt" \
  -out "$TEMP_DIR/typeflux_dev.p12" \
  -passout pass:typeflux

# Create a dedicated project keychain with NO password — no prompts needed.
if [[ ! -f "$KEYCHAIN_PATH" ]]; then
  security create-keychain -p "" "$KEYCHAIN_PATH"
  security set-keychain-settings -t 3600 "$KEYCHAIN_PATH"
fi

security import "$TEMP_DIR/typeflux_dev.p12" \
  -k "$KEYCHAIN_PATH" \
  -f pkcs12 \
  -P typeflux \
  -T /usr/bin/codesign

security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "" "$KEYCHAIN_PATH" 2>/dev/null || true

security add-trusted-cert -d -p codeSign \
  -k "$KEYCHAIN_PATH" \
  "$TEMP_DIR/typeflux_dev.crt"

# Register this keychain in the user search list so codesign and
# security find-identity see the new identity. Preserve valid existing
# keychains as separate arguments; never pass the whole printed list as one
# string, because that corrupts the user's search list on macOS.
repair_user_keychain_search_list

echo ""
echo "Certificate '$CERT_NAME' created and trusted for code signing."
echo "Run 'make run' — no password prompts needed."
echo "Keychain: $KEYCHAIN_PATH"
