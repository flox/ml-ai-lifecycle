{
  description = "Cross-platform development shell equivalent to flox manifest.toml";

  inputs = {
    # Pin this to a specific revision if you need the exact glibc 2.38-44 build.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

      isLinux = system: nixpkgs.lib.hasSuffix "-linux" system;
      isDarwin = system: nixpkgs.lib.hasSuffix "-darwin" system;
      isAarch64Darwin = system: system == "aarch64-darwin";
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
          };

          lib = pkgs.lib;

          commonPackages = with pkgs; [
            bash
            coreutils
            gnumake
            cmake
            pkg-config
            openssl
            cacert
          ];

          linuxPackages = with pkgs; [
            gcc
            gcc-unwrapped
            glibc
          ];

          darwinPackages = with pkgs; [
            clang
            gnused
            gawk
          ];

          aarch64DarwinPackages = with pkgs; [
            libiconv
          ];
        in
        {
          default = pkgs.symlinkJoin {
            name = "build-env";
            paths =
              commonPackages
              ++ lib.optionals (isLinux system) linuxPackages
              ++ lib.optionals (isDarwin system) darwinPackages
              ++ lib.optionals (isAarch64Darwin system) aarch64DarwinPackages;
          };
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
          };

          lib = pkgs.lib;
        in
        {
          default = pkgs.mkShell {
            packages = [ self.packages.${system}.default ];

            shellHook = ''
              export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
              export NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
            ''
            + lib.optionalString (isLinux system) ''
              export LD_LIBRARY_PATH=${pkgs.gcc-unwrapped.lib}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
            ''
            + lib.optionalString (isDarwin system) ''
              export PATH=${pkgs.gnused}/bin:${pkgs.gawk}/bin:$PATH
            ''
            + lib.optionalString (isAarch64Darwin system) ''
              export LIBRARY_PATH=${pkgs.libiconv}/lib''${LIBRARY_PATH:+:$LIBRARY_PATH}
              export CPATH=${pkgs.libiconv}/include''${CPATH:+:$CPATH}
            '';
          };
        }
      );
    };
}
