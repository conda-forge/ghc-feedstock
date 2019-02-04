export CC="x86_64-conda_cos6-linux-gnu-cc"
export LD="x86_64-conda_cos6-linux-gnu-cc"
export PATH="$PREFIX/bin:$BUILD_PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$PREFIX/x86_64-conda_cos6-linux-gnu/sysroot/lib:$PREFIX/lib:$LD_LIBRARY_PATH"
export LIBRARY_PATH="$PREFIX/x86_64-conda_cos6-linux-gnu/sysroot/lib:$PREFIX/lib:$LIBRARY_PATH"
export C_INCLUDE_PATH="$PREFIX/include:$C_INCLUDE_PATH"
export LDFLAGS="-L$PREFIX/x86_64-conda_cos6-linux-gnu/sysroot/lib -L$PREFIX/lib $LDFLAGS"
echo "ls PREFIX"
ls $PREFIX
echo "ls PREFIX/x86_64-conda_cos6-linux-gnu/sysroot/lib"
ls $PREFIX/x86_64-conda_cos6-linux-gnu/sysroot/lib
./configure --prefix=$PREFIX --with-hs-cpp-flags=-L$PREFIX/x86_64-conda_cos6-linux-gnu/sysroot/lib LDFLAGS=-L$PREFIX/x86_64-conda_cos6-linux-gnu/sysroot/lib CPPFLAGS=-I$PREFIX/include CPP=x86_64-conda_cos6-linux-gnu-cpp --with-gmp-includes=$PREFIX/include --with-gmp-libraries=$PREFIX/lib CC=$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc LD=$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc
make install
