export PATH="$PREFIX/bin:$BUILD_PREFIX/bin:$PATH"
#export CFLAGS="-I$PREFIX/include $CFLAGS"
#export LDFLAGS="-Wl,-L$PREFIX/lib $LDFLAGS"
export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH"
export LIBRARY_PATH="$PREFIX/lib:$LIBRARY_PATH"
echo $ARCH

if [ $ARCH == "aarch64" ]; then
   echo "aarch64 detected"

fi
if [ $ARCH == "x86_64" ]; then
  echo "x86_64 detected"
  export TARGETPLATFORM="x86_64-unknown-linux"
fi
uname -a
which perl
echo $TARGETPLATFORM
cp $SRC_PREFIX/build.mk $BUILD_PREFIX/mk/
./boot
./configure --prefix=$PREFIX --with-gmp-includes=$PREFIX/include --with-gmp-libraries=$PREFIX/lib
make
make install
if [[ -f "$LD" && ! $BUILD_PREFIX/bin/ld ]]; then
   ln -s $LD $BUILD_PREFIX/bin/ld;
fi

#ghc-pkg recache
