#!/bin/bash
#SBATCH --job-name=shakespeare-train
#SBATCH --output=shakespeare-train-%j.out
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --gres=gpu:1
#SBATCH --time=00:30:00

source "$(cd "$(dirname "$0")" && pwd)/../config.sh"

run_in_env bash -c '
set -euo pipefail
cd "$NANOGPT_DIR"

# Shakespeare uses a small model (~10M params) and runs on any GPU without changes.
python3 train.py config/train_shakespeare_char.py \
  --device=cuda \
  --compile=True \
  --dtype=bfloat16 \
  --n_layer=6 \
  --n_head=6 \
  --n_embd=384 \
  --block_size=256 \
  --batch_size=64 \
  --max_iters=5000 \
  --lr_decay_iters=5000 \
  --learning_rate=1e-3 \
  --min_lr=1e-4 \
  --eval_interval=250 \
  --eval_iters=200 \
  --log_interval=10 \
  --out_dir=out-shakespeare \
  --init_from=scratch
'
