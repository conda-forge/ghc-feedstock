#!/usr/bin/env bash
# ==============================================================================
# Triple Configuration - Centralized GHC triple mappings
# ==============================================================================
# SINGLE PLACE TO UPDATE when changing GHC versions.
# GHC 9.6.x uses specific triple formats that may differ from other versions.
# ==============================================================================

# GHC triple format for each platform (UPDATE HERE FOR NEW GHC VERSIONS)
_ghc_triple_for_platform() {
  case "$1" in
    linux-64)       echo "x86_64-unknown-linux-gnu" ;;
    linux-aarch64)  echo "aarch64-unknown-linux-gnu" ;;
    linux-ppc64le)  echo "powerpc64le-unknown-linux-gnu" ;;
    osx-64)         echo "x86_64-apple-darwin13.4.0" ;;  # GHC 9.6.x specific
    osx-arm64)      echo "aarch64-apple-darwin" ;;
    win-64)         echo "x86_64-unknown-mingw32" ;;
    *)              echo "${build_alias:-unknown}" ;;
  esac
}

# Configure all triple variables (native or cross)
# Sets: ghc_build, ghc_host, ghc_target, ghc_triple (legacy)
#       conda_build, conda_host, conda_target
#       build_arch, host_arch, target_arch
# Exports: build_alias, host_alias, target_alias (cross only), host_platform (cross only)
configure_triples() {
  local mode="${1:-auto}"

  # Auto-detect mode
  [[ "${mode}" == "auto" ]] && {
    [[ "${build_platform:-${target_platform}}" == "${target_platform}" ]] && mode="native" || mode="cross"
  }

  if [[ "${mode}" == "native" ]]; then
    local triple
    triple=$(_ghc_triple_for_platform "${target_platform}")

    ghc_build="${triple}"; ghc_host="${triple}"; ghc_target="${triple}"
    conda_build="${build_alias:-}"; conda_host="${build_alias:-}"; conda_target="${build_alias:-}"
    build_arch="${triple%%-*}"; host_arch="${build_arch}"; target_arch="${build_arch}"

    export build_alias="${triple}" host_alias="${triple}"
  else
    build_arch="${build_alias%%-*}"; target_arch="${host_alias%%-*}"; host_arch="${build_arch}"
    conda_build="${build_alias}"; conda_host="${build_alias}"; conda_target="${host_alias}"

    ghc_build=$(_ghc_triple_for_platform "${build_platform}")
    ghc_host="${ghc_build}"
    ghc_target=$(_ghc_triple_for_platform "${target_platform}")

    # Linux exports GHC-style, others export conda-style
    case "${target_platform}" in
      linux-*)
        export build_alias="${ghc_build}" host_alias="${ghc_host}" target_alias="${ghc_target}" ;;
      *)
        export build_alias="${conda_build}" host_alias="${conda_host}" target_alias="${conda_target}" ;;
    esac
    export host_platform="${build_platform}"
  fi

  ghc_triple="${ghc_target}"  # Legacy alias
  echo "Triples [${mode}]: build=${ghc_build} host=${ghc_host} target=${ghc_target}"
}
