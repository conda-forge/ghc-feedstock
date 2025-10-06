#!/usr/bin/env bash
set -eu

_log_index=0

source "${RECIPE_DIR}"/building/common.sh

# Create iconv compatibility wrapper FIRST, before any commands run
# This must happen before cabal, ghc-bootstrap, or any other tool executes
cat > /tmp/iconv_compat.c << 'EOFC'
#include <stddef.h>
typedef void* iconv_t;
extern iconv_t libiconv_open(const char*, const char*);
extern size_t libiconv(iconv_t, char**, size_t*, char**, size_t*);
extern int libiconv_close(iconv_t);
iconv_t iconv_open(const char* a, const char* b) { return libiconv_open(a, b); }
size_t iconv(iconv_t a, char** b, size_t* c, char** d, size_t* e) { return libiconv(a,b,c,d,e); }
int iconv_close(iconv_t a) { return libiconv_close(a); }
EOFC

# Build both static and dynamic versions with explicit SDK version for compatibility
# This ensures the object file matches the SDK version used during GHC linking
${CC} -c /tmp/iconv_compat.c -o /tmp/iconv_compat.o -mmacosx-version-min=10.13

# Debug: Check what ar AND ld we're using
echo "=== Toolchain Debug Info ==="
echo "AR=${AR}"
which "${AR}" || echo "AR not in PATH"
"${AR}" --version || "${AR}" -V || echo "Cannot get ar version"
echo ""
echo "LD=${LD}"
which "${LD}" || echo "LD not in PATH"
"${LD}" -v || "${LD}" --version || echo "Cannot get ld version"
echo ""
echo "Testing ar format compatibility:"
echo "Creating test archive with ${AR}..."
echo "int test_func() { return 42; }" > /tmp/test.c
${CC} -c /tmp/test.c -o /tmp/test.o
${AR} rcs /tmp/test.a /tmp/test.o
file /tmp/test.a
echo "Trying to link with ${LD}..."
${CC} -o /tmp/test_binary /tmp/test.o 2>&1 | head -20
echo "=============================="

# Create archive with explicit format for LLVM ar compatibility
${AR} rcs /tmp/libiconv_compat.a /tmp/iconv_compat.o

# Verify the archive and object file metadata
echo "=== Archive verification ==="
file /tmp/libiconv_compat.a
${AR} -t /tmp/libiconv_compat.a
echo ""
echo "Object file metadata:"
file /tmp/iconv_compat.o
otool -l /tmp/iconv_compat.o | grep -A 3 "LC_VERSION_MIN\|LC_BUILD_VERSION" || echo "No version info found"
echo ""
echo "Checking if ld can read the archive:"
${AR} -x /tmp/libiconv_compat.a
file iconv_compat.o
echo ""
echo "Detailed object file analysis:"
otool -l iconv_compat.o | grep -A 5 "LC_VERSION"
echo ""
echo "Test: Can ld actually link with this archive?"
echo "int main() { return 0; }" > /tmp/test_main.c
${CC} -c /tmp/test_main.c -o /tmp/test_main.o
${CC} -o /tmp/test_link /tmp/test_main.o /tmp/libiconv_compat.a -L"${PREFIX}/lib" -liconv 2>&1 || echo "Link test FAILED"
file /tmp/test_link 2>/dev/null && echo "Link test SUCCEEDED"
echo "============================"

# Create dylib for runtime preloading with absolute paths
${CC} -dynamiclib -o /tmp/libiconv_compat.dylib /tmp/iconv_compat.c \
    -L"${PREFIX}/lib" -liconv \
    -Wl,-rpath,"${PREFIX}/lib" \
    -install_name "/tmp/libiconv_compat.dylib"

# DO NOT use DYLD_INSERT_LIBRARIES or DYLD_LIBRARY_PATH as they cause segfaults
# Instead, we'll rely on -force_load at link time to embed the symbols

# This is needed as in seems to interfere with configure scripts
unset build_alias
unset host_alias

# Debug: Verify which ar/ranlib ghc-bootstrap will actually use
echo "=== Testing which ar ghc-bootstrap actually invokes ==="
"${BUILD_PREFIX}"/ghc-bootstrap/bin/ghc --print-libdir
"${BUILD_PREFIX}"/ghc-bootstrap/bin/ghc --info | grep -E "(ar command|ranlib command)"
echo "===================================================="

# Update cabal package database
run_and_log "cabal-update" cabal v2-update --allow-newer --minimize-conflict-set

# Debug hook: When the build fails with "ignoring file" warnings,
# this script will be called to analyze the problematic archives
cat > /tmp/analyze_archives.sh << 'EOFSCRIPT'
#!/bin/bash
echo "=== Analyzing archive format differences ==="
echo ""
echo "Searching for .a files in cabal store..."
archives=$(find /Users/runner/.local/state/cabal/store/ghc-9.6.7/ -name "*.a" -type f 2>/dev/null | head -20)

if [ -z "$archives" ]; then
    echo "No archives found yet"
    exit 0
fi

