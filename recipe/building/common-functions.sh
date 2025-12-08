#!/usr/bin/env bash
# ==============================================================================
# Common Build Functions - Default Implementations
# ==============================================================================
# Provides default behavior for all build phases.
# Platform configs can override by defining platform_xxx() functions.
#
# Hook Pattern:
#   Each phase calls:
#     1. platform_pre_xxx()  (if defined) - setup before phase
#     2. platform_xxx()      (if defined) - custom implementation
#        OR default_xxx()    (if platform_xxx not defined) - default
#     3. platform_post_xxx() (if defined) - cleanup/validation after phase
# ==============================================================================

set -eu

# ==============================================================================
# Logging Index (for run_and_log)
# ==============================================================================

_log_index=0

# ==============================================================================
# System Diagnostics - Performance Investigation
# ==============================================================================
# Collects comprehensive system information to diagnose cross-platform
# performance differences (e.g., macOS 3x slower than Linux despite more CPUs)

run_system_diagnostics() {
  echo ""
  echo "===================================================================="
  echo "  System Diagnostics - Performance Investigation"
  echo "===================================================================="
  echo ""

  local diag_file="${SRC_DIR}/_logs/00-system-diagnostics.log"
  local diag_start=$(date +%s)

  mkdir -p "${SRC_DIR}/_logs"

  {
    echo "========================================"
    echo "SYSTEM DIAGNOSTICS REPORT"
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Platform: ${target_platform:-unknown}"
    echo "========================================"
    echo ""

    # ----------------------------------------
    # 1. CPU Information
    # ----------------------------------------
    echo "=== CPU INFORMATION ==="
    echo ""

    if [[ "$(uname)" == "Darwin" ]]; then
      echo "--- macOS CPU Details ---"
      sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "CPU brand: unknown"
      echo "CPU cores (physical): $(sysctl -n hw.physicalcpu 2>/dev/null || echo unknown)"
      echo "CPU cores (logical): $(sysctl -n hw.logicalcpu 2>/dev/null || echo unknown)"
      echo "CPU frequency: $(sysctl -n hw.cpufrequency 2>/dev/null | awk '{printf "%.2f GHz", $1/1000000000}' || echo unknown)"
      echo "L1 icache: $(sysctl -n hw.l1icachesize 2>/dev/null | awk '{printf "%.0f KB", $1/1024}' || echo unknown)"
      echo "L1 dcache: $(sysctl -n hw.l1dcachesize 2>/dev/null | awk '{printf "%.0f KB", $1/1024}' || echo unknown)"
      echo "L2 cache: $(sysctl -n hw.l2cachesize 2>/dev/null | awk '{printf "%.0f KB", $1/1024}' || echo unknown)"
      echo "L3 cache: $(sysctl -n hw.l3cachesize 2>/dev/null | awk '{printf "%.0f MB", $1/1048576}' || echo unknown)"
      echo "Memory: $(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.1f GB", $1/1073741824}' || echo unknown)"
      echo ""
      echo "--- Full CPU Info ---"
      sysctl -a 2>/dev/null | grep -E "^(machdep\.cpu\.|hw\.)" | head -50
    else
      echo "--- Linux CPU Details ---"
      grep "model name" /proc/cpuinfo 2>/dev/null | head -1 || echo "CPU model: unknown"
      echo "CPU cores (online): $(nproc 2>/dev/null || echo unknown)"
      echo "CPU cores (total): $(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo unknown)"
      grep "cpu MHz" /proc/cpuinfo 2>/dev/null | head -1 || echo "CPU MHz: unknown"
      grep "cache size" /proc/cpuinfo 2>/dev/null | head -1 || echo "Cache: unknown"
      echo "Memory: $(free -h 2>/dev/null | grep Mem | awk '{print $2}' || echo unknown)"
      echo ""
      echo "--- /proc/cpuinfo (first CPU) ---"
      awk '/^$/{exit} {print}' /proc/cpuinfo 2>/dev/null || echo "cpuinfo unavailable"
      echo ""
      echo "--- lscpu ---"
      lscpu 2>/dev/null || echo "lscpu unavailable"
    fi
    echo ""

    # ----------------------------------------
    # 2. Environment Variables
    # ----------------------------------------
    echo "=== BUILD ENVIRONMENT ==="
    echo ""
    echo "CPU_COUNT: ${CPU_COUNT:-not set}"
    echo "MAKEFLAGS: ${MAKEFLAGS:-not set}"
    echo "CC: ${CC:-not set}"
    echo "CXX: ${CXX:-not set}"
    echo "AR: ${AR:-not set}"
    echo "LD: ${LD:-not set}"
    echo "CFLAGS: ${CFLAGS:-not set}"
    echo "CXXFLAGS: ${CXXFLAGS:-not set}"
    echo "LDFLAGS: ${LDFLAGS:-not set}"
    echo "PREFIX: ${PREFIX:-not set}"
    echo "BUILD_PREFIX: ${BUILD_PREFIX:-not set}"
    echo "CONDA_BUILD_SYSROOT: ${CONDA_BUILD_SYSROOT:-not set}"
    echo ""

    # ----------------------------------------
    # 3. Compiler Versions
    # ----------------------------------------
    echo "=== COMPILER VERSIONS ==="
    echo ""
    echo "--- CC version ---"
    ${CC:-cc} --version 2>&1 | head -3 || echo "CC not available"
    echo ""
    echo "--- CXX version ---"
    ${CXX:-c++} --version 2>&1 | head -3 || echo "CXX not available"
    echo ""
    echo "--- Bootstrap GHC ---"
    which ghc 2>/dev/null && ghc --version 2>/dev/null || echo "GHC not in PATH yet"
    echo ""
    echo "--- Cabal ---"
    which cabal 2>/dev/null && cabal --version 2>/dev/null || echo "Cabal not in PATH yet"
    echo ""

    # ----------------------------------------
    # 4. Filesystem Information
    # ----------------------------------------
    echo "=== FILESYSTEM ==="
    echo ""
    echo "--- Disk space ---"
    df -h "${SRC_DIR}" 2>/dev/null || df -h . 2>/dev/null || echo "df unavailable"
    echo ""
    echo "--- Filesystem type ---"
    if [[ "$(uname)" == "Darwin" ]]; then
      mount | grep " / " | head -1
      diskutil info / 2>/dev/null | grep -E "(File System|Type)" || true
    else
      mount | grep " / " | head -1
      stat -f -c %T "${SRC_DIR}" 2>/dev/null || echo "fs type unknown"
    fi
    echo ""

    # ----------------------------------------
    # 5. System Load
    # ----------------------------------------
    echo "=== SYSTEM LOAD ==="
    echo ""
    uptime 2>/dev/null || echo "uptime unavailable"
    echo ""

  } > "${diag_file}" 2>&1

  # Print summary to stdout
  echo "  CPU Info:"
  if [[ "$(uname)" == "Darwin" ]]; then
    echo "    Model: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
    echo "    Cores: $(sysctl -n hw.physicalcpu 2>/dev/null || echo unknown) physical, $(sysctl -n hw.logicalcpu 2>/dev/null || echo unknown) logical"
    echo "    Memory: $(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.1f GB", $1/1073741824}' || echo unknown)"
  else
    echo "    Model: $(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs || echo unknown)"
    echo "    Cores: $(nproc 2>/dev/null || echo unknown)"
    echo "    Memory: $(free -h 2>/dev/null | grep Mem | awk '{print $2}' || echo unknown)"
  fi
  echo "    CPU_COUNT env: ${CPU_COUNT:-not set}"
  echo ""

  # ----------------------------------------
  # 6. BENCHMARK: Single-threaded GHC compile
  # ----------------------------------------
  echo "  Running benchmarks..."
  echo ""

  {
    echo ""
    echo "=== BENCHMARK: Single-threaded Compile ==="
    echo ""
  } >> "${diag_file}"

  # Helper function for high-resolution timing (works on both Linux and macOS)
  # Returns milliseconds since epoch
  _get_time_ms() {
    if [[ "$(uname)" == "Darwin" ]]; then
      # macOS: use python for millisecond precision (date +%s%N not supported)
      python3 -c "import time; print(int(time.time() * 1000))" 2>/dev/null || echo $(($(date +%s) * 1000))
    else
      # Linux: use nanoseconds and convert to ms
      echo $(( $(date +%s%N) / 1000000 ))
    fi
  }

  # Create a simple Haskell benchmark file
  local bench_dir="${SRC_DIR}/_bench"
  mkdir -p "${bench_dir}"

  cat > "${bench_dir}/bench_simple.hs" << 'HSBENCH'
