{
  description = "CUDA 12.9 development shell equivalent to flox manifest.toml";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

      cudaPkgsFor = system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
              cudaSupport = true;
            };
          };
        in
        {
          inherit pkgs;
          cudaPkgs = pkgs.cudaPackages_12_9;
        };

      cudaPackageList = cudaPkgs: [
        cudaPkgs.cuda_nvcc
        cudaPkgs.cuda_cudart
        cudaPkgs.libcublas
        cudaPkgs.cudnn
        cudaPkgs.cuda_cupti
        cudaPkgs.cuda_gdb
        cudaPkgs.cuda_sanitizer_api
        cudaPkgs.nccl
        cudaPkgs.libcutensor
      ];
    in
    {
      packages = forAllSystems (
        system:
        let
          inherit (cudaPkgsFor system) pkgs cudaPkgs;
        in
        {
          default = pkgs.symlinkJoin {
            name = "cuda-dev-essentials";
            paths = cudaPackageList cudaPkgs;
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          inherit (cudaPkgsFor system) pkgs cudaPkgs;
        in
        {
          default = pkgs.mkShell {
            packages = [ self.packages.${system}.default ];

            CUDA_ENV_VERSION = "12.9";

            shellHook = ''
              export CUDA_ENV_VERSION=12.9

              export CUDA_PATH=${cudaPkgs.cuda_nvcc}
              export CUDA_HOME=$CUDA_PATH

              export CPATH=${cudaPkgs.cuda_cudart}/include:${cudaPkgs.libcublas}/include:${cudaPkgs.cudnn}/include:${cudaPkgs.nccl}/include:${cudaPkgs.libcutensor}/include''${CPATH:+:$CPATH}

              export LIBRARY_PATH=${cudaPkgs.cuda_cudart}/lib:${cudaPkgs.libcublas}/lib:${cudaPkgs.cudnn}/lib:${cudaPkgs.cuda_cupti}/lib:${cudaPkgs.nccl}/lib:${cudaPkgs.libcutensor}/lib''${LIBRARY_PATH:+:$LIBRARY_PATH}

              export LD_LIBRARY_PATH=${cudaPkgs.cuda_cudart}/lib:${cudaPkgs.libcublas}/lib:${cudaPkgs.cudnn}/lib:${cudaPkgs.cuda_cupti}/lib:${cudaPkgs.nccl}/lib:${cudaPkgs.libcutensor}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

              echo "CUDA dev shell active"
              echo "CUDA_ENV_VERSION=$CUDA_ENV_VERSION"
              echo "CUDA_PATH=$CUDA_PATH"
            '';
          };
        }
      );
    };
}
