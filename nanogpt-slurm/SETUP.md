# Environment Setup

This tutorial supports two environment managers: **Flox** (via FloxHub) and
**Nix** (via GitHub-hosted flakes). Pick one — both provide the same stack
(Python 3.13, CUDA, PyTorch, tiktoken, etc.). Flox uses CUDA 12.8; the Nix
flakes use CUDA 12.9.

## Option A: Flox

### Prerequisites

- [Flox](https://flox.dev) installed on all nodes (login + compute)
- A [FloxHub](https://hub.flox.dev) account

### Setup

1. Edit `config.sh` and set your FloxHub username:

   ```bash
   NANOGPT_FLOX_ENV="youruser/nanogpt-slurm"
   ```

2. Log in and push the environment:

   ```bash
   flox auth login
   flox push
   ```

3. Verify on the login node:

   ```bash
   flox activate -r youruser/nanogpt-slurm -- python3 -c "import torch; print(torch.cuda.is_available())"
   ```

Compute nodes pull the environment by name at job start. No further setup
needed on each node.

## Option B: Nix Flakes

### Prerequisites

- [Nix](https://nixos.org/download) installed on all nodes (login + compute)
  with flakes enabled (`experimental-features = nix-command flakes` in
  `nix.conf`)
- All compute nodes can reach GitHub (to fetch the flake)

### Setup

1. Edit `config.sh` and switch to Nix mode:

   ```bash
   ENV_MANAGER="nix"
   NANOGPT_FLAKE="github:flox/ml-ai-lifecycle?dir=model-training"
   ```

   The flake reference can be any valid flake URL:

   | Form | Example |
   |------|---------|
   | GitHub repo (default) | `github:flox/ml-ai-lifecycle?dir=model-training` |
   | Specific branch | `github:flox/ml-ai-lifecycle/main?dir=model-training` |
   | Pinned revision | `github:flox/ml-ai-lifecycle/<commit-sha>?dir=model-training` |
   | Local path | `path:/shared/nfs/ml-ai-lifecycle?dir=model-training` |

2. Verify on the login node:

   ```bash
   nix develop "$NANOGPT_FLAKE" --command python3 -c "import torch; print(torch.cuda.is_available())"
   ```

3. (Recommended) Pre-build the environment so compute nodes don't build from
   source on first job:

   ```bash
   # Option 1: Warm the local Nix store on each node
   ssh compute-node "nix build github:flox/ml-ai-lifecycle?dir=model-training"

   # Option 2: Push to a binary cache (e.g., Cachix)
   cachix push your-cache $(nix build github:flox/ml-ai-lifecycle?dir=model-training --print-out-paths)
   ```

   Without a binary cache or shared Nix store, each compute node builds the
   full environment on first run. This can take a long time.

## How Job Scripts Use the Environment

`config.sh` defines a `run_in_env` helper that dispatches to Flox or Nix
based on `ENV_MANAGER`:

```bash
# config.sh (simplified)
ENV_MANAGER="${ENV_MANAGER:-flox}"
NANOGPT_FLOX_ENV="${NANOGPT_FLOX_ENV:-youruser/nanogpt-slurm}"
NANOGPT_FLAKE="${NANOGPT_FLAKE:-github:flox/ml-ai-lifecycle?dir=model-training}"

run_in_env() {
  if [ "$ENV_MANAGER" = "nix" ]; then
    nix develop "$NANOGPT_FLAKE" --command "$@"
  else
    flox activate -r "$NANOGPT_FLOX_ENV" -- "$@"
  fi
}
```

Every job script sources `config.sh` and calls:

```bash
source config.sh
run_in_env bash -c '...'
```

## Submitting Jobs

Once `config.sh` is configured (either Flox or Nix), job submission is
identical. You submit all the commands below from the login node — Slurm's
`--dependency=afterok:$JOBID` flag ensures each step waits for the previous
one to succeed, so the entire pipeline runs unattended after you hit enter.

### Shakespeare (smoke test)

Start here to validate your setup. Paste this on the login node:

```bash
PREP=$(sbatch --parsable jobs/shakespeare-prep.sh)                               # CPU: tokenize data
TRAIN=$(sbatch --parsable --dependency=afterok:$PREP jobs/shakespeare-train.sh)   # GPU: train
sbatch --dependency=afterok:$TRAIN jobs/shakespeare-sample.sh                     # GPU: generate text
```

This trains a small ~10M parameter model and finishes in about 10 minutes.
Monitor with `squeue -u $USER`, read output from `*-<jobid>.out` files.

### GPT-2 124M

Same idea, longer-running jobs. Before submitting, check `batch_size` and
`gradient_accumulation_steps` in `jobs/gpt2-train.sh` against your GPU's VRAM:

| VRAM | GPUs | `batch_size` | `gradient_accumulation_steps` |
|------|------|:------------:|:-----------------------------:|
| 40-80 GB | A100, H100 | 32 | 16 |
| 32 GB | RTX 5090 | **16 (default)** | **32** |
| 24 GB | RTX 4090, A5000 | 12 | 43 |
| 16 GB | RTX 4080, T4 | 8 | 64 |
| 8-12 GB | RTX 3080, RTX 4060 | 4 | 128 |

The two values should satisfy
`batch_size * gradient_accumulation_steps * 1024 ≈ 524,288` (some rows round
slightly due to integer constraints). Smaller
`batch_size` means more gradient accumulation steps to maintain the same
effective batch size, so training takes longer but uses less VRAM.

Once you've set those, submit the whole pipeline at once:

```bash
# Pick one dataset:
PREP=$(sbatch --parsable jobs/openwebtext-prep.sh)       # Option A: OpenWebText (~2-4 hrs, ~20 GB)
# PREP=$(sbatch --parsable jobs/fineweb-prep.sh)         # Option B: FineWeb-Edu 10BT (~4-6 hrs, ~40 GB)

# Train
TRAIN=$(sbatch --parsable --dependency=afterok:$PREP jobs/gpt2-train.sh)

# Inference (both wait for training, then run)
sbatch --dependency=afterok:$TRAIN jobs/gpt2-sample.sh
sbatch --dependency=afterok:$TRAIN jobs/gpt2-eval.sh
```

Paste that block, and Slurm handles the rest — data prep, training, and
inference run in sequence without further intervention.

## Comparison

| | Flox | Nix |
|---|---|---|
| Environment definition | `manifest.toml` | `flake.nix` |
| Distribution | `flox push` to FloxHub | Push `flake.nix` to GitHub |
| Node consumption | `flox activate -r user/env` | `nix develop github:org/repo` |
| First-run speed | Fast (pre-built on FloxHub) | Slow unless binary cache is set up |
| Pinning/reproducibility | FloxHub handles it | `flake.lock` pins all inputs |
| Node prerequisites | Flox | Nix with flakes enabled |
