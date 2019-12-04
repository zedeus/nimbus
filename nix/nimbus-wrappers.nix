{ stdenv, callPackage, fetchFromGitHub, binutils, clang, go, nim, pcre, sqlite,
  llvmTargetTriple ? "", buildSamples ? true, suffix, nim-x-compile-flag ? "", buildStatic ? true, buildDynamic ? true }:

let
  inherit (stdenv.lib) concatMapStringsSep makeLibraryPath optional optionalString;

  mkFilter = callPackage ./mkFilter.nix { inherit (stdenv) lib; };
  vendorDeps = [
    "nim-chronicles" "nim-faststreams" "nim-json-serialization" "nim-chronos" "nim-eth" "nim-json"
    "nim-metrics" "nim-secp256k1" "nim-serialization" "nim-stew" "nim-stint" "nimcrypto"
  ];
  compiler = "clang";
  crossCompiling = llvmTargetTriple != "";
  CC = if crossCompiling then "${stdenv.cc}/bin/${llvmTargetTriple}-${compiler}" else "${clang}/bin/${compiler}";
  OBJCOPY = if crossCompiling then "${stdenv.cc.bintools.bintools}/bin/${llvmTargetTriple}-objcopy" else "${binutils.bintools}/bin/objcopy";
  # Remove metrics for Android as it causes an undefined symbol `__fwrite_chk` when linking with status-go
  nim-flags = optionalString crossCompiling ''-u:metrics --cc:${compiler} --${compiler}.exe="${CC}" --${compiler}.linkerexe:"${CC}"'';

in

stdenv.mkDerivation rec {
  pname = "nimbus-${suffix}";
  version = "0.0.1";
  src =
    let path = ./..; # Import the root /android and /mobile/js_files folders clean of any build artifacts
    in builtins.path { # We use builtins.path so that we can name the resulting derivation, otherwise the name would be taken from the checkout directory, which is outside of our control
      inherit path;
      name = "nimbus-sources";
      filter =
        # Keep this filter as restrictive as possible in order to avoid unnecessary rebuilds and limit closure size
        mkFilter {
          dirRootsToInclude = [
            "vendor" "wrappers"
          ];
          dirsToExclude = [ ".git" ".svn" "CVS" ".hg" "nimbus-build-system" "tests" ]
            ++ (builtins.map (dep: "vendor/${dep}") vendorDeps);
          filesToInclude = [ "nim.cfg" ];
          filesToExclude = [ "VERSION" "android/gradlew" ];
          root = path;
        };
    };
  nativeBuildInputs = [ nim ] ++ optional buildSamples go;
  buildInputs = [ pcre sqlite ];
  inherit CC;
  LD_LIBRARY_PATH = "${makeLibraryPath buildInputs}";

  buildPhase = ''
    mkdir -p ./build

    BUILD_MSG="\\e[92mBuilding:\\e[39m"

    ln -s nimbus.nimble nimbus.nims

    vendorPathOpts="${concatMapStringsSep " " (dep: "--path:./vendor/${dep}") vendorDeps}"
    ${optionalString buildDynamic ''
    mkdir -p $TMPDIR/.nimcache

    echo -e $BUILD_MSG "build/libnimbus.so" && \
      ${nim}/bin/nim compile --app:lib --noMain ${nim-x-compile-flag} ${nim-flags} --nimcache:$TMPDIR/.nimcache ''${vendorPathOpts} -o:./build/libnimbus.so wrappers/libnimbus.nim
    rm -rf $TMPDIR/.nimcache
    ''}
    ${optionalString buildStatic ''
    mkdir -p $TMPDIR/.nimcache_static

    echo -e $BUILD_MSG "build/libnimbus.a" && \
      ${nim}/bin/nim compile ${nim-x-compile-flag} ${nim-flags} --app:staticlib --noMain --nimcache:$TMPDIR/.nimcache_static ''${vendorPathOpts} -o:build/libnimbus.a wrappers/libnimbus.nim && \
      [[ -e "libnimbus.a" ]] && mv "libnimbus.a" build/ # workaround for https://github.com/nim-lang/Nim/issues/12745
    # Localize secp256k1 symbols so that the library is usable with other static libraries that import the secp256k1 library
    ${optionalString (!crossCompiling) ''
    ${OBJCOPY} -L secp256k1_context_create -L secp256k1_context_clone -L secp256k1_context_destroy -L secp256k1_context_set_illegal_callback -L secp256k1_context_set_error_callback -L secp256k1_ec_pubkey_parse -L secp256k1_ec_pubkey_serialize -L secp256k1_ecdsa_signature_parse_der -L secp256k1_ecdsa_signature_parse_compact -L secp256k1_ecdsa_signature_serialize_der -L secp256k1_ecdsa_signature_serialize_compact -L secp256k1_ecdsa_signature_normalize -L secp256k1_ecdsa_verify -L secp256k1_ecdsa_sign -L secp256k1_ec_seckey_verify -L secp256k1_ec_pubkey_create -L secp256k1_ec_privkey_tweak_add -L secp256k1_ec_pubkey_tweak_add -L secp256k1_ec_privkey_tweak_mul -L secp256k1_ec_pubkey_tweak_mul -L secp256k1_context_randomize -L secp256k1_ec_pubkey_combine -L secp256k1_ecdsa_recoverable_signature_parse_compact -L secp256k1_ecdsa_recoverable_signature_serialize_compact -L secp256k1_ecdsa_recoverable_signature_convert -L secp256k1_ecdsa_sign_recoverable -L secp256k1_ecdsa_recover -L secp256k1_nonce_function_default -L secp256k1_nonce_function_rfc6979 -L CURVE_B \
      build/libnimbus.a''}
    rm -rf $TMPDIR/.nimcache_static
    ''}
  '' +
  optionalString (buildSamples && buildDynamic) ''
    mkdir -p $TMPDIR/.home/.cache
    export HOME=$TMPDIR/.home
    echo -e $BUILD_MSG "build/C_wrapper_example" && \
      $CC wrappers/wrapper_example.c -Wl,-rpath,'$$ORIGIN' -Lbuild -lnimbus -lm -g -o build/C_wrapper_example
    echo -e $BUILD_MSG "build/go_wrapper_example" && \
      ${go}/bin/go build -o build/go_wrapper_example wrappers/wrapper_example.go wrappers/cfuncs.go
    echo -e $BUILD_MSG "build/go_wrapper_whisper_example" && \
      ${go}/bin/go build -o build/go_wrapper_whisper_example wrappers/wrapper_whisper_example.go wrappers/cfuncs.go

    rm -rf $TMPDIR/.home/.cache
  '';
  installPhase = ''
    mkdir -p $out/{include,lib}
    cp ./wrappers/libnimbus.h $out/include/
    ${optionalString buildDynamic "cp ./build/libnimbus.so $out/lib/"}
    ${optionalString buildStatic "cp ./build/libnimbus.a $out/lib/"}
  '' +
  optionalString buildSamples ''
    mkdir -p $out/samples
    cp ./build/{C_wrapper_example,go_wrapper_example,go_wrapper_whisper_example} $out/samples
  '';

  meta = with stdenv.lib; {
    description = "A C wrapper of the Nimbus Ethereum 2.0 Sharding Client for Resource-Restricted Devices";
    homepage = https://github.com/status-im/nimbus;
    license = with licenses; [ asl20 ];
    platforms = with platforms; unix ++ windows;
  };
}
