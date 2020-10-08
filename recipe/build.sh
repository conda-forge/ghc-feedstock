unset host_alias
unset build_alias
unset CFLAGS
unset CXXFLAGS
unset CPPFLAGS
unset LDFLAGS

export GHC_BUILD=$(echo $BUILD | sed "s/conda/unknown/g")
export GHC_HOST=$(echo $HOST | sed "s/conda/unknown/g")

# Make sure libraries for build are found without LDFLAGS
cp $BUILD_PREFIX/lib/libgmp.so $BUILD_PREFIX/$BUILD/sysroot/usr/lib/
cp $BUILD_PREFIX/lib/libncurses.so $BUILD_PREFIX/$BUILD/sysroot/usr/lib/
cp $BUILD_PREFIX/lib/libtinfo.so $BUILD_PREFIX/$BUILD/sysroot/usr/lib/

# Make sure libraries for host are found without LDFLAGS
cp $PREFIX/lib/libgmp.so $BUILD_PREFIX/$HOST/sysroot/usr/lib/
cp $PREFIX/lib/libncurses.so $BUILD_PREFIX/$HOST/sysroot/usr/lib/
cp $PREFIX/lib/libtinfo.so $BUILD_PREFIX/$HOST/sysroot/usr/lib/

# workaround some bugs in autoconf scripts
cp $(which $AR) $BUILD_PREFIX/bin/$GHC_HOST-ar
cp $(which $GCC) $BUILD_PREFIX/bin/$GHC_HOST-gcc

pushd binary
  # stage0 compiler: --build=$GHC_BUILD --host=$GHC_BUILD --target=$GHC_BUILD
  LDFLAGS="-L$BUILD_PREFIX/lib -Wl,-rpath,$BUILD_PREFIX/lib -Wl,-rpath-link,$BUILD_PREFIX/lib"  CC=$BUILD-gcc AR=$BUILD-ar LD=$BUILD-ld NM=$BUILD-nm OBJDUMP=$BUILD-objdump RANLIB=$BUILD-ranlib CPP=$BUILD-cpp ./configure --prefix=$BUILD_PREFIX --with-gmp-includes=$BUILD_PREFIX/include --with-gmp-libraries=$BUILD_PREFIX/lib --build=$GHC_BUILD --host=$GHC_BUILD --target=$GHC_BUILD
  make install
popd

pushd source
  # stage1 compiler: --build=$GHC_BUILD --host=$GHC_BUILD --target=$GHC_HOST
  # stage2 compiler: --build=$GHC_BUILD --host=$GHC_HOST --target=$GHC_HOST
  export CC=$GCC
  ./configure --prefix=$PREFIX --with-gmp-includes=$PREFIX/include --with-gmp-libraries=$PREFIX/lib --build=$GHC_BUILD --host=$GHC_BUILD --target=$GHC_HOST
  make HADDOCK_DOCS=NO BUILD_SPHINX_HTML=NO BUILD_SPHINX_PDF=NO install -j${CPU_COUNT}
popd

#echo "main = putStr \"smalltest\"" > Main.hs
#ghc -v -O0 -threaded -L$PREFIX/lib -fasm -o smalltest Main.hs
#./smalltest
ghc-pkg recache
