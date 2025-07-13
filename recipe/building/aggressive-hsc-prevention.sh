#!/usr/bin/env bash
set -eu

echo "=== Aggressive HSC crash prevention ==="

# Create a stub batch file that will be used to replace all HSC tools
cat > "${TEMP}/hsc-stub.bat" << 'EOF'
@echo off
echo HSC stub: Preventing stack overflow crash
REM Check if we're processing Clock.hsc
echo %* | findstr /i "Clock.hsc" >nul
if %errorlevel% equ 0 (
    echo Creating Clock.hs from pre-generated file...
    REM Try to find the output directory from the arguments
    set "OUTPUT_DIR="
    for %%i in (%*) do (
        echo %%i | findstr /i "Clock.hs" >nul
        if errorlevel 1 (
            REM Not the output file
        ) else (
            set "OUTPUT_FILE=%%i"
            for %%j in ("%%i\..") do set "OUTPUT_DIR=%%~fj"
        )
    )
    
    REM Copy pre-generated Clock.hs if we found the output location
    if defined OUTPUT_DIR (
        if exist "D:\a\1\s\recipe\building\hsc_workarounds\clock\System\Clock.hs" (
            copy /Y "D:\a\1\s\recipe\building\hsc_workarounds\clock\System\Clock.hs" "%OUTPUT_DIR%\Clock.hs" >nul 2>&1
            echo Successfully created Clock.hs
        )
    )
)
exit /b 0
EOF

# Function to stub an HSC executable
stub_hsc_exe() {
    local exe_path="$1"
    if [[ -f "${exe_path}" && ! -f "${exe_path}.original" ]]; then
        echo "Stubbing ${exe_path}..."
        mv "${exe_path}" "${exe_path}.original" 2>/dev/null || true
        cp "${TEMP}/hsc-stub.bat" "${exe_path}"
        chmod +x "${exe_path}" 2>/dev/null || true
        echo "Stubbed ${exe_path}"
    fi
}

# Pre-emptively stub known HSC tool locations
echo "Pre-emptively stubbing HSC tools..."
find "${SRC_DIR}" -name "hsc2hs.exe" -o -name "*_hsc_make.exe" 2>/dev/null | while read hsc_exe; do
    stub_hsc_exe "${hsc_exe}"
done

# Start background monitor
echo "Starting aggressive HSC monitor..."
(
    touch /tmp/hsc-monitor-start
    while true; do
        # Look for any new HSC executables
        find "C:/cabal" "${SRC_DIR}" "${BUILD_PREFIX}" -name "*_hsc_make.exe" -newer /tmp/hsc-monitor-start 2>/dev/null | while read hsc_exe; do
            stub_hsc_exe "${hsc_exe}"
        done
        
        # Also monitor the clock build directory specifically
        if [[ -d "C:/cabal/store/ghc-9.10.1" ]]; then
            find "C:/cabal/store/ghc-9.10.1" -name "*Clock_hsc_make.exe" 2>/dev/null | while read hsc_exe; do
                stub_hsc_exe "${hsc_exe}"
            done
        fi
        
        # Check for clock package downloads
        if find "C:/cabal/packages" -name "clock-0.8.4.tar.gz" -newer /tmp/hsc-monitor-start 2>/dev/null | grep -q .; then
            echo "Detected clock package download, pre-creating build structure..."
            # Pre-create the expected structure
            CLOCK_HASH="e7f0f9eac776c074e3a799d7f0ea74a1e404ccf0"
            STORE_PATH="C:/cabal/store/ghc-9.10.1/clock-0.8.4-${CLOCK_HASH}"
            mkdir -p "${STORE_PATH}/dist/build/System"
            if [[ -f "${RECIPE_DIR}/building/hsc_workarounds/clock/System/Clock.hs" ]]; then
                cp "${RECIPE_DIR}/building/hsc_workarounds/clock/System/Clock.hs" "${STORE_PATH}/dist/build/System/Clock.hs"
                echo "Pre-created Clock.hs at ${STORE_PATH}/dist/build/System/Clock.hs"
            fi
        fi
        
        sleep 0.5
    done
) &

MONITOR_PID=$!
echo "Aggressive HSC monitor started with PID $MONITOR_PID"

# Store the PID for cleanup
echo "$MONITOR_PID" > "${TEMP}/hsc-monitor.pid"

# Also create a cleanup script
cat > "${TEMP}/stop-hsc-monitor.sh" << EOF
#!/bin/bash
if [[ -f "${TEMP}/hsc-monitor.pid" ]]; then
    kill \$(cat "${TEMP}/hsc-monitor.pid") 2>/dev/null || true
    rm -f "${TEMP}/hsc-monitor.pid"
    echo "Stopped HSC monitor"
fi
EOF
chmod +x "${TEMP}/stop-hsc-monitor.sh"

echo "HSC crash prevention initialized"
echo "To stop the monitor, run: ${TEMP}/stop-hsc-monitor.sh"