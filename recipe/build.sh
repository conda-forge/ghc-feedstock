#!/bin/bash
export PATH="$PREFIX/bin:$BUILD_PREFIX/bin:$PATH"
echo $PREFIX/lib
export CFLAGS="-I$PREFIX/include $CFLAGS"
echo "$CFLAGS"
export LDFLAGS="-Wl,-L$PREFIX/lib $LDFLAGS"
echo "$LDFLAGS"
export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH"
export LIBRARY_PATH="$PREFIX/lib:$LIBRARY_PATH"
ls -lrt $PREFIX/lib
echo "Build_prefix/lib"
ls -lrt $BUILD_PREFIX/lib
./configure --prefix=$PREFIX --with-gmp-includes=$PREFIX/include --with-gmp-libraries=$PREFIX/lib
make install
#Small test
echo "ldconfig start"
ldconfig -v
echo "ldconfig end"
#echo "gcc7ldconfig start"
#x86_64-conda_cos6-linux-gnu-ldconfig -v
#echo "gcc7ldconfig end"
if [ -f "$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-ld" ]; then
   ln -s $BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-ld $BUILD_PREFIX/bin/ld
fi
echo "which ld"
which ld
echo "main = putStr \"smalltest\"" > Main.hs
ghc -L$PREFIX/lib -L/usr/lib -L/usr/lib64 -fasm -o smalltest Main.hs 
./smalltest
