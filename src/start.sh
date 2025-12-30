#!/usr/bin/env bash

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# Ensure ComfyUI-Manager runs in offline network mode inside the container
comfy-manager-set-mode offline || echo "worker-comfyui - Could not set ComfyUI-Manager network_mode" >&2

# ---------------------------
# SYMLINK OUTPUTS TO VOLUME
# ---------------------------
# If your actual mount point is /workspace instead of /runpod-volume, change VOLUME_ROOT accordingly.
VOLUME_ROOT="/runpod-volume"

# Optional: fail fast if volume isn't mounted or isn't writable
if ! mountpoint -q "$VOLUME_ROOT" 2>/dev/null; then
  echo "worker-comfyui - WARNING: $VOLUME_ROOT does not appear to be a mountpoint (network volume may not be attached)."
  # If you want to hard-fail instead of falling back to ephemeral disk, uncomment:
  # exit 1
fi

mkdir -p "${VOLUME_ROOT}/output" "${VOLUME_ROOT}/temp" "${VOLUME_ROOT}/input"

# Replace ComfyUI dirs with symlinks to the volume
rm -rf /comfyui/output /comfyui/temp /comfyui/input
ln -s "${VOLUME_ROOT}/output" /comfyui/output
ln -s "${VOLUME_ROOT}/temp"   /comfyui/temp
ln -s "${VOLUME_ROOT}/input"  /comfyui/input

echo "worker-comfyui - Output/temp/input redirected to ${VOLUME_ROOT}"
# ---------------------------

echo "worker-comfyui: Starting ComfyUI"

# Allow operators to tweak verbosity; default is DEBUG.
: "${COMFY_LOG_LEVEL:=DEBUG}"

# Serve the API and don't shutdown the container
if [ "$SERVE_API_LOCALLY" == "true" ]; then
    python -u /comfyui/main.py --disable-auto-launch --disable-metadata --listen --verbose "${COMFY_LOG_LEVEL}" --log-stdout --disable-async-offload --disable-pinned-memory --highvram&

    echo "worker-comfyui: Starting RunPod Handler"
    python -u /handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
    python -u /comfyui/main.py --disable-auto-launch --disable-metadata --verbose "${COMFY_LOG_LEVEL}" --log-stdout &

    echo "worker-comfyui: Starting RunPod Handler"
    python -u /handler.py
fi
