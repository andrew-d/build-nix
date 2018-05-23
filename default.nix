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

      # TODO: conditional
      prePatch = let
        inherit (pkgs.lib) getLib;

        in ''
          find . -name local.mk -exec \
            sed -Ei \
              -e 's|-laws-cpp-sdk-([^ ]+)|${getLib staticPkgs.aws-sdk-cpp}/lib/libaws-cpp-sdk-\1.a|g' \
              -e 's|-lbz2|${getLib staticPkgs.bzip2}/lib/libbz2.a|g' \
              -e 's|-lseccomp|${getLib staticPkgs.libseccomp}/lib/libseccomp.a|g' \
              -e 's|-l(boost_[^ ]+)|${getLib staticPkgs.boost}/lib/lib\1.a|g' \
              {} \;
        '';

      configureFlags =
        [ "--disable-init-state"
          "--enable-gc"
        ] ++ lib.optionals stdenv.isLinux [
          "--with-sandbox-shell=${pkgs.busybox-sandbox-shell}/bin/busybox"
        ];

      preConfigure = let
        inherit (pkgs.lib) getLib;

        in ''
          # Manually set library paths, since we may need spaces
          configureFlagsArray=(
            "BDW_GC_LIBS=${getLib staticPkgs.boehmgc}/lib/libgc.a"
            "LIBBROTLI_LIBS=${getLib staticPkgs.brotli}/lib/libbrotlidec-static.a ${getLib staticPkgs.brotli}/lib/libbrotlienc-static.a ${staticPkgs.brotli.lib}/lib/libbrotlicommon-static.a"
            "LIBCURL_LIBS=${getLib staticPkgs.curl}/lib/libcurl.a ${getLib staticPkgs.nghttp2}/lib/libnghttp2.a ${getLib staticPkgs.openssl}/lib/libssl.a ${getLib staticPkgs.openssl}/lib/libcrypto.a ${staticPkgs.zlib.static}/lib/libz.a"
            "LIBLZMA_LIBS=${getLib staticPkgs.xz}/lib/liblzma.a"
            ${if pkgs.stdenv.isLinux then "LIBSECCOMP_LIBS=${getLib staticPkgs.libseccomp}/lib/libseccomp.a" else ""}
            ${if (pkgs.stdenv.isLinux || pkgs.stdenv.isDarwin) then "SODIUM_LIBS=${getLib staticPkgs.libsodium}/lib/libsodium.a" else ""}
            "SQLITE3_LIBS=${getLib staticPkgs.sqlite}/lib/libsqlite3.a"
          )
        '';

      enableParallelBuilding = true;

      preBuild = "unset NIX_INDENT_MAKE";

      makeFlags = [
        "BUILD_SHARED_LIBS=0"
        #"LDFLAGS=-static"
        #"GLOBAL_LDFLAGS=-static -lnghttp2 -lssl -lcrypto"
        "V=1"
      ];

      doCheck = false;
      doInstallCheck = false;
    });

  # Lets us build individual dependencies
  pkgs = import ./static-packages.nix { inherit pkgs; };
}
