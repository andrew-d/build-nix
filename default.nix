{ nixpkgs ? builtins.fetchGit { url = https://github.com/NixOS/nixpkgs-channels.git; ref = "nixos-18.03"; }
, systems ? [ "x86_64-linux" "i686-linux" "x86_64-darwin" "aarch64-linux" ]
}:

let
  pkgs = import nixpkgs { system = builtins.currentSystem or "x86_64-linux"; };

  nix = pkgs.fetchFromGitHub {
    owner  = "NixOS";
    repo   = "nix";
    rev    = "966407bcf1cf86de508b20fef43cffb81d8a87dc";
    sha256 = "1yhzklq58816kik9w8xss481wf9mk8mi9sfvk03ghdxi2q0fi0ci";
  };

  #staticDeps = import ./static-deps.nix { inherit pkgs; };
  overlays = [ import ./static-overlay.nix ];

in {

  build = pkgs.lib.genAttrs systems (system:
    let
      pkgs = import nixpkgs {
        inherit system;
        config.packageOverrides = import ./static-override.nix;
      };
      #pkgs = import nixpkgs { inherit overlays system; };
      inherit (pkgs) lib stdenv;

    in stdenv.mkDerivation rec {
      name = "nix";
      src = nix;

      buildInputs = with pkgs;
        [ curl
          bzip2 xz brotli
          openssl pkgconfig sqlite boehmgc
          boost

          # Tests
          git
          mercurial
        ]
        ++ lib.optional stdenv.isLinux libseccomp
        ++ lib.optionals (stdenv.isLinux || stdenv.isDarwin) [ aws-sdk-cpp libsodium ];

      configureFlags =
        [ "--disable-init-state"
          "--enable-gc"
          "--sysconfdir=/etc"
        ] ++ lib.optionals stdenv.isLinux [
          "--with-sandbox-shell=${pkgs.busybox-sandbox-shell}/bin/busybox"
        ];

      enableParallelBuilding = true;

      preBuild = "unset NIX_INDENT_MAKE";

      doCheck = false;

      installFlags = "sysconfdir=$(out)/etc";

      doInstallCheck = true;
      installCheckFlags = "sysconfdir=$(out)/etc";
    });

  # Lets us build individual dependencies
  pkgs = import nixpkgs {
    system = builtins.currentSystem or "x86_64-linux";
    config.packageOverrides = import ./static-override.nix;
  };
}
