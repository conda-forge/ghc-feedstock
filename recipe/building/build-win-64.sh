#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

conda_host="${build_alias}"
conda_target="${host_alias}"

ghc_host="${conda_host/w64/unknown}"
ghc_target="${conda_target/w64/unknown}"
_build_alias=${build_alias}
_host_alias=${host_alias}

export build_alias="${ghc_host}"
export host_alias="${ghc_host}"

export PATH="${_BUILD_PREFIX}/ghc-bootstrap/bin${PATH:+:}${PATH:-}:/c/Windows/System32"
export CABAL="${_BUILD_PREFIX}/bin/cabal"
export CABAL_DIR="${SRC_DIR}\\.cabal"
export _PYTHON="${_BUILD_PREFIX}/python.exe"
export GHC="${BUILD_PREFIX}\\ghc-bootstrap\\bin\\ghc.exe"
# Explicitely set CC to GCC (needed for a 'weak' ghc-bootstrap)
export CC="${GCC}"

# Bug in ghc-bootstrap
WINDRES_PATH="${BUILD_PREFIX//\\/\\\\}\\\\Library\\\\bin\\\\${WINDRES}"
perl -pi -e "s#WINDRES_CMD=.*windres\.exe#WINDRES_CMD=${WINDRES_PATH}#" "${_BUILD_PREFIX}"/ghc-bootstrap/bin/windres.bat
perl -pi -e 's/findstr/C:\\Windows\\System32\\findstr/g' "${_BUILD_PREFIX}"/ghc-bootstrap/bin/windres.bat

# Update Stage0 settings file with conda include paths for Windows build
settings_file="${_BUILD_PREFIX}/ghc-bootstrap/lib/settings"
if [[ -f "${settings_file}" ]]; then
  echo "=== Updating bootstrap settings with conda include paths ==="
  # Add -I flags to C compiler flags for ffi.h, gmp.h, etc.
  # CRITICAL: Use _PREFIX (Unix paths) NOT PREFIX (Windows paths with \b escape sequences)
  perl -pi -e "s#(C compiler flags\", \")([^\"]*)(\")#\$1\$2 -I${_PREFIX}/Library/include -I${_BUILD_PREFIX}/Library/include\$3#" "${settings_file}"
  perl -pi -e "s#(C\+\+ compiler flags\", \")([^\"]*)(\")#\$1\$2 -I${_PREFIX}/Library/include -I${_BUILD_PREFIX}/Library/include\$3#" "${settings_file}"
  grep "C compiler flags\|C++ compiler flags" "${settings_file}"
else
  echo "WARNING: Stage0 settings file not found at ${settings_file}"
fi

cd "${SRC_DIR}"

mkdir -p ".cabal" && "${CABAL}" user-config init
run_and_log "cabal-update" "${CABAL}" v2-update

export LIBRARY_PATH="${_BUILD_PREFIX}/Library/lib${LIBRARY_PATH:+:}${LIBRARY_PATH:-}"

# Set up temp variables
export TMP="$(cygpath -w "${TEMP}")"
export TMPDIR="$(cygpath -w "${TEMP}")"

# Find the latest MSVC version directory dynamically
MSVC_VERSION_DIR=$(ls -d "C:/Program Files/Microsoft Visual Studio/2022/Enterprise/VC/Tools/MSVC/"*/ 2>/dev/null | sort -V | tail -1 | sed 's/\/$//')

# Use the discovered path or fall back to a default if not found
if [ -z "$MSVC_VERSION_DIR" ]; then
  echo "Warning: Could not find MSVC tools directory, using fallback path"
  MSVC_VERSION_DIR="C:/Program Files/Microsoft Visual Studio/2022/Enterprise/VC/Tools/MSVC/14.38.33130"
fi

# Export LIB with the dynamic path
export LIB="${BUILD_PREFIX}/Library/lib;${PREFIX}/Library/lib;C:/Program Files (x86)/Windows Kits/10/Lib/10.0.26100.0/um/x64;${MSVC_VERSION_DIR}/lib/x64${LIB:+;}${LIB:-}"

# Export INCLUDE with conda libraries FIRST (for ffi.h, gmp.h, iconv.h, etc.)
export INCLUDE="${PREFIX}/Library/include;${BUILD_PREFIX}/Library/include;C:/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/ucrt;C:/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/um;C:/Program Files (x86)/Windows Kits/10/Include/10.0.26100.0/shared;${MSVC_VERSION_DIR}/include${INCLUDE:+;}${INCLUDE:-}"

mkdir -p "${_BUILD_PREFIX}/bin"
cp "${_BUILD_PREFIX}/Library/usr/bin/m4.exe" "${_BUILD_PREFIX}/bin"

