unset host_alias
unset build_alias
export PATH="$PREFIX/bin:$BUILD_PREFIX/bin:$PATH"
#export CFLAGS="-I$PREFIX/include $CFLAGS"
#export LDFLAGS="-Wl,-L$PREFIX/lib $LDFLAGS"
export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH"
export LIBRARY_PATH="$PREFIX/lib:$LIBRARY_PATH"
# from eggzilla/ghc-feedstock
echo "echo $PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0"
ls $PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-ld.gold $PREFIX/bin/ld.gold
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-ld $PREFIX/bin/ld
echo "ls $PREFIX/lib"
ls $PREFIX/lib
echo "$BUILD_PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0"
ls $PREFIX/lib/gcc/
ls $PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu
#ls $PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0

export LD=$PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc
export LD_NO_GOLD=$PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc
ghc-pkg recache
if [ $ARCH == "aarch64" ]; then
   echo "aarch64 detected"

fi
if [ $ARCH == "64" ]; then
  echo "x86_64 detected"
  export TARGETPLATFORM="x86_64-unknown-linux"
fi
uname -a
which perl
echo $TARGETPLATFORM
#cp build.mk $BUILD_PREFIX/mk/
./boot
# from eggzilla
# ./configure --prefix=$PREFIX --enable-bootstrap-with-devel-snapshot --with-ffi-includes=$PREFIX/include --with-ffi-libraries=$PREFIX/lib --with-system-libffi CPP=$PREFIX/bin/cpp --with-gmp-includes=$PREFIX/include --with-curses-libraries=$PREFIX/lib --with-gmp-libraries=$PREFIX/lib LDFLAGS=-L$PREFIX/lib CC=$PREFIX/bin/cc LD=$PREFIX/bin/cc AR=$PREFIX/bin/ar AS=$BUILD_PREFIX/bin/as CFLAGS=-fno-builtin CONF_GCC_LINKER_OPTS_STAGE0=-fuse-ld=gold CONF_GCC_LINKER_OPTS_STAGE1=-fuse-ld=gold CONF_GCC_LINKER_OPTS_STAGE2=-fuse-ld=gold LD_NO_GOLD=$PREFIX/bin/cc
#./configure --prefix=$PREFIX --with-gmp-includes=$PREFIX/include --with-gmp-libraries=$PREFIX/lib
if [ $ARCH == "64" ]; then
  ./configure --prefix=$PREFIX CPP=x86_64-conda_cos6-linux-gnu-cpp --with-gmp-includes=$PREFIX/include --with-gmp-libraries=$PREFIX/lib CC=$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc LD=$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc
fi
if [ $ARCH == "aarch64" ]; then
  ./configure --prefix=$BUILD_PREFIX --with-gmp-includes=$BUILD_PREFIX/include --with-gmp-libraries=$BUILD_PREFIX/lib
fi
# from eggzilla
cp mk/build.mk.sample mk/build.mk
perl -pi -e 's/#BuildFlavour = quick\n/BuildFlavour = quickest\n/' mk/build.mk
#echo "V=0" >> mk/build.mk
#
make
make install
if [[ -f "$LD" && ! $BUILD_PREFIX/bin/ld ]]; then
   ln -s $LD $BUILD_PREFIX/bin/ld;
fi

#ghc-pkg recache
