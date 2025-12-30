# syntax=docker/dockerfile:1

ARG BASE_IMAGE=nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04

# =========================
# Stage 1: Builder
# =========================
FROM ${BASE_IMAGE} AS builder

ARG COMFYUI_VERSION=latest
ARG CUDA_VERSION_FOR_COMFY
ARG ENABLE_PYTORCH_UPGRADE=false
ARG PYTORCH_INDEX_URL

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    PYTHONUNBUFFERED=1 \
    CMAKE_BUILD_PARALLEL_LEVEL=8 \
    RUST_LOG=info \
    UV_LOG_LEVEL=info \
    PIP_NO_INPUT=1

# Build deps + tools needed for installing nodes and compiling any extensions
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    git \
    wget \
    curl \
    ca-certificates \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg \
    build-essential \
    pkg-config \
    libgomp1 \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && rm -rf /var/lib/apt/lists/*

# Install uv and create venv
RUN wget -qO- https://astral.sh/uv/install.sh | sh \
    && ln -sf /root/.local/bin/uv /usr/local/bin/uv \
    && ln -sf /root/.local/bin/uvx /usr/local/bin/uvx \
    && uv venv /opt/venv

ENV PATH="/opt/venv/bin:${PATH}" \
    VIRTUAL_ENV="/opt/venv"

# Install comfy-cli and bootstrap tooling
RUN uv pip install --upgrade pip setuptools wheel comfy-cli

# Install ComfyUI
RUN if [ -n "${CUDA_VERSION_FOR_COMFY}" ]; then \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --cuda-version "${CUDA_VERSION_FOR_COMFY}" --nvidia; \
    else \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --nvidia; \
    fi

# Optional PyTorch upgrade
RUN if [ "${ENABLE_PYTORCH_UPGRADE}" = "true" ]; then \
      uv pip install --force-reinstall torch torchvision torchaudio --index-url "${PYTORCH_INDEX_URL}"; \
    fi

# Handler deps (stay in venv so we can copy just the venv to runtime)
RUN uv pip install runpod requests websocket-client

# Add scripts needed during build (node installs, prefetch)
COPY scripts/comfy-node-install.sh /usr/local/bin/comfy-node-install
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
COPY scripts/prefetch-annotators.sh /usr/local/bin/prefetch-annotators
RUN chmod +x /usr/local/bin/comfy-node-install /usr/local/bin/comfy-manager-set-mode /usr/local/bin/prefetch-annotators

# Prefetch annotators + install custom nodes
COPY config/annotators.manifest /tmp/annotators.manifest
RUN /usr/local/bin/comfy-manager-set-mode public \
 && comfy node install comfyui_ipadapter_plus comfyui_controlnet_aux comfyui-impact-pack comfyui-impact-subpack rgthree-comfy efficiency-nodes-comfyui comfyui_ultimatesdupscale \
 && /usr/local/bin/prefetch-annotators /tmp/annotators.manifest \
 && rm -f /tmp/annotators.manifest

# Heavy GPU deps (kept isolated so it caches well)
# NOTE: You used --no-cache-dir; keep it if you prefer smaller layers,
# but it means a cache miss re-downloads huge wheels.
RUN uv pip install --no-cache-dir \
    pillow==10.2.0 \
    onnxruntime \
    onnxruntime-gpu \
    insightface

# Model symlink layer (build-time)
WORKDIR /comfyui
COPY config/models.dirs /tmp/models.dirs
RUN set -eux; \
    while IFS= read -r d; do [ -z "$d" ] && continue; mkdir -p "/runpod-volume/${d}"; done < /tmp/models.dirs; \
    while IFS= read -r d; do [ -z "$d" ] && continue; rm -rf "/comfyui/models/${d}"; done < /tmp/models.dirs; \
    while IFS= read -r d; do [ -z "$d" ] && continue; mkdir -p "/comfyui/models/$(dirname "${d}")"; ln -s "/runpod-volume/${d}" "/comfyui/models/${d}"; done < /tmp/models.dirs; \
    rm -f /tmp/models.dirs

# =========================
# Stage 2: Runtime (lean)
# =========================
FROM ${BASE_IMAGE} AS runtime

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    PYTHONUNBUFFERED=1 \
    RUST_LOG=info \
    UV_LOG_LEVEL=info \
    PIP_NO_INPUT=1

# Runtime deps only (no build-essential, no git, no python-dev)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    ca-certificates \
    curl \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg \
    libgomp1 \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && rm -rf /var/lib/apt/lists/*

# Copy only what you need to run
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /comfyui /comfyui

# Runtime scripts (used by start.sh)
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-manager-set-mode

ENV PATH="/opt/venv/bin:${PATH}" \
    VIRTUAL_ENV="/opt/venv"

WORKDIR /

# Put frequently changed files LAST for fastest rebuilds
COPY src/start.sh /start.sh
COPY handler.py /handler.py
COPY test_input.json /test_input.json
RUN chmod +x /start.sh

CMD ["/start.sh"]
