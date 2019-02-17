export PATH="$BUILD_PREFIX/x86_64-conda_cos6-linux-gnu/bin:$PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH"
export LIBRARY_PATH="$PREFIX/lib:$LIBRARY_PATH"
export C_INCLUDE_PATH="$PREFIX/include:$C_INCLUDE_PATH"
export LDFLAGS+=" -L$PREFIX/lib -lgmp -lpthread "
##export CPPFLAGS=" -Wl,-L$PREFIX/lib -Wl,-lgmp -Wl,-lpthread -Wl,-lgcc_s $CPPFLAGS "
#ldconfig -p
#echo "echo CPPFLAGS"
#echo $CPPFLAGS
export LIBS=" -L$PREFIX/lib -lgmp -lpthread -lgcc_s $LIBS "
export PRIM_EXTRA_LIBRARIES=" -L$PREFIX/lib -lgmp -lpthread "
export PRIM_CFLAGS=" -fuse-ld=gold "
ghc-pkg recache
#ghc-pkg describe rts
#ghc-pkg describe rts > rts.pkg
#perl -pi -e 's/$PREFIX\/lib\/ghc-8.2.2\/rts/$PREFIX\/lib\/ghc-8.2.2\/rts \$\{pkgroot\}\/../g' rts.pkg
#cat rts.pkg
#ghc-pkg update rts.pkg
#export CONF_GCC_LINKER_OPTS_STAGE0=$LDFLAGS
#export CONF_GCC_LINKER_OPTS_STAGE1=$LDFLAGS
#export CONF_GCC_LINKER_OPTS_STAGE2=$LDFLAGS
#export CONF_GCC_LINKER_OPTS_STAGE3=$LDFLAGS
#export CONF_CC_LINKER_OPTS_STAGE0=$LDFLAGS
#export CONF_CC_LINKER_OPTS_STAGE1=$LDFLAGS
#export CONF_CC_LINKER_OPTS_STAGE2=$LDFLAGS
#export CONF_CC_LINKER_OPTS_STAGE3=$LDFLAGS
#export CONF_CPP_OPTS_STAGE0=$CFLAGS
#export CONF_CPP_OPTS_STAGE1="$CPPFLAGS"
#export CONF_CPP_OPTS_STAGE2="$CPPFLAGS"
#export CONF_CPP_OPTS_STAGE3="$CPPFLAGS"

