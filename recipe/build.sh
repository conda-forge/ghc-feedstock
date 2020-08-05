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
# make sure this is more arch specific
if [ $ARCH == "x86_64" ]; then
  if [ -f "$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-ld" ]; then
     ln -s $BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-ld $BUILD_PREFIX/bin/ld
  fi
fi
if [ $ARCH == "aarch64" ]; then
  if [ -f "$BUILD_PREFIX/bin/aarch64-conda_cos6-linux-gnu-ld" ]; then
     ln -s $BUILD_PREFIX/bin/aarch64-conda_cos6-linux-gnu-ld $BUILD_PREFIX/bin/ld
  fi
fi
#echo "main = putStr \"smalltest\"" > Main.hs
#ghc -v -O0 -threaded -L$PREFIX/lib -fasm -o smalltest Main.hs 
#./smalltest
ghc-pkg recache
