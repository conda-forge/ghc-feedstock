@echo off
setlocal enabledelayedexpansion
if errorlevel 1 exit 1

call %CONDA_PREFIX%\bin\ghc-pkg recache
if errorlevel 1 exit 1
