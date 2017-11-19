{ lib
, localSystem, crossSystem, config, overlays
} @ args:

assert crossSystem != null;

let
  bootStages = import "${(import ./nixpkgs {}).path}/pkgs/stdenv" {
    inherit lib localSystem overlays;
    crossSystem = null;
    # Ignore custom stdenvs when cross compiling for compatability
    config = builtins.removeAttrs config [ "replaceStdenv" ];
  };

in bootStages ++ [

  # Build Packages
  (vanillaPackages: {
    inherit config overlays;
    selfBuild = false;
    stdenv = vanillaPackages.stdenv.override (oldStdenv: {
      targetPlatform = crossSystem;
    });
  })

  # Run Packages
  (toolPackages: let
    prefix = "${crossSystem.config}-";
    llvmPackages = toolPackages.llvmPackages_HEAD;
    mkClang = { libc ? null, ccFlags ? null }: toolPackages.wrapCCWith {
      name = "clang-cross-wrapper";
      cc = llvmPackages.clang-unwrapped;
      binutils = toolPackages.wrapBinutilsWith {
        binutils = llvmPackages.llvm-binutils;
        inherit libc;
      };
      inherit libc;
      extraBuildCommands = ''
        # We don't yet support C++
        # https://github.com/WebGHC/wasm-cross/issues/1
        echo "-target ${crossSystem.config} -nostdlib++" >> $out/nix-support/cc-cflags
        # Clang's wasm backend assumes the presence of a working
        # lld (optionally with prefix). We symlink it here to get
        # a wrapper version.
        ln -s $out/bin/${prefix}ld $out/bin/${prefix}lld

        # Something about the way clang is handled on macOS makes
        # this necessary even on Linux.
        echo 'export CC=${prefix}cc' >> $out/nix-support/setup-hook
        echo 'export CXX=${prefix}c++' >> $out/nix-support/setup-hook
      '' + toolPackages.lib.optionalString (ccFlags != null) ''
        echo "${ccFlags}" >> $out/nix-support/cc-cflags
      '' + toolPackages.lib.optionalString (crossSystem.fpu or null != null) ''
        echo "-mfpu=${crossSystem.fpu}" >> $out/nix-support/cc-cflags
      '' + toolPackages.lib.optionalString (crossSystem.arch == "wasm32") ''
        echo "--allow-undefined -entry=main" >> $out/nix-support/cc-ldflags
        echo "-nostartfiles" >> $out/nix-support/cc-cflags
      '';
    };
    mkStdenv = cc: let x = toolPackages.makeStdenvCross {
      inherit (toolPackages) stdenv;
      buildPlatform = localSystem;
      hostPlatform = crossSystem;
      targetPlatform = crossSystem;
      inherit cc;
    }; in x // {
      mkDerivation = args: x.mkDerivation (args // {
        hardeningDisable = args.hardeningDisable or []
          ++ ["stackprotector"]
          ++ toolPackages.lib.optional (crossSystem.arch == "wasm32") "pic";
        dontDisableStatic = true;
        NIX_NO_SELF_RPATH=1;
        configureFlags =
          (let flags = args.configureFlags or [];
            in if builtins.isString flags then [flags] else flags)
          ++ toolPackages.lib.optionals (!(args.dontConfigureStatic or false)) ["--enable-static" "--disable-shared"];
      });
      isStatic = true;
    };

    clangCross-noLibc = mkClang {
      ccFlags = "-nostdinc -nodefaultlibs";
    };
    clangCross-noCompilerRt = mkClang {
      libc = musl-cross;
      ccFlags = "-nodefaultlibs -lc";
    };
    clangCross = mkClang {
      ccFlags = "-rtlib=compiler-rt -resource-dir ${compiler-rt}";
      libc = musl-cross;
    };

    stdenv-noLibc = mkStdenv clangCross-noLibc;
    stdenv-noCompilerRt = mkStdenv clangCross-noCompilerRt;

    musl-cross = toolPackages.callPackage ./musl-cross.nix {
      hostPlatform = crossSystem;
      stdenv = stdenv-noLibc;
    };
    compiler-rt = toolPackages.llvmPackages.compiler-rt.override {
      baremetal = true;
      hostPlatform = crossSystem;
      stdenv = stdenv-noCompilerRt;
    };
  in {
    inherit config;
    overlays = overlays ++ [
      (self: super: {
        inherit compiler-rt musl-cross clangCross-noLibc clangCross-noCompilerRt clangCross;
      })
      (import ./cross-overlays.nix args)
    ];
    selfBuild = false;
    stdenv = mkStdenv clangCross;
  })

]
