self: super:

let
  # Generic wrapper that builds a derivation statically
  makeStatic = (pkg: pkg.overrideAttrs (oldArgs: {
    dontDisableStatic = true;
    doCheck = false;

    # We probably won't have this for shared libraries.
    separateDebugInfo = false;

    configureFlags = if builtins.hasAttr "configureFlags" oldArgs
                      then oldArgs.configureFlags ++ ["--disable-shared" "--enable-static"]
                      else null;
  }));

in {

  aws-sdk-cpp = (super.aws-sdk-cpp.override {
    #inherit (self) curl openssl zlib;

    apis = ["s3" "transfer"];
    customMemoryManagement = false;

  }).overrideAttrs (oldArgs: {
    cmakeFlags = oldArgs.cmakeFlags ++ [
      "-DBUILD_SHARED_LIBS=OFF"
      "-DENABLE_TESTING=OFF"
    ];
  });

  boost = (super.boost.override {
    enableShared = false;
    enableStatic = true;

    enableRelease = true;
    enableDebug   = false;
  }).overrideAttrs (oldArgs: {
    # From: https://stackoverflow.com/a/29444881
    buildPhase = let
      newArgs = #builtins.replaceStrings
      #  ["variant=release"]
      #  ["variant=release address-model=64 architecture=x86 --layout=tagged"]
        oldArgs.buildPhase;

    in ''
      echo "build command is: ${super.lib.escapeShellArg newArgs}"
      ${newArgs}
    '';
  });

  curl = makeStatic (super.curl.override {
    #inherit (self) nghttp2 openssl zlib;

    sslSupport = true;
    scpSupport = false;
    gssSupport = false;
  });

  nghttp2 = makeStatic (super.nghttp2.override {
    #inherit (self) openssl zlib;
  });

  openssl = super.openssl.overrideAttrs (oldArgs: {
    dontDisableStatic = true;
    doCheck = false;

    configureFlags = remove "shared" oldArgs.configureFlags ++ ["no-shared"];
    installFlags = ["install_sw"];
  });

  zlib = super.zlib.override {
    static = true;
  };

  # General static overrides
  boehmgc = makeStatic super.boehmgc;
  brotli = makeStatic super.brotli;
  bzip2 = makeStatic super.bzip2;
  libseccomp = makeStatic super.libseccomp;
  libsodium = makeStatic super.libsodium;
  sqlite = makeStatic super.sqlite;
  xz = makeStatic super.xz;
}