#export SRC_HC_OPTS=" -L$PREFIX/lib -lgmp -threaded -pgmc x86_64-conda_cos6-linux-gnu-cc -pgml x86_64-conda_cos6-linux-gnu-cc "
#export SRC_HSC2HS_OPTS=" -L$PREFIX/lib -lgmp -threaded -pgmc x86_64-conda_cos6-linux-gnu-cc -pgml x86_64-conda_cos6-linux-gnu-cc "
#export CONF_HC_OPTS_STAGE0=" -L$PREFIX/lib -lgmp -threaded -pgmc x86_64-conda_cos6-linux-gnu-cc -pgml x86_64-conda_cos6-linux-gnu-cc "
#export CONF_HC_OPTS_STAGE1=" -L$PREFIX/lib -lgmp -threaded -pgmc x86_64-conda_cos6-linux-gnu-cc -pgml x86_64-conda_cos6-linux-gnu-cc "
#export CONF_HC_OPTS_STAGE2=" -L$PREFIX/lib -lgmp -threaded -pgmc x86_64-conda_cos6-linux-gnu-cc -pgml x86_64-conda_cos6-linux-gnu-cc "
#export CONF_HC_OPTS_STAGE3=" -L$PREFIX/lib -lgmp -threaded -pgmc x86_64-conda_cos6-linux-gnu-cc -pgml x86_64-conda_cos6-linux-gnu-cc "
#perl -pi -e 's/GhcLibHcOpts=/GhcLibHcOpts= -pgmc x86_64-conda_cos6-linux-gnu-cc -pgml x86_64-conda_cos6-linux-gnu-cc -threaded /g' mk/config.mk.in
#perl -pi -e 's/GhcRtsHcOpts=-O2 -fomit-frame-pointer -g/GhcRtsHcOpts=-O2 -fomit-frame-pointer -g -pgmc x86_64-conda_cos6-linux-gnu-cc -pgml x86_64-conda_cos6-linux-gnu-cc -threaded /g' mk/config.mk.in
#perl -pi -e 's/GhcHcOpts=/GhcHcOpts= -pgmc x86_64-conda_cos6-linux-gnu-cc -pgml x86_64-conda_cos6-linux-gnu-cc -threaded /g' mk/config.mk.in
#perl -pi -e 's/GhcStage1HcOpts=/GhcStage1HcOpts= -pgmc x86_64-conda_cos6-linux-gnu-cc -pgml x86_64-conda_cos6-linux-gnu-cc -threaded /g' mk/config.mk.in
#perl -pi -e 's/GhcStage2HcOpts=/GhcStage2HcOpts= -pgmc x86_64-conda_cos6-linux-gnu-cc -pgml x86_64-conda_cos6-linux-gnu-cc -threaded /g' mk/config.mk.in
#perl -pi -e 's/GhcStage3HcOpts=/GhcStage3HcOpts= -pgmc x86_64-conda_cos6-linux-gnu-cc -pgml x86_64-conda_cos6-linux-gnu-cc -threaded /g' mk/config.mk.in
#cat mk/config.mk.in
#./configure --prefix=$PREFIX --with-hs-cpp=$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cpp --with-gmp-includes="$PREFIX/include" --with-curses-libraries="$PREFIX/lib" --with-gmp-libraries="$PREFIX/lib" CC="$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc" LD="$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc" CPPFLAGS="$_INCLUDE_PATH" LDFLAGS=" -L$PREFIX/lib -lgmp -lpthread" 
./configure --prefix=$PREFIX --enable-bootstrap-with-devel-snapshot --with-ffi-includes=$PREFIX/include --with-ffi-libraries=$PREFIX/lib --with-system-libffi CPP=$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cpp CPPFLAGS=-I$PREFIX/include --with-gmp-includes=$PREFIX/include --with-curses-libraries=$PREFIX/lib --with-gmp-libraries=$PREFIX/lib LDFLAGS=-L$PREFIX/lib CC=$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc LD=$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc AR=$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-ar AS=$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-as CFLAGS=-fuse-ld=gold CONF_GCC_LINKER_OPTS_STAGE1=-fuse-ld=gold CONF_GCC_LINKER_OPTS_STAGE2=-fuse-ld=gold PRIM_EXTRA_LIBRARIES=-L$PREFIX/lib PRIM_CFLAGS=-fuse-ld=gold
#cat mk/config.mk 
cp mk/build.mk.sample mk/build.mk
perl -pi -e 's/#BuildFlavour = quick\n/BuildFlavour = quick\n/' mk/build.mk
#perl -pi -e 's/#V=0/V=0/g' mk/build.mk
#perl -pi -e 's/#HADDOCK_DOCS = YES/HADDOCK_DOCS = NO/g' mk/build.mk
echo "V=0" >> mk/build.mk
echo "GhcLibHcOpts += -fPIC" >> mk/build.mk
echo "GhcRtsHcOpts += -fPIC" >> mk/build.mk
echo "EXTRA_CC_OPTS += -std=gnu99" >> mk/build.mk
#echo "HADDOCK_DOCS = NO" >> mk/build.mk
echo "SRC_HC_OPTS = -O0 -H64m -optl-fuse-ld=gold -optl-L$PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0 -optl-L$PREFIX/lib -lgmp -threaded -lgcc -lgcc_s -pgmc $BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc -pgml $BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-cc " >> mk/build.mk
#echo "CONF_CC_OPTS_STAGE0 = -Wl,-L$PREFIX/lib -Wl,-lgcc " >> mk/build.mk
#echo "CONF_CC_OPTS_STAGE1 = -Wl,-L$PREFIX/lib " >> mk/build.mk
#echo "CONF_CC_OPTS_STAGE2 = -Wl,-L$PREFIX/lib -Wl,-lgmp -lpthread " >> mk/build.mk
#echo "CONF_CC_OPTS_STAGE3 = -Wl,-L$PREFIX/lib -Wl,-lgmp -lpthread " >> mk/build.mk
##echo "libraries/ghc-prim_dist-boot_HC_OPTS += -optl -Wl,-L$PREFIX/lib -optl -Wl,-L$PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0 -optl -Wl,-lgcc_s -optl -Wl,-lgcc " >> mk/ghc.mk
##echo "libraries/ghc-prim_dist-install_CPP_OPTS += -Wl,-L$PREFIX/lib -Wl,-L$PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0 -Wl,-lgcc_s -Wl,-lgcc " >> mk/ghc.mk
echo "SRC_HSC2HS_OPTS = -lgmp -lpthread " >> mk/build.mk
#echo "libraries/integer-gmp_CONFIGURE_OPTS += --configure-option=LDFLAGS=\" -L$PREFIX/lib \" --ghc-options=\" -L$PREFIX/lib -lgmp -threaded -pgmc x86_64-conda_cos6-linux-gnu-cc -pgml x86_64-conda_cos6-linux-gnu-cc \"" >> mk/build.mk
#echo "libraries/integer-gmp_CONFIGURE_OPTS = --with-gmp-includes=\"$PREFIX/include\" --with-gmp-libraries=\"$PREFIX/include\" " >> mk/build.mk
# -Wl,-L$PREFIX/lib -Wl,-lgmp -Wl,-lpthread -Wl,-lgcc_s
##echo "GhcLibHcOpts= -optl -Wl,-L$PREFIX/lib -optl -Wl,-L$PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0 -optl -Wl,-lgcc_s -optl -Wl,-lgcc -pgmP x86_64-conda_cos6-linux-gnu-cpp -pgmc x86_64-conda_cos6-linux-gnu-cc -pgml x86_64-conda_cos6-linux-gnu-ld.gold " >> mk/build.mk
##echo "GhcRtsHcOpts= -optl -Wl,-L$PREFIX/lib  -optl -Wl,-L$PREFIX/lib/gcc/x86_64-conda_cos6-linux-gnu/7.3.0 -optl -Wl,-lgcc_s -optl -Wl,-lgcc  -pgmP x86_64-conda_cos6-linux-gnu-cpp -pgmc x86_64-conda_cos6-linux-gnu-cc -pgml x86_64-conda_cos6-linux-gnu-ld.gold " >> mk/build.mk
cat mk/build.mk
#./validate --build-only
echo "Settings"
#cat settings
make -j
make install
#Small test 
#if [ -f "$BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-ld" ]; then
#   ln -s $BUILD_PREFIX/bin/x86_64-conda_cos6-linux-gnu-ld $BUILD_PREFIX/bin/ld
#fi
echo "main = putStr \"smalltest\"" > Main.hs
ghc -v -O0 -threaded -L$PREFIX/lib -pgmc x86_64-conda_cos6-linux-gnu-cc -pgml x86_64-conda_cos6-linux-gnu-cc -fasm -o smalltest Main.hs 
./smalltest