-- Simple benchmark: compute sum of list
main :: IO ()
main = print (sum [1..1000000 :: Integer])
HSBENCH

  cat > "${bench_dir}/bench_fib.hs" << 'HSBENCH'
-- Fibonacci benchmark (more compile-intensive)
{-# LANGUAGE BangPatterns #-}
fib :: Int -> Integer
fib n = go n 0 1
  where
    go !n !a !b
      | n == 0    = a
      | otherwise = go (n-1) b (a+b)

main :: IO ()
main = print (fib 100000)
HSBENCH

  # Find bootstrap GHC
  local bench_ghc=""
  if [[ -x "${BUILD_PREFIX}/ghc-bootstrap/bin/ghc" ]]; then
    bench_ghc="${BUILD_PREFIX}/ghc-bootstrap/bin/ghc"
  elif which ghc >/dev/null 2>&1; then
    bench_ghc=$(which ghc)
  fi

  if [[ -n "${bench_ghc}" ]] && ${bench_ghc} --version >/dev/null 2>&1; then
    echo "  Benchmark 1: Single-threaded compile (simple)"
    {
      echo "Using GHC: ${bench_ghc}"
      echo "GHC version: $(${bench_ghc} --version 2>&1)"
      echo ""
      echo "--- Compile bench_simple.hs (no optimization) ---"
    } >> "${diag_file}"

    local compile_start=$(_get_time_ms)
    if ${bench_ghc} -O0 -o "${bench_dir}/bench_simple" "${bench_dir}/bench_simple.hs" >> "${diag_file}" 2>&1; then
      local compile_end=$(_get_time_ms)
      local compile_ms=$((compile_end - compile_start))
      echo "    -O0 compile: ${compile_ms}ms"
      { echo "Compile time: ${compile_ms}ms"; echo ""; } >> "${diag_file}"
    else
      echo "    -O0 compile: FAILED (see log)"
      { echo "Compile FAILED"; echo ""; } >> "${diag_file}"
    fi

    {
      echo "--- Compile bench_simple.hs (-O2 optimization) ---"
    } >> "${diag_file}"

    compile_start=$(_get_time_ms)
    if ${bench_ghc} -O2 -o "${bench_dir}/bench_simple_o2" "${bench_dir}/bench_simple.hs" >> "${diag_file}" 2>&1; then
      local compile_end=$(_get_time_ms)
      local compile_ms=$((compile_end - compile_start))
      echo "    -O2 compile: ${compile_ms}ms"
      { echo "Compile time: ${compile_ms}ms"; echo ""; } >> "${diag_file}"
    else
      echo "    -O2 compile: FAILED (see log)"
      { echo "Compile FAILED"; echo ""; } >> "${diag_file}"
    fi

    echo "  Benchmark 2: Single-threaded compile (fibonacci)"
    {
      echo "--- Compile bench_fib.hs (-O2 optimization) ---"
    } >> "${diag_file}"

    compile_start=$(_get_time_ms)
    if ${bench_ghc} -O2 -o "${bench_dir}/bench_fib" "${bench_dir}/bench_fib.hs" >> "${diag_file}" 2>&1; then
      local compile_end=$(_get_time_ms)
      local compile_ms=$((compile_end - compile_start))
      echo "    -O2 compile: ${compile_ms}ms"
      { echo "Compile time: ${compile_ms}ms"; echo ""; } >> "${diag_file}"
    else
      echo "    -O2 compile: FAILED (see log)"
      { echo "Compile FAILED"; echo ""; } >> "${diag_file}"
    fi

  else
    echo "    (Bootstrap GHC not available or not working, skipping compile benchmarks)"
    echo "Bootstrap GHC not available or not working, skipping compile benchmarks" >> "${diag_file}"
  fi

  # ----------------------------------------
  # 6b. BENCHMARK: Clang/C compiler
  # ----------------------------------------
  echo "  Benchmark 2b: C compiler (Clang)"
  {
    echo ""
    echo "=== BENCHMARK: C Compiler (Clang) ==="
    echo ""
  } >> "${diag_file}"

  # Create a simple C benchmark file
  cat > "${bench_dir}/bench.c" << 'CBENCH'
#include <stdio.h>
#include <stdlib.h>

// Simple compute-intensive function
long fib(int n) {
    if (n <= 1) return n;
    long a = 0, b = 1;
    for (int i = 2; i <= n; i++) {
        long t = a + b;
        a = b;
        b = t;
    }
    return b;
}

int main() {
    printf("%ld\n", fib(45));
    return 0;
}
CBENCH

  # Create a more complex C file with templates/macros
  cat > "${bench_dir}/bench_complex.c" << 'CBENCH'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define ARRAY_SIZE 1000
#define ITERATIONS 100

double compute_stuff(double* arr, int size) {
    double sum = 0.0;
    for (int iter = 0; iter < ITERATIONS; iter++) {
        for (int i = 0; i < size; i++) {
            arr[i] = sin(arr[i]) * cos(arr[i] * 0.5) + sqrt(fabs(arr[i]));
            sum += arr[i];
        }
    }
    return sum;
}

int main() {
    double* arr = malloc(ARRAY_SIZE * sizeof(double));
    for (int i = 0; i < ARRAY_SIZE; i++) arr[i] = (double)i / ARRAY_SIZE;
    printf("%.6f\n", compute_stuff(arr, ARRAY_SIZE));
    free(arr);
    return 0;
}
CBENCH

  local bench_cc="${CC:-cc}"
  {
    echo "Using CC: ${bench_cc}"
    echo "CC version: $(${bench_cc} --version 2>&1 | head -1)"
    echo ""
  } >> "${diag_file}"

  # Simple C compile -O0
  {
    echo "--- Compile bench.c (-O0) ---"
  } >> "${diag_file}"
  local c_start=$(_get_time_ms)
  if ${bench_cc} -O0 -o "${bench_dir}/bench_c" "${bench_dir}/bench.c" >> "${diag_file}" 2>&1; then
    local c_end=$(_get_time_ms)
    local c_ms=$((c_end - c_start))
    echo "    -O0 compile: ${c_ms}ms"
    { echo "Compile time: ${c_ms}ms"; echo ""; } >> "${diag_file}"
  else
    echo "    -O0 compile: FAILED"
    { echo "Compile FAILED"; echo ""; } >> "${diag_file}"
  fi

  # Simple C compile -O2
  {
    echo "--- Compile bench.c (-O2) ---"
  } >> "${diag_file}"
  c_start=$(_get_time_ms)
  if ${bench_cc} -O2 -o "${bench_dir}/bench_c_o2" "${bench_dir}/bench.c" >> "${diag_file}" 2>&1; then
    local c_end=$(_get_time_ms)
    local c_ms=$((c_end - c_start))
    echo "    -O2 compile: ${c_ms}ms"
    { echo "Compile time: ${c_ms}ms"; echo ""; } >> "${diag_file}"
  else
    echo "    -O2 compile: FAILED"
    { echo "Compile FAILED"; echo ""; } >> "${diag_file}"
  fi

  # Complex C compile with math library -O2
  {
    echo "--- Compile bench_complex.c (-O2 -lm) ---"
  } >> "${diag_file}"
  c_start=$(_get_time_ms)
  if ${bench_cc} -O2 -o "${bench_dir}/bench_complex" "${bench_dir}/bench_complex.c" -lm >> "${diag_file}" 2>&1; then
    local c_end=$(_get_time_ms)
    local c_ms=$((c_end - c_start))
    echo "    -O2 complex compile: ${c_ms}ms"
    { echo "Compile time: ${c_ms}ms"; echo ""; } >> "${diag_file}"
  else
    echo "    -O2 complex compile: FAILED"
    { echo "Compile FAILED"; echo ""; } >> "${diag_file}"
  fi

  # Test linker speed separately
  echo "  Benchmark 2c: Linker speed"
  {
    echo ""
    echo "=== BENCHMARK: Linker ==="
    echo ""
  } >> "${diag_file}"

  # Compile to object file only, then link separately
  if ${bench_cc} -O2 -c -o "${bench_dir}/bench.o" "${bench_dir}/bench.c" 2>/dev/null; then
    c_start=$(_get_time_ms)
    if ${bench_cc} -o "${bench_dir}/bench_linked" "${bench_dir}/bench.o" >> "${diag_file}" 2>&1; then
      local c_end=$(_get_time_ms)
      local c_ms=$((c_end - c_start))
      echo "    Link single .o: ${c_ms}ms"
      { echo "Link time: ${c_ms}ms"; echo ""; } >> "${diag_file}"
    else
      echo "    Link: FAILED"
      { echo "Link FAILED"; echo ""; } >> "${diag_file}"
    fi
  else
    echo "    Link: SKIPPED (compile failed)"
  fi

  {
    echo "LD: ${LD:-default}"
    ${LD:-ld} --version 2>&1 | head -1 || echo "ld version unknown"
  } >> "${diag_file}"

  # ----------------------------------------
  # 7. BENCHMARK: Process spawn rate
  # ----------------------------------------
  echo "  Benchmark 3: Process spawn rate"
  {
    echo ""
    echo "=== BENCHMARK: Process Spawn Rate ==="
    echo ""
  } >> "${diag_file}"

  # Use /usr/bin/true on macOS, /bin/true on Linux
  local true_cmd="/bin/true"
  [[ "$(uname)" == "Darwin" ]] && true_cmd="/usr/bin/true"

  local spawn_start=$(_get_time_ms)
  for i in {1..100}; do
    ${true_cmd}
  done
  local spawn_end=$(_get_time_ms)
  local spawn_ms=$((spawn_end - spawn_start))
  local spawn_per_sec="N/A"
  if [[ ${spawn_ms} -gt 0 ]]; then
    spawn_per_sec=$((100 * 1000 / spawn_ms))
  fi
  echo "    100x /bin/true: ${spawn_ms}ms (${spawn_per_sec}/sec)"
  {
    echo "100x /bin/true: ${spawn_ms}ms"
    echo "Spawns per second: ${spawn_per_sec}"
  } >> "${diag_file}"

  # Test with actual command execution
  spawn_start=$(_get_time_ms)
  for i in {1..50}; do
    echo "test" > /dev/null
  done
  spawn_end=$(_get_time_ms)
  spawn_ms=$((spawn_end - spawn_start))
  echo "    50x echo: ${spawn_ms}ms"
  {
    echo "50x echo: ${spawn_ms}ms"
    echo ""
  } >> "${diag_file}"

  # ----------------------------------------
  # 8. BENCHMARK: Filesystem I/O
  # ----------------------------------------
  echo "  Benchmark 4: Filesystem I/O"
  {
    echo ""
    echo "=== BENCHMARK: Filesystem I/O ==="
    echo ""
  } >> "${diag_file}"

  # Create many small files (simulates GHC's .hi/.o file creation)
  local io_dir="${bench_dir}/io_test"
  mkdir -p "${io_dir}"

  local io_start=$(_get_time_ms)
  for i in {1..100}; do
    echo "test content for file ${i}" > "${io_dir}/file_${i}.txt"
  done
  local io_end=$(_get_time_ms)
  local io_write_ms=$((io_end - io_start))
  echo "    Create 100 files: ${io_write_ms}ms"
  {
    echo "Create 100 files: ${io_write_ms}ms"
  } >> "${diag_file}"

  # Read many small files
  io_start=$(_get_time_ms)
  for i in {1..100}; do
    cat "${io_dir}/file_${i}.txt" > /dev/null
  done
  io_end=$(_get_time_ms)
  local io_read_ms=$((io_end - io_start))
  echo "    Read 100 files: ${io_read_ms}ms"
  {
    echo "Read 100 files: ${io_read_ms}ms"
  } >> "${diag_file}"

  # Sync to measure actual write
  io_start=$(_get_time_ms)
  sync 2>/dev/null || true
  io_end=$(_get_time_ms)
  local sync_ms=$((io_end - io_start))
  echo "    sync: ${sync_ms}ms"
  {
    echo "sync: ${sync_ms}ms"
  } >> "${diag_file}"

  # Cleanup
  rm -rf "${io_dir}"

  # ----------------------------------------
  # 9. BENCHMARK: Parallel efficiency test
  # ----------------------------------------
  echo "  Benchmark 5: Parallel process test"
  {
    echo ""
    echo "=== BENCHMARK: Parallel Efficiency ==="
    echo ""
  } >> "${diag_file}"

  local par_count=${CPU_COUNT:-2}

  # Sequential baseline
  local seq_start=$(_get_time_ms)
  for i in $(seq 1 ${par_count}); do
    for j in {1..50}; do ${true_cmd}; done
  done
  local seq_end=$(_get_time_ms)
  local seq_ms=$((seq_end - seq_start))
  echo "    Sequential (${par_count}x50 spawns): ${seq_ms}ms"
  {
    echo "Sequential ${par_count}x50 spawns: ${seq_ms}ms"
  } >> "${diag_file}"

  # Parallel execution
  local par_start=$(_get_time_ms)
  for i in $(seq 1 ${par_count}); do
    ( for j in {1..50}; do ${true_cmd}; done ) &
  done
  wait
  local par_end=$(_get_time_ms)
  local par_ms=$((par_end - par_start))
  local speedup="N/A"
  if [[ ${par_ms} -gt 0 ]]; then
    speedup=$(awk "BEGIN {printf \"%.2f\", ${seq_ms}.0/${par_ms}.0}")
  fi
  echo "    Parallel (${par_count} workers): ${par_ms}ms (speedup: ${speedup}x)"
  {
    echo "Parallel ${par_count} workers: ${par_ms}ms"
    echo "Speedup: ${speedup}x (ideal: ${par_count}x)"
  } >> "${diag_file}"

  # ----------------------------------------
  # 10. Memory bandwidth (simple test)
  # ----------------------------------------
  echo "  Benchmark 6: Memory/disk write test"
  {
    echo ""
    echo "=== BENCHMARK: Memory/Disk ==="
    echo ""
  } >> "${diag_file}"

  # Use dd to test memory/disk throughput
  local mem_start=$(_get_time_ms)
  dd if=/dev/zero of="${bench_dir}/memtest" bs=1M count=100 2>/dev/null || true
  local mem_end=$(_get_time_ms)
  local mem_ms=$((mem_end - mem_start))
  local mem_mbps="N/A"
  if [[ ${mem_ms} -gt 0 ]]; then
    mem_mbps=$(awk "BEGIN {printf \"%.0f\", 100.0 * 1000.0 / ${mem_ms}.0}")
  fi
  echo "    Write 100MB: ${mem_ms}ms (${mem_mbps} MB/s)"
  {
    echo "Write 100MB: ${mem_ms}ms"
    echo "Throughput: ${mem_mbps} MB/s"
  } >> "${diag_file}"

  rm -f "${bench_dir}/memtest"

  # Cleanup bench dir
  rm -rf "${bench_dir}"

  local diag_end=$(date +%s)
  local diag_duration=$((diag_end - diag_start))

  {
    echo ""
    echo "========================================"
    echo "DIAGNOSTICS COMPLETE"
    echo "Duration: ${diag_duration}s"
    echo "========================================"
  } >> "${diag_file}"

  echo ""
  echo "  ✓ Diagnostics complete (${diag_duration}s)"
  echo "  Full report: ${diag_file}"
  echo ""
}

