#!/bin/bash

set -e -o pipefail -x

export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH"
export LIBRARY_PATH="$PREFIX/lib:$LIBRARY_PATH"
export C_INCLUDE_PATH="$PREFIX/include:$C_INCLUDE_PATH"
export CABAL_DIR="$PREFIX"
export CPPFLAGS=" -I$PREFIX/include $CPPFLAGS "
export CFLAGS=" -I$PREFIX/include -L$PREFIX/lib $CFLAGS "
export CXXFLAGS=" -I$PREFIX/include -L$PREFIX/lib $CXXFLAGS "
export LDFLAGS=" -L$PREFIX/lib $LDFLAGS "
export GMP_INCLUDE_DIRS=$PREFIX/include
export GMP_LIB_DIRS=$PREFIX/lib

echo "#!/bin/bash" > $CC-mine
echo "set -e -o pipefail -x " >> $CC-mine
echo "$CC -I$PREFIX/include -L$PREFIX/lib -pthread -fPIC \"\$@\"" >> $CC-mine
chmod u+x $CC-mine
export CC=$CC-mine

echo "#!/bin/bash" > $CXX-mine
echo "set -e -o pipefail -x " >> $CXX-mine
echo "$CXX -I$PREFIX/include -L$PREFIX/lib -pthread -fPIC \"\$@\"" >> $CXX-mine
chmod u+x $CXX-mine
export CXX=$CXX-mine

echo "#!/bin/bash" > $GCC-mine
echo "set -e -o pipefail -x " >> $GCC-mine
echo "$GCC -I$PREFIX/include -L$PREFIX/lib -pthread -fPIC \"\$@\"" >> $GCC-mine
chmod u+x $GCC-mine
export GCC=$GCC-mine

echo "#!/bin/bash" > $GXX-mine
echo "set -e -o pipefail -x " >> $GXX-mine
echo "$GXX -I$PREFIX/include -L$PREFIX/lib -pthread -fPIC \"\$@\"" >> $GXX-mine
chmod u+x $GXX-mine
export GXX=$GXX-mine

echo "#!/bin/bash" > $LD-mine
echo "set -e -o pipefail -x " >> $LD-mine
echo "$LD -L$PREFIX/lib  \"\$@\"" >> $LD-mine
chmod u+x $LD-mine
export LD=$LD-mine

echo "#!/bin/bash" > ${LD}.gold
echo "set -e -o pipefail -x " >> ${LD}.gold
echo "$LD_GOLD -L$PREFIX/lib  \"\$@\"" >> ${LD}.gold
chmod u+x ${LD}.gold
export LD_GOLD=${LD}.gold

ghc-pkg recache 
cabal v1-update
#cabal v1-install --prefix=$PREFIX --bindir=$BUILD_PREFIX/bin --libdir=$BUILD_PREFIX/lib --ghc-options="-threaded -lgmp -pgmc $GCC -pgml $GCC -optl=-lgmp -optl=-L$PREFIX/lib" --extra-lib-dirs=$PREFIX/lib --extra-include-dirs=$PREFIX/include happy alex
ghc-pkg recache 
which ghc
echo ENV IS
env
ghc --version
echo "SRC_HC_OPTS += -threaded -pgmc $GCC -pgml $GCC -optc-I$PREFIX/include -optl-L$PREFIX/lib " > mk/build.mk
echo "GhcHcOpts += -threaded -pgmc $GCC -pgml $GCC -optc-I$PREFIX/include -optl-L$PREFIX/lib " >> mk/build.mk
echo "GhcLibOpts += -threaded -pgmc $GCC -pgml $GCC -optc-I$PREFIX/include -optl-L$PREFIX/lib " >> mk/build.mk
echo "SRC_CPP_OPTS += -I$PREFIX/include " >> mk/build.mk
echo "SRC_CC_OPTS += -pthread -I$PREFIX/include -L$PREFIX/lib " >> mk/build.mk
echo "SRC_GCC_OPTS += -pthread -I$PREFIX/include -L$PREFIX/lib " >> mk/build.mk
echo "SRC_LD_OPTS += -L$PREFIX/lib " >> mk/build.mk
echo "CONF_CC_OPTS_STAGE0 += -pthread -I$PREFIX/include -L$PREFIX/lib " >> mk/build.mk
echo "CONF_CC_OPTS_STAGE1 += -pthread -I$PREFIX/include -L$PREFIX/lib " >> mk/build.mk
echo "CONF_CC_OPTS_STAGE2 += -pthread -I$PREFIX/include -L$PREFIX/lib " >> mk/build.mk
echo "CONF_CPP_OPTS_STAGE0 += -I$PREFIX/include " >> mk/build.mk
echo "CONF_CPP_OPTS_STAGE1 += -I$PREFIX/include " >> mk/build.mk
echo "CONF_CPP_OPTS_STAGE2 += -I$PREFIX/include " >> mk/build.mk
echo "CONF_GCC_LINKER_OPTS_STAGE0 += -L$PREFIX/lib " >> mk/build.mk
echo "CONF_GCC_LINKER_OPTS_STAGE1 += -L$PREFIX/lib " >> mk/build.mk
echo "CONF_GCC_LINKER_OPTS_STAGE2 += -L$PREFIX/lib " >> mk/build.mk
echo "CONF_LD_LINKER_OPTS_STAGE0 += -L$PREFIX/lib " >> mk/build.mk
echo "CONF_LD_LINKER_OPTS_STAGE1 += -L$PREFIX/lib " >> mk/build.mk
echo "CONF_LD_LINKER_OPTS_STAGE2 += -L$PREFIX/lib " >> mk/build.mk
echo mk/build.mk is
cat mk/build.mk


./boot
./configure --prefix=$PREFIX CC=$GCC
make
make install
