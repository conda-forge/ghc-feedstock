
# Function to run a command, log its output, and increment log index
run_and_log() {
  local _logname="$1"
  shift
  local cmd=("$@")

  # Create log directory if it doesn't exist
  mkdir -p "${SRC_DIR}/_logs"

  echo " ";echo "|";echo "|";echo "|";echo "|"
  echo "Running: ${cmd[*]}"
  local start_time=$(date +%s)
  local exit_status_file=$(mktemp)
  # Run the command in a subshell to prevent set -e from terminating
  (
    # Temporarily disable errexit in this subshell
    set +e
    "${cmd[@]}" > "${SRC_DIR}/_logs/${_log_index}_${_logname}.log" 2>&1
    echo $? > "$exit_status_file"
  ) &
  local cmd_pid=$!
  local tail_counter=0

  # Periodically flush and show progress
  while kill -0 $cmd_pid 2>/dev/null; do
    sync
    echo -n "."
    sleep 5
    let "tail_counter += 1"

    if [ $tail_counter -ge 22 ]; then
      echo "."
      tail -5 "${SRC_DIR}/_logs/${_log_index}_${_logname}.log"
      tail_counter=0
    fi
  done

  wait $cmd_pid || true  # Use || true to prevent set -e from triggering
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  local exit_code=$(cat "$exit_status_file")
  rm "$exit_status_file"

  echo "."
  echo "─────────────────────────────────────────"
  printf "Command: %s\n" "${cmd[*]} in ${duration}s"
  echo "Exit code: $exit_code"
  echo "─────────────────────────────────────────"

  # Show more context on failure
  if [[ $exit_code -ne 0 ]]; then
    echo "COMMAND FAILED - Last 50 lines of log:"
    tail -50 "${SRC_DIR}/_logs/${_log_index}_${_logname}.log"
  else
    echo "COMMAND SUCCEEDED - Last 20 lines of log:"
    tail -20 "${SRC_DIR}/_logs/${_log_index}_${_logname}.log"
  fi

  echo "─────────────────────────────────────────"
  echo "Full log: ${SRC_DIR}/_logs/${_log_index}_${_logname}.log"
  echo "|";echo "|";echo "|";echo "|"

  let "_log_index += 1"
  return $exit_code
}

# Function to calculate relative path from one directory to another
calculate_relative_path() {
    local from_path="$1"
    local to_path="$2"

    # Convert to absolute paths
    from_path=$(realpath "$from_path")
    to_path=$(realpath "$to_path")

    # Use Python to calculate relative path (most reliable)
    python3 -c "
import os
print(os.path.relpath('$to_path', '$from_path'))
"
}

# Function to convert relative path to $ORIGIN-based rpath
calculate_origin_rpath() {
    local binary_path="$1"
    local target_lib_path="$2"

    # Get directory containing the binary
    local binary_dir=$(dirname "$binary_path")

    # Calculate relative path from binary dir to target lib
    local rel_path=$(calculate_relative_path "$binary_dir" "$target_lib_path")

    # Convert to $ORIGIN syntax
    echo "\$ORIGIN/$rel_path"
}

# Function to set the system ar/ranlib for OSX
set_macos_system_ar_ranlib() {
  local settings_file="$1"

  if [[ -f "$settings_file" ]]; then
    if [[ "$(basename "${settings_file}")" == "default."* ]]; then
      perl -i -pe "s#(arMkArchive\s*=\s*).*#\$1Program {prgPath = \"/usr/bin/ar\", prgFlags = [\"qcls\"]}#g" "${settings_file}"
      perl -i -pe 's#((arIsGnu|arSupportsAtFile)\s*=\s*).*#$1False#g' "${settings_file}"
      perl -i -pe 's#(arNeedsRanlib\s*=\s*).*#$1True#g' "${settings_file}"
      perl -i -pe "s#(tgtRanlib\s*=\s*).*#\$1Just (Ranlib {ranlibProgram = Program {prgPath = \"/usr/bin/ranlib\", prgFlags = []}})#g" "${settings_file}"
    else
      perl -i -pe "s#(\"ar command\", \")[^\"]*#\$1/usr/bin/ar#g" "${settings_file}"
      perl -i -pe "s#(\"ar flags\", \")[^\"]*#\$1qcls#g" "${settings_file}"
      perl -i -pe "s#(\"ranlib command\", \")[^\"]*#\$1/usr/bin/ranlib#g" "${settings_file}"
    fi
  else
    echo "Error: $settings_file not found!"
    exit 1
  fi
}

# Function to set the conda ar/ranlib for OSX
set_macos_conda_ar_ranlib() {
  local settings_file="$1"
  local toolchain="${2:-x86_64-apple-darwin13.4.0}"

  if [[ -f "$settings_file" ]]; then
    if [[ "$(basename "${settings_file}")" == "default."* ]]; then
      perl -i -pe "s#(arMkArchive\s*=\s*).*#\$1Program {prgPath = \"${toolchain}-ar\", prgFlags = [\"qcsS\"]}#g" "${settings_file}"
      perl -i -pe 's#((arIsGnu|arSupportsAtFile)\s*=\s*).*#$1True#g' "${settings_file}"
      perl -i -pe 's#(arNeedsRanlib\s*=\s*).*#$1False#g' "${settings_file}"
      perl -i -pe "s#(tgtRanlib\s*=\s*).*#\$1Just (Ranlib {ranlibProgram = Program {prgPath = \"${toolchain}-ranlib\", prgFlags = []}})#g" "${settings_file}"
    else
      perl -i -pe "s#(\"ar command\", \")[^\"]*#\$1${toolchain}-ar#g" "${settings_file}"
      perl -i -pe "s#(\"ar flags\", \")[^\"]*#\$1qcsS#g" "${settings_file}"
      perl -i -pe "s#(\"ranlib command\", \")[^\"]*#\$1${toolchain}-ranlib#g" "${settings_file}"
    fi
  else
    echo "Error: $settings_file not found!"
    exit 1
  fi
}
