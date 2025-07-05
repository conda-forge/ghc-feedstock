#!/usr/bin/env python
"""
Extract HSC command line arguments from response files to help debug issues.
"""
import os
import sys
import subprocess
import tempfile
import shutil

def extract_hsc_content(rsp_file):
    """Extract and analyze HSC content from a response file."""
    print(f"Examining HSC response file: {rsp_file}")

    if not os.path.exists(rsp_file):
        print(f"Error: Response file {rsp_file} not found")
        return False

    with open(rsp_file, 'r') as f:
        content = f.read().strip()
        lines = content.splitlines()
        print(f"Response file contains {len(lines)} lines:")
        for i, line in enumerate(lines):
            print(f"  {i+1}: {line}")

    # Extract directory of the rsp file
    rsp_dir = os.path.dirname(rsp_file)

    # Look for the HSC executable
    hsc_exe = os.path.join(rsp_dir, "Clock_hsc_make.exe")
    if os.path.exists(hsc_exe):
        print(f"Found HSC executable: {hsc_exe}")

        # Create a temporary directory for our analysis
        temp_dir = tempfile.mkdtemp(prefix="hsc_analysis_")
        try:
            # Copy the HSC executable to our temp dir
            temp_exe = os.path.join(temp_dir, "Clock_hsc_make.exe")
            shutil.copy2(hsc_exe, temp_exe)

            # Try to run it with various options
            print("\nAttempting to run HSC with various debug options:")

            # Prepare output file
            output_file = os.path.join(temp_dir, "Clock.hs")

            try:
                # Try with basic command
                cmd = [temp_exe, f">{output_file}"]
                print(f"Running: {' '.join(cmd)}")
                result = subprocess.run(cmd,
                                       cwd=temp_dir,
                                       stderr=subprocess.PIPE,
                                       stdout=subprocess.PIPE,
                                       text=True,
                                       timeout=30)
                print(f"Exit code: {result.returncode}")
                if result.stdout:
                    print(f"Stdout: {result.stdout}")
                if result.stderr:
                    print(f"Stderr: {result.stderr}")
            except subprocess.TimeoutExpired:
                print("Command timed out")
            except Exception as e:
                print(f"Error running HSC: {e}")

            # Check if we produced any output
            if os.path.exists(output_file):
                print(f"\nSuccessfully created output file: {output_file}")
                with open(output_file, 'r') as f:
                    print(f"First 100 chars: {f.read(100)}...")
            else:
                print("\nNo output file was created")
        finally:
            # Clean up
            shutil.rmtree(temp_dir, ignore_errors=True)
    else:
        print(f"HSC executable not found at expected location: {hsc_exe}")

    return True

def main():
    """Main entry point for the script."""
    if len(sys.argv) > 1:
        return extract_hsc_content(sys.argv[1])
    else:
        print("Please provide the path to an HSC response file")
        return False

if __name__ == "__main__":
    sys.exit(0 if main() else 1)

