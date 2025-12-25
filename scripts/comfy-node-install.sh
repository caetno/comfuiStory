#!/usr/bin/env bash
# comfy-node-install: install custom ComfyUI nodes into the correct workspace and verify.
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "Usage: comfy-node-install <node1> [<node2> …]" >&2
  exit 64
fi

# REQUIRED: point this at the SAME workspace you used for `comfy install --workspace ...`
: "${COMFY_WORKSPACE:=/comfyui}"

log=$(mktemp)

echo "Using COMFY_WORKSPACE=${COMFY_WORKSPACE}" >&2
comfy --workspace="${COMFY_WORKSPACE}" which 2>&1 | tee -a "$log" || true

# Run installation (capture output). Some versions can return non-zero spuriously.
set +e
comfy --workspace="${COMFY_WORKSPACE}" node install --mode=remote "$@" 2>&1 | tee -a "$log"
cli_status=$?
set -e

# Detect install failures more robustly.
failed_nodes=$(grep -oP "(?<=An error occurred while installing ')[^']+" "$log" | sort -u || true)
if [[ -z "$failed_nodes" ]]; then
  failed_nodes=$(grep -oP "(?<=Node ')[^@']+" "$log" | sort -u || true)
fi

# Also treat obvious tracebacks/errors as failure (even if node name isn't extracted).
if grep -qiE "traceback|exception|ERROR|fatal:" "$log"; then
  if [[ -z "$failed_nodes" ]]; then
    failed_nodes="(unknown - see log)"
  fi
fi

if [[ -n "$failed_nodes" ]]; then
  echo "Comfy node installation failed for:" >&2
  echo "$failed_nodes" | while read -r n; do echo "  • $n" >&2 ; done
  echo >&2
  echo "Full log:" >&2
  sed -n '1,220p' "$log" >&2 || true
  exit 1
fi

if [[ $cli_status -ne 0 ]]; then
  echo "Warning: comfy node install exited with status $cli_status but no errors detected — assuming success." >&2
fi

# Hard verification: ensure IPAdapterAdvanced is actually registered.
# This catches: wrong workspace, node disabled, dependency import failure, etc.
python - <<'PY'
import os, sys, subprocess, re

workspace = os.environ.get("COMFY_WORKSPACE", "/comfyui")
# Ask comfy-cli where the real ComfyUI path is
p = subprocess.run(["comfy", f"--workspace={workspace}", "which"], capture_output=True, text=True)
out = p.stdout + "\n" + p.stderr
m = re.search(r"Target ComfyUI path:\s*(.*)", out)
if not m:
    raise SystemExit("Could not parse 'comfy which' output. Ensure comfy-cli is installed and workspace is valid.\n" + out)

comfy_path = m.group(1).strip()
sys.path.insert(0, comfy_path)

import nodes
ok = "IPAdapterAdvanced" in getattr(nodes, "NODE_CLASS_MAPPINGS", {})
print("ComfyUI path:", comfy_path)
print("IPAdapterAdvanced present:", ok)
if not ok:
    raise SystemExit("IPAdapterAdvanced is NOT registered. Likely wrong workspace or import/dependency error in custom node.")
PY

echo "Custom node installation verified OK." >&2