echo "Found archives, analyzing first 10:"
echo "$archives" | head -10 | while read archive; do
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Archive: $(basename $archive)"
    echo "Full path: $archive"

    # Check archive format
    echo "Format signature:"
    head -c 20 "$archive" | od -An -tx1

    # Check if it's a thin archive
    if head -c 20 "$archive" | grep -q "!<thin>"; then
        echo "⚠️  THIN ARCHIVE detected"
    else
        echo "✓ Regular archive"
    fi

    # Extract and check first object file
    tmpdir=$(mktemp -d)
    cd "$tmpdir"
    ar -x "$archive" 2>/dev/null
    first_obj=$(ls *.o 2>/dev/null | head -1)

    if [ -n "$first_obj" ]; then
        echo "First object file: $first_obj"
        file "$first_obj"
        echo "Object file load commands:"
        otool -l "$first_obj" 2>/dev/null | grep -A 5 "LC_VERSION\|LC_BUILD" | head -20
    else
        echo "❌ Could not extract object files from archive"
    fi

    cd /tmp
    rm -rf "$tmpdir"
done
echo ""
echo "=========================================="
EOFSCRIPT
chmod +x /tmp/analyze_archives.sh

# Configure and build GHC
SYSTEM_CONFIG=(
  --build="x86_64-apple-darwin13.4.0"
  --host="x86_64-apple-darwin13.4.0"
  --prefix="${PREFIX}"
)

