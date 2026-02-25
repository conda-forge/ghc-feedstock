#!/usr/bin/env bash
# support/utils.sh - Minimal shared utilities
# ONLY platform-agnostic functions that ALL domains need

set -eu

#=============================================================================
# PLATFORM DETECTION
#=============================================================================

is_windows() { [[ "${target_platform:-}" == "win-64" ]]; }
is_linux() { [[ "${target_platform:-}" == linux-* ]]; }
is_macos() { [[ "${target_platform:-}" == osx-* ]]; }
is_unix() { ! is_windows; }
is_cross_compile() { [[ "${build_platform:-${target_platform}}" != "${target_platform}" ]]; }

#=============================================================================
# LOGGING
#=============================================================================

log_info()  { echo "  [INFO] $*"; }
log_warn()  { echo "  [WARN] $*" >&2; }
log_error() { echo "  [ERROR] $*" >&2; }
die() { log_error "$@"; exit 1; }

run_and_log() {
    local log_name="$1"
    shift

    mkdir -p "${SRC_DIR}/_logs"
    local log_file="${SRC_DIR}/_logs/${log_name}.log"

    log_info "Running: ${log_name}"
    log_info "Command: $*"

    if "$@" > "${log_file}" 2>&1; then
        log_info "✓ ${log_name} succeeded"
        return 0
    else
        local exit_code=$?
        log_error "════════════════════════════════════════════════════════════════"
        log_error "✗ ${log_name} FAILED (exit code: ${exit_code})"
        log_error "Command: $*"
        log_error "Log file: ${log_file}"
        log_error "════════════════════════════════════════════════════════════════"
        log_error ""
        log_error "Last 200 lines of output:"
        log_error "────────────────────────────────────────────────────────────────"
        tail -200 "${log_file}" >&2
        log_error "────────────────────────────────────────────────────────────────"
        log_error ""

        # Try to extract common error patterns
        if grep -qi "error:\|failed\|cannot" "${log_file}" 2>/dev/null; then
            log_error "Detected errors (grep for 'error:', 'failed', 'cannot'):"
            log_error "────────────────────────────────────────────────────────────────"
            grep -i "error:\|failed\|cannot" "${log_file}" | tail -50 >&2 || true
            log_error "────────────────────────────────────────────────────────────────"
        fi

        return ${exit_code}
    fi
}
