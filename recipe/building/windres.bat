@echo off
setlocal enabledelayedexpansion

REM Windres wrapper to handle clang as preprocessor
REM Based on ghc-bootstrap-feedstock windres.bat

REM Find the real windres.exe
where x86_64-w64-mingw32-windres.exe 2>nul 1>nul
if %errorlevel% == 0 (
    set "WINDRES_CMD=x86_64-w64-mingw32-windres.exe"
) else (
    set "WINDRES_CMD=%BUILD_PREFIX%\Library\bin\x86_64-w64-mingw32-windres.exe"
)

REM Set preprocessor to clang with appropriate flags
REM Use absolute path since batch script may not have full PATH
set "PREPROC_CMD=%BUILD_PREFIX%\Library\bin\clang.exe"
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
