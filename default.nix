{ debugLlvm ? false }:

(import ./nixpkgs {}).lib.makeExtensible (project: {
  nixpkgsArgs = {
    overlays = [(self: super: {
      fib-example = self.callPackage ./fib-example {};

      hello-example = self.callPackage ./hello-example {};
      free-example = self.callPackage ./free-example {};


      llvmPackages_HEAD = self.callPackage ./llvm-head {
        buildTools = self.buildPackages.llvmPackages_HEAD;
        debugVersion = debugLlvm;
      };

      llvmPackages = self.llvmPackages_HEAD;

      wabt = self.callPackage ./wabt.nix {};

      build-wasm-app = www: drv: self.buildEnv {
        name = "wasm-app-${drv.name}";
        paths = [
          www
          "${self.musl-cross.src}/arch/wasm32/js"
          "${drv}/bin"
        ];

        passthru = { inherit drv; };
      };
    })];
  };
  nixpkgsCrossArgs = project.nixpkgsArgs // {
    stdenvStages = import ./cross.nix;
  };

  nixpkgs = import ./nixpkgs project.nixpkgsArgs;
  nixpkgsWasm = import ./nixpkgs (project.nixpkgsCrossArgs // {
    crossSystem = {
      config = "wasm32-unknown-unknown-wasm";
      arch = "wasm32";
      libc = null;
      disableDynamicLinker = true;
      thread-model = "single";
      # target-cpu = "bleeding-edge";
      entry = "main";
    };
  });
  nixpkgsArm = import ./nixpkgs (project.nixpkgsCrossArgs // {
    crossSystem = (import "${(import ./nixpkgs {}).path}/lib/systems/examples.nix" { inherit (project.nixpkgs) lib; }).aarch64-multiplatform;
  });
  nixpkgsRpi = import ./nixpkgs (project.nixpkgsCrossArgs // {
    crossSystem = (import "${(import ./nixpkgs {}).path}/lib/systems/examples.nix" { inherit (project.nixpkgs) lib; }).raspberryPi // { disableDynamicLinker = true; };
  });
})
