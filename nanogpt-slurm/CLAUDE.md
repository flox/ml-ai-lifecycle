# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Slurm job scripts and a Flox environment wrapping [nanoGPT](https://github.com/karpathy/nanoGPT) for training GPT language models on GPU clusters. nanoGPT itself is not in this repo — it's cloned at activation time and exposed as `$NANOGPT_DIR` by the environment.

## Environment

Two environment managers are supported: **Flox** (via FloxHub) and **Nix** (via
GitHub-hosted flakes). Both provide the same stack: Python 3.13, CUDA (12.8 via Flox, 12.9 via Nix),
PyTorch, tiktoken, etc. `config.sh` controls which one is active via
`ENV_MANAGER` (defaults to `flox`). See `SETUP.md` for full setup instructions.

**Never run Python or training scripts outside the activated environment.**

## Key Files

- `config.sh` — Single config file sourced by all job scripts. Sets `ENV_MANAGER`, `NANOGPT_FLOX_ENV`, `NANOGPT_FLAKE`, and defines the `run_in_env` helper.
- `jobs/` — Slurm batch scripts. Each sources `config.sh` then runs inside `run_in_env`.
- `SETUP.md` — Setup instructions for both Flox and Nix paths.
- `.flox/env/manifest.toml` — Flox environment: packages, env vars, activation hook.

## Job Submission Pattern

All jobs follow the same pattern: `sbatch jobs/<script>.sh`. Chain dependent jobs with:
```bash
PREP=$(sbatch --parsable jobs/shakespeare-prep.sh)
TRAIN=$(sbatch --parsable --dependency=afterok:$PREP jobs/shakespeare-train.sh)
sbatch --dependency=afterok:$TRAIN jobs/shakespeare-sample.sh
```

## Two Training Targets

1. **Shakespeare** (~10M params) — quick validation, any GPU, ~10 min end-to-end
2. **GPT-2 124M** (OpenWebText or FineWeb-Edu) — real pre-training, hours to days

## GPU Sizing

Training scripts hardcode `batch_size` and `gradient_accumulation_steps`. When editing these, maintain the invariant:
```
batch_size * gradient_accumulation_steps * block_size ≈ 524,288
```
For GPT-2 with block_size=1024: `gradient_accumulation_steps = 524288 / (batch_size * 1024)`.

## Editing Job Scripts

Job scripts embed training commands inside a `run_in_env bash -c '...'` block (which dispatches to Flox or Nix based on `ENV_MANAGER`). The inner script runs with `set -euo pipefail` and `cd "$NANOGPT_DIR"`. When modifying training parameters, edit the `python3 train.py` arguments inside this block.

To switch datasets for GPT-2, change `--dataset=openwebtext` to `--dataset=fineweb_edu`. To resume training, change `--init_from=scratch` to `--init_from=resume`.
