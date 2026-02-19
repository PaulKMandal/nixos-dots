#!/usr/bin/env bash
set -euo pipefail

require() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing: $1" >&2; exit 1; }; }
require curl
require jq
require awk

LIBREWOLF_DIR="${LIBREWOLF_DIR:-$HOME/.librewolf}"
PROFILES_INI="$LIBREWOLF_DIR/profiles.ini"

if [[ ! -f "$PROFILES_INI" ]]; then
  echo "ERROR: $PROFILES_INI not found. Start LibreWolf once first." >&2
  exit 1
fi

DEFAULT_PROFILE_PATH="$(
  awk '
    /^\[Profile[0-9]+\]$/ { in_prof=1; default=0; path="" }
    in_prof && /^Default=1$/ { default=1 }
    in_prof && /^Path=/ { sub(/^Path=/,""); path=$0 }
    in_prof && default && path!="" { print path; exit }
  ' "$PROFILES_INI"
)"

if [[ -z "${DEFAULT_PROFILE_PATH:-}" ]]; then
  echo "ERROR: Could not find Default=1 profile Path in $PROFILES_INI" >&2
  exit 1
fi

PROFILE_DIR="$LIBREWOLF_DIR/$DEFAULT_PROFILE_PATH"
EXT_DIR="$PROFILE_DIR/extensions"
mkdir -p "$EXT_DIR"

echo "LibreWolf profile: $PROFILE_DIR"
echo "Extensions dir   : $EXT_DIR"
echo
echo "Close LibreWolf before continuing. (Press Enter to continue)"
read -r _

AMO_API_BASE="https://addons.mozilla.org/api/v5/addons/addon"

ADDON_SLUGS=(
  "ublock-origin"
  "leechblock-ng"
  "clearurls"
  "return-youtube-dislikes"
  "darkreader"
  "keepassxc-browser"
  "link-cleaner"
  "remove-youtube-s-suggestions"
  "youtube-shorts-block"
)

fetch_addon_json() {
  local slug="$1"
  curl -fsSL "${AMO_API_BASE}/${slug}/"
}

extract_guid() {
  jq -r '.guid // empty'
}

extract_xpi_url() {
  jq -r '
    .current_version.files
    | map(select(.url | type=="string"))
    | map(select(.url | test("\\.xpi(\\?|$)")))
    | .[0].url // empty
  '
}

for slug in "${ADDON_SLUGS[@]}"; do
  echo "==> $slug"
  json="$(fetch_addon_json "$slug")" || {
    echo "ERROR: Failed to fetch AMO metadata for slug: $slug" >&2
    echo "Check: https://addons.mozilla.org/firefox/addon/$slug/" >&2
    exit 1
  }

  guid="$(printf '%s' "$json" | extract_guid)"
  xpi_url="$(printf '%s' "$json" | extract_xpi_url)"

  if [[ -z "$guid" || -z "$xpi_url" ]]; then
    echo "ERROR: Could not extract guid/xpi URL for slug: $slug" >&2
    echo "GUID: ${guid:-<empty>}" >&2
    echo "XPI : ${xpi_url:-<empty>}" >&2
    exit 1
  fi

  out="$EXT_DIR/${guid}.xpi"
  tmp="$out.part"

  echo "    GUID: $guid"
  echo "    ->  $out"
  curl -fL --retry 3 --retry-delay 1 -o "$tmp" "$xpi_url"
  mv -f "$tmp" "$out"
  echo
done

echo "Done."
echo "Start LibreWolf. Add-ons should appear in about:addons."

