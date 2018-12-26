#!/bin/bash

export CFLAGS="-I$PREFIX/include:$CFLAGS" 
export LDFLAGS="-L$PREFIX/lib:$PREFIX/lib:$LDFLAGS"
export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH"
export LIBRARY_PATH="$PREFIX/lib:$LIBRARY_PATH"
ls -lrt $PREFIX/lib
./configure --prefix $PREFIX
make install
#Small test
echo "main = putStr \"smalltest\"" > Main.hs
ghc -dynamic -fasm -v5 -o smalltest Main.hs 
./smalltest
