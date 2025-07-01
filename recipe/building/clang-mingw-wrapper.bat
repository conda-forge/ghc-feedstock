@echo off
REM clang-mingw-wrapper.bat - Disable virtualenv detection
setlocal
set PYTHONNOUSERSITE=1
set PYTHONPATH=
set VIRTUAL_ENV=

REM Try multiple ways to find Python
if defined PYTHON (
    "%PYTHON%" -E "%~dp0clang-mingw-wrapper.py" %*
) else (
    echo Trying system Python...
    where python
    if %ERRORLEVEL% EQU 0 (
        python -E "%~dp0clang-mingw-wrapper.py" %*
    ) else (
        echo ERROR: Python not found. Please add it to PATH or set PYTHON env var.
        exit /b 1
    )
)
exit /b %ERRORLEVEL%
