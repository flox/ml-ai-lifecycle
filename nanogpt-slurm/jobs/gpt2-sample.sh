#!/bin/bash
#SBATCH --job-name=gpt2-sample
#SBATCH --output=gpt2-sample-%j.out
#SBATCH --gres=gpu:1
#SBATCH --time=00:10:00

source "$(cd "$(dirname "$0")" && pwd)/../config.sh"

run_in_env bash -c '
set -euo pipefail
cd "$NANOGPT_DIR"

python3 sample.py \
  --out_dir=out-gpt2-124m \
  --device=cuda \
  --dtype=bfloat16 \
  --num_samples=5 \
  --max_new_tokens=256 \
  --temperature=0.8 \
  --top_k=200 \
  --start="The meaning of life is"
'
