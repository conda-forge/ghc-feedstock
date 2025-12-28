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
    if "$@" > "${log_file}" 2>&1; then
        log_info "✓ ${log_name} succeeded"
        return 0
    else
        local exit_code=$?
        log_error "✗ ${log_name} failed (exit ${exit_code})"
        tail -100 "${log_file}" >&2
        return ${exit_code}
    fi
}
