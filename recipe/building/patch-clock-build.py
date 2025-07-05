#!/usr/bin/env python
"""
Patch the clock package build process to work around HSC2HS crashes.
"""
import os
import sys
import glob
import shutil
import subprocess

def find_clock_dir():
    """Find the directory where the clock package is being built."""
    # Common patterns for cabal build directories
    patterns = [
        "**/clock-*/",
        "**/clock-*.*.*/"
    ]

    for pattern in patterns:
        dirs = glob.glob(pattern, recursive=True)
        for d in dirs:
            if os.path.isdir(d) and "dist" in os.listdir(d):
                return d

    return None

def patch_clock_makefile(clock_dir):
    """Patch the Clock Makefile to use our pre-generated HS file."""
    if not clock_dir:
        print("Error: Could not find clock build directory")
        return False

    # Find the System directory with the Makefile
    system_dir = os.path.join(clock_dir, "dist", "build", "System")
    if not os.path.isdir(system_dir):
        print(f"Error: Could not find System directory in {clock_dir}")
        return False

    makefile = os.path.join(system_dir, "Makefile")
    if not os.path.exists(makefile):
        print(f"Error: Could not find Makefile in {system_dir}")
        return False

    # Backup the original makefile
    backup = makefile + ".backup"
    shutil.copy2(makefile, backup)
    print(f"Created backup of Makefile: {backup}")

    # Get the path to our pre-generated Clock.hs file
    script_dir = os.path.dirname(os.path.abspath(__file__))
    workaround_file = os.path.join(script_dir, "clock_workaround", "Clock.hs")

    if not os.path.exists(workaround_file):
        print(f"Error: Workaround file not found at {workaround_file}")
        return False

    # Copy our pre-generated Clock.hs to the output location
    output_file = os.path.join(system_dir, "Clock.hs")
    shutil.copy2(workaround_file, output_file)
    print(f"Copied pre-generated Clock.hs to {output_file}")

    # Modify the makefile to skip HSC2HS processing
    with open(makefile, "r") as f:
        content = f.read()

    # Replace the HSC rule with a simple copy operation
    modified = content.replace(
        "Clock.hs: Clock.hsc Clock_hsc_make.exe",
        "Clock.hs: Clock.hsc\n\t@echo Using pre-generated Clock.hs"
    )

    # Remove the invocation of Clock_hsc_make.exe
    modified = modified.replace(
        "Clock.hs: Clock.hsc Clock_hsc_make.exe\n\tClock_hsc_make.exe  >Clock.hs",
        "Clock.hs: Clock.hsc\n\t@echo Using pre-generated Clock.hs"
    )

    # Write the modified content back
    with open(makefile, "w") as f:
        f.write(modified)

    print(f"Successfully patched {makefile}")

    # Touch the output file to ensure it's newer than dependencies
    os.utime(output_file, None)

    return True

def main():
    """Main entry point."""
    # Find the clock directory
    clock_dir = find_clock_dir()
    if not clock_dir:
        print("Could not find clock package directory")
        return False

    print(f"Found clock package at: {clock_dir}")

    # Patch the makefile
    if not patch_clock_makefile(clock_dir):
        print("Failed to patch clock package build")
        return False

    print("Successfully patched clock package build")
    return True

if __name__ == "__main__":
    sys.exit(0 if main() else 1)

