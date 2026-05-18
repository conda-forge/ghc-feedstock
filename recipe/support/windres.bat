@echo off
setlocal enabledelayedexpansion

REM Windres wrapper to handle GCC as preprocessor
REM EXPERIMENTAL GCC BRANCH: Use GCC instead of Clang
REM Based on ghc-bootstrap-feedstock windres.bat

REM Find the real windres.exe via PATH
where x86_64-w64-mingw32-windres.exe 2>nul 1>nul
if %errorlevel% == 0 (
    set "WINDRES_CMD=x86_64-w64-mingw32-windres.exe"
) else (
    echo ERROR: Cannot find x86_64-w64-mingw32-windres.exe in PATH 1>&2
    exit /b 1
)

REM Find preprocessor (cpp.exe) via PATH
where x86_64-w64-mingw32-cpp.exe 2>nul 1>nul
if %errorlevel% == 0 (
    set "PREPROC_CMD=x86_64-w64-mingw32-cpp.exe"
) else (
    REM Fall back to gcc -E if cpp not in PATH
    where x86_64-w64-mingw32-gcc.exe 2>nul 1>nul
    if !errorlevel! == 0 (
        set "PREPROC_CMD=x86_64-w64-mingw32-gcc.exe"
    ) else (
        echo ERROR: Cannot find cpp.exe or gcc.exe in PATH 1>&2
        exit /b 1
    )
)
set "PREPROC_ARGS=-E -xc-header -DRC_INVOKED"

REM Filter out --preprocessor arguments from GHC (which may be malformed)
REM and build our own preprocessor specification
set "OTHER_ARGS="

:loop
if "%~1"=="" goto :endloop

REM Check if this argument starts with --preprocessor
set "ARG=%~1"
set "CHECK=!ARG:~0,14!"

if "!CHECK!" == "--preprocessor" (
    REM Skip GHC's preprocessor argument
    shift
    goto :loop
)

REM Keep this argument
set "OTHER_ARGS=!OTHER_ARGS! %1"
shift
goto :loop

:endloop

REM Build final command with our preprocessor specification
set "FINAL=--preprocessor=!PREPROC_CMD!"
for %%a in (!PREPROC_ARGS!) do (
    set "FINAL=!FINAL! --preprocessor-arg=%%a"
)
set "FINAL=!FINAL!!OTHER_ARGS!"

REM Execute the real windres with corrected arguments
!WINDRES_CMD! !FINAL!
exit /b %errorlevel%
