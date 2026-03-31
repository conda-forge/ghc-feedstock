@REM set "BUILD_BIN=%BUILD_PREFIX%/Library/bin"`
@REM set "PATH=%SRC_DIR:/=\%\binary\bin;%PATH%"

@REM cabal update
@REM if %ERRORLEVEL% NEQ 0 exit /b 1
@REM cabal install -j --installdir="%BUILD_BIN%" --install-method=copy alex-3.2.6 happy hscolour
@REM if %ERRORLEVEL% NEQ 0 exit /b 1

@REM cd source
@REM bash configure
@REM if %ERRORLEVEL% NEQ 0 exit /b 1
@REM make -j${CPU_COUNT}
@REM if %ERRORLEVEL% NEQ 0 exit /b 1

mkdir "%LIBRARY_PREFIX%"
cd binary
XCOPY /s /i * "%LIBRARY_PREFIX%"

@REM set "STACK_ROOT=%BUILD_PREFIX%"
@REM mkdir %BUILD_PREFIX%\Library\bin

@REM echo local-bin-path: "%BUILD_PREFIX:\=/%/Library/bin" > %BUILD_PREFIX:\=/%/config.yaml
@REM echo local-programs-path: "%BUILD_PREFIX:\=/%/Library/bin" >> %BUILD_PREFIX:\=/%/config.yaml

@REM curl -L https://github.com/commercialhaskell/stack/releases/download/v2.7.5/stack-2.7.5-windows-x86_64-bin.exe -o "%BUILD_PREFIX:\=/%/Library/bin/stack.exe"

@REM stack install alex happy
