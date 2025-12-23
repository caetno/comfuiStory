#!/usr/bin/env bash
# comfy-manager-set-mode: Set ComfyUI-Manager network_mode in config.ini (new + legacy paths).
# Usage: comfy-manager-set-mode <public|private|offline>
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: comfy-manager-set-mode <public|private|offline>" >&2
  exit 64
fi

MODE="$1"
if [[ "$MODE" != "public" && "$MODE" != "private" && "$MODE" != "offline" ]]; then
  echo "Invalid mode: $MODE. Must be public, private, or offline." >&2
  exit 64
fi

# Candidate config paths (new + legacy). If COMFYUI_MANAGER_CONFIG is set, update it too.
declare -a CANDIDATES=(
  "/comfyui/user/__manager/config.ini"
  "/comfyui/user/default/ComfyUI-Manager/config.ini"
)

if [[ -n "${COMFYUI_MANAGER_CONFIG:-}" ]]; then
  CANDIDATES=("${COMFYUI_MANAGER_CONFIG}" "${CANDIDATES[@]}")
fi

# De-duplicate paths (preserve order)
declare -A SEEN=()
declare -a CFG_FILES=()
for p in "${CANDIDATES[@]}"; do
  [[ -z "$p" ]] && continue
  if [[ -z "${SEEN[$p]+x}" ]]; then
    SEEN["$p"]=1
    CFG_FILES+=("$p")
  fi
done

set_mode_in_file() {
  local cfg="$1"
  mkdir -p "$(dirname "$cfg")"

  if [[ -f "$cfg" ]]; then
    # Ensure [default] exists
    if ! grep -q "^\[default\]" "$cfg"; then
      printf "\n[default]\n" >> "$cfg"
    fi

    if grep -qE "^[[:space:]]*network_mode[[:space:]]*=" "$cfg"; then
      # Replace existing network_mode line (keep simple and robust)
      sed -i -E "s|^[[:space:]]*network_mode[[:space:]]*=.*|network_mode = ${MODE}|g" "$cfg"
    else
      # Append under [default] (best-effort: append at end)
      printf "network_mode = %s\n" "$MODE" >> "$cfg"
    fi
  else
    # Create new file
    printf "[default]\nnetwork_mode = %s\n" "$MODE" > "$cfg"
  fi
}

UPDATED=()
for cfg in "${CFG_FILES[@]}"; do
  set_mode_in_file "$cfg"
  UPDATED+=("$cfg")
done

echo "worker-comfyui - ComfyUI-Manager network_mode set to '$MODE' in:"
for u in "${UPDATED[@]}"; do
  echo "  - $u"
done
