@echo off
setlocal enabledelayedexpansion

echo [HSC-WRAPPER] Running HSC Tool: %*

REM Set stack size explicitly to a large value (16MB)
set LargeStackSize=16777216
editbin /STACK:!LargeStackSize! "%~1" >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
  echo [HSC-WRAPPER] Warning: Could not set stack size for %~1
)

REM Run the HSC tool with its arguments
"%~1" %2 %3 %4 %5 %6 %7 %8 %9
set HSC_EXIT=%ERRORLEVEL%

REM Check for failures and dump diagnostics
if %HSC_EXIT% NEQ 0 (
  echo [HSC-WRAPPER] HSC tool failed with exit code %HSC_EXIT%
  if exist "%~dpnx1.exe.stackdump" (
    echo [HSC-WRAPPER] Stack dump found:
    type "%~dpnx1.exe.stackdump"
  )

  REM Check for crash dump files
  for %%F in ("%TEMP%\*.dmp") do (
    echo [HSC-WRAPPER] Found crash dump: %%F
    if exist "!WinDbg!" (
      echo [HSC-WRAPPER] Analyzing crash dump...
      "!WinDbg!" -z "%%F" -c ".ecxr;k;q" > "%TEMP%\hsc_crash_analysis.txt"
      type "%TEMP%\hsc_crash_analysis.txt"
    )
  )
)

exit /b %HSC_EXIT%

