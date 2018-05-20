{ pkgs }:

let
  inherit (pkgs.lib.attrsets) mapAttrs;
  inherit (pkgs.lib.lists) remove unique;
  inherit (pkgs.lib.strings) concatMapStrings;

  ##makeStaticDerivation = (deriv: let
  ##    nonStatic = deriv.overrideAttrs (oldArgs: {
  ##      dontDisableStatic = true;
  ##      doCheck = false;
  ##    });
  ##  
  ##  in pkgs.stdenv.mkDerivation rec {
  ##    name = deriv.name + "-static";

  ##    phases = [ "installPhase" ];

  ##    installPhase = let
  ##      debug = false;

  ##      startDebug = if debug then "set -x" else "";
  ##      endDebug = if debug then "set +x" else "";

  ##      # Finds all outputs for a package.
  ##      packageOutputs = pkg: unique
  ##        [pkg]
  ##        ++ (if builtins.hasAttr "outputs" pkg then map (a: builtins.getAttr a pkg) pkg.outputs else [])
  ##        ++ (if builtins.hasAttr "out" pkg then [pkg.out] else []);

  ##      # Copies files that we care about to our output directory
  ##      copyFiles = (pkg: 
  ##        ''
  ##          if [[ -d "${pkg}/include" ]]; then
  ##            cp -avR "${pkg}/include" "$out/"
  ##          fi

  ##          if [[ -n "$(echo "${pkg}"/lib/*.a)" ]]; then
  ##            mkdir -p "$out/lib"

  ##            for libfile in "${pkg}"/lib/*.a; do
  ##              if [[ ! -e "$out/lib/$(basename "$libfile")" ]]; then
  ##                cp -av "$libfile" "$out/lib/"
  ##              fi
  ##            done
  ##          fi
  ##        '');

  ##      ### Helper function that will run copyFiles on an attr of a given input
  ##      ##copyFilesAttr = (pkg: attr:
  ##      ##  if (builtins.hasAttr attr pkg) then
  ##      ##    copyFiles (builtins.getAttr attr pkg)
  ##      ##  else
  ##      ##    "");

  ##      ### Helper function that will copy from all outputs, or if the "outputs"
  ##      ### attribute isn't set, the "out" attribute.
  ##      ##copyFilesOutputs = pkg:
  ##      ##  if builtins.hasAttr "outputs" pkg
  ##      ##    then concatMapStrings (out: copyFilesAttr pkg out) pkg.outputs
  ##      ##    else copyFilesAttr pkg "out";

  ##      in ''
  ##        ${startDebug}
  ##        mkdir -p "$out"

  ##      ''
  ##      + builtins.concatStringsSep "\n" (map copyFiles (packageOutputs nonStatic))
  ##      + ''
  ##        ${endDebug}
  ##      '';

  ##    ##doInstallCheck = true;
  ##    ##installCheck = ''
  ##    ##  # TODO
  ##    ##'';
  ##  });

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

  # Custom packages that need further configuration
  customPackages = rec {
    zlib = pkgs.zlib.override {
      static = true;
    };

    openssl = pkgs.openssl.overrideAttrs (oldArgs: {
      dontDisableStatic = true;
      doCheck = false;

      configureFlags = remove "shared" oldArgs.configureFlags ++ ["no-shared"];
      installFlags = ["install_sw"];
    });

    boost = (pkgs.boost.override {
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
        echo "build command is: ${pkgs.lib.escapeShellArg newArgs}"
        ${newArgs}
      '';
    });

    nghttp2 = makeStatic (pkgs.nghttp2.override {
      inherit openssl zlib;
    });

    curl = makeStatic (pkgs.curl.override {
      inherit nghttp2 openssl zlib;

      sslSupport = true;
      scpSupport = false;
      gssSupport = false;
    });

    # TODO: ++ lib.optional (stdenv.isLinux || stdenv.isDarwin); ?
    aws-sdk-cpp = (pkgs.aws-sdk-cpp.override {
      inherit curl openssl zlib;

      apis = ["s3" "transfer"];
      customMemoryManagement = false;
    }).overrideAttrs (oldArgs: {
      cmakeFlags = oldArgs.cmakeFlags ++ [
        "-DBUILD_SHARED_LIBS=OFF"
        "-DENABLE_TESTING=OFF"
      ];
    });
  };

  # Non-static build dependencies (e.g. git)
  nonStaticBuildDeps = {
    inherit (pkgs) git mercurial pkgconfig;
  };

  # Build dependencies that are libraries (and should be built statically).
  # Keep this in sync with the list in release-common.nix
  libDeps = with pkgs;
    [ boehmgc
      brotli
      bzip2
      sqlite
      xz

      # The following dependencies are more custom; see above
      #curl
      #boost
      #openssl
    ]
    ++ lib.optional stdenv.isLinux libseccomp
    ++ lib.optional (stdenv.isLinux || stdenv.isDarwin) libsodium;

  # The library build deps, transformed into static ones.
  staticBuildDeps = builtins.listToAttrs (
    map (pkg: {
      name = (builtins.parseDrvName pkg.name).name;
      value = makeStatic pkg;
    }) libDeps
  );

  allDeps = nonStaticBuildDeps // staticBuildDeps // customPackages;

# in builtins.trace allDeps allDeps
in allDeps
