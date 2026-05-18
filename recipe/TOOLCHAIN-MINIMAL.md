# GHC Toolchain: What's Actually Required

Based on analysis of GHC 9.6.7 source code (`configure.ac`, `system.config.in`, Hadrian).

## TL;DR: The Minimal Requirements

### For Native Builds (linux-64, osx-64)

**Configure arguments only:**
```bash
./configure \
    --prefix="${PREFIX}" \
    CC="${CC}" \
    CXX="${CXX}" \
    LD="${LD}" \
    AR="${AR}" \
    RANLIB="${RANLIB}" \
    NM="${NM}" \
    CFLAGS="${CFLAGS}" \
    LDFLAGS="${LDFLAGS}" \
    --with-system-libffi \
    --with-ffi-includes="${PREFIX}/include" \
    --with-ffi-libraries="${PREFIX}/lib" \
    --with-gmp-includes="${PREFIX}/include" \
    --with-gmp-libraries="${PREFIX}/lib"
```

**That's it.** Configure generates system.config correctly.

### For Cross-Compile (linux-aarch64, osx-arm64)

**Add STAGE0 tools and cross_compiling:**
```bash
./configure \
    ... (same as above) \
    CC_STAGE0="${BUILD_PREFIX}/bin/${host}-cc" \
    LD_STAGE0="${BUILD_PREFIX}/bin/${host}-ld" \
    AR_STAGE0="${BUILD_PREFIX}/bin/${host}-ar" \
    cross_compiling=yes
```

### For Windows (win-64)

**Add --enable-distro-toolchain:**
```bash
./configure \
    ... (same as native) \
    --enable-distro-toolchain
```

---

## What Configure Does (from source analysis)

### configure.ac Key Lines

```
Line 170: AC_ARG_VAR(CC_STAGE0, [C compiler command (bootstrap)])
Line 171: AC_ARG_VAR(LD_STAGE0, [Linker command (bootstrap)])
Line 172: AC_ARG_VAR(AR_STAGE0, [Archive command (bootstrap)])

Line 192-200: If CC_STAGE0 not set, extract from bootstrap GHC's --info

Line 469: AC_PROG_CC([cc gcc clang])  # Detects CC if not provided
Line 468: "later CC is copied to CC_STAGE{1,2,3}"
```

**Key insight:** If you pass `CC=...` to configure, it uses that. Otherwise it searches.

### system.config.in Substitutions

Configure substitutes these into system.config:

| Template Variable | Source | Purpose |
|-------------------|--------|---------|
| `@CC@` | CC from configure | Target C compiler |
| `@CC_STAGE0@` | CC_STAGE0 or bootstrap GHC | Bootstrap C compiler |
| `@ArCmd@` | AR from configure | Target archiver |
| `@AR_STAGE0@` | AR_STAGE0 or bootstrap GHC | Bootstrap archiver |
| `@LdCmd@` | LD from configure | Target linker |
| `@LD_STAGE0@` | LD_STAGE0 or configure | Bootstrap linker |
| `@CONF_CC_OPTS_STAGE0@` | CFLAGS processed | Stage0 compiler flags |
| `@CONF_CC_OPTS_STAGE1@` | CFLAGS processed | Stage1 compiler flags |
| `@CONF_GCC_LINKER_OPTS_STAGE1@` | LDFLAGS processed | Stage1 linker flags |

**Configure does the work.** We don't need to patch system.config for tool paths.

---

## What We're Currently Doing (Redundant)

### Mechanism 1: Environment Exports
```bash
export CC="${BUILD_PREFIX}/bin/x86_64-conda-linux-gnu-cc"
export CXX=...
```
**Verdict:** ✅ NEEDED - but only because we also use them in CFLAGS/LDFLAGS

### Mechanism 2: Configure Arguments
```bash
./configure CC="${CC}" CXX="${CXX}" ...
```
**Verdict:** ✅ NEEDED - this is the official API

### Mechanism 3: Autoconf Cache Variables
```bash
export ac_cv_prog_CC="${CC}"
export ac_cv_path_CC="${CC}"
```
**Verdict:** ⚠️ MAYBE NEEDED - only if sub-packages re-run configure detection

### Mechanism 4: Hadrian system.config Patching
```bash
perl -i -pe 's|^(cc-prog:).*|$1 ...|' system.config
```
**Verdict:** ❌ NOT NEEDED for tool paths - configure already sets them

### Mechanism 5: Settings File Patching (post-install)
```bash
perl -i -pe 's|${BUILD_PREFIX}||' lib/settings
```
**Verdict:** ✅ NEEDED - installed paths must not contain BUILD_PREFIX

---

## The Real Problems We're Solving

After tracing through the code, here's what actually needs fixing:

### Problem 1: BUILD_PREFIX in Installed Settings

The installed `lib/settings` file contains BUILD_PREFIX paths that won't exist at runtime.

**Solution:** Post-install patching (keep this)
```bash
# Strip BUILD_PREFIX from installed settings
perl -i -pe "s|${BUILD_PREFIX}/bin/||g" "${PREFIX}/lib/ghc-*/lib/settings"
```

### Problem 2: Python Path for Cross-Compile

Python runs on the build host, but configure might set target Python path.

**Solution:** Fix in post-configure
```bash
# For cross-compile only
perl -i -pe "s|^(python =).*|\$1 ${BUILD_PREFIX}/bin/python3|" system.config
```

