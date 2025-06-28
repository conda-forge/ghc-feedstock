echo source D:/Miniforge/etc/profile.d/conda.sh       > conda_build.sh
echo conda activate "${PREFIX}"                       >> conda_build.sh
echo conda activate --stack "${BUILD_PREFIX}"         >> conda_build.sh
echo export PREFIX="$(cygpath -w "${PREFIX}")"               >> conda_build.sh
echo export BUILD_PREFIX="$(cygpath -w "${BUILD_PREFIX}")"  >> conda_build.sh
echo export CONDA_PREFIX="$(cygpath -w "${CONDA_PREFIX}")"  >> conda_build.sh
echo export SRC_DIR="$(cygpath -w "${SRC_DIR}")"  >> conda_build.sh
type "%RECIPE_DIR%\build.sh"                          >> conda_build.sh

:: set PREFIX=%PREFIX:\=/%
:: set BUILD_PREFIX=%BUILD_PREFIX:\=/%
:: set CONDA_PREFIX=%CONDA_PREFIX:\=/%
:: set SRC_DIR=%SRC_DIR:\=/%
set MSYS2_PATH_TYPE=inherit
set CHERE_INVOKING=1
bash -lce "./conda_build.sh"
if errorlevel 1 exit 1
