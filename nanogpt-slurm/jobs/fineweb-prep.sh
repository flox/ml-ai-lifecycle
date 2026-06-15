#!/bin/bash
#SBATCH --job-name=fineweb-prep
#SBATCH --output=fineweb-prep-%j.out
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --mem=64G
#SBATCH --time=06:00:00

# FineWeb-Edu is not included in nanoGPT — this script creates
# a compatible dataset using HuggingFace datasets + tiktoken.

source "$(cd "$(dirname "$0")" && pwd)/../config.sh"

run_in_env bash -c '
set -euo pipefail
cd "$NANOGPT_DIR"

mkdir -p data/fineweb_edu

python3 << '\''PYEOF'\''
"""Prepare FineWeb-Edu 10BT for nanoGPT.

Downloads from HuggingFace, tokenizes with GPT-2 BPE (tiktoken),
saves as train.bin / val.bin in nanoGPT uint16 memmap format.
"""
import os
import numpy as np
import tiktoken
from datasets import load_dataset
from tqdm import tqdm

out_dir = "data/fineweb_edu"

enc = tiktoken.get_encoding("gpt2")
eot = enc._special_tokens["<|endoftext|>"]

dataset = load_dataset(
    "HuggingFaceFW/fineweb-edu",
    name="sample-10BT",
    split="train",
    streaming=True,
)

all_tokens = []
print("Tokenizing FineWeb-Edu 10BT ...")
for doc in tqdm(dataset, desc="documents"):
    tokens = enc.encode_ordinary(doc["text"])
    tokens.append(eot)
    all_tokens.extend(tokens)

total = len(all_tokens)
print(f"Total tokens: {total:,}")

all_tokens = np.array(all_tokens, dtype=np.uint16)
split_idx = int(total * 0.9)
train_tokens = all_tokens[:split_idx]
val_tokens = all_tokens[split_idx:]

print(f"Train: {len(train_tokens):,} tokens")
print(f"Val:   {len(val_tokens):,} tokens")

train_tokens.tofile(os.path.join(out_dir, "train.bin"))
val_tokens.tofile(os.path.join(out_dir, "val.bin"))
print(f"Saved to {out_dir}/")
PYEOF

echo "FineWeb-Edu preparation complete."
ls -lh data/fineweb_edu/
'
