export PATH="$PREFIX/bin:$BUILD_PREFIX/bin:$PATH"
#export CFLAGS="-I$PREFIX/include $CFLAGS"
#export LDFLAGS="-Wl,-L$PREFIX/lib $LDFLAGS"
export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH"
export LIBRARY_PATH="$PREFIX/lib:$LIBRARY_PATH"
if [ $ARCH == "aarch64" ]; then
   echo "aarch64 detected"
fi
./configure --prefix=$PREFIX --with-gmp-includes=$PREFIX/include --with-gmp-libraries=$PREFIX/lib
make install
if [[ -f "$LD" && ! $BUILD_PREFIX/bin/ld ]]; then
   ln -s $LD $BUILD_PREFIX/bin/ld;
fi
#echo "main = putStr \"smalltest\"" > Main.hs
#ghc -v -O0 -threaded -L$PREFIX/lib -fasm -o smalltest Main.hs 
#./smalltest
ghc-pkg recache