# ==============================================================================
# Helper Functions
# ==============================================================================

run_and_log() {
  local phase="$1"
  shift

  ((_log_index++)) || true
  mkdir -p "${SRC_DIR}/_logs"
  local log_file="${SRC_DIR}/_logs/$(printf "%02d" ${_log_index})-${phase}.log"

  echo "  Running: $*"
  echo "  Log: ${log_file}"

  local start_time=$(date +%s)
  "$@" > "${log_file}" 2>&1 || {
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    echo "*** Command failed after ${duration}s! Last 50 lines:"
    tail -50 "${log_file}"
    return 1
  }
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  local minutes=$((duration / 60))
  local seconds=$((duration % 60))
  echo "  ✓ ${phase} completed in ${minutes}m ${seconds}s"
  return 0
}

# ==============================================================================
# Build Profiling Functions
# ==============================================================================

# Start background process monitor
# Usage: start_process_monitor "phase-name"
start_process_monitor() {
  local phase="$1"
  local monitor_file="${SRC_DIR}/_logs/monitor-${phase}.log"

  echo "  Starting process monitor for ${phase}..."
  (
    echo "timestamp,ghc_procs,cabal_procs,cc_procs,ld_procs,total_procs" > "${monitor_file}"
    while true; do
      # Use ps + grep instead of pgrep for better cross-platform compatibility
      # Count processes containing these patterns in their command line
      local ghc_count=$(ps aux 2>/dev/null | grep -E '[g]hc|[g]hc-[0-9]|[g]hc-pkg|[g]hc-bin' | wc -l | tr -d ' ')
      local cabal_count=$(ps aux 2>/dev/null | grep -E '[c]abal' | wc -l | tr -d ' ')
      local cc_count=$(ps aux 2>/dev/null | grep -E '[c]lang|[g]cc' | grep -v 'ghc' | wc -l | tr -d ' ')
      local ld_count=$(ps aux 2>/dev/null | grep -E '[l]d\b|[l]d64|[l]ld' | wc -l | tr -d ' ')
      local total=$(ps aux 2>/dev/null | wc -l | tr -d ' ')
      echo "$(date +%s),${ghc_count},${cabal_count},${cc_count},${ld_count},${total}" >> "${monitor_file}"
      sleep 2
    done
  ) &
  MONITOR_PID=$!
  echo "  Monitor PID: ${MONITOR_PID}"
}

