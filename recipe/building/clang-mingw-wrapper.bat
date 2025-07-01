@echo off
REM clang-mingw-wrapper.bat - Uses full Python path from env var
IF defined PYTHON (
  "%PYTHON%" "%~dp0clang-mingw-wrapper.py" %*
) ELSE (
  echo ERROR: PYTHON environment variable not defined
  echo Trying system Python as fallback...
  python "%~dp0clang-mingw-wrapper.py" %*
)
exit /b %ERRORLEVEL%