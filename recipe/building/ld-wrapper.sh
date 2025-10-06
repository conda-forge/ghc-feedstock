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
i=0
args=("$@")

while [[ $i -lt ${#args[@]} ]]; do
    arg="${args[$i]}"

    if [[ "$arg" == "-rpath" ]]; then
        # Look ahead to see if next argument is the contaminated path
        next_i=$((i + 1))
        if [[ $next_i -lt ${#args[@]} ]]; then
            next_arg="${args[$next_i]}"
            if [[ "$next_arg" == *"MacOSX15.5.sdk"* ]] || [[ "$next_arg" == *"15.5"* ]]; then
                # Skip both -rpath and the contaminated path
                i=$((i + 2))
                continue
            fi
        fi
    fi

    # Keep this argument
    filtered_args+=("$arg")
    i=$((i + 1))
done

# Execute real ld with filtered arguments
exec "$REAL_LD" "${filtered_args[@]}"