# Stop process monitor and print summary
# Usage: stop_process_monitor "phase-name"
stop_process_monitor() {
  local phase="$1"
  local monitor_file="${SRC_DIR}/_logs/monitor-${phase}.log"

  if [[ -n "${MONITOR_PID:-}" ]]; then
    kill "${MONITOR_PID}" 2>/dev/null || true
    wait "${MONITOR_PID}" 2>/dev/null || true
    unset MONITOR_PID
  fi

  if [[ -f "${monitor_file}" ]]; then
    local sample_count=$(( $(wc -l < "${monitor_file}" | tr -d ' ') - 1 ))
    local max_ghc=$(cut -d',' -f2 "${monitor_file}" | tail -n +2 | sort -n | tail -1)
    local max_cabal=$(cut -d',' -f3 "${monitor_file}" | tail -n +2 | sort -n | tail -1)
    local max_cc=$(cut -d',' -f4 "${monitor_file}" | tail -n +2 | sort -n | tail -1)
    local max_ld=$(cut -d',' -f5 "${monitor_file}" | tail -n +2 | sort -n | tail -1)

    echo "  === Process Monitor Summary for ${phase} ==="
    echo "  Samples:      ${sample_count}"
    echo "  Max GHC processes: ${max_ghc:-0}"
    echo "  Max Cabal processes: ${max_cabal:-0}"
    echo "  Max CC processes: ${max_cc:-0}"
    echo "  Max LD processes: ${max_ld:-0}"
    echo "  ==========================================="
  fi
}

