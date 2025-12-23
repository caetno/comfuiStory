# Build argument for base image selection
ARG BASE_IMAGE=nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04

# Stage 1: Base image with common dependencies
FROM ${BASE_IMAGE} AS base

# Build arguments for this stage with sensible defaults for standalone builds
ARG COMFYUI_VERSION=latest
ARG CUDA_VERSION_FOR_COMFY
ARG ENABLE_PYTORCH_UPGRADE=false
ARG PYTORCH_INDEX_URL

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Install Python, git and other necessary tools
RUN apt-get update && apt-get install -y \
    python3.12 \
    python3.12-venv \
    git \
    wget \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip

# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Install uv (latest) using official installer and create isolated venv
RUN wget -qO- https://astral.sh/uv/install.sh | sh \
    && ln -s /root/.local/bin/uv /usr/local/bin/uv \
    && ln -s /root/.local/bin/uvx /usr/local/bin/uvx \
    && uv venv /opt/venv

# Use the virtual environment for all subsequent commands
ENV PATH="/opt/venv/bin:${PATH}"

# Install comfy-cli + dependencies needed by it to install ComfyUI
RUN uv pip install comfy-cli pip setuptools wheel

# Install ComfyUI
RUN if [ -n "${CUDA_VERSION_FOR_COMFY}" ]; then \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --cuda-version "${CUDA_VERSION_FOR_COMFY}" --nvidia; \
    else \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --nvidia; \
    fi

# Upgrade PyTorch if needed (for newer CUDA versions)
RUN if [ "$ENABLE_PYTORCH_UPGRADE" = "true" ]; then \
      uv pip install --force-reinstall torch torchvision torchaudio --index-url ${PYTORCH_INDEX_URL}; \
    fi

# Change working directory to ComfyUI
WORKDIR /comfyui

# --- SYMLINK IMPLEMENTATION START ---

# Ensure the Network Volume has the expected folder structure
RUN mkdir -p \
    /runpod-volume/audio_encoders \
    /runpod-volume/checkpoints \
    /runpod-volume/clip \
    /runpod-volume/clip_vision \
    /runpod-volume/configs \
    /runpod-volume/controlnet \
    /runpod-volume/diffusers \
    /runpod-volume/diffusion_models \
    /runpod-volume/embeddings \
    /runpod-volume/gligen \
    /runpod-volume/hypernetworks \
    /runpod-volume/latent_upscale_models \
    /runpod-volume/loras \
    /runpod-volume/model_patches \
    /runpod-volume/photomaker \
    /runpod-volume/style_models \
    /runpod-volume/text_encoders \
    /runpod-volume/unet \
    /runpod-volume/upscale_models \
    /runpod-volume/vae \
    /runpod-volume/vae_approx

# Clean out the empty model directories that ComfyUI installs
RUN rm -rf \
    /comfyui/models/audio_encoders \
    /comfyui/models/checkpoints \
    /comfyui/models/clip \
    /comfyui/models/clip_vision \
    /comfyui/models/configs \
    /comfyui/models/controlnet \
    /comfyui/models/diffusers \
    /comfyui/models/diffusion_models \
    /comfyui/models/embeddings \
    /comfyui/models/gligen \
    /comfyui/models/hypernetworks \
    /comfyui/models/latent_upscale_models \
    /comfyui/models/loras \
    /comfyui/models/model_patches \
    /comfyui/models/photomaker \
    /comfyui/models/style_models \
    /comfyui/models/text_encoders \
    /comfyui/models/unet \
    /comfyui/models/upscale_models \
    /comfyui/models/vae \
    /comfyui/models/vae_approx

# Create symbolic links to the Network Volume mount point (/runpod-volume)
# This fools ComfyUI into thinking the models are local.

# Audio Encoders
RUN ln -s /runpod-volume/audio_encoders /comfyui/models/audio_encoders

# Checkpoints (classic SD/SDXL loader path)
RUN ln -s /runpod-volume/checkpoints /comfyui/models/checkpoints

# CLIP (legacy; some loaders still look here)
RUN ln -s /runpod-volume/clip /comfyui/models/clip

# CLIP Vision (IP-Adapter and similar)
RUN ln -s /runpod-volume/clip_vision /comfyui/models/clip_vision

# Configs
RUN ln -s /runpod-volume/configs /comfyui/models/configs

# ControlNet
RUN ln -s /runpod-volume/controlnet /comfyui/models/controlnet

# Diffusers
RUN ln -s /runpod-volume/diffusers /comfyui/models/diffusers

# UNETs / Diffusion Models (newer ComfyUI path)
RUN ln -s /runpod-volume/diffusion_models /comfyui/models/diffusion_models

# Embeddings
RUN ln -s /runpod-volume/embeddings /comfyui/models/embeddings

# GLIGEN
RUN ln -s /runpod-volume/gligen /comfyui/models/gligen

# Hypernetworks
RUN ln -s /runpod-volume/hypernetworks /comfyui/models/hypernetworks

# Latent Upscale Models
RUN ln -s /runpod-volume/latent_upscale_models /comfyui/models/latent_upscale_models

# LoRAs
RUN ln -s /runpod-volume/loras /comfyui/models/loras

# Model Patches
RUN ln -s /runpod-volume/model_patches /comfyui/models/model_patches

# PhotoMaker
RUN ln -s /runpod-volume/photomaker /comfyui/models/photomaker

# Style Models
RUN ln -s /runpod-volume/style_models /comfyui/models/style_models

# Text Encoders (newer CLIP folder name)
RUN ln -s /runpod-volume/text_encoders /comfyui/models/text_encoders

# UNET (legacy folder still referenced by some nodes/workflows)
RUN ln -s /runpod-volume/unet /comfyui/models/unet

# Upscale Models
RUN ln -s /runpod-volume/upscale_models /comfyui/models/upscale_models

# VAEs
RUN ln -s /runpod-volume/vae /comfyui/models/vae

# VAE Approx
RUN ln -s /runpod-volume/vae_approx /comfyui/models/vae_approx

# --- SYMLINK IMPLEMENTATION END ---


# Go back to the root
WORKDIR /

# Install Python runtime dependencies for the handler
RUN uv pip install runpod requests websocket-client

# Add application code and scripts
ADD src/start.sh handler.py test_input.json ./
RUN chmod +x /start.sh

# Add script to install custom nodes
COPY scripts/comfy-node-install.sh /usr/local/bin/comfy-node-install
RUN chmod +x /usr/local/bin/comfy-node-install

# Prevent pip from asking for confirmation during uninstall steps in custom nodes
ENV PIP_NO_INPUT=1

# Copy helper script to switch Manager network mode at container start
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-manager-set-mode

RUN /usr/local/bin/comfy-manager-set-mode \
 && /usr/local/bin/comfy-node-install ComfyUI_IPAdapter_plus

# Set the default command to run when starting the container
CMD ["/start.sh"]
