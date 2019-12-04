let
  pkgs = import (fetchTarball {
    url = https://github.com/NixOS/nixpkgs/archive/d5291756487d70bc336e33512a9baf9fa1788faf.tar.gz;
    sha256 = "0mhqhq21y5vrr1f30qd2bvydv4bbbslvyzclhw0kdxmkgg3z4c92";
  });
  pkgsNative = pkgs {};
  pkgsAndroid = pkgs {
    crossSystem = pkgsNative.lib.systems.examples.armv7a-android-prebuilt;
  };
  pkgsAndroidx86 = pkgs {
    crossSystem = x86-android-prebuilt;
  };
  pkgsAndroidx64 = pkgs {
    crossSystem = pkgsNative.lib.systems.examples.aarch64-android-prebuilt;
  };

  x86-android-prebuilt = {
    config = "i686-unknown-linux-android";
    sdkVer = "24";
    ndkVer = "18b";
    platform = {
      name = "x86";
      gcc = {
        arch = "i686";
        #float-abi = "softfp";
        fpu = "vfpv3-d16";
      };
    };
    useAndroidPrebuilt = true;
  };

  native = pkgsNative.callPackage ./nimbus-wrappers.nix { suffix = "x86_64"; nim-x-compile-flag = ""; };
  crossAndroid = pkgsAndroid.callPackage ./nimbus-wrappers.nix {
    inherit (pkgsAndroid.buildPackages) go nim;
    suffix = "android-arm";
    nim-x-compile-flag = "--cpu=arm";
    llvmTargetTriple = pkgsNative.lib.systems.examples.armv7a-android-prebuilt.config;
    buildDynamic = false;
    buildSamples = false;
  };
  crossAndroidx86 = pkgsAndroidx86.callPackage ./nimbus-wrappers.nix {
    inherit (pkgsAndroidx86.buildPackages) go nim;
    suffix = "android-x86";
    nim-x-compile-flag = "--cpu=i386";
    llvmTargetTriple = x86-android-prebuilt.config;
    buildDynamic = false;
    buildSamples = false;
  };
  crossAndroidx64 = pkgsAndroidx64.callPackage ./nimbus-wrappers.nix {
    inherit (pkgsAndroidx64.buildPackages) go nim;
    suffix = "android-arm64";
    nim-x-compile-flag = "--cpu=arm64";
    llvmTargetTriple = pkgsNative.lib.systems.examples.aarch64-android-prebuilt.config;
    buildDynamic = false;
    buildSamples = false;
  };

in {
  wrappers-native = native;
  wrappers-android = {
    arm = crossAndroid;
    arm64 = crossAndroidx64;
    x86 = crossAndroidx86;
  };
}
