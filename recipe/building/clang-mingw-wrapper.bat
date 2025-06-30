@echo on
setlocal enabledelayedexpansion

echo [WRAPPER] Starting clang-mingw-wrapper 1>&2
echo [WRAPPER] Arguments: %* 1>&2

set "filtered_args="
set "needs_mingw_include=0"
set "needs_mingw_lib=0"

REM Process each argument
for %%a in (%*) do (
    set "arg=%%a"
    set "skip=0"

    REM Check if argument starts with -I or -L
    if "!arg:~0,2!"=="-I" (
        if not "!arg:mingw=!"=="!arg!" (
            set "skip=1"
            set "needs_mingw_include=1"
        )
        if not "!arg:bootstrap=!"=="!arg!" set "skip=1"
    ) else if "!arg:~0,2!"=="-L" (
        if not "!arg:mingw=!"=="!arg!" (
            set "skip=1"
            set "needs_mingw_lib=1"
        )
        if not "!arg:bootstrap=!"=="!arg!" set "skip=1"
    )

    if "!skip!"=="1" (
        echo [WRAPPER] Skipping: !arg! 1>&2
    ) else (
        set "filtered_args=!filtered_args! "%%a""
    )
)

REM Add the conda mingw paths instead of bootstrap ones
if "!needs_mingw_include!"=="1" (
    set "filtered_args=!filtered_args! "-I%BUILD_PREFIX%\Library\mingw-w64\include""
    echo [WRAPPER] Added conda mingw include path 1>&2
)

if "!needs_mingw_lib!"=="1" (
    set "filtered_args=!filtered_args! "-L%BUILD_PREFIX%\Library\mingw-w64\lib""
    echo [WRAPPER] Added conda mingw lib path 1>&2
)

REM Add builtins library for missing symbols if not already present
set "has_builtins=0"
for %%a in (%*) do (
    if not "%%a:clang_rt.builtins=!"=="%%a" set "has_builtins=1"
)

if "!has_builtins!"=="0" (
    for /f "delims=" %%a in ('dir /s /b "%BUILD_PREFIX%\Library\lib\clang\*\lib\windows\clang_rt.builtins-x86_64.lib" 2^>nul') do (
        set "builtins=%%a"
        echo [WRAPPER] Found builtins: !builtins! 1>&2
        set "filtered_args=!filtered_args! "!builtins!""
    )
)

echo [WRAPPER] Final command: "%BUILD_PREFIX%\Library\bin\clang.exe" !filtered_args! --target=x86_64-w64-mingw32 -fuse-ld=lld -rtlib=compiler-rt 1>&2

REM Execute clang directly with the filtered arguments
"%BUILD_PREFIX%\Library\bin\clang.exe" !filtered_args! --target=x86_64-w64-mingw32 -fuse-ld=lld -rtlib=compiler-rt

set exit_code=%ERRORLEVEL%
echo [WRAPPER] Clang exit code: %exit_code% 1>&2

exit /b %exit_code%