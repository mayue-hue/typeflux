#!/usr/bin/env bash
set -euo pipefail

DEV_KEYCHAIN_PATH="$HOME/Library/Keychains/typeflux-dev.keychain-db"
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

  if [[ -f "$LOGIN_KEYCHAIN_PATH" ]]; then
    append_keychain_once "$LOGIN_KEYCHAIN_PATH"
  fi

  while IFS= read -r keychain; do
    keychain="$(normalize_keychain_path "$keychain")"
    [[ -n "$keychain" ]] || continue
    [[ -e "$keychain" ]] || continue
    append_keychain_once "$keychain"
  done < <(security list-keychains -d user 2>/dev/null || true)

  if [[ -f "$DEV_KEYCHAIN_PATH" ]]; then
    append_keychain_once "$DEV_KEYCHAIN_PATH"
  fi

  if [[ $keychain_count -gt 0 ]]; then
    security list-keychains -d user -s "${keychains[@]}"
  fi

  if [[ -f "$LOGIN_KEYCHAIN_PATH" ]]; then
    security default-keychain -d user -s "$LOGIN_KEYCHAIN_PATH"
  fi
}

repair_user_keychain_search_list

services=(
  "ai.gulu.app.typeflux.auth"
  "ai.gulu.app.typeflux.auth.v2"
  "ai.gulu.app.typeflux.auth.v1"
  "dev.typeflux.auth"
  "debug.typeflux.auth"
  "debug.typeflux.auth3"
  "com.apple.dt.xctest.tool.auth"
)

accounts=(
  "session"
  "userProfile"
)

for service in "${services[@]}"; do
  for account in "${accounts[@]}"; do
    if security delete-generic-password -s "$service" -a "$account" >/dev/null 2>&1; then
      echo "Deleted Keychain item: service=$service account=$account"
    fi
  done
done

fallback_dir="$HOME/Library/Application Support/Typeflux/AuthStore"
if [[ -d "$fallback_dir" ]]; then
  rm -rf "$fallback_dir"
  echo "Deleted fallback auth store: $fallback_dir"
fi

echo "Typeflux dev auth state reset complete."
