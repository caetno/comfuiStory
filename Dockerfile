# Build argument for base image selection
ARG BASE_IMAGE=nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04

FROM ${BASE_IMAGE} AS base

# Build arguments for this stage with sensible defaults for standalone builds
ARG COMFYUI_VERSION=latest
ARG CUDA_VERSION_FOR_COMFY
ARG ENABLE_PYTORCH_UPGRADE=false
ARG PYTORCH_INDEX_URL

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_PREFER_BINARY=1
ENV PYTHONUNBUFFERED=1
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# comfy-cli workspace & actual ComfyUI root
ENV COMFY_WORKSPACE=/comfyui
ENV COMFY_ROOT=/comfyui/ComfyUI

# Install Python, git and other necessary tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
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
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

# Install uv (latest) using official installer and create isolated venv
RUN wget -qO- https://astral.sh/uv/install.sh | sh \
    && ln -s /root/.local/bin/uv /usr/local/bin/uv \
    && ln -s /root/.local/bin/uvx /usr/local/bin/uvx \
    && uv venv /opt/venv

# Use the virtual environment for all subsequent commands
ENV PATH="/opt/venv/bin:${PATH}"

# Install comfy-cli + dependencies needed by it to install ComfyUI
RUN uv pip install comfy-cli pip setuptools wheel

# Install ComfyUI (workspace install => /comfyui/ComfyUI)
RUN if [ -n "${CUDA_VERSION_FOR_COMFY}" ]; then \
      /usr/bin/yes | comfy --workspace "${COMFY_WORKSPACE}" install --version "${COMFYUI_VERSION}" --cuda-version "${CUDA_VERSION_FOR_COMFY}" --nvidia; \
    else \
      /usr/bin/yes | comfy --workspace "${COMFY_WORKSPACE}" install --version "${COMFYUI_VERSION}" --nvidia; \
    fi

# Upgrade PyTorch if needed (for newer CUDA versions)
RUN if [ "$ENABLE_PYTORCH_UPGRADE" = "true" ]; then \
      uv pip install --force-reinstall torch torchvision torchaudio --index-url ${PYTORCH_INDEX_URL}; \
    fi

# Ensure COMFY_ROOT exists
RUN test -d "${COMFY_ROOT}"

# --- SYMLINK IMPLEMENTATION START (FIXED PATHS) ---

WORKDIR ${COMFY_ROOT}

COPY config/models.dirs /tmp/models.dirs

RUN set -eux; \
    # 1) Ensure volume folders exist
    while IFS= read -r d; do \
      mkdir -p "/runpod-volume/${d}"; \
    done < /tmp/models.dirs; \
    \
    # 2) Remove ComfyUI model directories (in the real ComfyUI root)
    while IFS= read -r d; do \
      rm -rf "${COMFY_ROOT}/models/${d}"; \
    done < /tmp/models.dirs; \
    \
    # 3) Create symlinks into /runpod-volume
    while IFS= read -r d; do \
      ln -s "/runpod-volume/${d}" "${COMFY_ROOT}/models/${d}"; \
    done < /tmp/models.dirs; \
    \
    rm -f /tmp/models.dirs

# --- SYMLINK IMPLEMENTATION END ---

# Go back to the root
WORKDIR /

# Install Python runtime dependencies for the handler
RUN uv pip install runpod requests websocket-client

# Add script to install custom nodes (kept, but we will also call comfy directly w/ workspace)
COPY scripts/comfy-node-install.sh /usr/local/bin/comfy-node-install
RUN chmod +x /usr/local/bin/comfy-node-install

# Prevent pip from asking for confirmation during uninstall steps in custom nodes
ENV PIP_NO_INPUT=1

# Copy helper script to switch Manager network mode at container start
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-manager-set-mode

# Add annotator prefetch tooling + manifest
COPY scripts/prefetch-annotators.sh /usr/local/bin/prefetch-annotators
RUN chmod +x /usr/local/bin/prefetch-annotators
COPY config/annotators.manifest /tmp/annotators.manifest

# Install custom nodes against the SAME workspace, from inside the real ComfyUI root
WORKDIR ${COMFY_ROOT}

RUN /usr/local/bin/comfy-manager-set-mode public \
 && comfy --workspace "${COMFY_WORKSPACE}" node install --mode=remote \
      ComfyUI_IPAdapter_plus \
      comfyui_controlnet_aux \
      comfyui-impact-pack \
      rgthree-comfy \
      efficiency-nodes-comfyui \
 && /usr/local/bin/prefetch-annotators /tmp/annotators.manifest

# Build-time sanity check: verify IPAdapterAdvanced is registered (no heredoc)
RUN python -c "import os,sys,subprocess,re; ws=os.environ.get('COMFY_WORKSPACE','/comfyui'); p=subprocess.run(['comfy', f'--workspace={ws}', 'which'], capture_output=True, text=True); out=p.stdout+p.stderr; m=re.search(r'Target ComfyUI path:\\\\s*(.*)', out); assert m, 'Could not parse comfy which output:\\n'+out; root=m.group(1).strip(); sys.path.insert(0, root); import nodes; ok=('IPAdapterAdvanced' in getattr(nodes,'NODE_CLASS_MAPPINGS',{})); print('ComfyUI root:', root); print('IPAdapterAdvanced present:', ok); assert ok, 'IPAdapterAdvanced missing (wrong workspace / node not loaded / dependency import error)'"

# Add application code and scripts
ADD src/start.sh handler.py test_input.json ./
RUN chmod +x /start.sh

CMD ["/start.sh"]