CONFIGURE_ARGS=(
  # default is auto: --disable-numa
  # --disable-ld-override
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

export ac_cv_path_ac_pt_CC=""
export ac_cv_path_ac_pt_CXX=""
export ac_cv_prog_AR="${AR}"
export ac_cv_prog_CC="${CC}"
export ac_cv_prog_CXX="${CXX}"
export ac_cv_prog_LD="${LD}"
export ac_cv_prog_RANLIB="${RANLIB}"
export ac_cv_path_AR="${AR}"
export ac_cv_path_CC="${CC}"
export ac_cv_path_CXX="${CXX}"
export ac_cv_path_LD="${LD}"
export ac_cv_path_RANLIB="${RANLIB}"
export DEVELOPER_DIR=""

# Verify the iconv compatibility libraries were created
echo "=== Verifying iconv compatibility symbols ==="
echo "Static library (all symbols):"
nm /tmp/libiconv_compat.a | grep iconv || true
echo ""
echo "Dynamic library (exported symbols only):"
nm -gU /tmp/libiconv_compat.dylib | grep iconv || true
echo ""
echo "Dylib dependencies:"
otool -L /tmp/libiconv_compat.dylib || true
echo ""
echo "NOTE: Not using DYLD_INSERT_LIBRARIES/DYLD_LIBRARY_PATH (causes segfaults)"
echo "Using -force_load at link time instead"
echo "=============================================="

settings_file=$(find "${BUILD_PREFIX}"/ghc-bootstrap -name settings | head -n 1)

# Debug: Show ghc-bootstrap's ORIGINAL ar/ranlib settings before modification
echo "=== ghc-bootstrap ORIGINAL settings ==="
grep -E "(ar command|ar flags|ranlib command)" "${settings_file}" || true
echo "========================================"

# Force load the compat library to ensure symbols are exported in executables
perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -v -Wl,-L$ENV{PREFIX}/lib -Wl,-force_load,/tmp/libiconv_compat.a -Wl,-liconv#' "${settings_file}"
perl -pi -e 's#(ld flags", "[^"]*)#$1 -v -L$ENV{PREFIX}/lib -force_load /tmp/libiconv_compat.a -liconv#' "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

# Debug: Show UPDATED settings after conda-forge toolchain modification
echo "=== ghc-bootstrap AFTER conda-forge ar/ranlib ==="
grep -E "(ar command|ar flags|ranlib command)" "${settings_file}" || true
echo "=================================================="

cat "${settings_file}"

ln -sf "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-as "${BUILD_PREFIX}"/bin/as
ln -sf "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-ld "${BUILD_PREFIX}"/bin/ld
ln -sf "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-ranlib "${BUILD_PREFIX}"/bin/ranlib

run_and_log "configure" ./configure "${SYSTEM_CONFIG[@]}" "${CONFIGURE_ARGS[@]}"

cat config.log

set_macos_conda_ar_ranlib "${SRC_DIR}"/hadrian/cfg/default.host.target "${CONDA_TOOLCHAIN_BUILD}"
set_macos_conda_ar_ranlib "${SRC_DIR}"/hadrian/cfg/default.target "${CONDA_TOOLCHAIN_BUILD}"

_hadrian_build=("${SRC_DIR}"/hadrian/build "-j${CPU_COUNT}")

# GHC selection of tools seems to fail to use conda-forge toolchain tools
rm -f /Users/runner/miniforge3/bin/{as,ranlib,ld}
#ln -s "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-as /Users/runner/miniforge3/bin/as
#ln -s "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-ld /Users/runner/miniforge3/bin/ld
#ln -s "${BUILD_PREFIX}"/bin/"${CONDA_TOOLCHAIN_BUILD}"-ranlib /Users/runner/miniforge3/bin/ranlib

# Before building, analyze any archives that exist to understand format differences
echo "=== Pre-build archive analysis ==="
/tmp/analyze_archives.sh || echo "Archive analysis skipped (no archives yet)"
echo "==================================="

# Run the build but capture output to detect link warnings
build_log="${SRC_DIR}/_logs/stage1_ghc_bin_build.log"
"${_hadrian_build[@]}" stage1:exe:ghc-bin --flavour=release 2>&1 | tee "$build_log"
build_exit_code=${PIPESTATUS[0]}

# If we see "ignoring file" warnings, run detailed analysis
if grep -q "ignoring file.*unknown-unsupported file format" "$build_log"; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  Detected 'unknown-unsupported file format' warnings"
    echo "Running detailed archive analysis..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    /tmp/analyze_archives.sh
    echo ""
fi

# Propagate the build exit code
if [ $build_exit_code -ne 0 ]; then
    echo "Build failed with exit code $build_exit_code"
    exit $build_exit_code
fi

settings_file="${SRC_DIR}"/_build/stage0/lib/settings
perl -pi -e 's#(C compiler link flags", "[^"]*)#$1 -v -Wl,-L$ENV{PREFIX}/lib -Wl,-L\$topdir/../../../../lib -Wl,-rpath,\$topdir/../../../../lib -Wl,-force_load,/tmp/libiconv_compat.a -Wl,-liconv#' "${settings_file}"
perl -pi -e 's#(ld flags", "[^"]*)#$1 -v -L$ENV{PREFIX}/lib -L\$topdir/../../../../lib -rpath \$topdir/../../../../lib -force_load /tmp/libiconv_compat.a -liconv#' "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

# Enable verbose linking to see actual ld commands
export LDFLAGS="${LDFLAGS} -v"

run_and_log "stage1_lib" "${_hadrian_build[@]}" stage1:lib:ghc --flavour=release

perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -v -Wl,-L\$ENV{PREFIX}/lib -Wl,-L\\\$topdir/../../../../lib -Wl,-rpath,\\\$topdir/../../../../lib -Wl,-force_load,/tmp/libiconv_compat.a -Wl,-liconv#" "${settings_file}"
perl -i -pe "s#(ld flags\", \")([^\"]*)#\1\2 -v -L\$ENV{PREFIX}/lib -L\\\$topdir/../../../../lib -force_load /tmp/libiconv_compat.a -liconv#" "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

"${_hadrian_build[@]}" stage2:exe:ghc-bin --flavour=quickest

export DYLD_LIBRARY_PATH="${BUILD_PREFIX}/lib:${PREFIX}/lib:${DYLD_LIBRARY_PATH:-}"
settings_file="${SRC_DIR}"/_build/stage1/lib/settings
perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -v -Wl,-L\$ENV{PREFIX}/lib -Wl,-L\\\$topdir/../../../../lib -Wl,-rpath,\\\$topdir/../../../../lib -Wl,-force_load,/tmp/libiconv_compat.a -Wl,-liconv#" "${settings_file}"
perl -i -pe "s#(ld flags\", \")([^\"]*)#\1\2 -v -L\$ENV{PREFIX}/lib -v -L\\\$topdir/../../../../lib -force_load /tmp/libiconv_compat.a -liconv#" "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"
run_and_log "stage2_lib" "${_hadrian_build[@]}" stage2:lib:ghc --flavour=release

run_and_log "install" "${_hadrian_build[@]}" install --prefix="${PREFIX}" --flavour=release --docs=none --progress-info=none

settings_file=$(find "${PREFIX}" -name settings | head -n 1)
perl -i -pe "s#(C compiler flags\", \")([^\"]*)#\1\2 -v -fno-lto#" "${settings_file}"
perl -i -pe "s#(C\+\+ compiler flags\", \")([^\"]*)#\1\2 -v -fno-lto#" "${settings_file}"
perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -v -Wl,-L\\\$topdir/../../../../lib -Wl,-rpath,\\\$topdir/../../../../lib -Wl,-force_load,/tmp/libiconv_compat.a -Wl,-liconv#" "${settings_file}"
perl -i -pe "s#(ld flags\", \")([^\"]*)#\1\2 -v -L\\\$topdir/../../../../lib -force_load /tmp/libiconv_compat.a -liconv#" "${settings_file}"
set_macos_conda_ar_ranlib "${settings_file}" "${CONDA_TOOLCHAIN_BUILD}"

cat "${settings_file}"

# Add debugging to verify archive format after build completes
echo "=== Post-build archive format check ==="
echo "Comparing ACCEPTED vs REJECTED archive formats:"
echo ""
echo "Our test archive (ACCEPTED in test, but IGNORED in actual link):"
file /tmp/libiconv_compat.a
head -c 20 /tmp/libiconv_compat.a | od -An -tx1
echo ""
echo "Checking cabal-built archives:"
find /Users/runner/.local/state/cabal/store/ghc-9.6.7/ -name "*.a" -type f | head -5 | while read f; do
  echo "File: $f"
  file "$f"
  head -c 20 "$f" | od -An -tx1
  echo ""
done
echo "=========================================="
