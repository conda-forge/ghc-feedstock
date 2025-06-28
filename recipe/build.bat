@echo off
setlocal enabledelayedexpansion

echo source D:/Miniforge/etc/profile.d/conda.sh       > conda_build.sh
echo conda activate "${PREFIX}"                       >> conda_build.sh
echo conda activate --stack "${BUILD_PREFIX}"         >> conda_build.sh
echo CONDA_PREFIX=${CONDA_PREFIX//\\//}               >> conda_build.sh
type "%RECIPE_DIR%\build.sh"                          >> conda_build.sh

set _PREFIX=%PREFIX:\=/%
set _BUILD_PREFIX=%BUILD_PREFIX:\=/%
set _SRC_DIR=%SRC_DIR:\=/%
for %%D in (C D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    set "_PREFIX=!_PREFIX:%%D:=/%%D:~0,1,1!"
    set "_BUILD_PREFIX=!_BUILD_PREFIX:%%D:=/%%D:~0,1,1!"
    set "_SRC_DIR=!_SRC_DIR:%%D:=/%%D:~0,1,1!"
)
set MSYSTEM=MINGW64
set MSYS2_PATH_TYPE=inherit
set MSYS2_ARG_CONV_EXCL="*"
set CHERE_INVOKING=1
bash -lce "./conda_build.sh"
if errorlevel 1 exit 1
