export PATH="$PREFIX/bin:$PATH"
#echo $PATH
#find $PREFIX -name "collect2"
#find $BUILD_PREFIX -name "collect2"
#rm -r $BUILD_PREFIX/x86_64-conda_cos6-linux-gnu/bin/ld
rm -r $BUILD_PREFIX/libexec
#rm -r $PREFIX/x86_64-conda_cos6-linux-gnu/bin/ld
#ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc $PREFIX/x86_64-conda_cos6-linux-gnu/bin/ld
rm -r $PREFIX/libexec/gcc/x86_64-conda_cos6-linux-gnu/7.3.0/collect2
rm -r $PREFIX/libexec/gcc/x86_64-conda_cos6-linux-gnu/7.3.0/lto-wrapper
#rm -r $BUILD_PREFIX/x86_64-conda_cos6-linux-gnu
#rm -r $PREFIX/x86_64-conda_cos6-linux-gnu/bin/collect2
echo "echo $PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0"
ls $PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-addr2line $PREFIX/bin/addr2line
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc $PREFIX/bin/cc
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-c++filt $PREFIX/bin/c++filt
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-cpp $PREFIX/bin/cpp
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-ct-ng.config $PREFIX/bin/ct-ng.config
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-dwp $PREFIX/bin/dwp
#ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-elfedit  $PREFIX/bin/elfedit 
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-gcc $PREFIX/bin/gcc
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-gcc-ar $PREFIX/bin/gcc-ar
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-gcc-nm $PREFIX/bin/gcc-nm
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-elfedit  $PREFIX/bin/elfedit 
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-gcc-ranlib $PREFIX/bin/gcc-ranlib
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-gcc-gcov $PREFIX/bin/gcc-gcov
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-gcc-gcov-dump $PREFIX/bin/gcc-gcov-dump
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-gcov-tool  $PREFIX/bin/gcov-tool
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-gcc-gprof $PREFIX/bin/gprof
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-gcc-nm $PREFIX/bin/nm
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-gcc-objcopy $PREFIX/bin/objcopy
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-gcc-ranlib $PREFIX/bin/ranlib
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-gcc-readelf $PREFIX/bin/readelf
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-gcc-size $PREFIX/bin/size
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-gcc-strings $PREFIX/bin/strings
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-gcc-strip $PREFIX/bin/strip
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-ld.gold $PREFIX/bin/ld.gold
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-ld $PREFIX/bin/ld
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-ar $PREFIX/bin/ar
ln -s $PREFIX/bin/x86_64-conda_cos6-linux-gnu-as $PREFIX/bin/as
cp $RECIPE_DIR/memcopy.c $PREFIX/lib
#gcc -c $PREFIX/lib/memcopy.c -o $PREFIX/lib/memcopy.o
#gcc -shared $PREFIX/lib/memcopy.o -o $PREFIX/lib/memcopy.so

