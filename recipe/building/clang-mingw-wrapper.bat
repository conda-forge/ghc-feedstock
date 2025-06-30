@echo on
setlocal enabledelayedexpansion

echo [WRAPPER] Starting clang-mingw-wrapper 1>&2
echo [WRAPPER] Arguments: %* 1>&2

set "filtered_args="

REM Check if we're dealing with a response file
for %%a in (%*) do (
    set "arg=%%a"

    REM Special handling for response files (starting with @)
    if "!arg:~0,1!"=="@" (
        echo [WRAPPER] Found response file: !arg! 1>&2
        set "resp_file=!arg:~1!"

        REM Create a temporary filtered response file
        set "temp_resp=%TEMP%\filtered_rsp_%RANDOM%.txt"
        echo [WRAPPER] Creating filtered response file: !temp_resp! 1>&2

        REM Process the response file line by line
        if exist "!resp_file!" (
            for /f "usebackq delims=" %%i in ("!resp_file!") do (
                set "rline=%%i"
                set "skip_line=0"

                if "!rline:~0,2!"=="-I" (
                    if not "!rline:mingw=!"=="!rline!" set "skip_line=1"
                    if not "!rline:bootstrap=!"=="!rline!" set "skip_line=1"
                ) else if "!rline:~0,2!"=="-L" (
                    if not "!rline:mingw=!"=="!rline!" set "skip_line=1"
                    if not "!rline:bootstrap=!"=="!rline!" set "skip_line=1"
                )

                if "!skip_line!"=="1" (
                    echo [WRAPPER] Skipping line from response file: !rline! 1>&2
                ) else (
                    echo !rline!>>"!temp_resp!"
                )
            )

            REM Add conda mingw paths to the response file
            echo -I%BUILD_PREFIX%\Library\mingw-w64\include>>"!temp_resp!"
            echo -L%BUILD_PREFIX%\Library\mingw-w64\lib>>"!temp_resp!"

            REM Use the filtered response file
            set "filtered_args=!filtered_args! "@!temp_resp!""
        ) else (
            echo [WRAPPER] Warning: Response file !resp_file! not found 1>&2
            set "filtered_args=!filtered_args! "!arg!""
        )
    ) else (
        REM Handle normal arguments
        set "skip=0"

        if "!arg:~0,2!"=="-I" (
            if not "!arg:mingw=!"=="!arg!" set "skip=1"
            if not "!arg:bootstrap=!"=="!arg!" set "skip=1"
        ) else if "!arg:~0,2!"=="-L" (
            if not "!arg:mingw=!"=="!arg!" set "skip=1"
            if not "!arg:bootstrap=!"=="!arg!" set "skip=1"
        )

        if "!skip!"=="1" (
            echo [WRAPPER] Skipping: !arg! 1>&2
        ) else (
            set "filtered_args=!filtered_args! "!arg!""
        )
    )
)

REM Add conda mingw paths if not using a response file
echo [WRAPPER] Adding conda mingw paths 1>&2
set "filtered_args=!filtered_args! "-I%BUILD_PREFIX%\Library\mingw-w64\include" "-L%BUILD_PREFIX%\Library\mingw-w64\lib" "-L%BUILD_PREFIX%\Library\mingw-w64\lib""

echo [WRAPPER] Final command: "%BUILD_PREFIX%\Library\bin\clang.exe" !filtered_args! --target=x86_64-w64-mingw32 -fuse-ld=lld -rtlib=compiler-rt -Wl,-lclang_rt.builtins-x86_64 1>&2

REM Find the exact builtins library
set "builtins_found=0"
for /f "delims=" %%a in ('dir /s /b "%BUILD_PREFIX%\Library\lib\clang\*\lib\windows\clang_rt.builtins-x86_64.lib" "%BUILD_PREFIX%\Lib\clang\*\lib\windows\clang_rt.builtins-x86_64.lib" 2^>nul') do (
    set "builtins=%%a"
    set "builtins_found=1"
    echo [WRAPPER] Found builtins: !builtins! 1>&2
    goto :found
)
:found

if "!builtins_found!"=="1" (
    echo [WRAPPER] Using direct path to builtins library 1>&2
    "%BUILD_PREFIX%\Library\bin\clang.exe" !filtered_args! --target=x86_64-w64-mingw32 -fuse-ld=lld -rtlib=compiler-rt "!builtins!"
) else (
    echo [WRAPPER] Falling back to library search 1>&2
    "%BUILD_PREFIX%\Library\bin\clang.exe" !filtered_args! --target=x86_64-w64-mingw32 -fuse-ld=lld -rtlib=compiler-rt -lclang_rt.builtins-x86_64
)

set exit_code=%ERRORLEVEL%
echo [WRAPPER] Clang exit code: %exit_code% 1>&2

exit /b %exit_code%