_hadrian_build=("${_SRC_DIR}"/hadrian/build.bat)

# Configure and build GHC
SYSTEM_CONFIG=(
  --host="${ghc_target}"
  --prefix="${_PREFIX}"
)

# Add stack protector flags to ensure proper stack checking
CONFIGURE_ARGS=(
  --enable-distro-toolchain
  --with-system-libffi=yes
  --with-intree-gmp=no
  --with-curses-includes="${_PREFIX}"/Library/include
  --with-curses-libraries="${_PREFIX}"/Library/lib
  --with-ffi-includes="${_PREFIX}"/Library/include
  --with-ffi-libraries="${_PREFIX}"/Library/lib
  --with-gmp-includes="${_PREFIX}"/Library/include
  --with-gmp-libraries="${_PREFIX}"/Library/lib
  --with-iconv-includes="${_PREFIX}"/Library/include
  --with-iconv-libraries="${_PREFIX}"/Library/lib

  ac_cv_path_AR="${GCC_AR}"
  ac_cv_path_AS="${_BUILD_PREFIX}"/Library/bin/"${conda_target}"-as
  ac_cv_path_CC="${GCC}"
  ac_cv_path_CXX="${GXX}"
  ac_cv_path_LD="${_BUILD_PREFIX}"/Library/bin/"${conda_target}"-ld
  ac_cv_path_NM="${GCC_NM}"
  ac_cv_path_OBJDUMP="${_BUILD_PREFIX}"/Library/bin/"${conda_target}"-objdump
  ac_cv_path_RANLIB="${GCC_RANLIB}"
  ac_cv_path_LLC="${_BUILD_PREFIX}"/Library/bin/"${conda_target}"-llc
  ac_cv_path_OPT="${_BUILD_PREFIX}"/Library/bin/"${conda_target}"-opt
  ac_cv_path_WINDRES="${WINDRES}"
)

# Configure with environment variables that help debugging
export ac_cv_lib_ffi_ffi_call=yes

# export AR_STAGE0=llvm-ar
export AR_STAGE0=${GCC_AR}
export CC_STAGE0=${GCC}
export LD_STAGE0=${LD}

export WINDOWS_TOOLCHAIN_AUTOCONF=no

# Add conda include paths to CFLAGS so C compiler can find ffi.h, gmp.h, etc.
CFLAGS="${CFLAGS//-nostdlib/} -v -fno-stack-check -fno-stack-protector -I${_PREFIX}/Library/include -I${_BUILD_PREFIX}/Library/include" \
CXXFLAGS="${CXXFLAGS//-nostdlib/} -v -fno-stack-check -fno-stack-protector -I${_PREFIX}/Library/include -I${_BUILD_PREFIX}/Library/include" \
LDFLAGS="${LDFLAGS//-nostdlib/} -v" \
MergeObjsCmd="${LD}" \
MergeObjsArgs="" \
run_and_log "ghc-configure" bash configure "${CONFIGURE_ARGS[@]}" || ( cat config.log ; exit 1 )

cat "${_SRC_DIR}"/hadrian/cfg/system.config
echo $(find ${_BUILD_PREFIX} ${_PREFIX} -name "libssp*.dll")

# Fix Python path in system.config (configure sets Linux path, we need Windows)
# Use forward slashes to avoid escape sequence issues (\n, \t, \b, etc.)
perl -pi -e "s#(^python\\s*=).*#\$1 ${_PYTHON}#" "${_SRC_DIR}"/hadrian/cfg/system.config
echo "=== Converting FFI paths to Windows format in system.config ==="
perl -pi -e 's#^ffi-include-dir\s*=\s*/c/#ffi-include-dir   = C:/#' "${SRC_DIR}"/hadrian/cfg/system.config
perl -pi -e 's#^ffi-lib-dir\s*=\s*/c/#ffi-lib-dir       = C:/#' "${SRC_DIR}"/hadrian/cfg/system.config
perl -pi -e 's#^([a-z-]+dir)\s*=\s*/c/#$1 = C:/#g' "${SRC_DIR}"/hadrian/cfg/system.config
cat "${SRC_DIR}"/hadrian/cfg/system.config | grep "include-dir\|lib-dir"

# Ensure CFLAGS/CXXFLAGS include conda headers for the build phase too
export CFLAGS="${CFLAGS} -fno-stack-protector -fno-stack-check -I${PREFIX}/Library/include -I${BUILD_PREFIX}/Library/include"
export CXXFLAGS="${CXXFLAGS} -fno-stack-protector -fno-stack-check -I${PREFIX}/Library/include -I${BUILD_PREFIX}/Library/include"
export LDFLAGS="${LDFLAGS} -fno-stack-protector"

