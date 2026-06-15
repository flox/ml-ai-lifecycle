#!/bin/bash
#SBATCH --job-name=shakespeare-prep
#SBATCH --output=shakespeare-prep-%j.out
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4

source "$(cd "$(dirname "$0")" && pwd)/../config.sh"

run_in_env bash -c '
set -euo pipefail
cd "$NANOGPT_DIR"
python3 data/shakespeare_char/prepare.py
echo "Shakespeare dataset prepared."
'
