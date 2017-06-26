{ newScope
, stdenv
, cmake
, libxml2
, python2
, isl
, fetchurl
, overrideCC
, wrapCC
, ccWrapperFun
, buildTools
, lib
, runCommand
, enableSharedLibraries ? true
, hostPlatform
, targetPlatform
}:
let
  callPackage = newScope (buildTools.tools // libraries // {
    inherit stdenv cmake libxml2 python2 isl release_version fetch-llvm-mirror enableSharedLibraries;
  });

  release_version = "5.0.0";

  fetch-llvm-mirror = url: fetchurl {
    url = "https://github.com/llvm-mirror/${url.name}/archive/${url.rev}.tar.gz";
    inherit (url) sha256;
  };

  clang-tools-extra_src = fetch-llvm-mirror {
    name = "clang-tools-extra";
    rev = "05cb0e144a998cc4a016097e50ca8090e7ac7b5a";
    sha256 = "0wdjk7z6gi9znsswzw956jsdsl6gb54n99ck4pybjkm0jdjik40k";
  };

  tools = {
    llvm = callPackage ./llvm.nix {};

    clang-unwrapped = callPackage ./clang {
      inherit clang-tools-extra_src;
    };

    clang = wrapCC tools.clang-unwrapped;

    libcxxClang = ccWrapperFun {
      cc = tools.clang-unwrapped;
      isClang = true;
      inherit (tools) stdenv;
      /* FIXME is this right? */
      inherit (stdenv.cc) libc nativeTools nativeLibc;
      extraPackages = [ libraries.libcxx libraries.libcxxabi ];
    };

    stdenv = overrideCC stdenv tools.clang;

    libcxxStdenv = overrideCC stdenv tools.libcxxClang;

    lld = callPackage ./lld.nix {};

    lldb = callPackage ./lldb.nix {};

    # Bad binutils based on LLVM
    llvm-binutils = let
      prefix =
        if hostPlatform != targetPlatform
        then "${targetPlatform.config}-"
        else "";
    in with tools; runCommand "binutils" { propogatedNativeBuildInputs = [ llvm lld ]; } (''
      mkdir -p $out/bin
      for prog in ${lld}/bin/*; do
        ln -s $prog $out/bin/${prefix}$(basename $prog)
      done
      for prog in ${llvm}/bin/llvm-*; do
        ln -s $prog $out/bin/${prefix}$(echo $(basename $prog) | sed -e "s|llvm-||")
      done

      ln -s ${lld}/bin/lld $out/bin/${prefix}ld
      ln -s ${lld}/bin/lld $out/bin/${prefix}ld.gold # TODO: Figure out the ld.gold thing for GHC
    '' + lib.optionalString (hostPlatform != targetPlatform) ''
      ln -s ${lld}/bin/lld $out/bin/ld
      ln -s ${llvm}/bin/llvm-ar $out/bin/ar
      ln -s ${llvm}/bin/llvm-ranlib $out/bin/ranlib
    '');
  };

  libraries = {
    compiler-rt = callPackage ./compiler-rt.nix {};

    libunwind = callPackage ./libunwind.nix {};

    libcxx-headers = runCommand "libcxx-headers" {} ''
      unpackFile ${libraries.libcxx.src}
      mkdir -p $out
      mv libcxx*/include $out
    '';

    libcxx = callPackage ./libc++ {};

    libcxxabi = callPackage ./libc++abi.nix {};
  };

in { inherit tools libraries; } // tools // libraries
