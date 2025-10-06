#!/usr/bin/env bash
# ld wrapper to surgically remove MacOSX15.5.sdk rpath contamination

# Find the real ld
REAL_LD="${BUILD_PREFIX}/bin/x86_64-apple-darwin13.4.0-ld.real"
if [[ ! -x "$REAL_LD" ]]; then
    REAL_LD="${BUILD_PREFIX}/bin/${CONDA_TOOLCHAIN_BUILD}-ld.real"
fi
if [[ ! -x "$REAL_LD" ]]; then
    echo "ERROR: Cannot find real ld" >&2
    exit 1
fi

# Filter out 15.5 SDK rpath
filtered_args=()
skip_next=false

for arg in "$@"; do
    if [[ "$skip_next" == "true" ]]; then
        # Check if this is the 15.5 SDK path we want to skip
        if [[ "$arg" == *"MacOSX15.5.sdk"* ]] || [[ "$arg" == *"15.5"* ]]; then
            # Skip this argument
            skip_next=false
            continue
        else
            # Keep this rpath, it's not the contaminated one
            filtered_args+=("$arg")
            skip_next=false
        fi
    elif [[ "$arg" == "-rpath" ]]; then
        # Next argument might be the 15.5 SDK path
        filtered_args+=("$arg")
        skip_next=true
    else
        filtered_args+=("$arg")
    fi
done

# Execute real ld with filtered arguments
exec "$REAL_LD" "${filtered_args[@]}"
