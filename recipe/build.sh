export CC="x86_64-conda_cos6-linux-gnu-cc"
export LD="x86_64-conda_cos6-linux-gnu-ld"
export PATH="$PREFIX/bin:$BUILD_PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH"
export LIBRARY_PATH="$PREFIX/lib:$LIBRARY_PATH"
export C_INCLUDE_PATH="$PWD/includes:$PREFIX/include:$C_INCLUDE_PATH"
export LDFLAGS=" -Wl,-L$PREFIX/lib -Wl,-lgmp $LDFLAGS"
ghc-pkg recache
./configure --prefix=$PREFIX --with-gmp-includes=$PREFIX/include --with-gmp-libraries=$PREFIX/lib
cp mk/build.mk.sample mk/build.mk
perl -pi -e 's/#BuildFlavour = quick/BuildFlavour = quick/g' mk/build.mk
#./validate --build-only
echo "Settings"
cat settings
make
make install
#Small test
if [ -f "$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-ld" ]; then
   ln -s $BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-ld $BUILD_PREFIX/bin/ld
fi
echo "main = putStr \"smalltest\"" > Main.hs
ghc -v -O0 -threaded -L$PREFIX/lib -fasm -o smalltest Main.hs 
./smalltest

