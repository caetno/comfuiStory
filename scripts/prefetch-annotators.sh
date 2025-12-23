#!/usr/bin/env bash
set -euo pipefail

MANIFEST="${1:-}"
if [[ -z "$MANIFEST" || ! -f "$MANIFEST" ]]; then
  echo "Usage: prefetch-annotators.sh <manifest-file>" >&2
  exit 64
fi

# Where comfyui_controlnet_aux expects to find annotator weights by default
BASE_DIR="${CNAUX_CKPTS_DIR:-/comfyui/custom_nodes/comfyui_controlnet_aux/ckpts}"

mkdir -p "$BASE_DIR"

download_one() {
  local url="$1"
  local rel="$2"
  local out="${BASE_DIR}/${rel}"

  mkdir -p "$(dirname "$out")"

  if [[ -s "$out" ]]; then
    echo "OK (exists): $rel"
    return 0
  fi

  echo "GET: $url -> $rel"
  # curl is usually more robust than wget for redirects; -f fails on HTTP errors
  curl -fL --retry 5 --retry-delay 2 --connect-timeout 20 -o "$out".tmp "$url"
  mv "$out".tmp "$out"
}

# Read: URL<TAB>REL_DEST, ignore blanks and comments
while IFS=$'\t' read -r url rel; do
  [[ -z "${url// /}" ]] && continue
  [[ "${url:0:1}" == "#" ]] && continue
  if [[ -z "${rel:-}" ]]; then
    echo "Invalid manifest line (missing destination): $url" >&2
    exit 65
  fi
  download_one "$url" "$rel"
done < "$MANIFEST"

echo "Annotator prefetch complete. Base dir: $BASE_DIR"
