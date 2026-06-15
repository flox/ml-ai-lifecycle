# nanogpt-slurm

Train a GPT language model from scratch on a Slurm cluster.

This repo wraps Andrej Karpathy's [nanoGPT](https://github.com/karpathy/nanoGPT)
with Slurm job scripts and [Flox](https://flox.dev)-managed dependencies so you
can go from zero to generating text on a GPU cluster with a handful of `sbatch`
commands. Two training targets let you validate fast, then scale up:

1. **Shakespeare (~10M params)** -- end-to-end in ~10 minutes
2. **GPT-2 124M on OpenWebText** -- real pre-training, hours to days depending
   on your GPU

No Docker, no Conda, no manual pip installs. The environment (Python, CUDA,
PyTorch, tokenizers) is managed declaratively via **Flox** or **Nix flakes** —
pick whichever your cluster already has. See [SETUP.md](SETUP.md) for full
instructions on both paths.

## Prerequisites

- A **Slurm cluster** with at least one GPU node
- **[Flox](https://flox.dev)** installed on all nodes, **or** **[Nix](https://nixos.org)** with flakes enabled
- If using Flox: a **[FloxHub](https://hub.flox.dev)** account
- If using Nix: compute nodes must be able to reach GitHub (to fetch the flake)

> **What is Flox?** Flox is a virtual-environment manager built on Nix. It
> declares all dependencies (system libraries, Python, CUDA) in a
> `manifest.toml` and reproduces them identically on any Linux machine. FloxHub
> is its package registry -- you push an environment once and compute nodes pull
> it on demand.
>
> **What about plain Nix?** If your cluster already has Nix, you can skip Flox
> entirely and point jobs at a GitHub-hosted flake instead. See
> [SETUP.md](SETUP.md) for details.

## Setup

Full setup instructions for both Flox and Nix are in [SETUP.md](SETUP.md).
The short version:

1. Edit `config.sh` — set `ENV_MANAGER` (`flox` or `nix`) and the
   corresponding environment path (`NANOGPT_FLOX_ENV` or `NANOGPT_FLAKE`).
2. Publish the environment (Flox: `flox push`; Nix: push the flake repo to
   GitHub).
3. Verify on the login node — `config.sh` defines a `run_in_env` helper that
   dispatches to the right tool.

Every job script sources `config.sh` and calls `run_in_env`, so this is the
only place you need to configure.

## Quick Start: Shakespeare (~10 min)

The Shakespeare pipeline has three phases: prepare data, train, sample. Use
Slurm's `--dependency` flag to chain them:

```bash
# Prepare the dataset (CPU only)
PREP=$(sbatch --parsable jobs/shakespeare-prep.sh)

# Train on a GPU (starts after prep finishes)
TRAIN=$(sbatch --parsable --dependency=afterok:$PREP jobs/shakespeare-train.sh)

# Generate text (starts after training finishes)
sbatch --dependency=afterok:$TRAIN jobs/shakespeare-sample.sh
```

If your cluster requires a GPU partition, add it at submit time:

```bash
sbatch --partition=gpu jobs/shakespeare-train.sh
```

Check progress with `squeue -u $USER` and read output with
`cat shakespeare-train-<jobid>.out`.

## Full Training: GPT-2 124M

### Phase 1: Prepare data

Choose one dataset. OpenWebText ships with nanoGPT; FineWeb-Edu is a
higher-quality alternative.

```bash
# Option A: OpenWebText (~2-4 hours, ~20 GB disk)
sbatch jobs/openwebtext-prep.sh

# Option B: FineWeb-Edu 10BT (~4-6 hours, ~40 GB disk)
sbatch jobs/fineweb-prep.sh
```

### Phase 2: Train

```bash
PREP=<jobid-from-above>
TRAIN=$(sbatch --parsable --dependency=afterok:$PREP jobs/gpt2-train.sh)
```

Before submitting, check the batch size in `jobs/gpt2-train.sh` against the
GPU Sizing Guide below. The defaults target 32 GB VRAM (RTX 5090).

### Phase 3: Inference

```bash
# Generate text samples
sbatch --dependency=afterok:$TRAIN jobs/gpt2-sample.sh

# Evaluate validation loss and perplexity
sbatch --dependency=afterok:$TRAIN jobs/gpt2-eval.sh
```

## GPU Sizing Guide

nanoGPT's GPT-2 training targets an effective batch size of ~524K tokens per
step (`batch_size * gradient_accumulation_steps * block_size`). Adjust
`batch_size` for your VRAM and recompute `gradient_accumulation_steps`:

```
gradient_accumulation_steps ≈ 524288 / (batch_size * 1024)
```

| GPU | VRAM | `batch_size` | `gradient_accumulation_steps` | Est. time (GPT-2 124M) |
|-----|------|:------------:|:-----------------------------:|------------------------|
| A100 / H100 | 40-80 GB | 32 | 16 | ~4-8 hrs |
| RTX 5090 | 32 GB | 16 | 32 | ~8-20 hrs |
| RTX 4090 / A5000 | 24 GB | 12 | 43 | ~12-24 hrs |
| RTX 4080 / T4 | 16 GB | 8 | 64 | ~20-36 hrs |
| RTX 3080 / RTX 4060 | 8-12 GB | 4 | 128 | ~36-72 hrs |

Edit `batch_size` and `gradient_accumulation_steps` in `jobs/gpt2-train.sh`.
Shakespeare training uses a much smaller model and runs on any GPU without
changes.

## Datasets

| Dataset | Script | Size | Notes |
|---------|--------|------|-------|
| OpenWebText | `jobs/openwebtext-prep.sh` | ~20 GB | Default. Ships with nanoGPT, well-tested. |
| FineWeb-Edu 10BT | `jobs/fineweb-prep.sh` | ~40 GB | Higher quality. Streamed from HuggingFace. |

To use FineWeb-Edu for training, edit `jobs/gpt2-train.sh`:

```bash
--dataset=fineweb_edu    # instead of openwebtext
```

And in `jobs/gpt2-eval.sh`, change the validation data path to
`data/fineweb_edu/val.bin`.

## Resuming Training

nanoGPT checkpoints automatically every `eval_interval` steps. To resume:

```bash
sed -i 's/--init_from=scratch/--init_from=resume/' jobs/gpt2-train.sh
sbatch jobs/gpt2-train.sh
```

The model loads from `out-gpt2-124m/ckpt.pt` and continues where it left off.

## Job Scripts Reference

| Script | Purpose | GPU | Est. time |
|--------|---------|:---:|-----------|
| `jobs/shakespeare-prep.sh` | Tokenize Shakespeare dataset | No | ~1 min |
| `jobs/shakespeare-train.sh` | Train ~10M param character model | Yes | ~5-15 min |
| `jobs/shakespeare-sample.sh` | Generate Shakespeare-style text | Yes | ~1 min |
| `jobs/openwebtext-prep.sh` | Download + tokenize OpenWebText | No | ~2-4 hrs |
| `jobs/fineweb-prep.sh` | Download + tokenize FineWeb-Edu 10BT | No | ~4-6 hrs |
| `jobs/gpt2-train.sh` | Train GPT-2 124M | Yes | ~8-72 hrs |
| `jobs/gpt2-sample.sh` | Generate text from trained GPT-2 | Yes | ~1 min |
| `jobs/gpt2-eval.sh` | Compute validation loss + perplexity | Yes | ~10 min |

## Where Things Live

```
nanogpt-slurm/
  config.sh                         Cluster configuration (edit this)
  SETUP.md                          Environment setup guide (Flox & Nix)
  jobs/                             Slurm batch scripts
  .flox/env/manifest.toml           Flox environment definition

$NANOGPT_DIR/                       (set by the environment on activation)
  data/openwebtext/                 Tokenized OpenWebText
  data/fineweb_edu/                 Tokenized FineWeb-Edu (if prepared)
  data/shakespeare_char/            Tokenized Shakespeare
  out-shakespeare/                  Shakespeare checkpoints
  out-gpt2-124m/                    GPT-2 124M checkpoints
```

Use `echo $NANOGPT_DIR` inside an activated environment to find the exact
path. With Flox this is under `$FLOX_ENV_CACHE/nanoGPT`; with Nix it depends
on the flake's shell hook.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `CUDA out of memory` | Reduce `batch_size`, increase `gradient_accumulation_steps` (see GPU Sizing Guide) |
| `torch.compile` errors | Add `--compile=False` to the training command |
| `tiktoken` import error | Flox: `rm $FLOX_ENV_CACHE/.deps_installed` and re-activate. Nix: exit and re-enter `nix develop` |
| Checkpoint not resuming | Set `--init_from=resume` (default is `scratch`) |
| `bfloat16` not supported | Use `--dtype=float16` (older GPUs lack bf16) |
| Slow first activation | Flox: `ssh node "flox activate -r youruser/nanogpt-slurm -- true"`. Nix: `ssh node "nix build github:flox/ml-ai-lifecycle?dir=model-training"` |
| Environment variable not set | Edit `config.sh` — set `NANOGPT_FLOX_ENV` (Flox) or `NANOGPT_FLAKE` (Nix) |
| Job pending forever | Check `sinfo` for available partitions, submit with `--partition=<name>` |

## What the Environment Provides

Both the Flox manifest (`.flox/env/manifest.toml`) and the Nix flake declare
the same stack:

| Package | Purpose |
|---------|---------|
| python313Full | Python 3.13 |
| uv | Fast pip replacement |
| gcc + gcc-unwrapped | libstdc++ for PyTorch |
| git | Clone nanoGPT |
| CUDA (nvcc, cudart, cublas) — 12.8 via Flox, 12.9 via Nix | GPU compute |

On activation, the environment automatically:
1. Creates a Python venv and installs CUDA or CPU PyTorch (auto-detected)
2. Installs tiktoken, datasets, numpy, tqdm, wandb
3. Clones nanoGPT and exports its location as `$NANOGPT_DIR`
