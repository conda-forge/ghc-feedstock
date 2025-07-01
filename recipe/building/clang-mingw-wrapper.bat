@echo off
REM clang-mingw-wrapper.bat - Calls the Python script
python "%~dp0clang-mingw-wrapper.py" %*
exit /b %ERRORLEVEL%
