@echo on
setlocal enabledelayedexpansion

echo [WRAPPER] Starting clang-mingw-wrapper 1>&2
echo [WRAPPER] Arguments: %* 1>&2

set "filtered_args="

REM Process all arguments
for %%a in (%*) do (
    set "arg=%%a"

    REM Handle response files (starting with @)
    if "!arg:~0,1!"=="@" (
        echo [WRAPPER] Found response file: !arg! 1>&2
        set "resp_file=!arg:~1!"

        REM Create a temporary filtered response file
        set "temp_resp=%TEMP%\filtered_rsp_%RANDOM%.txt"
        echo [WRAPPER] Creating filtered response file: !temp_resp! 1>&2

        if exist "!resp_file!" (
            REM Process the response file line by line
            for /f "usebackq tokens=* delims=" %%i in ("!resp_file!") do (
                set "line=%%i"
                set "skip_line=0"

                REM Only filter -I and -L flags containing mingw/bootstrap
                if "!line:~0,2!"=="-I" (
                    if not "!line:mingw=!"=="!line!" set "skip_line=1"
                    if not "!line:bootstrap=!"=="!line!" set "skip_line=1"
                ) else if "!line:~0,2!"=="-L" (
                    if not "!line:mingw=!"=="!line!" set "skip_line=1"
                    if not "!line:bootstrap=!"=="!line!" set "skip_line=1"
                )

                if "!skip_line!"=="1" (
                    echo [WRAPPER] Skipping line from response file: !line! 1>&2
                ) else (
                    REM Preserve all other flags
                    echo !line!>>"!temp_resp!"
                )
            )

            REM Use the filtered response file
            set "filtered_args=!filtered_args! "@!temp_resp!""
        ) else (
            echo [WRAPPER] Warning: Response file !resp_file! not found 1>&2
            set "filtered_args=!filtered_args! "!arg!""
        )
    ) else (
        REM Handle normal arguments - only filter mingw/bootstrap paths
        set "skip=0"

        if "!arg:~0,2!"=="-I" (
            if not "!arg:mingw=!"=="!arg!" set "skip=1"
            if not "!arg:bootstrap=!"=="!arg!" set "skip=1"
        ) else if "!arg:~0,2!"=="-L" (
            if not "!arg:mingw=!"=="!arg!" set "skip=1"
            if not "!arg:bootstrap=!"=="!arg!" set "skip=1"
        )

        if "!skip!"=="1" (
            echo [WRAPPER] Skipping argument: !arg! 1>&2
        ) else (
            set "filtered_args=!filtered_args! "!arg!""
        )
    )
)

REM Add conda mingw paths
echo [WRAPPER] Adding conda mingw paths 1>&2
set "filtered_args=!filtered_args! "-I%BUILD_PREFIX%\Library\mingw-w64\include" "-L%BUILD_PREFIX%\Library\mingw-w64\lib" "-L%BUILD_PREFIX%\Library\mingw-w64\lib""

echo [WRAPPER] Final command: "%BUILD_PREFIX%\Library\bin\clang.exe" !filtered_args! --target=x86_64-w64-mingw32 -fuse-ld=lld -rtlib=compiler-rt -lclang_rt.builtins-x86_64 1>&2
"%BUILD_PREFIX%\Library\bin\clang.exe" !filtered_args! --target=x86_64-w64-mingw32 -fuse-ld=lld -rtlib=compiler-rt -lclang_rt.builtins-x86_64

exit /b %ERRORLEVEL%