# Run command with process monitoring and verbose timing
# Usage: run_and_log_profiled "phase" command args...
run_and_log_profiled() {
  local phase="$1"
  shift

  ((_log_index++)) || true
  mkdir -p "${SRC_DIR}/_logs"
  local log_file="${SRC_DIR}/_logs/$(printf "%02d" ${_log_index})-${phase}.log"
  local timing_file="${SRC_DIR}/_logs/$(printf "%02d" ${_log_index})-${phase}-timing.log"

  echo "  [PROFILED] Running: $*"
  echo "  Log: ${log_file}"
  echo "  Timing: ${timing_file}"

  # Start process monitor
  start_process_monitor "${phase}"

  local start_time=$(date +%s)
  local start_date=$(date '+%Y-%m-%d %H:%M:%S')

  # Run with time command for detailed resource usage
  { time "$@" ; } > "${log_file}" 2>&1 || {
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    stop_process_monitor "${phase}"
    echo "*** Command failed after ${duration}s! Last 50 lines:"
    tail -50 "${log_file}"
    return 1
  }

  local end_time=$(date +%s)
  local end_date=$(date '+%Y-%m-%d %H:%M:%S')
  local duration=$((end_time - start_time))
  local minutes=$((duration / 60))
  local seconds=$((duration % 60))

  # Stop monitor and get summary
  stop_process_monitor "${phase}"

  # Save timing info to file AND print to stdout
  {
    echo "Phase: ${phase}"
    echo "Start: ${start_date}"
    echo "End: ${end_date}"
    echo "Duration: ${minutes}m ${seconds}s (${duration}s)"
    echo "Command: $*"
  } | tee "${timing_file}"

  # Extract and print Hadrian timing info if present (from --timing flag)
  if [[ -f "${log_file}" ]]; then
    local timing_lines=$(grep -E "^(Build completed|Finished|Total time|spent|Rule .* took)" "${log_file}" 2>/dev/null | tail -20)
    if [[ -n "${timing_lines}" ]]; then
      echo "  --- Hadrian Timing Summary ---"
      echo "${timing_lines}" | sed 's/^/  /'
      echo "  ------------------------------"
    fi

    # Show slowest rules if timing data exists
    local slow_rules=$(grep -E "took [0-9]+\.[0-9]+s" "${log_file}" 2>/dev/null | sort -t' ' -k3 -rn | head -10)
    if [[ -n "${slow_rules}" ]]; then
      echo "  --- Top 10 Slowest Rules ---"
      echo "${slow_rules}" | sed 's/^/  /'
      echo "  ----------------------------"
    fi
  fi

  echo "  ✓ ${phase} completed in ${minutes}m ${seconds}s"
  return 0
}

# Install bash completion script
# Should be called from platform_post_install or default_post_install
install_bash_completion() {
  echo "  Installing bash completion..."
  mkdir -p "${PREFIX}/etc/bash_completion.d"
  if [[ -f "${SRC_DIR}/utils/completion/ghc.bash" ]]; then
    cp "${SRC_DIR}/utils/completion/ghc.bash" "${PREFIX}/etc/bash_completion.d/ghc"
    echo "  ✓ Bash completion installed"
  else
    echo "  WARNING: ghc.bash completion file not found at ${SRC_DIR}/utils/completion/ghc.bash"
  fi
}

# ==============================================================================
# Settings Update Helpers
# ==============================================================================

# Update stage settings file with library paths and rpaths
# This is commonly needed between build phases to ensure proper linking
#
# Usage:
#   update_stage_settings "stage0"
#   update_stage_settings "stage1"
#
# Parameters:
#   $1 - stage: Which stage settings to update (stage0, stage1)
#
update_stage_settings() {
  local stage="$1"
  local settings_file="${SRC_DIR}/_build/${stage}/lib/settings"

  if [[ ! -f "${settings_file}" ]]; then
    echo "  WARNING: ${stage} settings file not found at ${settings_file}"
    return 0
  fi

  # Check if flags are already present (idempotent operation)
  if grep -q "Wl,-L\${PREFIX}/lib" "${settings_file}" 2>/dev/null || \
     grep -q "Wl,-L${PREFIX}/lib" "${settings_file}" 2>/dev/null; then
    echo "  ${stage} settings already have library paths, skipping update"
    return 0
  fi

  echo "  Updating ${stage} settings with library paths..."

  # Add library paths and rpath
  perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib#" "${settings_file}"
  perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${PREFIX}/lib -rpath ${PREFIX}/lib#" "${settings_file}"

  echo "  ${stage} settings after update:"
  grep -E "(C compiler link flags|ld flags)" "${settings_file}" 2>/dev/null || echo "  (no matching lines)"

  echo "  ✓ ${stage} settings updated"
}

