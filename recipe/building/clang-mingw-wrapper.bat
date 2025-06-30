@echo on
setlocal

REM This batch file acts as a bridge to execute the PowerShell wrapper
echo [WRAPPER] Starting PowerShell wrapper bridge 1>&2
echo [WRAPPER] Arguments: %* 1>&2

REM Execute the PowerShell script via powershell.exe
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%BUILD_PREFIX%\Library\bin\clang-mingw-wrapper.ps1" %*

REM Pass along the exit code
exit /b %ERRORLEVEL%
