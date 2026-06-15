# ml-ai-lifecycle

Composable, reproducible environments for ML training on GPU clusters. Each
layer is available as both a [Flox](https://flox.dev) environment and a
[Nix flake](https://nixos.org), so you can use whichever your infrastructure
already has.

## Layers

The repo is organized as a stack of independent environments that compose
upward. Each can be used standalone or pulled in as a dependency.

```
┌─────────────────────────────────────────────┐
│  nanogpt-slurm        Tutorial: train GPT   │
│                        on a Slurm cluster    │
├─────────────────────────────────────────────┤
│  model-training       Composed ML training   │
│                        environment           │
├──────────┬──────────────────┬───────────────┤
│ build-env│cuda-dev-essentials│pytorch-runtime│
│ gcc,cmake│ CUDA 12.9 toolkit │ Python 3.13 + │
│ openssl  │ nvcc, cudnn, nccl │ PyTorch       │
└──────────┴──────────────────┴───────────────┘
```

### [`build-env`](build-env/)

Cross-platform build toolchain: gcc/clang, cmake, openssl, pkg-config,
coreutils. Works on Linux (x86_64, aarch64) and macOS (x86_64, aarch64).

### [`cuda-dev-essentials`](cuda-dev-essentials/)

CUDA 12.9 development tools: nvcc, cudart, cuBLAS, cuDNN, NCCL, cuTensor,
CUPTI, cuda-gdb, sanitizer API. Linux only.

### [`pytorch-runtime`](pytorch-runtime/)

Python 3.13 with PyTorch. CUDA-accelerated on Linux, MPS-accelerated on
aarch64-darwin. The Nix
flake exposes layered package outputs: `runtime`, `training` (adds
TensorBoard, W&B), `eval`, and `dev` (adds Jupyter). `model-training` uses
the `runtime` output and installs additional training deps via pip.

### [`model-training`](model-training/)

Composed environment that pulls in `build-env`, `cuda-dev-essentials`, and
`pytorch-runtime`. Adds uv for fast package management and sets up a venv with
ML training dependencies (datasets, transformers, accelerate, etc.). This is the
environment you'd point a training job at.

### [`nanogpt-slurm`](nanogpt-slurm/)

End-to-end tutorial: train a GPT language model on a Slurm cluster using the
`model-training` environment. Includes Slurm job scripts for data prep,
training, sampling, and evaluation. See its own
[README](nanogpt-slurm/README.md) and [SETUP.md](nanogpt-slurm/SETUP.md).

## Using with Flox

Each environment is published to FloxHub under the `flox-labs` namespace.
You can use them individually or composed:

```bash
# Use a single layer
flox activate -r flox-labs/pytorch-runtime

# Use the composed training environment
flox activate -r flox-labs/model-training
```

The `model-training` environment includes the other three via Flox's
`[include]` mechanism — you don't need to activate them separately.

## Using with Nix

Each directory contains a `flake.nix`. Use them directly from GitHub:

```bash
# Use a single layer
nix develop github:flox/ml-ai-lifecycle?dir=pytorch-runtime

# Use the composed training environment
nix develop github:flox/ml-ai-lifecycle?dir=model-training
```

The `model-training` flake pulls in the other three as inputs with
`nixpkgs.follows` to ensure a single nixpkgs evaluation.

## What Each Layer Provides

| Layer | Flox | Nix | Key packages |
|-------|------|-----|--------------|
| `build-env` | `flox-labs/build-env` | `?dir=build-env` | gcc/clang, cmake, openssl, coreutils |
| `cuda-dev-essentials` | `flox-labs/cuda-dev-essentials` | `?dir=cuda-dev-essentials` | CUDA 12.9 (nvcc, cudnn, nccl, cublas) |
| `pytorch-runtime` | `flox-labs/pytorch-runtime` | `?dir=pytorch-runtime` | Python 3.13, PyTorch (CUDA on Linux) |
| `model-training` | `flox-labs/model-training` | `?dir=model-training` | All of the above + uv, datasets, transformers |
| `nanogpt-slurm` | — | — | Slurm job scripts (uses `model-training`) |

## Platform Support

| Layer | x86_64-linux | aarch64-linux | x86_64-darwin | aarch64-darwin |
|-------|:---:|:---:|:---:|:---:|
| `build-env` | Yes | Yes | Yes | Yes |
| `cuda-dev-essentials` | Yes | Yes | — | — |
| `pytorch-runtime` | Yes (CUDA) | Yes (CUDA) | Nix only (CPU) | Yes (MPS) |
| `model-training` | Yes | Yes | Yes | Yes |
