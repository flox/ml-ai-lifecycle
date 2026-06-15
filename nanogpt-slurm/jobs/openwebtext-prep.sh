#!/bin/bash
#SBATCH --job-name=owt-prep
#SBATCH --output=owt-prep-%j.out
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=64G
#SBATCH --time=04:00:00

source "$(cd "$(dirname "$0")" && pwd)/../config.sh"

run_in_env bash -c '
set -euo pipefail
cd "$NANOGPT_DIR"
python3 data/openwebtext/prepare.py
echo "OpenWebText preparation complete."
ls -lh data/openwebtext/
'
