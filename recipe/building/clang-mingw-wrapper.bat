@echo off
setlocal enabledelayedexpansion

set "args="

REM Process each argument
for %%a in (%*) do (
    set "arg=%%a"

    REM Skip problematic mingw paths
    if "!arg!"=="-I%SRC_DIR%\bootstrap-ghc\lib/../mingw//include" (
        echo Skipping: !arg!
    ) else if "!arg!"=="-L%SRC_DIR%\bootstrap-ghc\lib/../mingw//lib" (
        echo Skipping: !arg!
    ) else if "!arg!"=="-L%SRC_DIR%\bootstrap-ghc\lib/../mingw//x86_64-w64-mingw32/lib" (
        echo Skipping: !arg!
    ) else (
        set "args=!args! "%%a""
    )
)

REM Execute clang directly with the filtered arguments
"%BUILD_PREFIX%\Library\bin\clang.exe" %args% --target=x86_64-w64-mingw32 -fuse-ld=lld -rtlib=compiler-rt

exit /b %ERRORLEVEL%
