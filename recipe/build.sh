#!/usr/bin/env bash
set -eu

# Set up binary directory
mkdir -p binary/bin _logs

# Create bash completion
mkdir -p "${PREFIX}"/etc/bash_completion.d

export MergeObjsCmd=${LD_GOLD:-${LD}}
export M4=${BUILD_PREFIX}/bin/m4
export PYTHON=${BUILD_PREFIX}/bin/python
export PATH=${BUILD_PREFIX}/ghc-bootstrap/bin${PATH:+:}${PATH:-}

SYSTEM_CONFIG=(
  --prefix="${PREFIX}"
)

CONFIGURE_ARGS=(
  --with-system-libffi=yes
  --with-curses-includes="${PREFIX}"/include
  --with-curses-libraries="${PREFIX}"/lib
  --with-ffi-includes="${PREFIX}"/include
  --with-ffi-libraries="${PREFIX}"/lib
  --with-gmp-includes="${PREFIX}"/include
  --with-gmp-libraries="${PREFIX}"/lib
  --with-iconv-includes="${PREFIX}"/include
  --with-iconv-libraries="${PREFIX}"/lib
)

if [[ "${target_platform}" == "linux-aarch64" ]] || [[ "${target_platform}" == "linux-ppc64le" ]]; then
  source "${RECIPE_DIR}"/building/build-linux-cross.sh
else
  source "${RECIPE_DIR}"/building/build-"${target_platform}.sh"
fi

# Create bash completion
mkdir -p "${PREFIX}"/etc/bash_completion.d
cp utils/completion/ghc.bash "${PREFIX}"/etc/bash_completion.d/ghc

# Clean up package cache, we use ghc-pkg in the activation
rm -f "${PREFIX}"/lib/*ghc-"${PKG_VERSION}"/lib/package.conf.d/package.cache
rm -f "${PREFIX}"/lib/*ghc-"${PKG_VERSION}"/lib/package.conf.d/package.cache.lock

mkdir -p "${PREFIX}/etc/conda/activate.d"
cp "${RECIPE_DIR}/activate.sh" "${PREFIX}/etc/conda/activate.d/${PKG_NAME}_activate.sh"

# Cleanup potential hard-coded build env paths
settings_file=$(find "${PREFIX}"/lib/ -name settings | head -1)
perl -pi -e "s#(${BUILD_PREFIX}|${PREFIX})/(bin|lib)/##g" "${settings_file}"

# Find all the dynamic libraries libs with the '-ghc<version>' extension and link them to non-'-ghc<version>'
find "${PREFIX}/lib" -name "*-ghc${PKG_VERSION}.dylib" -o -name "*-ghc${PKG_VERSION}.so" | while read -r lib; do
  base_lib="${lib//-ghc${PKG_VERSION}./.}"
  if [[ ! -e "$base_lib" ]]; then
    ln -s "$(basename "$lib")" "$base_lib"
  fi
done

# Find licenses
for lic_file in $(find "${SRC_DIR}"/libraries/*/LICENSE); do
  folder=$(dirname "${lic_file}")
  mkdir -p "${SRC_DIR}"/license_files/"${folder}"
  cp "${lic_file}" "${SRC_DIR}"/license_files/"${folder}"
done
