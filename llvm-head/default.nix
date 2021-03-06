{ newScope
, stdenv
, cmake
, libxml2
, python2
, isl
, fetchurl
, overrideCC
, wrapCC
# , ccWrapperFun
, buildTools
, lib
, runCommand
, debugVersion ? false
, enableSharedLibraries ? true
, hostPlatform
, targetPlatform
, coreutils
, buildPackages
}:
let
  callLibrary = newScope (buildTools.tools // libraries // {
    inherit stdenv cmake libxml2 python2 isl release_version enableSharedLibraries sources debugVersion;
  });

  callTool = newScope (tools // libraries // {
    inherit stdenv cmake libxml2 python2 isl release_version enableSharedLibraries sources debugVersion;
  });

  sources = callLibrary ./sources.nix {};

  release_version = "7.0.0";

  tools = {
    llvm = callTool ./llvm.nix {};

    clang-unwrapped = callTool ./clang {};

    clang = wrapCC tools.clang-unwrapped;

    # libcxxClang = ccWrapperFun {
    #   cc = tools.clang-unwrapped;
    #   isClang = true;
    #   inherit (tools) stdenv;
    #   /* FIXME is this right? */
    #   inherit (stdenv.cc) libc nativeTools nativeLibc;
    #   extraPackages = [ libraries.libcxx libraries.libcxxabi ];
    # };

    stdenv = overrideCC stdenv tools.clang;

    libcxxStdenv = overrideCC stdenv tools.libcxxClang;

    lld = callTool ./lld.nix {};

    lldb = callTool ./lldb.nix {};

    # Bad binutils based on LLVM
    llvm-binutils = let
      prefix =
        if hostPlatform != targetPlatform
        then "${targetPlatform.config}-"
        else "";
      strip = buildPackages.writeShellScriptBin "strip" "true";
    in with tools; runCommand "llvm-binutils-${release_version}" { preferLocalBuild = true; } (''
      mkdir -p $out/bin
      # for prog in ${lld}/bin/*; do
      #   ln -s $prog $out/bin/${prefix}$(basename $prog)
      # done
      for prog in ${llvm}/bin/*; do
        ln -s $prog $out/bin/${prefix}$(echo $(basename $prog) | sed -e "s|llvm-||")
      done

      rm $out/bin/${prefix}cat

      ln -s ${lld}/bin/lld $out/bin/${prefix}ld
      # ln -s ${lld}/bin/lld $out/bin/${prefix}ld.lld
      # ln -s ${lld}/bin/lld $out/bin/${prefix}lld
    '' + lib.optionalString targetPlatform.isWasm ''
      # llvm-strip doesn't work on wasm
      rm $out/bin/${prefix}strip
      ln -s ${strip}/bin/strip $out/bin/${prefix}strip
    '');
  };

  libraries = {
    compiler-rt = callLibrary ./compiler-rt.nix {};

    libunwind = callLibrary ./libunwind.nix {};

    libcxx-headers = runCommand "libcxx-headers" {} ''
      unpackFile ${libraries.libcxx.src}
      mkdir -p $out
      cp -r libcxx*/include $out
    '';

    libcxx = callLibrary ./libc++ {};

    libcxxabi = callLibrary ./libc++abi.nix {};
  };

in { inherit tools libraries; } // tools // libraries
