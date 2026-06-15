#!/bin/bash
#SBATCH --job-name=shakespeare-sample
#SBATCH --output=shakespeare-sample-%j.out
#SBATCH --gres=gpu:1
#SBATCH --time=00:05:00

source "$(cd "$(dirname "$0")" && pwd)/../config.sh"

run_in_env bash -c '
set -euo pipefail
cd "$NANOGPT_DIR"

python3 sample.py \
  --out_dir=out-shakespeare \
  --device=cuda \
  --num_samples=3 \
  --max_new_tokens=500 \
  --start="ROMEO:"
'
