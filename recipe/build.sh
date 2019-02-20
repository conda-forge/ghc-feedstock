export PATH="$BUILD_PREFIX/bin:$PREFIX/bin:$PATH"
ln -s $BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc $BUILD_PREFIX/bin/ld
echo "which ld"
which ld
ln -s $BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc $BUILD_PREFIX/bin/collect2
echo "which collect2"
which collect2
ln -s $BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-ld.gold $BUILD_PREFIX/bin/ld.gold
echo "which ld.gold"
which ld.gold
ln -s $BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-ar $BUILD_PREFIX/bin/ar
echo "which ar"
which ar
ln -s $BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-as $BUILD_PREFIX/bin/as
echo "which as"
which as
export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH"
export LIBRARY_PATH="$PREFIX/lib:$LIBRARY_PATH"
export C_INCLUDE_PATH="$PREFIX/include:$C_INCLUDE_PATH"
export LDFLAGS+=" -L$PREFIX/lib -lgmp -lpthread "
export LIBS=" -L$PREFIX/lib -lgmp -lpthread -lgcc_s $LIBS "
#export PRIM_EXTRA_LIBRARIES=" -Wl,-L$PREFIX/lib -Wl,-lgmp -Wl,-lpthread "
#export PRIM_CFLAGS=" -fuse-ld=gold "
export LD=$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc
export LD_NO_GOLD=$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc
ghc-pkg recache
./configure --prefix=$PREFIX --enable-bootstrap-with-devel-snapshot --with-ffi-includes=$PREFIX/include --with-ffi-libraries=$PREFIX/lib --with-system-libffi CPP=$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cpp CPPFLAGS=-I$PREFIX/include --with-gmp-includes=$PREFIX/include --with-curses-libraries=$PREFIX/lib --with-gmp-libraries=$PREFIX/lib LDFLAGS=-L$PREFIX/lib CC=$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc LD=$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc AR=$BUILD_PREFIX/bin/ar AS=$BUILD_PREFIX/bin/as CFLAGS=-fuse-ld=gold CONF_GCC_LINKER_OPTS_STAGE0=-fuse-ld=gold CONF_GCC_LINKER_OPTS_STAGE1=-fuse-ld=gold CONF_GCC_LINKER_OPTS_STAGE2=-fuse-ld=gold LD_NO_GOLD=$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc
# CONF_CPP_OPTS_STAGE0=-fuse-ld=gold CONF_CPP_OPTS_STAGE1=-fuse-ld=gold CONF_CPP_OPTS_STAGE2=-fuse-ld=gold CONF_CC_OPTS_STAGE0=-fuse-ld=gold CONF_CC_OPTS_STAGE1=-fuse-ld=gold CONF_CC_OPTS_STAGE2=-fuse-ld=gold PRIM_EXTRA_LIBRARIES=-L$PREFIX/lib PRIM_CFLAGS=-fuse-ld=gold --with-iconv-includes=$PREFIX/include" "--with-iconv-libraries=$PREFIX/lib
cp mk/build.mk.sample mk/build.mk
perl -pi -e 's/#BuildFlavour = quick\n/BuildFlavour = quick\n/' mk/build.mk
echo "V=0" >> mk/build.mk
echo "GhcLibHcOpts += -fPIC -pgmc $BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc -pgml $BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc -optl-fuse-ld=gold -optl-L$PREFIX/lib -optl-L$PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0 -lgcc -lgcc_s " >> mk/build.mk
echo "GhcRtsHcOpts += -fPIC -pgmc $BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc -pgml $BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc -optl-fuse-ld=gold -optl-L$PREFIX/lib -optl-L$PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0 -lgcc -lgcc_s " >> mk/build.mk
echo "SplitObjs=NO" >> mk/build.mk
echo "EXTRA_CC_OPTS += -std=gnu99" >> mk/build.mk
echo "SRC_HC_OPTS = -O0 -H64m -optl-fuse-ld=gold -optl-L$PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0 -optl-L$PREFIX/lib -lgmp -threaded -lgcc -lgcc_s -pgmc $BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc -pgml $BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc " >> mk/build.mk
echo "SRC_HSC2HS_OPTS = -lgmp -lpthread " >> mk/build.mk
#cat mk/build.mk
echo "config.mk"
cat mk/config.mk
perl -pi -e "s|LD_NO_GOLD = \$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc|LD_NO_GOLD = $BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc|" mk/config.mk
perl -pi -e "s|LD = \$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc|LD = $BUILD_PREFIX/bin/ld.gold|" mk/config.mk
perl -pi -e "s|AR = ar|AR = $BUILD_PREFIX\/bin\/x86_64-conda_cos6-linux-gnu-ar|" mk/config.mk
make -j
make install
echo "main = putStr \"smalltest\"" > Main.hs
ghc -v -O0 -threaded -L$PREFIX/lib -pgmc x86_64-conda_cos6-linux-gnu-cc -pgml x86_64-conda_cos6-linux-gnu-cc -fasm -o smalltest Main.hs 
./smalltest
