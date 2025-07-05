#!/usr/bin/env python
"""
Fix HSC tool crashes in GHC build process on Windows.
This script provides pre-generated files for problematic HSC tools.
"""
import os
import sys
import glob
import shutil
import re
import tempfile
import subprocess

# Known problematic packages and their HSC files
PROBLEMATIC_PACKAGES = {
    "clock": {
        "patterns": ["clock-*/", "clock-*.*.*"],
        "hsc_files": {
            "System/Clock.hs": "System/Clock.hsc"
        },
    },
    "file-io": {
        "patterns": ["file-io-*/", "file-io-*.*.*"],
        "hsc_files": {
            "System/File/Platform.hs": "System/File/Platform.hsc"
        },
    }
}

def find_cabal_build_dirs():
    """Find all cabal build directories on the system."""
    search_paths = [
        os.path.expanduser("~"),
        "/c/cabal",
        "C:/cabal",
        "C:/Users",
        os.getcwd()
    ]

    build_dirs = []
    for path in search_paths:
        if os.path.exists(path):
            print(f"Searching for Cabal build directories in {path}")
            # Look for typical Cabal build directory patterns
            patterns = [
                "**/.cabal/**",
                "**/cabal/**",
                "**/dist-newstyle/**",
                "**/dist/**"
            ]
            for pattern in patterns:
                full_pattern = os.path.join(path, pattern)
                matches = glob.glob(full_pattern, recursive=True)
                for match in matches:
                    if os.path.isdir(match) and not match in build_dirs:
                        build_dirs.append(match)

    print(f"Found {len(build_dirs)} potential Cabal build directories")
    return build_dirs

def find_package_dirs(package_name, build_dirs):
    """Find directories for a specific package within cabal build dirs."""
    package_dirs = []
    patterns = PROBLEMATIC_PACKAGES.get(package_name, {}).get("patterns", [])

    for build_dir in build_dirs:
        for pattern in patterns:
            # For each pattern, search recursively but not too deep
            search_pattern = os.path.join(build_dir, "**", pattern)
            for path in glob.glob(search_pattern, recursive=True):
                if os.path.isdir(path) and path not in package_dirs:
                    package_dirs.append(path)

    print(f"Found {len(package_dirs)} directories for {package_name}")
    return package_dirs

def find_hsc_makefiles(package_dir):
    """Find HSC-related Makefiles in a directory."""
    makefiles = []

    # Try different build directory patterns
    build_dirs = [
        os.path.join(package_dir, "dist", "build"),
        os.path.join(package_dir, "dist-newstyle", "build"),
        os.path.join(package_dir, "build"),
    ]

    for build_dir in build_dirs:
        if os.path.isdir(build_dir):
            print(f"Searching for makefiles in {build_dir}")
            # Find all Makefiles
            for root, _, files in os.walk(build_dir):
                if "Makefile" in files:
                    makefile_path = os.path.join(root, "Makefile")
                    with open(makefile_path, "r", errors="replace") as f:
                        content = f.read()
                        # Check if this is an HSC-related Makefile
                        if "_hsc_make.exe" in content:
                            makefiles.append(makefile_path)

    print(f"Found {len(makefiles)} HSC makefiles")
    return makefiles

