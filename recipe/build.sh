unset host_alias
unset build_alias
export PATH="$PREFIX/bin:$BUILD_PREFIX/bin:$PATH"
#export CFLAGS="-I$PREFIX/include $CFLAGS"
#export LDFLAGS="-Wl,-L$PREFIX/lib $LDFLAGS"
#export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH"
#export LIBRARY_PATH="$PREFIX/lib:$LIBRARY_PATH"
# from eggzilla/ghc-feedstock
#ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-ld $PREFIX/bin/ld
#echo "ls $PREFIX/lib"
#ls $PREFIX/lib
#echo "$BUILD_PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0"
#ls $PREFIX/lib/gcc/
#ls $PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu
#ls $PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0

#export LD=$PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc
#export LD_NO_GOLD=$PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc

if [ $ARCH == "aarch64" ]; then
   echo "aarch64 detected"

fi
if [ $ARCH == "64" ]; then
  echo "x86_64 detected"
  export TARGETPLATFORM="x86_64-unknown-linux"
fi
echo "Targetplatform"
echo $TARGETPLATFORM

#cp $BUILD_PREFIX/mk/build.mk.sample $BUILD_PREFIX/mk/build.mk
echo "PWD"
ls $PWD
echo "build prefix"
ls $BUILD_PREFIX
echo "pwd mk"
ls $PWD/mk/
echo "booting ghc"
./boot
# from eggzilla
# ./configure --prefix=$PREFIX --enable-bootstrap-with-devel-snapshot --with-ffi-includes=$PREFIX/include --with-ffi-libraries=$PREFIX/lib --with-system-libffi CPP=$PREFIX/bin/cpp --with-gmp-includes=$PREFIX/include --with-curses-libraries=$PREFIX/lib --with-gmp-libraries=$PREFIX/lib LDFLAGS=-L$PREFIX/lib CC=$PREFIX/bin/cc LD=$PREFIX/bin/cc AR=$PREFIX/bin/ar AS=$BUILD_PREFIX/bin/as CFLAGS=-fno-builtin CONF_GCC_LINKER_OPTS_STAGE0=-fuse-ld=gold CONF_GCC_LINKER_OPTS_STAGE1=-fuse-ld=gold CONF_GCC_LINKER_OPTS_STAGE2=-fuse-ld=gold LD_NO_GOLD=$PREFIX/bin/cc
#./configure --prefix=$PREFIX --with-gmp-includes=$PREFIX/include --with-gmp-libraries=$PREFIX/lib
echo "ARCH"
echo $ARCH
echo "ghc"
which ghc
if [ $ARCH == "64" ]; then
  echo "running configure for x86_64
  #export CC=$BUILD_PREFIX/bin/x86_64-conda-linux-gnu-cc"
  echo $CC
  ./configure --prefix=$PREFIX CC=$PREFIX/bin/cc
  #./configure --prefix=$PREFIX CPP=x86_64-conda_cos6-linux-gnu-cpp --with-gmp-includes=$PREFIX/include --with-gmp-libraries=$PREFIX/lib CC=$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc LD=$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc
fi
if [ $ARCH == "aarch64" ]; then
  echo "running configure for aarch64"
  ./configure --prefix=$BUILD_PREFIX --with-gmp-includes=$BUILD_PREFIX/include --with-gmp-libraries=$BUILD_PREFIX/lib
fi
echo "PWD again"
ls $PWD
echo "build prefix again"
ls $BUILD_PREFIX
# from eggzilla
echo "trying to copy build config"
cp $PWD/mk/build.mk.sample $PWD/mk/build.mk
perl -pi -e 's/#BuildFlavour = quick\n/BuildFlavour = quickest\n/' mk/build.mk
#echo "V=0" >> mk/build.mk
echo "make"
which make
make
make install
#iif [[ -f "$LD" && ! $BUILD_PREFIX/bin/ld ]]; then
#   ln -s $LD $BUILD_PREFIX/bin/ld;
#fi

#ghc-pkg recache
