#!/bin/bash
echo $PREFIX/lib
export CFLAGS="-I$PREFIX/include $CFLAGS"
echo "$CFLAGS"
export LDFLAGS="-Wl,-L$PREFIX/lib -Wl,--verbose $LDFLAGS"
echo "$LDFLAGS"
export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH"
export LIBRARY_PATH="$PREFIX/lib:$LIBRARY_PATH"
ls -lrt $PREFIX/lib
./configure --prefix $PREFIX --with-gmp-includes=$PREFIX/include --with-gmp-libraries=$PREFIX/lib
make install
#Small test
#echo "ldconfig start"
#ldconfig -p
#echo "ldconfig end"
echo "main = putStr \"smalltest\"" > Main.hs
ghc -fasm -o smalltest Main.hs 
./smalltest
