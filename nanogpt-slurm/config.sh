# nanogpt-slurm configuration
# Source this file in job scripts. Edit the variables below for your setup.

# Environment manager: "flox" or "nix"
ENV_MANAGER="${ENV_MANAGER:-flox}"

# Flox: FloxHub environment path (e.g., "youruser/nanogpt-slurm")
# Push your environment first: flox auth login && flox push
NANOGPT_FLOX_ENV="${NANOGPT_FLOX_ENV:-youruser/nanogpt-slurm}"

# Nix: Flake reference (GitHub repo, branch, pinned rev, or local path)
NANOGPT_FLAKE="${NANOGPT_FLAKE:-github:flox/ml-ai-lifecycle?dir=model-training}"

# Helper: run a command inside the chosen environment.
# Usage: run_in_env bash -c '...'
run_in_env() {
  if [ "$ENV_MANAGER" = "nix" ]; then
    nix develop "$NANOGPT_FLAKE" --command "$@"
  else
    flox activate -r "$NANOGPT_FLOX_ENV" -- "$@"
  fi
}

# Batch size guidance — see the GPU Sizing Guide in README.md
# The training scripts hardcode batch_size and gradient_accumulation_steps.
# To adjust for your GPU:
#   1. Find your GPU in the README table
#   2. Edit batch_size in the training script
#   3. Recompute: gradient_accumulation_steps = 524288 / (batch_size * 1024)
#
# Example settings:
#   40-80 GB VRAM (A100, H100):    batch_size=32, grad_accum=16
#   32 GB VRAM (RTX 5090):         batch_size=16, grad_accum=32  (default)
#   24 GB VRAM (RTX 4090, A5000):  batch_size=12, grad_accum=43
#   16 GB VRAM (RTX 4080, T4):     batch_size=8,  grad_accum=64
#    8-12 GB VRAM (RTX 3080, etc): batch_size=4,  grad_accum=128
