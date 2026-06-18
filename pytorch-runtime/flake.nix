{
  description = "Cross-platform Python 3.13 + PyTorch runtime shared by dev, training, eval, CI, and container outputs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }:
    let
      lib = nixpkgs.lib;

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      # Enable CUDA only on Linux systems where you have validated the build.
      # Start with x86_64-linux for common Slurm, DGX, A100, H100, and RTX fleets.
      cudaSystems = [
        "x86_64-linux"

        # Add after validation on your target fleet:
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
              # allowUnfreePredicate to admit only the needed CUDA packages.
              allowUnfree = true;
            }
            // lib.optionalAttrs (isCudaSystem system) {
              # CUDA is selected at package-set import time.
              # Do not select pythonPackages.torchWithCuda from a non-CUDA
              # package set.
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

      pythonFor = pkgs:
        pkgs.python313;

      pythonEnvFor = pkgs: layerFn:
        (pythonFor pkgs).withPackages layerFn;

      runtimePkgs = ps: [
        # On CUDA-enabled Linux package sets, this resolves to CUDA-enabled
        # PyTorch because pkgs was imported with config.cudaSupport = true.
        #
        # On Darwin and non-CUDA Linux package sets, this resolves to the
        # default PyTorch build for that platform.
        ps.torch
      ];

      trainingPkgs = ps:
        runtimePkgs ps ++ [
          ps.tensorboard
          ps.wandb
        ];

      evalPkgs = ps:
        runtimePkgs ps ++ [
          # Add eval-specific Python packages here.
          # ps.mlflow
        ];

      devPkgs = ps:
        runtimePkgs ps ++ [
          ps.ipython
          ps.jupyter
        ];

      runtimeCheckFor = pkgs:
        pkgs.writeShellApplication {
          name = "check-pytorch-runtime";

          runtimeInputs = [
            (pythonEnvFor pkgs runtimePkgs)
          ];

          text = ''
            python - <<'PY'
import torch

print("torch:", torch.__version__)
print("cuda available:", torch.cuda.is_available())

if torch.cuda.is_available():
    print("cuda device:", torch.cuda.get_device_name(0))

if hasattr(torch.backends, "mps"):
    print("mps available:", torch.backends.mps.is_available())
PY
          '';
        };
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;

          runtime = pythonEnvFor pkgs runtimePkgs;
          training = pythonEnvFor pkgs trainingPkgs;
          evalEnv = pythonEnvFor pkgs evalPkgs;
          runtimeCheck = runtimeCheckFor pkgs;
        in
        {
          inherit runtime training runtimeCheck;

          eval = evalEnv;
          default = runtime;
        }
        // lib.optionalAttrs (isCudaSystem system) {
          container = pkgs.dockerTools.buildLayeredImage {
            name = "pytorch-runtime";
            tag = "latest";

            contents = [
              runtime
              pkgs.bashInteractive
              pkgs.cacert
              pkgs.coreutils
              pkgs.iana-etc
            ];

            config = {
              Cmd = [ "${runtime}/bin/python" ];

              Env = [
                "PATH=${runtime}/bin:${pkgs.coreutils}/bin"
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                "NVIDIA_VISIBLE_DEVICES=all"
                "NVIDIA_DRIVER_CAPABILITIES=compute,utility"
              ];
            };
          };
        });

      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;

          runtime = pythonEnvFor pkgs runtimePkgs;
          devEnv = pythonEnvFor pkgs devPkgs;
          runtimeCheck = runtimeCheckFor pkgs;

          # Use CUDA libraries from this same pkgs instance. Do not hard-code
          # pkgs.cudaPackages_12_x here unless the whole package set has been
          # configured around that CUDA version.
          cudaDevPkgs =
            lib.optionals (isCudaSystem system) [
              pkgs.cudaPackages.cuda_nvcc
              pkgs.cudaPackages.cuda_cudart
              pkgs.cudaPackages.libcublas
              pkgs.cudaPackages.cudnn
              pkgs.cudaPackages.nccl
              pkgs.cudaPackages.cuda_cupti
            ];

          cudaLibraryPath =
            lib.optionals (isCudaSystem system) [
              pkgs.stdenv.cc.cc.lib
              pkgs.cudaPackages.cuda_cudart
              pkgs.cudaPackages.libcublas
              pkgs.cudaPackages.cudnn
              pkgs.cudaPackages.nccl
              pkgs.cudaPackages.cuda_cupti
            ];
        in
        {
          default = pkgs.mkShell {
            packages =
              [
                devEnv
                runtimeCheck
                pkgs.uv
              ]
              ++ cudaDevPkgs;

            shellHook = ''
              export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
              export NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
            ''
            + lib.optionalString (isCudaSystem system) ''
              export CUDA_HOME=${pkgs.cudaPackages.cuda_nvcc}
              export CUDA_PATH=$CUDA_HOME
              export LD_LIBRARY_PATH=${lib.makeLibraryPath cudaLibraryPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
            ''
            + ''
              check-pytorch-runtime
            '';
          };

          ci = pkgs.mkShell {
            packages = [
              runtime
              runtimeCheck
            ];
          };
        });

      apps = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          runtimeCheck = runtimeCheckFor pkgs;
        in
        {
          check = {
            type = "app";
            program = "${runtimeCheck}/bin/check-pytorch-runtime";
          };

          default = {
            type = "app";
            program = "${runtimeCheck}/bin/check-pytorch-runtime";
          };
        });
    };
}

