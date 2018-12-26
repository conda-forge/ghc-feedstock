#!/bin/bash
echo "$PREFIX/lib"
export CFLAGS="-I$PREFIX/include $CFLAGS"
echo "$CFLAGS"
export LDFLAGS="-L$PREFIX/lib $LDFLAGS"
echo "$LDFLAGS"
export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH"
export LIBRARY_PATH="$PREFIX/lib:$LIBRARY_PATH"
ls -lrt $PREFIX/lib
./configure --prefix $PREFIX --with-gmp-includes=$PREFIX/include --with-gmp-libraries=$PREFIX/lib
make install
#Small test
ldconfig -p | grep libgmp
echo "main = putStr \"smalltest\"" > Main.hs
ghc -L$PREFIX/lib -fasm -v5 -o smalltest Main.hs 
./smalltest