# Also ensure stack protection is disabled for all stages
cat > ${_SRC_DIR}/hadrian/hadrian.settings << EOF
stage1.*.cabal.configure.opts += --verbose=3 --with-compiler="${GHC}"
stage1.*.cc.c.opts += -fno-stack-protector -fno-stack-check
stage1.*.cc.cpp.opts += -fno-stack-protector -fno-stack-check
stage1.*.ghc.c.opts += -optc-fno-stack-protector -optc-fno-stack-check
stage1.*.ghc.cpp.opts += -optcxx-fno-stack-protector -optcxx-fno-stack-check
stage0.*.cc.c.opts += -fno-stack-protector -fno-stack-check
stage0.*.cc.cpp.opts += -fno-stack-protector -fno-stack-check
stage0.*.ghc.c.opts += -optc-fno-stack-protector -optc-fno-stack-check
stage0.*.ghc.cpp.opts += -optcxx-fno-stack-protector -optcxx-fno-stack-check
EOF

export CABFLAGS="--with-compiler=${GHC} --ghc-options=-optc-fno-stack-protector --ghc-options=-optc-fno-stack-check"
# Enable debugging mode for more verbose output
export GHC_DEBUG=1

# Ensure stack protection is disabled for all tools
export CFLAGS="${CFLAGS} -fno-stack-protector -fno-stack-check"
export CXXFLAGS="${CXXFLAGS} -fno-stack-protector -fno-stack-check"
export LDFLAGS="${LDFLAGS} -fno-stack-protector"

# Build stage1 GHC
echo "*** Building stage1 GHC ***"

# Ensure cabal wrapper is in PATH for hadrian
echo "*** Final cabal PATH verification ***"
export PATH="${_BUILD_PREFIX}/bin:${PATH}"
grep -A 10 "include-dirs:" rts/rts.cabal.in

run_and_log "stage1_ghc" "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=quickest --docs=none --progress-info=none
# "${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=quickest --docs=none --progress-info=none
settings_file="${_SRC_DIR}"/_build/stage0/lib/settings
if [[ -f "${settings_file}" ]]; then
  echo "=== Updating Stage0 settings with conda include paths ==="
  # Add -I flags to C compiler flags for ffi.h, gmp.h, etc.
  # CRITICAL: Use _PREFIX (Unix paths) NOT PREFIX (Windows paths with \b escape sequences)
  perl -pi -e "s#(C compiler flags\", \")([^\"]*)(\")#\$1\$2 -I${_PREFIX}/Library/include -I${_BUILD_PREFIX}/Library/include\$3#" "${settings_file}"
  perl -pi -e "s#(C\+\+ compiler flags\", \")([^\"]*)(\")#\$1\$2 -I${_PREFIX}/Library/include -I${_BUILD_PREFIX}/Library/include\$3#" "${settings_file}"
  grep "C compiler flags\|C++ compiler flags" "${settings_file}"
else
  echo "WARNING: Stage0 settings file not found at ${settings_file}"
fi

  echo "=== Waiting for Hadrian to generate rts.cabal ==="
  for i in {1..60}; do
    if [[ -f "${SRC_DIR}"/rts/rts.cabal ]]; then
      echo "=== GENERATED rts.cabal found! Checking FFI paths ==="
      grep -n "include-dirs\|extra-include-dirs\|/c/bld" "${SRC_DIR}"/rts/rts.cabal | head -20
      break
    fi
    sleep 1
  done

run_and_log "stage1_pkg" "${_hadrian_build[@]}" stage1:exe:ghc-pkg --flavour=quick --docs=none --progress-info=none
run_and_log "stage1_hs" "${_hadrian_build[@]}" stage1:exe:hsc2hs --flavour=quick --docs=none --progress-info=none
run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=quick --docs=none --progress-info=none || { \
  echo "=== Checking if Hadrian patch was applied ==="; \
  grep -A 3 "interpolateSetting.*FFIIncludeDir" "${SRC_DIR}"/hadrian/src/Rules/Generate.hs || echo "ERROR: Hadrian patch NOT applied!"; \
  grep -n "include-dirs\|extra-include-dirs\|/c/bld" "${SRC_DIR}"/rts/rts.cabal | head -20; \
  exit 1; \
}
  


cat "${_SRC_DIR}"/_build/stage0/lib/settings

run_and_log "stage2_exe" "${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=quick --freeze1 --docs=none --progress-info=none
run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc --flavour=quick --freeze1 --docs=none --progress-info=none
run_and_log "install" "${_hadrian_build[@]}" install --prefix="${_PREFIX}" --flavour=quick --freeze1 --freeze2 --docs=none