# Update settings file with platform-specific link flags
# Used by platform scripts to patch GHC settings during build
#
# Usage:
#   update_settings_link_flags "${settings_file}"
#
# Parameters:
#   $1 - settings_file: Path to GHC settings file
#   $2 - toolchain: Toolchain prefix (optional, defaults to $CONDA_TOOLCHAIN_HOST)
#   $3 - prefix: Install prefix (optional, defaults to $PREFIX)
#
update_settings_link_flags() {
  local settings_file="$1"
  local toolchain="${2:-$CONDA_TOOLCHAIN_HOST}"
  local prefix="${3:-$PREFIX}"

  if [[ "${target_platform}" == "linux-"* ]]; then
    perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -Wno-strict-prototypes#' "${settings_file}"
    perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -Wno-strict-prototypes#' "${settings_file}"

    perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L${BUILD_PREFIX}/lib -Wl,-L${prefix}/lib -Wl,-rpath,${BUILD_PREFIX}/lib -Wl,-rpath,${prefix}/lib#" "${settings_file}"
    perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${BUILD_PREFIX}/lib -L${prefix}/lib -rpath ${BUILD_PREFIX}/lib -rpath ${prefix}/lib#" "${settings_file}"

  elif [[ "${target_platform}" == "osx-64" ]]; then
    # Add -fno-lto DURING build to prevent ABI mismatches and runtime crashes
    perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"
    perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"
    perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -fno-lto -Wl,-L${prefix}/lib -Wl,-liconv -Wl,-L${prefix}/lib/ghc-${PKG_VERSION}/lib -Wl,-liconv_compat#" "${settings_file}"
    perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${prefix}/lib -liconv -L${prefix}/lib/ghc-${PKG_VERSION}/lib -liconv_compat#" "${settings_file}"

  elif [[ "${target_platform}" == "osx-arm64" ]]; then
    # Add -fno-lto DURING build to prevent ABI mismatches and runtime crashes
    perl -pi -e 's#(C compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"
    perl -pi -e 's#(C\+\+ compiler flags", "[^"]*)#$1 -fno-lto#' "${settings_file}"
    perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -fuse-ld=lld -fno-lto -Wl,-L${prefix}/lib -Wl,-liconv -Wl,-L${prefix}/lib/ghc-${PKG_VERSION}/lib -Wl,-liconv_compat#" "${settings_file}"
    perl -pi -e "s#(ld flags\", \"[^\"]*)#\$1 -L${prefix}/lib -liconv -L${prefix}/lib/ghc-${PKG_VERSION}/lib -liconv_compat#" "${settings_file}"
  fi

  # Update toolchain paths (strip absolute paths, keep tool name with prefix)
  # Note: [/\w] doesn't match hyphen, use [^"]* then capture prefix-tool pattern
  perl -pi -e "s#\"[^\"]*/([^/]*-)(ar|as|clang|clang\+\+|ld|nm|objdump|ranlib|llc|opt)\"#\"\$1\$2\"#g" "${settings_file}"
}

# Set macOS-specific ar and ranlib settings for LLVM toolchain
# Apple ld64 requires LLVM ar instead of GNU ar
#
# Usage:
#   set_macos_conda_ar_ranlib "${settings_file}"
#
# Parameters:
#   $1 - settings_file: Path to GHC settings file
#   $2 - toolchain: Toolchain prefix (optional, defaults to x86_64-apple-darwin13.4.0)
#
set_macos_conda_ar_ranlib() {
  local settings_file="$1"
  local toolchain="${2:-x86_64-apple-darwin13.4.0}"

  if [[ -f "$settings_file" ]]; then
    if [[ "$(basename "${settings_file}")" == "default."* ]]; then
      # Use LLVM ar instead of GNU ar for compatibility with Apple ld64
      perl -i -pe 's#(arMkArchive\s*=\s*).*#$1Program {prgPath = "llvm-ar", prgFlags = ["qcs"]}#g' "${settings_file}"
      perl -i -pe 's#((arIsGnu|arSupportsAtFile)\s*=\s*).*#$1False#g' "${settings_file}"
      perl -i -pe 's#(arNeedsRanlib\s*=\s*).*#$1False#g' "${settings_file}"
      perl -i -pe 's#(tgtRanlib\s*=\s*).*#$1Nothing#g' "${settings_file}"
    else
      # Use LLVM ar instead of GNU ar for compatibility with Apple ld64
      perl -i -pe 's#("ar command", ")[^"]*#$1llvm-ar#g' "${settings_file}"
      perl -i -pe 's#("ar flags", ")[^"]*#$1qcs#g' "${settings_file}"
      perl -i -pe "s#(\"(clang|llc|opt|ranlib) command\", \")[^\"]*#\$1${toolchain}-\$2#g" "${settings_file}"
    fi
  else
    echo "Error: $settings_file not found!"
    exit 1
  fi
}

# Update installed GHC settings with final link flags and toolchain paths
# Called after GHC is installed to PREFIX
#
# Usage:
#   update_installed_settings
#   update_installed_settings "x86_64-apple-darwin13.4.0"
#
# Parameters:
#   $1 - toolchain: Toolchain prefix (optional, defaults to $CONDA_TOOLCHAIN_HOST)
#
update_installed_settings() {
  local toolchain="${1:-$CONDA_TOOLCHAIN_HOST}"

  local settings_file=$(find "${PREFIX}/lib" -name settings | head -n 1)
  if [[ "${target_platform}" == "linux-"* ]]; then
    perl -pi -e "s#(C compiler link flags\", \"[^\"]*)#\$1 -Wl,-L\\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -Wl,-rpath,\\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -Wl,-L\\\$topdir/../../../lib -Wl,-rpath,\\\$topdir/../../../lib#" "${settings_file}"
    perl -pi -e "s#(ld flags\", \")#\$1-L\\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -rpath \\\$topdir/x86_64-linux-ghc-${PKG_VERSION} -L\\\$topdir/../../../lib -rpath \\\$topdir/../../../lib#" "${settings_file}"

  elif [[ "${target_platform}" == "osx-"* ]]; then
    perl -i -pe "s#(C compiler flags\", \")([^\"]*)#\1\2 -fno-lto#" "${settings_file}"
    perl -i -pe "s#(C\\+\\+ compiler flags\", \")([^\"]*)#\1\2 -fno-lto#" "${settings_file}"
    perl -i -pe "s#(C compiler link flags\", \")([^\"]*)#\1\2 -v -fuse-ld=lld -fno-lto -fno-use-linker-plugin -Wl,-L\\\$topdir/../../../lib -Wl,-rpath,\\\$topdir/../../../lib -liconv -Wl,-L\\\$topdir/../lib -Wl,-rpath,\\\$topdir/../lib -liconv_compat#" "${settings_file}"
  fi

  # Remove build-time paths
  perl -pi -e "s#(-Wl,-L${BUILD_PREFIX}/lib|-Wl,-L${PREFIX}/lib|-Wl,-rpath,${BUILD_PREFIX}/lib|-Wl,-rpath,${PREFIX}/lib)##g" "${settings_file}"
  perl -pi -e "s#(-L${BUILD_PREFIX}/lib|-L${PREFIX}/lib|-rpath ${PREFIX}/lib|-rpath ${BUILD_PREFIX}/lib)##g" "${settings_file}"

  # Update toolchain paths (strip absolute paths, keep tool name with prefix)
  # Note: [/\w] doesn't match hyphen, use [^"]* then capture prefix-tool pattern
  perl -pi -e "s#\"[^\"]*/([^/]*-)(ar|as|clang|clang\+\+|ld|nm|objdump|ranlib|llc|opt)\"#\"\$1\$2\"#g" "${settings_file}"
}

