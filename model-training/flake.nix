{
  description = "ML training environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    build-env = {
      url = "github:flox/ml-ai-lifecycle?dir=build-env";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cuda-dev-essentials = {
      url = "github:flox/ml-ai-lifecycle?dir=cuda-dev-essentials";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pytorch-runtime = {
      url = "github:flox/ml-ai-lifecycle?dir=pytorch-runtime";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs
    , build-env
    , cuda-dev-essentials
    , pytorch-runtime
    , ...
    }:
    let
      lib = nixpkgs.lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      cudaSystems = [
        "x86_64-linux"

        # Add after testing on your target fleet:
        # "aarch64-linux"
      ];

      forAllSystems = f:
        lib.genAttrs systems f;

      isCudaSystem = system:
        builtins.elem system cudaSystems;

      pkgsFor = system:
        import nixpkgs {
          inherit system;

          config =
            {
              # Tutorial setting. Production configs can use
              # allowUnfreePredicate for a narrower unfree-package policy.
              allowUnfree = true;
            }
            // lib.optionalAttrs (isCudaSystem system) {
              # CUDA is selected at package-set import time.
              cudaSupport = true;

              # Optional: tune this list to the GPUs in your Slurm fleet.
              #
              # A100: cudaCapabilities = [ "8.0" ];
              # RTX 4090 / RTX 6000 Ada: cudaCapabilities = [ "8.9" ];
              # H100: cudaCapabilities = [ "9.0" ];
              #
              # Mixed fleet example:
              # cudaCapabilities = [ "8.0" "8.9" "9.0" ];
            };
        };

      getPackage = flake: system: name:
        if builtins.hasAttr "packages" flake
          && builtins.hasAttr system flake.packages
          && builtins.hasAttr name flake.packages.${system}
        then
          flake.packages.${system}.${name}
        else
          throw "Expected flake to expose packages.${system}.${name}";
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;

          buildTools =
            getPackage build-env system "default";

          pytorchRuntime =
            getPackage pytorch-runtime system "runtime";

          cudaTools =
            lib.optionals (isCudaSystem system) [
              (getPackage cuda-dev-essentials system "default")
            ];

          cudaPkgs =
            pkgs.cudaPackages;

          cudaRuntimeLibs =
            lib.optionals (isCudaSystem system) [
              pkgs.stdenv.cc.cc.lib
              cudaPkgs.cuda_cudart
              cudaPkgs.libcublas
              cudaPkgs.cudnn
              cudaPkgs.cuda_cupti
              cudaPkgs.nccl
            ];

          cudaIncludeDirs =
            lib.optionals (isCudaSystem system) [
              "${cudaPkgs.cuda_cudart}/include"
              "${cudaPkgs.libcublas}/include"
              "${cudaPkgs.cudnn}/include"
              "${cudaPkgs.nccl}/include"
            ];

          cudaLibraryDirs =
            lib.optionals (isCudaSystem system) [
              "${cudaPkgs.cuda_cudart}/lib"
              "${cudaPkgs.libcublas}/lib"
              "${cudaPkgs.cudnn}/lib"
              "${cudaPkgs.cuda_cupti}/lib"
              "${cudaPkgs.nccl}/lib"
            ];
        in
        {
          default = pkgs.mkShell {
            packages =
              [
                pkgs.uv
                buildTools
                pytorchRuntime
              ]
              ++ cudaTools;

            # Use the Python interpreter from the PyTorch runtime layer so the
            # venv can inherit torch and related runtime packages.
            PYTHON_FOR_VENV = "${pytorchRuntime}/bin/python3";

            shellHook = ''
              export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
              export NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
            ''
            + lib.optionalString (isCudaSystem system) ''
              export CUDA_HOME=${cudaPkgs.cuda_nvcc}
              export CUDA_PATH=$CUDA_HOME

              export LD_LIBRARY_PATH=${lib.makeLibraryPath cudaRuntimeLibs}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
              export CPATH=${lib.concatStringsSep ":" cudaIncludeDirs}''${CPATH:+:$CPATH}
              export LIBRARY_PATH=${lib.concatStringsSep ":" cudaLibraryDirs}''${LIBRARY_PATH:+:$LIBRARY_PATH}
            ''
            + ''
              export ML_TRAINING_CACHE="$PWD/.cache/ml-training"
              export ML_TRAINING_VENV="$ML_TRAINING_CACHE/venv"
              export UV_CACHE_DIR="$ML_TRAINING_CACHE/uv"
              export PIP_CACHE_DIR="$ML_TRAINING_CACHE/pip"

              mkdir -p "$ML_TRAINING_CACHE" "$UV_CACHE_DIR" "$PIP_CACHE_DIR"

              ml_training_setup() {
                venv="$ML_TRAINING_VENV"

                if [ ! -d "$venv" ]; then
                  uv venv "$venv" \
                    --python "$PYTHON_FOR_VENV" \
                    --system-site-packages || return 1
                fi

                if [ -f "$venv/bin/activate" ]; then
                  . "$venv/bin/activate"
                fi

                if [ ! -f "$ML_TRAINING_CACHE/.training_deps_installed" ]; then
                  uv pip install --python "$venv/bin/python" --quiet \
                    numpy datasets tokenizers transformers accelerate \
                    safetensors tensorboard scikit-learn tqdm pyyaml \
                    fastapi uvicorn || return 1

                  touch "$ML_TRAINING_CACHE/.training_deps_installed" || return 1
                fi

                python - <<'PY'
import torch

print("torch:", torch.__version__)
print("cuda available:", torch.cuda.is_available())

if torch.cuda.is_available():
    print("cuda device:", torch.cuda.get_device_name(0))

if hasattr(torch.backends, "mps"):
    print("mps available:", torch.backends.mps.is_available())
PY
              }

              ml_training_setup
            '';
          };
        });
    };
}