### Problem 3: macOS llvm-ar Requirement

Apple ld64 requires BSD archive format. GNU ar produces incompatible archives.

**Solution:** Pass AR to configure
```bash
./configure AR="${BUILD_PREFIX}/bin/llvm-ar" RANLIB="${BUILD_PREFIX}/bin/llvm-ranlib"
```

### Problem 4: Library Path Flags

Conda libraries are in PREFIX/lib, need to be in link flags.

**Solution:** Pass LDFLAGS to configure
```bash
./configure LDFLAGS="-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib ${LDFLAGS}"
```

### Problem 5: Linux glibc Compatibility (statx)

statx() was added in glibc 2.28, but conda-forge targets 2.17.

**Solution:** Pass to configure
```bash
./configure ac_cv_func_statx=no
```

---

## Streamlined Approach

### New `lib/toolchain.sh`

```bash
#!/usr/bin/env bash
# toolchain.sh - Single source of truth for toolchain configuration

# Build the configure arguments based on platform
build_configure_toolchain() {
    local -n _args="$1"

    # Common: tool paths from environment (set by conda-build)
    _args+=("CC=${CC}")
    _args+=("CXX=${CXX}")
    _args+=("LD=${LD}")
    _args+=("AR=${AR}")
    _args+=("RANLIB=${RANLIB}")
    _args+=("NM=${NM}")

    # Common: flags with library paths
    _args+=("CFLAGS=${CFLAGS}")
    _args+=("LDFLAGS=-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib ${LDFLAGS}")

    # Platform-specific
    case "${target_platform}" in
        linux-*)
            _args+=("ac_cv_func_statx=no")  # glibc 2.17 compat
            ;;
        osx-*)
            # Use llvm-ar for BSD archive format
            _args+=("AR=${BUILD_PREFIX}/bin/llvm-ar")
            _args+=("RANLIB=${BUILD_PREFIX}/bin/llvm-ranlib")
            ;;
        win-64)
            _args+=("--enable-distro-toolchain")
            ;;
    esac

    # Cross-compile: add STAGE0 tools
    if is_cross_compile; then
        local host_prefix="${CONDA_TOOLCHAIN_HOST:-${conda_build}}"
        _args+=("CC_STAGE0=${BUILD_PREFIX}/bin/${host_prefix}-cc")
        _args+=("LD_STAGE0=${BUILD_PREFIX}/bin/${host_prefix}-ld")
        _args+=("AR_STAGE0=${BUILD_PREFIX}/bin/${host_prefix}-ar")
        _args+=("cross_compiling=yes")
    fi
}

# Post-configure fixes (only what configure can't handle)
post_configure_fixes() {
    local system_config="${SRC_DIR}/hadrian/cfg/system.config"

    # Cross-compile: fix Python path (runs on host, not target)
    if is_cross_compile; then
        perl -i -pe "s|^(python =).*|\$1 ${BUILD_PREFIX}/bin/python3|" "${system_config}"
    fi

    # That's it! Configure handles the rest.
}

# Post-install fixes (strip build paths from installed settings)
post_install_fixes() {
    local settings="${PREFIX}/lib/ghc-${PKG_VERSION}/lib/settings"

    # Remove BUILD_PREFIX from installed paths
    perl -i -pe "s|${BUILD_PREFIX}/bin/||g" "${settings}"
    perl -i -pe "s|${BUILD_PREFIX}/||g" "${settings}"
}
```

### Usage in Platform Scripts

```bash
# platforms/linux-64.sh

configure_ghc() {
    local -a args
    build_configure_toolchain args

    run_and_log "configure" ./configure \
        --prefix="${PREFIX}" \
        "${args[@]}" \
        --with-system-libffi \
        --with-ffi-includes="${PREFIX}/include" \
        --with-ffi-libraries="${PREFIX}/lib" \
        --with-gmp-includes="${PREFIX}/include" \
        --with-gmp-libraries="${PREFIX}/lib"
}

post_configure_ghc() {
    post_configure_fixes  # Minimal: just Python path for cross
}

post_install() {
    post_install_fixes    # Strip BUILD_PREFIX
}
```

---

## What We Can Remove

| Current Code | Can Remove? | Reason |
|--------------|-------------|--------|
| `set_autoconf_toolchain_vars()` | ⚠️ Simplify | Only keep `ac_cv_func_statx=no` for Linux |
| `patch_settings --linker-flags` | ❌ REMOVE | Configure handles via LDFLAGS |
| `patch_settings --strip-build-prefix` (configure-time) | ❌ REMOVE | Only needed post-install |
| `patch_settings --toolchain-prefix` | ❌ REMOVE | Configure handles tool paths |
| `cross_build_toolchain_args` (70+ lines) | ✅ SIMPLIFY | Just need CC_STAGE0, LD_STAGE0, AR_STAGE0 |
| 11 atomic `_patch_*` functions | ✅ REDUCE to 2 | post_configure_fixes, post_install_fixes |

---

## Summary

**Before:** 5 mechanisms, 150+ lines of toolchain code, patching at 4 stages
**After:** 1 function for configure args, 2 small fix functions

The key insight: **Trust configure.** It was designed to handle this. We only need to:
1. Pass the right arguments
2. Fix Python path for cross-compile
3. Strip BUILD_PREFIX from installed settings