rm $PREFIX/x86_64-conda_cos6-linux-gnu/bin/ld
echo "ls $PREFIX/lib"
ls $PREFIX/lib
echo "$BUILD_PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0"
ls $PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0
rm  $PREFIX/lib/libgcc_s.so.1
ln -s $BUILD_PREFIX/x86_64-conda_cos6-linux-gnu/lib/libgcc_s.so.1 $PREFIX/lib/libgcc_s.so.1
#ln -s $PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0/libgcc.a $PREFIX/lib/libgcc_s.a
#ln -s $PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0/libgcc.a $PREFIX/lib/libgcc.a
#cp $PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0/libgcc.a $PREFIX/lib/libgcc_s.a
#cp $PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0/libgcc.a $PREFIX/lib/libgcc.a
chmod 755 $PREFIX/x86_64-conda_cos6-linux-gnu/lib/libgcc_s.so
chmod 755 $PREFIX/x86_64-conda_cos6-linux-gnu/lib/libgcc_s.so.1
chmod 755 $PREFIX/lib/libgcc_s.so
#rm $PREFIX/lib/libgcc_s.so
#ln -s $PREFIX/lib/libgcc_s.so.1 $PREFIX/lib/libgcc_s.so
chmod 755 $PREFIX/lib/libgcc_s.so.1
#cp /home/egg/current/Projects/ghc-feedstock/libgcc_s.so  $PREFIX/lib/libgcc_s.so
#export CFLAGS="-static -Wl,-Bdynamic,-lgcc_s,-Bstatic"
export LD_LIBRARY_PATH="$BUILD_PREFIX/lib/ghc-8.2.2/rts:$PREFIX/lib:$LD_LIBRARY_PATH"
export LIBRARY_PATH="$BUILD_PREFIX/lib/ghc-8.2.2/rts:$PREFIX/lib:$LIBRARY_PATH"
export C_INCLUDE_PATH="$PREFIX/include:$C_INCLUDE_PATH"
export LDFLAGS="-L$PREFIX/lib"
export LIBS=" -L$BUILD_PREFIX/lib -L$BUILD_PREFIX/lib/ghc-8.2.2/rts -L$PREFIX/lib -lgmp -lpthread -lrt -lgcc_s "
#export PRIM_EXTRA_LIBRARIES=" -Wl,-L$PREFIX/lib -Wl,-lgmp -Wl,-lpthread "
#export PRIM_CFLAGS=" -fuse-ld=gold "
export LD=$PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc
export LD_NO_GOLD=$PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc
#echo "ldconfig"
#ldconfig -v | grep libgcc_s
ghc-pkg recache
#make maintainer-clean
./configure --prefix=$PREFIX --enable-bootstrap-with-devel-snapshot --with-ffi-includes=$PREFIX/include --with-ffi-libraries=$PREFIX/lib --with-system-libffi CPP=$PREFIX/bin/cpp --with-gmp-includes=$PREFIX/include --with-curses-libraries=$PREFIX/lib --with-gmp-libraries=$PREFIX/lib LDFLAGS=-L$PREFIX/lib CC=$PREFIX/bin/cc LD=$PREFIX/bin/cc AR=$PREFIX/bin/ar AS=$BUILD_PREFIX/bin/as CFLAGS=-fno-builtin CONF_GCC_LINKER_OPTS_STAGE0=-fuse-ld=gold CONF_GCC_LINKER_OPTS_STAGE1=-fuse-ld=gold CONF_GCC_LINKER_OPTS_STAGE2=-fuse-ld=gold LD_NO_GOLD=$PREFIX/bin/cc
# CONF_CPP_OPTS_STAGE0=-fuse-ld=gold CONF_CPP_OPTS_STAGE1=-fuse-ld=gold CONF_CPP_OPTS_STAGE2=-fuse-ld=gold CONF_CC_OPTS_STAGE0=-fuse-ld=gold CONF_CC_OPTS_STAGE1=-fuse-ld=gold CONF_CC_OPTS_STAGE2=-fuse-ld=gold PRIM_EXTRA_LIBRARIES=-L$PREFIX/lib PRIM_CFLAGS=-fuse-ld=gold --with-iconv-includes=$PREFIX/include" "--with-iconv-libraries=$PREFIX/lib
cp mk/build.mk.sample mk/build.mk
perl -pi -e 's/#BuildFlavour = quick\n/BuildFlavour = quickest\n/' mk/build.mk
echo "V=0" >> mk/build.mk
echo "GhcLibHcOpts += -fPIC -pgmc $PREFIX/bin/cc -pgml $PREFIX/bin/cc -optl-fuse-ld=gold -optl-L$PREFIX/lib -optl-lgmp " >> mk/build.mk
#echo "GhcRtsHcOpts += -fPIC -pgmc $PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc -pgml $PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc -optl-fuse-ld=gold -optl-L$PREFIX/lib -optl-L$PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0 " >> mk/build.mk
echo "SplitObjs=NO" >> mk/build.mk
#echo "DYNAMIC_GHC_PROGRAMS=NO" >> mk/build.mk
#echo "EXTRA_CC_OPTS += -std=gnu99" >> mk/build.mk
echo "SRC_HC_OPTS = -O0 -H64m -optl-L$PREFIX/lib -lgmp -threaded -pgmc $PREFIX/bin/cc -pgml $PREFIX/bin/cc " >> mk/build.mk 
echo "SRC_HSC2HS_OPTS = -lgmp -lpthread " >> mk/build.mk
#echo "CC_OPTS += = -L$BUILD_PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0 " >> mk/build.mk
#echo "CONF_CC_OPTS += -L$PREFIX/lib -lgmp" >> mk/build.mk
#echo "CONF_CC_OPTS += -B$PREFIX/bin -static -static-gcc" >> mk/build.mk
echo "libraries/ghc-prim/cbits/atomic_CC_OPTS += -Wl,-rpath -Wl,$PREFIX/lib " >> mk/build.mk
#echo "libraries/ghc-prim/cbits/atomic_CC_OPTS += -static -Wl,-rpath -Wl,$PREFIX  -Wl,-Bdynamic,-lgcc_s,-Bstatic " >> mk/build.mk
#echo "libraries/ghc-prim/cbits/atomic_CC_OPTS += -shared-libgcc " >> mk/build.mk
#cat mk/build.mk
echo "config.mk"
cat mk/config.mk
#perl -pi -e "s|LD_NO_GOLD = \$PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc|LD_NO_GOLD = $PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc|" mk/config.mk
#perl -pi -e "s|LD = \$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc|LD = $BUILD_PREFIX/bin/ld.gold|" mk/config.mk
perl -pi -e "s|AR = ar|AR = $PREFIX\/bin\/ar|" mk/config.mk
make -j #3
make install
echo "main = putStr \"smalltest\"" > Main.hs
ghc -v -O0 -threaded -L$PREFIX/lib -pgmc x86_64-conda_cos6-linux-gnu-cc -pgml x86_64-conda_cos6-linux-gnu-cc -fasm -o smalltest Main.hs 
./smalltest