# ==============================================================================
# Cross-Compilation Helpers
# ==============================================================================

# Disable Hadrian's copy optimization for cross-compilation
# By default, Hadrian tries to copy the bootstrap GHC binary instead of building
# a new one. For cross-compilation, we need to force building the cross binary.
#
# Usage:
#   disable_copy_optimization
#
disable_copy_optimization() {
  echo "  Disabling copy optimization for cross-compilation..."

  # Force building the cross binary instead of copying
  perl -i -pe 's/\(True, s\) \| s > stage0InTree ->/\(False, s\) | s > stage0InTree \&\& False ->/' \
    "${SRC_DIR}/hadrian/src/Rules/Program.hs"

  echo "  ✓ Copy optimization disabled"
}

# ==============================================================================
# Phase 1: Environment Setup
# ==============================================================================

phase_setup_environment() {
  echo ""
  echo "===================================================================="
  echo "  Phase 1: Environment Setup"
  echo "===================================================================="

  call_hook "pre_setup_environment"

  if type -t platform_setup_environment >/dev/null 2>&1; then
    platform_setup_environment
  else
    default_setup_environment
  fi

  call_hook "post_setup_environment"

  echo "  ✓ Environment setup complete"
  echo ""
}

default_setup_environment() {
  # Common environment setup (Linux/macOS)
  export PATH="${BUILD_PREFIX}/bin:${BUILD_PREFIX}/ghc-bootstrap/bin:${PATH}"
  export M4="${BUILD_PREFIX}/bin/m4"
  export PYTHON="${BUILD_PREFIX}/bin/python"

  echo "  Standard environment configured"
}

# ==============================================================================
# Phase 2: Bootstrap Setup
# ==============================================================================

phase_setup_bootstrap() {
  echo ""
  echo "===================================================================="
  echo "  Phase 2: Bootstrap Setup"
  echo "===================================================================="

  call_hook "pre_setup_bootstrap"

  if type -t platform_setup_bootstrap >/dev/null 2>&1; then
    platform_setup_bootstrap
  else
    default_setup_bootstrap
  fi

  call_hook "post_setup_bootstrap"

  # Verify bootstrap GHC
  if [[ -n "${GHC:-}" ]]; then
    echo "  Bootstrap GHC: ${GHC}"
    "${GHC}" --version || {
      echo "ERROR: Bootstrap GHC failed"
      exit 1
    }
  fi

  echo "  ✓ Bootstrap setup complete"
  echo ""
}

default_setup_bootstrap() {
  # Find bootstrap GHC
  export GHC=$(which ghc 2>/dev/null || echo "")
  if [[ -z "${GHC}" ]]; then
    echo "ERROR: Bootstrap GHC not found in PATH"
    exit 1
  fi

  echo "  Bootstrap GHC found: ${GHC}"
}

# ==============================================================================
# Phase 3: Cabal Setup
# ==============================================================================

phase_setup_cabal() {
  echo ""
  echo "===================================================================="
  echo "  Phase 3: Cabal Setup"
  echo "===================================================================="

  call_hook "pre_setup_cabal"

  if type -t platform_setup_cabal >/dev/null 2>&1; then
    platform_setup_cabal
  else
    default_setup_cabal
  fi

  call_hook "post_setup_cabal"

  echo "  ✓ Cabal setup complete"
  echo ""
}

default_setup_cabal() {
  export CABAL="${BUILD_PREFIX}/bin/cabal"
  export CABAL_DIR="${HOME}/.cabal"

  mkdir -p "${CABAL_DIR}"

  # Initialize cabal if config doesn't exist
  if [[ ! -f "${CABAL_DIR}/config" ]]; then
    "${CABAL}" user-config init
  fi

  # Update package index
  run_and_log "cabal-update" "${CABAL}" v2-update
}

# ==============================================================================
# Phase 4: Configure GHC
# ==============================================================================

phase_configure_ghc() {
  echo ""
  echo "===================================================================="
  echo "  Phase 4: Configure GHC"
  echo "===================================================================="

  call_hook "pre_configure_ghc"

  if type -t platform_configure_ghc >/dev/null 2>&1; then
    platform_configure_ghc
  else
    default_configure_ghc
  fi

  call_hook "post_configure_ghc"

  echo "  ✓ GHC configure complete"
  echo ""
}

default_configure_ghc() {
  # Build configure arguments
  local configure_args=(
    --prefix="${PREFIX}"
    --enable-distro-toolchain
    --with-intree-gmp=no
    --with-gmp-includes="${PREFIX}/include"
    --with-gmp-libraries="${PREFIX}/lib"
    --with-ffi-includes="${PREFIX}/include"
    --with-ffi-libraries="${PREFIX}/lib"
    --with-iconv-includes="${PREFIX}/include"
    --with-iconv-libraries="${PREFIX}/lib"
    --with-curses-includes="${PREFIX}/include"
    --with-curses-libraries="${PREFIX}/lib"
  )

  # Add platform-specific args if provided
  if type -t platform_add_configure_args >/dev/null 2>&1; then
    platform_add_configure_args configure_args
  fi

  # Run configure
  pushd "${SRC_DIR}" >/dev/null
  run_and_log "configure" ./configure "${configure_args[@]}"
  popd >/dev/null
}

# ==============================================================================
# Phase 5: Build Hadrian
# ==============================================================================

phase_build_hadrian() {
  echo ""
  echo "===================================================================="
  echo "  Phase 5: Build Hadrian"
  echo "===================================================================="

  call_hook "pre_build_hadrian"

  if type -t platform_build_hadrian >/dev/null 2>&1; then
    platform_build_hadrian
  else
    default_build_hadrian
  fi

  call_hook "post_build_hadrian"

  echo "  Hadrian command: ${HADRIAN_CMD[*]}"
  echo "  ✓ Hadrian build complete"
  echo ""
}

default_build_hadrian() {
  pushd "${SRC_DIR}/hadrian" >/dev/null
    run_and_log "build-hadrian" "${CABAL}" v2-build hadrian
  popd >/dev/null

  # Find Hadrian binary
  local hadrian_bin=$(find "${SRC_DIR}"/hadrian/dist-newstyle -name hadrian -type f | head -1)

  if [[ ! -f "${hadrian_bin}" ]]; then
    echo "ERROR: Hadrian binary not found after build"
    exit 1
  fi

  # Set up Hadrian command array
  HADRIAN_CMD=("${hadrian_bin}" "-j${CPU_COUNT:-1}" "--directory" "${SRC_DIR}")
  HADRIAN_FLAVOUR="${HADRIAN_FLAVOUR:-release}"
}

