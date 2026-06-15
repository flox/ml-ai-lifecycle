{
  description = "ML training environment comparable to the composed Flox environment";

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

      linuxSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f:
        lib.genAttrs systems f;

      pkgsFor = system:
        import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            cudaSupport = isLinux system;
          };
        };

      isLinux = system:
        builtins.elem system linuxSystems;

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
            lib.optionals (isLinux system) [
              (getPackage cuda-dev-essentials system "default")
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
            + lib.optionalString (isLinux system) (
              let cudaPkgs = pkgs.cudaPackages_12_9; in ''
              export LD_LIBRARY_PATH=${pkgs.gcc-unwrapped.lib}/lib:${cudaPkgs.cuda_cudart}/lib:${cudaPkgs.libcublas}/lib:${cudaPkgs.cudnn}/lib:${cudaPkgs.cuda_cupti}/lib:${cudaPkgs.nccl}/lib:${cudaPkgs.libcutensor}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

              export CPATH=${cudaPkgs.cuda_cudart}/include:${cudaPkgs.libcublas}/include:${cudaPkgs.cudnn}/include:${cudaPkgs.nccl}/include:${cudaPkgs.libcutensor}/include''${CPATH:+:$CPATH}

              export LIBRARY_PATH=${cudaPkgs.cuda_cudart}/lib:${cudaPkgs.libcublas}/lib:${cudaPkgs.cudnn}/lib:${cudaPkgs.cuda_cupti}/lib:${cudaPkgs.nccl}/lib:${cudaPkgs.libcutensor}/lib''${LIBRARY_PATH:+:$LIBRARY_PATH}

              export CUDA_PATH=${cudaPkgs.cuda_nvcc}
              export CUDA_HOME=$CUDA_PATH
            '')
            + ''
              export ML_TRAINING_CACHE="$PWD/.cache/ml-training"
              export ML_TRAINING_VENV="$ML_TRAINING_CACHE/venv"
              export UV_CACHE_DIR="$ML_TRAINING_CACHE/uv"
              export PIP_CACHE_DIR="$ML_TRAINING_CACHE/pip"

              mkdir -p "$ML_TRAINING_CACHE" "$UV_CACHE_DIR" "$PIP_CACHE_DIR"

              ml_training_setup() {
                set -euo pipefail

                venv="$ML_TRAINING_VENV"

                if [ ! -d "$venv" ]; then
                  uv venv "$venv" \
                    --python "$PYTHON_FOR_VENV" \
                    --system-site-packages
                fi

                if [ -f "$venv/bin/activate" ]; then
                  . "$venv/bin/activate"
                fi

                if [ ! -f "$ML_TRAINING_CACHE/.training_deps_installed" ]; then
                  uv pip install --python "$venv/bin/python" --quiet \
                    numpy datasets tokenizers transformers accelerate \
                    safetensors tensorboard scikit-learn tqdm pyyaml \
                    fastapi uvicorn

                  touch "$ML_TRAINING_CACHE/.training_deps_installed"
                fi
              }

              ml_training_setup
            '';
          };
        });
    };
}
