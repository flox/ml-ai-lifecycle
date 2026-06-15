{
  description = "Python 3.13 + PyTorch runtime base shared by dev, training, eval, CI, and container outputs";

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

      # CUDA is intentionally opt-in. Add systems here only after verifying
      # that torchWithCuda evaluates and builds for that system/pinned nixpkgs.
      cudaSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = f: lib.genAttrs systems f;

      pkgsFor = system: import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      isCudaSystem = system: builtins.elem system cudaSystems;

      torchFor = system: ps:
        if isCudaSystem system
        then ps.torchWithCuda
        else ps.torch;

      # Shared runtime layer.
      basePkgs = system: ps: [
        (torchFor system ps)
      ];

      # Training layer extends the shared runtime layer.
      trainingPkgs = system: ps: basePkgs system ps ++ [
        ps.tensorboard
        ps.wandb
      ];

      # Eval layer extends the shared runtime layer.
      evalPkgs = system: ps: basePkgs system ps ++ [
        # Add eval-specific deps here.
        # Example:
        # ps.mlflow
      ];

      # Dev layer extends the shared runtime layer.
      devPkgs = system: ps: basePkgs system ps ++ [
        ps.jupyter
        ps.ipython
      ];
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;

          pythonWith = layerFn:
            pkgs.python313.withPackages (layerFn system);

          runtime = pythonWith basePkgs;
          training = pythonWith trainingPkgs;
          evalEnv = pythonWith evalPkgs;
        in
        {
          runtime = runtime;
          training = training;
          eval = evalEnv;
          default = runtime;
        } // lib.optionalAttrs (isCudaSystem system) {
          container = pkgs.dockerTools.buildLayeredImage {
            name = "pytorch-runtime";
            tag = "latest";

            contents = [
              runtime
              pkgs.cacert
              pkgs.iana-etc
            ];

            config = {
              Cmd = [ "${runtime}/bin/python" ];

              Env = [
                "PATH=${runtime}/bin"
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
                "NVIDIA_VISIBLE_DEVICES=all"
                "NVIDIA_DRIVER_CAPABILITIES=compute,utility"
              ];
            };
          };
        }
      );

      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;

          pythonWith = layerFn:
            pkgs.python313.withPackages (layerFn system);

          runtime = pythonWith basePkgs;
          devEnv = pythonWith devPkgs;
        in
        {
          default = pkgs.mkShell {
            packages = [ devEnv ];

            shellHook = ''
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

          ci = pkgs.mkShell {
            packages = [ runtime ];
          };
        }
      );
    };
}
