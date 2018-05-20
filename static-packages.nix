{ pkgs }:

let
  inherit (pkgs) lib;

  # Generic wrapper that builds a derivation statically
  makeStatic = pkg: pkg.overrideAttrs (oldArgs: {
    dontDisableStatic = true;
    doCheck = false;

    # We probably won't have this for shared libraries.
    separateDebugInfo = false;

    configureFlags = if builtins.hasAttr "configureFlags" oldArgs
      then (
        if lib.isString oldArgs.configureFlags
          then oldArgs.configureFlags + "--disable-shared --enable-static"
        else if lib.isList oldArgs.configureFlags
          then oldArgs.configureFlags ++ ["--disable-shared" "--enable-static"]
        else throw "Unknown type for 'configureFlags'"
      )
      else ["--disable-shared" "--enable-static"];
  });

  pkgset = rec {
    aws-sdk-cpp = (pkgs.aws-sdk-cpp.override {
      inherit (pkgset) curl openssl zlib;

      apis = ["s3" "transfer"];
      customMemoryManagement = false;

    }).overrideAttrs (oldArgs: {
      cmakeFlags = oldArgs.cmakeFlags ++ [
        "-DBUILD_SHARED_LIBS=OFF"
        "-DENABLE_TESTING=OFF"
      ];
    });

    boost = (pkgs.boost.override {
      inherit (pkgset) bzip2 libiconv zlib;

      enableShared = false;
      enableStatic = true;

      enableRelease = true;
      enableDebug   = false;
    }).overrideAttrs (oldArgs: let
        # From: https://stackoverflow.com/a/29444881
        replace = builtins.replaceStrings
          ["runtime-link=static"]
          ["address-model=64 architecture=x86"];

      in {
        buildPhase = replace oldArgs.buildPhase;
        installPhase = replace oldArgs.installPhase;
      });

    bzip2 = pkgs.bzip2.override { linkStatic = true; };

    curl = makeStatic (pkgs.curl.override {
      inherit (pkgset) libssh2 nghttp2 openssl zlib;

      sslSupport = true;
      scpSupport = false;
      gssSupport = false;
    });

    libssh2 = makeStatic (pkgs.libssh2.override {
      inherit (pkgset) openssl zlib;
    });

    nghttp2 = makeStatic (pkgs.nghttp2.override {
      inherit (pkgset) openssl zlib;
    });

    openssl = pkgs.openssl.overrideAttrs (oldArgs: {
      dontDisableStatic = true;
      doCheck = false;

      configureFlags = lib.remove "shared" oldArgs.configureFlags ++ [
        "no-shared"
        "no-dso"
      ];
      installFlags = ["install_sw"];
    });

    zlib = pkgs.zlib.override { static = true; };

    # General static overrides
    boehmgc = makeStatic pkgs.boehmgc;
    brotli = makeStatic pkgs.brotli;
    expat = makeStatic pkgs.expat;
    icu = makeStatic pkgs.icu;
    libiconv = makeStatic pkgs.libiconv;
    libseccomp = makeStatic pkgs.libseccomp;
    libsodium = makeStatic pkgs.libsodium;
    sqlite = makeStatic pkgs.sqlite;
    xz = makeStatic pkgs.xz;
  };

in pkgset
