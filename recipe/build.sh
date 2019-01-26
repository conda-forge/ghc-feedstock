export PATH="$PREFIX/bin:$BUILD_PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH"
export LIBRARY_PATH="$PREFIX/lib:$LIBRARY_PATH"
export C_INCLUDE_PATH="$PWD/includes:$PREFIX/include:$C_INCLUDE_PATH"
export LD="x86_64-conda_cos6-linux-gnu-ld"
./configure --prefix=$PREFIX --with-gmp-includes=$PREFIX/include --with-gmp-libraries=$PREFIX/lib
ls
echo "includes"
ls includes
#cp $PWD/includes/ghcversion.h $PREFIX/include
make
ls includes
make install
#Small test
if [ -f "$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-ld" ]; then
   ln -s $BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-ld $BUILD_PREFIX/bin/ld
fi
echo "main = putStr \"smalltest\"" > Main.hs
ghc -v -O0 -threaded -L$PREFIX/lib -fasm -o smalltest Main.hs 
./smalltest

