#!/usr/bin/env bash
# ld wrapper to surgically remove MacOSX15.5.sdk rpath contamination

# Debug: Log that wrapper is running
echo "=== LD WRAPPER INVOKED ===" >&2

# Find the real ld
REAL_LD="${BUILD_PREFIX}/bin/x86_64-apple-darwin13.4.0-ld.real"
if [[ ! -x "$REAL_LD" ]]; then
    REAL_LD="${BUILD_PREFIX}/bin/${CONDA_TOOLCHAIN_BUILD}-ld.real"
fi
if [[ ! -x "$REAL_LD" ]]; then
    echo "ERROR: Cannot find real ld" >&2
    exit 1
fi

echo "REAL_LD=$REAL_LD" >&2

# Filter out 15.5 SDK rpath AND LTO flags
filtered_args=()
i=0
args=("$@")

while [[ $i -lt ${#args[@]} ]]; do
    arg="${args[$i]}"

    # Skip LTO library flag and its argument
    if [[ "$arg" == "-lto_library" ]]; then
        # Skip this flag and the next argument (the library path)
        i=$((i + 2))
        continue
    fi

    # Skip LLVM-specific LTO optimization flags
    if [[ "$arg" == "-mllvm" ]]; then
        next_i=$((i + 1))
        if [[ $next_i -lt ${#args[@]} ]]; then
            next_arg="${args[$next_i]}"
            # Skip both -mllvm and its argument if it's LTO-related
            if [[ "$next_arg" == *"lto"* ]] || [[ "$next_arg" == *"linkonce"* ]]; then
                i=$((i + 2))
                continue
            fi
        fi
    fi

    # Skip 15.5 SDK rpath
    if [[ "$arg" == "-rpath" ]]; then
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

# Debug: Show what was filtered
echo "FILTERED OUT:" >&2
if [[ "$arg" == "-lto_library" ]] || [[ "$arg" == *"15.5"* ]]; then
    echo "  LTO and 15.5 SDK flags were removed" >&2
fi
echo "EXECUTING: $REAL_LD with ${#filtered_args[@]} arguments" >&2
echo "=== END LD WRAPPER ===" >&2

# Execute real ld with filtered arguments
exec "$REAL_LD" "${filtered_args[@]}"