# ==============================================================================
# Phase 6: Build Stage 1
# ==============================================================================

phase_build_stage1() {
  echo ""
  echo "===================================================================="
  echo "  Phase 6: Build Stage 1"
  echo "===================================================================="

  call_hook "pre_build_stage1"

  if type -t platform_build_stage1 >/dev/null 2>&1; then
    platform_build_stage1
  else
    default_build_stage1
  fi

  call_hook "post_build_stage1"

  echo "  ✓ Stage 1 build complete"
  echo ""
}

default_build_stage1() {
  # Build Stage 1 GHC executables
  options=(--flavour="${HADRIAN_FLAVOUR}" --docs=none --progress-info=none)
  run_and_log    "stage1-ghc" "${HADRIAN_CMD[@]}" ${options[@]} stage1:exe:ghc-bin
  run_and_log    "stage1-pkg" "${HADRIAN_CMD[@]}" ${options[@]} stage1:exe:ghc-pkg
  run_and_log "stage1-hsc2hs" "${HADRIAN_CMD[@]}" ${options[@]} stage1:exe:hsc2hs

  # Update stage0 settings before building libraries (if helper available)
  if type -t update_stage_settings >/dev/null 2>&1; then
    update_stage_settings "stage0"
  fi

  # Build Stage 1 libraries in staggered order to avoid race conditions
  run_and_log   "stage1-lib-prim" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:lib:ghc-prim
  run_and_log "stage1-lib-bignum" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:lib:ghc-bignum
  run_and_log   "stage1-lib-base" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:lib:base
  run_and_log     "stage1-lib-th" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:lib:template-haskell
  run_and_log   "stage1-lib-ghci" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:lib:ghci
  run_and_log    "stage1-lib-ghc" "${HADRIAN_CMD[@]}" "${options[@]}" stage1:lib:ghc

  # Update stage0 settings again after library build
  if type -t update_stage_settings >/dev/null 2>&1; then
    update_stage_settings "stage0"
  fi
}

# ==============================================================================
# Phase 7: Build Stage 2
# ==============================================================================

phase_build_stage2() {
  echo ""
  echo "===================================================================="
  echo "  Phase 7: Build Stage 2"
  echo "===================================================================="

  call_hook "pre_build_stage2"

  if type -t platform_build_stage2 >/dev/null 2>&1; then
    platform_build_stage2
  else
    default_build_stage2
  fi

  call_hook "post_build_stage2"

  echo "  ✓ Stage 2 build complete"
  echo ""
}

default_build_stage2() {
  # Build Stage 2 GHC libraries
  options=(--flavour="${HADRIAN_FLAVOUR}" --docs=none --progress-info=none)
  run_and_log    "stage2-ghc" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:exe:ghc-bin
  run_and_log    "stage2-pkg" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:exe:ghc-pkg
  run_and_log "stage2-hsc2hs" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:exe:hsc2hs

  # Build Stage 1 libraries in staggered order to avoid race conditions
  run_and_log   "stage2-lib-prim" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:ghc-prim
  run_and_log "stage2-lib-bignum" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:ghc-bignum
  run_and_log   "stage2-lib-base" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:base
  run_and_log     "stage2-lib-th" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:template-haskell
  run_and_log   "stage2-lib-ghci" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:ghci
  run_and_log    "stage2-lib-ghc" "${HADRIAN_CMD[@]}" "${options[@]}" stage2:lib:ghc
}

# ==============================================================================
# Phase 8: Install GHC
# ==============================================================================

phase_install_ghc() {
  echo ""
  echo "===================================================================="
  echo "  Phase 8: Install GHC"
  echo "===================================================================="

  call_hook "pre_install_ghc"

  if type -t platform_install_ghc >/dev/null 2>&1; then
    platform_install_ghc
  else
    default_install_ghc
  fi

  call_hook "post_install_ghc"

  echo "  ✓ GHC installation complete"
  echo ""
}

default_install_ghc() {
  # Create binary distribution (--docs=none to skip documentation build)
  run_and_log "binary-dist" "${HADRIAN_CMD[@]}" --flavour="${HADRIAN_FLAVOUR}" binary-dist --prefix="${PREFIX}" --docs=none

  # Find bindist directory
  local bindist_dir=$(find "${SRC_DIR}"/_build/bindist -type d -name "ghc-${PKG_VERSION}-*" | head -1)

  if [[ -z "${bindist_dir}" ]]; then
    echo "ERROR: Binary distribution directory not found"
    exit 1
  fi

  echo "  Installing from: ${bindist_dir}"

  # Install from bindist
  pushd "${bindist_dir}" >/dev/null
    ./configure --prefix="${PREFIX}" || { cat config.log; exit 1; }
    run_and_log "make-install" make install
  popd >/dev/null
}

# ==============================================================================
# Phase 9: Post-Install
# ==============================================================================

phase_post_install() {
  echo ""
  echo "===================================================================="
  echo "  Phase 9: Post-Install"
  echo "===================================================================="

  call_hook "pre_post_install"

  if type -t platform_post_install >/dev/null 2>&1; then
    platform_post_install
  else
    default_post_install
  fi

  call_hook "post_post_install"

  echo "  ✓ Post-install complete"
  echo ""
}

default_post_install() {
  # Verify installation
  echo "  Verifying GHC installation..."
  "${PREFIX}/bin/ghc" --version || {
    echo "ERROR: Installed GHC failed to run"
    exit 1
  }

  install_bash_completion

  echo "  GHC installed successfully"
}

# ==============================================================================
# Phase 10: Activation
# ==============================================================================

phase_activation() {
  echo ""
  echo "===================================================================="
  echo "  Phase 10: Activation"
  echo "===================================================================="

  if type -t platform_activation >/dev/null 2>&1; then
    platform_activation
  else
    default_activation
  fi

  echo "  ✓ Post-install complete"
  echo ""
}

default_activation() {
  # Verify installation
  echo "  Activation GHC installation..."

  case "${target_platform}" in
    linux-64|linux-aarch64|linux-ppc64le|osx-64|osx-arm64)
      sh_ext="sh"
      ;;
    *)
      sh_ext="bat"
      ;;
  esac
  
  mkdir -p "${PREFIX}"/etc/conda/activate.d/
  cp ${RECIPE_DIR}/activate.${sh_ext} ${PREFIX}/etc/conda/activate.d/ghc_activate.${sh_ext}
  echo "  GHC installed successfully"
}

# ==============================================================================
# Hook Execution Helper
# ==============================================================================

call_hook() {
  local hook_name="platform_$1"
  if type -t "${hook_name}" >/dev/null 2>&1; then
    "${hook_name}"
  fi
}
