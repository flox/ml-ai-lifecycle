#!/bin/bash
#SBATCH --job-name=gpt2-124m
#SBATCH --output=gpt2-124m-%j.out
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --gres=gpu:1
#SBATCH --time=24:00:00

# Default dataset is openwebtext (ships with nanoGPT).
# If you prepared FineWeb-Edu, change --dataset=openwebtext to --dataset=fineweb_edu.
#
# To resume from a checkpoint, change --init_from=scratch to --init_from=resume.

source "$(cd "$(dirname "$0")" && pwd)/../config.sh"

run_in_env bash -c '
set -euo pipefail
cd "$NANOGPT_DIR"

# Adjust batch_size for your GPU, then recompute gradient_accumulation_steps.
# See README GPU Sizing Guide.
python3 train.py \
  --dataset=openwebtext \
  --init_from=scratch \
  --out_dir=out-gpt2-124m \
  --device=cuda \
  --compile=True \
  --dtype=bfloat16 \
  --n_layer=12 \
  --n_head=12 \
  --n_embd=768 \
  --block_size=1024 \
  --batch_size=16 \
  --gradient_accumulation_steps=32 \
  --learning_rate=6e-4 \
  --min_lr=6e-5 \
  --warmup_iters=700 \
  --lr_decay_iters=19073 \
  --max_iters=19073 \
  --weight_decay=0.1 \
  --beta1=0.9 \
  --beta2=0.95 \
  --grad_clip=1.0 \
  --eval_interval=500 \
  --eval_iters=200 \
  --log_interval=10 \
  --always_save_checkpoint=True
'
