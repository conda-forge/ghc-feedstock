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

#if [[ "${target_platform}" == "linux-aarch64" ]] || [["${target_platform}" == "linux-ppc64le"]]; then
if [["${target_platform}" == "linux-ppc64le"]]; then
  "${RECIPE_DIR}"/building/build-linux-cross.sh
else
  "${RECIPE_DIR}"/building/build-"${target_platform}.sh"
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
if [[ -f "${PREFIX}"/lib/ghc-"${PKG_VERSION}"/lib/settings ]]; then
  python -c "
import os, re
f = '${PREFIX}/lib/ghc-${PKG_VERSION}/lib/settings'
with open(f, 'r') as file: content = file.read()
content = re.sub(rf'({re.escape(os.environ.get(\"BUILD_PREFIX\", \"\"))}|{re.escape(os.environ.get(\"PREFIX\", \"\"))})/bin/', '', content)
with open(f, 'w') as file: file.write(content)
"
fi

# Find all the .dylib libs with the '-ghc<version>' extension and link them to non-'-ghc<version>'
find "${PREFIX}/lib" -name "*-ghc${PKG_VERSION}.dylib" -o -name "*-ghc${PKG_VERSION}.so" | while read -r lib; do
  base_lib="${lib//-ghc${PKG_VERSION}./.}"
  if [[ ! -e "$base_lib" ]]; then
    ln -s "$(basename "$lib")" "$base_lib"
  fi
done

# # Add package licenses
# arch="-${target_platform#*-}"
# arch="${arch//-64/-x86_64}"
# arch="${arch#*-}"
# arch="${arch//arm64/aarch64}"
#
# # 9.6.7
# pushd "${PREFIX}/share/doc/${arch}-${target_platform%%-*}-ghc-${PKG_VERSION}" || true
# # 9.12+
# # pushd "${PREFIX}/share/doc/${arch}-${target_platform%%-*}-ghc-${PKG_VERSION}-inplace" || true
#   for file in */LICENSE; do
#     cp "${file///-}" "${SRC_DIR}"/license_files
#   done
# popd
