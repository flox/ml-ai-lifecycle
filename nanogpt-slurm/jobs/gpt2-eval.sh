#!/bin/bash
#SBATCH --job-name=gpt2-eval
#SBATCH --output=gpt2-eval-%j.out
#SBATCH --gres=gpu:1
#SBATCH --time=00:30:00

# Change data path to data/fineweb_edu/val.bin if using FineWeb-Edu.

source "$(cd "$(dirname "$0")" && pwd)/../config.sh"

run_in_env bash -c '
set -euo pipefail
cd "$NANOGPT_DIR"

python3 -c "
import math
import torch
from model import GPT, GPTConfig
import numpy as np

# Load checkpoint
ckpt = torch.load(\"out-gpt2-124m/ckpt.pt\", map_location=\"cuda\", weights_only=False)
conf = GPTConfig(**ckpt[\"model_args\"])
model = GPT(conf)
model.load_state_dict(ckpt[\"model\"], strict=False)
model.to(\"cuda\")
model.eval()

# Load validation data (change path if using fineweb_edu)
val_data = np.memmap(\"data/openwebtext/val.bin\", dtype=np.uint16, mode=\"r\")
block_size = ckpt[\"model_args\"][\"block_size\"]

# Estimate val loss over 200 batches
losses = []
for _ in range(200):
    ix = torch.randint(len(val_data) - block_size, (16,))
    x = torch.stack([torch.from_numpy(val_data[i:i+block_size].astype(np.int64)) for i in ix]).to(\"cuda\")
    y = torch.stack([torch.from_numpy(val_data[i+1:i+1+block_size].astype(np.int64)) for i in ix]).to(\"cuda\")
    with torch.no_grad():
        _, loss = model(x, y)
    losses.append(loss.item())

avg_loss = sum(losses) / len(losses)
perplexity = math.exp(avg_loss)
print(f\"Val loss: {avg_loss:.4f}\")
print(f\"Perplexity: {perplexity:.2f}\")
"
'
