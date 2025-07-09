#!/usr/bin/env bash
set -eu

echo "=== Stubbing HSC tools to prevent crashes ==="

# Function to create a stub batch file
create_stub() {
    local tool_path="$1"
    
    if [[ -f "${tool_path}" ]]; then
        # Backup original if not already backed up
        if [[ ! -f "${tool_path}.original" ]]; then
            mv "${tool_path}" "${tool_path}.original"
        fi
        
        # Create stub batch file
        cat > "${tool_path}" << 'EOF'
@echo off
REM Stub HSC tool - just returns success
REM The actual .hs files should be pre-generated
exit /b 0
EOF
        echo "Stubbed: ${tool_path}"
    fi
}

# Find and stub all Clock_hsc_make.exe files in the cabal store
echo "Looking for Clock_hsc_make.exe to stub..."
find "C:/cabal/store" -name "Clock_hsc_make.exe" 2>/dev/null | while read hsc_tool; do
    create_stub "${hsc_tool}"
done

# Also look in the dist directories
find "C:/cabal/dist-newstyle" -name "Clock_hsc_make.exe" 2>/dev/null | while read hsc_tool; do
    create_stub "${hsc_tool}"
done

# Look in temp directories where Cabal might be building
find "${TEMP}" -name "Clock_hsc_make.exe" 2>/dev/null | head -20 | while read hsc_tool; do
    create_stub "${hsc_tool}"
done

# Pre-create the expected Clock.hs file in common locations
echo "Pre-creating Clock.hs files..."

# Function to ensure Clock.hs exists
ensure_clock_hs() {
    local dir="$1"
    if [[ -d "${dir}" ]]; then
        if [[ ! -f "${dir}/Clock.hs" ]]; then
            if [[ -f "${RECIPE_DIR}/building/hsc_workarounds/clock/System/Clock.hs" ]]; then
                cp "${RECIPE_DIR}/building/hsc_workarounds/clock/System/Clock.hs" "${dir}/Clock.hs"
                echo "Created Clock.hs in ${dir}"
            fi
        fi
    fi
}

# Check common build directories
find "C:/cabal/store" -type d -name "System" -path "*/clock-*/dist*/build/*" 2>/dev/null | while read sys_dir; do
    ensure_clock_hs "${sys_dir}"
done

echo "=== HSC tool stubbing completed ==="