def fix_hsc_makefile(makefile, package_name):
    """Patch a Makefile to skip HSC tool execution and use pre-generated files."""
    try:
        with open(makefile, "r", errors="replace") as f:
            content = f.read()
    except:
        print(f"Error reading {makefile}")
        return False

    # Get the directory containing the Makefile
    makefile_dir = os.path.dirname(makefile)

    # Find all hsc_make.exe commands
    hsc_rules = re.findall(r'([a-zA-Z0-9_./\\]+\.hs):\s+([a-zA-Z0-9_./\\]+\.hsc)\s+([a-zA-Z0-9_./\\]+_hsc_make\.exe)', content)
    if not hsc_rules:
        print(f"No HSC rules found in {makefile}")
        return False

    # Get directory of this script
    script_dir = os.path.dirname(os.path.abspath(__file__))
    workaround_dir = os.path.join(script_dir, "hsc_workarounds", package_name)

    modified = False
    for output_file, input_file, hsc_tool in hsc_rules:
        # Clean up paths - they might use windows or unix style
        output_file = output_file.replace('\\', '/')
        input_file = input_file.replace('\\', '/')
        hsc_tool = hsc_tool.replace('\\', '/')

        # Construct paths for the pre-generated file and target location
        pre_gen_file = os.path.join(workaround_dir, output_file)
        target_path = os.path.join(makefile_dir, output_file)

        # Ensure pre-gen file exists
        if not os.path.exists(pre_gen_file):
            print(f"Pre-generated file not found: {pre_gen_file}")
            continue

        # Create target directory if it doesn't exist
        os.makedirs(os.path.dirname(target_path), exist_ok=True)

        # Copy the pre-generated file
        shutil.copy2(pre_gen_file, target_path)
        print(f"Copied {pre_gen_file} to {target_path}")

        # Modify the Makefile to skip running the HSC tool
        old_rule = f"{output_file}: {input_file} {hsc_tool}\n\t{hsc_tool}"
        new_rule = f"{output_file}: {input_file}\n\t@echo Using pre-generated {output_file}"

        if old_rule in content:
            content = content.replace(old_rule, new_rule)
            modified = True
        else:
            # Try with different line endings or formatting
            pattern = re.escape(f"{output_file}: {input_file} {hsc_tool}") + r'\s*\n\s*' + re.escape(hsc_tool)
            replacement = f"{output_file}: {input_file}\n\t@echo Using pre-generated {output_file}"
            new_content = re.sub(pattern, replacement, content)
            if new_content != content:
                content = new_content
                modified = True

    if modified:
        # Backup original Makefile
        backup_path = f"{makefile}.bak"
        shutil.copy2(makefile, backup_path)

        # Write the modified content
        with open(makefile, "w") as f:
            f.write(content)

        print(f"Modified {makefile} to use pre-generated files")
        return True
    else:
        print(f"No modifications made to {makefile}")
        return False

def main():
    """Main entry point."""
    print("\nStarting HSC tool fix script...")

    # Find all Cabal build directories
    build_dirs = find_cabal_build_dirs()

    success = False

    # Process each problematic package
    for package_name in PROBLEMATIC_PACKAGES:
        print(f"\nProcessing {package_name} package:")

        # Find package directories
        package_dirs = find_package_dirs(package_name, build_dirs)

        if not package_dirs:
            print(f"No {package_name} directories found!")

            # Try a direct scan in all cabal directories for the specific HSC files
            print(f"Trying direct search for {package_name} HSC makefiles...")
            hsc_makefiles = []
            for build_dir in build_dirs:
                if os.path.exists(build_dir):
                    for makefile_path in glob.glob(os.path.join(build_dir, "**", "Makefile"), recursive=True):
                        try:
                            with open(makefile_path, "r", errors="replace") as f:
                                content = f.read()
                                if "_hsc_make.exe" in content and package_name in content.lower():
                                    hsc_makefiles.append(makefile_path)
                        except:
                            pass

            if hsc_makefiles:
                print(f"Found {len(hsc_makefiles)} potential makefiles by direct search")
                for makefile in hsc_makefiles:
                    if fix_hsc_makefile(makefile, package_name):
                        success = True

            continue

        # For each package directory, find and fix HSC makefiles
        for package_dir in package_dirs:
            makefiles = find_hsc_makefiles(package_dir)
            for makefile in makefiles:
                if fix_hsc_makefile(makefile, package_name):
                    success = True

    if success:
        print("\nSuccessfully applied HSC tool fixes")
        return 0
    else:
        print("\nFailed to apply any HSC tool fixes")
        # Return success anyway to not block the build
        return 0

if __name__ == "__main__":
    sys.exit(main())

