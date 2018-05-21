{ nixpkgs ? builtins.fetchGit { url = https://github.com/NixOS/nixpkgs-channels.git; ref = "nixos-18.03"; }
, systems ? [ "x86_64-linux" "i686-linux" "x86_64-darwin" "aarch64-linux" ]
}:

let
  pkgs = import nixpkgs { system = builtins.currentSystem or "x86_64-linux"; };

  version = "2.1";
  nix = pkgs.fetchgit { #pkgs.fetchFromGitHub {
    #owner  = "NixOS";
    #repo   = "nix";
    url    = "https://github.com/NixOS/nix.git";
    rev    = "966407bcf1cf86de508b20fef43cffb81d8a87dc";
    sha256 = "1invpfvlmklkgrbh2p3asybknxrnb9h3vpnxgpr1k2hfsxkm2gsn";
  };

  overlays = [ import ./static-overlay.nix ];

in {

  build = pkgs.lib.genAttrs systems (system:
    let
      pkgs = import nixpkgs { inherit system; };
      staticPkgs = import ./static-packages.nix { inherit pkgs; };

      inherit (pkgs) lib stdenv;

    in stdenv.mkDerivation rec {
      name = "nix";
      src = nix;
      #src = tarball;

      nativeBuildInputs = with pkgs; [
        autoconf-archive
        autoreconfHook
        bison
        docbook5
        docbook5_xsl
        flex
        git
        help2man
        libxml2
        libxslt
        mercurial
        pkgconfig
      ];

      buildInputs = with staticPkgs;
        [ boehmgc
          boost
          brotli
          bzip2
          curl
          openssl
          sqlite
          xz
        ]
        ++ pkgs.lib.optional pkgs.stdenv.isLinux libseccomp
        ++ pkgs.lib.optionals (pkgs.stdenv.isLinux || pkgs.stdenv.isDarwin) [ aws-sdk-cpp libsodium ];

      configureFlags =
        [ "--disable-init-state"
          "--enable-gc"
          "--sysconfdir=/etc"
        ] ++ lib.optionals stdenv.isLinux [
          "--with-sandbox-shell=${pkgs.busybox-sandbox-shell}/bin/busybox"
        ];

      enableParallelBuilding = true;

      preBuild = "unset NIX_INDENT_MAKE";

      makeFlags = [
        "BUILD_SHARED_LIBS=0"
        "LDFLAGS=-static"
        "GLOBAL_LDFLAGS=-static -lnghttp2 -lssl -lcrypto"
      ];

      doCheck = false;

      installFlags = "sysconfdir=$(out)/etc";

      doInstallCheck = true;
      installCheckFlags = "sysconfdir=$(out)/etc";
    });

  # Lets us build individual dependencies
  pkgs = import ./static-packages.nix { inherit pkgs; };
}
