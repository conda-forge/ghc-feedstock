#!/usr/bin/env pwsh

Write-Host "[WRAPPER] Starting clang-mingw-wrapper" -ForegroundColor Yellow
Write-Host "[WRAPPER] Arguments: $args" -ForegroundColor Yellow

$filteredArgs = @()

# Process all arguments
foreach ($arg in $args) {
    # Handle response files (starting with @)
    if ($arg.StartsWith('@')) {
        $respFile = $arg.Substring(1)
        Write-Host "[WRAPPER] Found response file: $respFile" -ForegroundColor Yellow

        $tempResp = Join-Path $env:TEMP "filtered_rsp_$([Guid]::NewGuid().ToString()).txt"
        Write-Host "[WRAPPER] Creating filtered response file: $tempResp" -ForegroundColor Yellow

        if (Test-Path $respFile) {
            foreach ($line in (Get-Content $respFile)) {
                $skipLine = $false

                # Only filter -I and -L flags containing mingw or bootstrap
                if (($line.StartsWith('-I') -or $line.StartsWith('-L')) -and
                    ($line -like '*mingw*' -or $line -like '*bootstrap*')) {
                    $skipLine = $true
                    Write-Host "[WRAPPER] Skipping line: $line" -ForegroundColor Yellow
                }

                if (-not $skipLine) {
                    Add-Content -Path $tempResp -Value $line
                }
            }
            $filteredArgs += "@$tempResp"
        } else {
            Write-Host "[WRAPPER] Warning: Response file not found" -ForegroundColor Yellow
            $filteredArgs += $arg
        }
    } else {
        # Handle regular arguments
        $skipArg = $false

        if (($arg.StartsWith('-I') -or $arg.StartsWith('-L')) -and
            ($arg -like '*mingw*' -or $arg -like '*bootstrap*')) {
            $skipArg = $true
            Write-Host "[WRAPPER] Skipping: $arg" -ForegroundColor Yellow
        }

        if (-not $skipArg) {
            $filteredArgs += $arg
        }
    }
}

# Add conda mingw paths
Write-Host "[WRAPPER] Adding conda mingw paths" -ForegroundColor Yellow
$filteredArgs += "-I$env:BUILD_PREFIX\Library\mingw-w64\include"
$filteredArgs += "-L$env:BUILD_PREFIX\Library\mingw-w64\lib"
$filteredArgs += "-L$env:BUILD_PREFIX\Library\mingw-w64\lib"

# Search for builtins library
$builtins = Get-ChildItem -Path "$env:BUILD_PREFIX" -Recurse -Include "*clang_rt.builtins*.lib","*clang_rt.builtins*.a" -ErrorAction SilentlyContinue | Select-Object -First 1
$builtinsFound = $null -ne $builtins

if ($builtinsFound) {
    Write-Host "[WRAPPER] Found builtins: $($builtins.FullName)" -ForegroundColor Yellow
    $finalArgs = $filteredArgs + @("--target=x86_64-w64-mingw32", "-fuse-ld=lld", "-rtlib=compiler-rt", $builtins.FullName)
} else {
    Write-Host "[WRAPPER] Falling back to library search" -ForegroundColor Yellow
    $finalArgs = $filteredArgs + @("--target=x86_64-w64-mingw32", "-fuse-ld=lld", "-rtlib=compiler-rt", "-lclang_rt.builtins-x86_64")
}

# Execute clang with the filtered arguments
$clangExe = "$env:BUILD_PREFIX\Library\bin\clang.exe"
Write-Host "[WRAPPER] Final command: $clangExe $finalArgs" -ForegroundColor Yellow
& $clangExe $finalArgs

# Pass along clang's exit code
exit $LASTEXITCODE