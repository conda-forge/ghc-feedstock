#!/usr/bin/env bash
set -eu

echo "=== Intercepting clock build to prevent HSC crashes ==="

# Set up environment
export GHC="${SRC_DIR}\\bootstrap-ghc\\bin\\ghc.exe"

# Create a monitor script that will run in background
cat > "${TEMP}/clock-build-interceptor.sh" << 'EOF'
#!/usr/bin/env bash

echo "Clock build interceptor started..."

while true; do
    # Look for any Clock_hsc_make.exe that gets created
    if find "C:/cabal" -name "*Clock_hsc_make.exe" -newer /tmp/interceptor-start 2>/dev/null | grep -q .; then
        echo "Found Clock_hsc_make.exe, replacing with stub..."
        
        find "C:/cabal" -name "*Clock_hsc_make.exe" -newer /tmp/interceptor-start 2>/dev/null | while read hsc_exe; do
            if [[ -f "${hsc_exe}" ]]; then
                echo "Intercepting: ${hsc_exe}"
                
                # Get the directory where Clock.hs should go
                hsc_dir=$(dirname "${hsc_exe}")
                
                # Create the Clock.hs file instead of running the tool
                if [[ -f "D:/a/1/s/recipe/building/hsc_workarounds/clock/System/Clock.hs" ]]; then
                    cp "D:/a/1/s/recipe/building/hsc_workarounds/clock/System/Clock.hs" "${hsc_dir}/Clock.hs"
                    echo "Created ${hsc_dir}/Clock.hs"
                fi
                
                # Replace the HSC tool with a stub that just exits successfully
                mv "${hsc_exe}" "${hsc_exe}.original" 2>/dev/null || true
                cat > "${hsc_exe}" << 'HSCEOF'
@echo off
echo HSC interceptor: Using pre-generated Clock.hs
exit /b 0
HSCEOF
                echo "Stubbed ${hsc_exe}"
            fi
        done
    fi
    
    sleep 1
done
EOF

chmod +x "${TEMP}/clock-build-interceptor.sh"

# Create marker file for "newer than" checks
touch /tmp/interceptor-start

# Start the interceptor in background
"${TEMP}/clock-build-interceptor.sh" &
INTERCEPTOR_PID=$!

echo "Clock build interceptor started with PID $INTERCEPTOR_PID"
echo "Interceptor will monitor for Clock_hsc_make.exe and replace with stubs"

# Store the PID so we can kill it later
echo "$INTERCEPTOR_PID" > "${TEMP}/clock-interceptor.pid"