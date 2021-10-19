#!/bin/bash

# TODOs:
# * What to do about CFLAGS?
# * symlink lib/ghc-arch- to lib/conda-arch-
# * split into version specific and unspecific files
# * ensure plain ghc still works
# * add ppc64le
# * add darwin in possible separate PR
# * are there still files left to be deleted from the PKG since we have switched to quick-cross now?

if [[ "${target_platform}" == linux-* ]]; then
  # Scripts are activated in alphabetical order, we though want to have the correct target_platform activated here
  echo Activate binutils
  source $CONDA_PREFIX/etc/conda/activate.d/activate-binutils_${target_platform}.sh
  echo Activate gcc
  source $CONDA_PREFIX/etc/conda/activate.d/activate-gcc_${target_platform}.sh
  echo Activate gxx
  source $CONDA_PREFIX/etc/conda/activate.d/activate-gxx_${target_platform}.sh
fi

# Only now switch to strict bash mode, otherwise activation may fail
set -exuo pipefail

unset host_alias
unset build_alias

export GHC_BUILD=$(echo $BUILD | sed "s/conda/unknown/g")
export GHC_HOST=$(echo $HOST | sed "s/conda/unknown/g")
export GHC_TARGET=${ghc_target_arch}


if [[ "${target_platform}" == linux-* ]]; then
  # Make sure libraries for build are found without LDFLAGS
  cp $BUILD_PREFIX/lib/libgmp.so $BUILD_PREFIX/$BUILD/sysroot/usr/lib/
  cp $BUILD_PREFIX/lib/libncurses.so $BUILD_PREFIX/$BUILD/sysroot/usr/lib/
  cp $BUILD_PREFIX/lib/libtinfo.so $BUILD_PREFIX/$BUILD/sysroot/usr/lib/

  # Make sure libraries for host are found without LDFLAGS
  cp $PREFIX/lib/libgmp.so $BUILD_PREFIX/$HOST/sysroot/usr/lib/
  cp $PREFIX/lib/libncurses.so $BUILD_PREFIX/$HOST/sysroot/usr/lib/
  cp $PREFIX/lib/libtinfo.so $BUILD_PREFIX/$HOST/sysroot/usr/lib/
fi

mkdir stage0
stage0="$( pwd )/stage0"
pushd binary
  cp $BUILD_PREFIX/share/gnuconfig/config.* .
  # stage0 compiler: --build=$GHC_BUILD --host=$GHC_BUILD --target=$GHC_BUILD
  (
    unset CFLAGS
    LDFLAGS=${LDFLAGS//$PREFIX/$BUILD_PREFIX}
    CC=${CC_FOR_BUILD:-$CC}
    AR=($CC -print-prog-name=ar)
    NM=($CC -print-prog-name=nm)
    if [[ "${build_platform}" == linux-* ]]; then
      CPP=$BUILD-cpp
    fi
    LD=$BUILD-ld OBJDUMP=$BUILD-objdump RANLIB=$BUILD-ranlib STRIP=$BUILD-strip ./configure --prefix="${stage0}" --with-gmp-includes=$BUILD_PREFIX/include --with-gmp-libraries=$BUILD_PREFIX/lib --build=$GHC_BUILD --host=$GHC_BUILD --target=$GHC_BUILD || (cat config.log; exit 1)
    make install -j${CPU_COUNT}
  )
popd

pushd source
  # stage1 compiler: --build=$GHC_BUILD --host=$GHC_BUILD --target=$GHC_HOST
  # stage2 compiler: --build=$GHC_BUILD --host=$GHC_HOST --target=$GHC_HOST
  if [[ "${target_platform}" == linux-* ]]; then
    export CC=$(basename $GCC)
    export AR=$(basename $AR)
    export LD=$(basename $LD)
    export RANLIB=$(basename $RANLIB)
  fi
  cp $BUILD_PREFIX/share/gnuconfig/config.* .
  (
    export
    PATH="${stage0}/bin:${PATH}"
    export ac_cv_prog_fp_prog_ar="${AR}"
    if [[ "${ghc_target_platform}" != "${target_platform}" ]]; then
      sed 's/#\(BuildFlavour = quick-cross\)/\1/' mk/build.mk.sample > mk/build.mk
      echo 'Stage1Only = YES' >> mk/build.mk
    else
      sed 's/#\(BuildFlavour = quick\)/\1/' mk/build.mk.sample > mk/build.mk
    fi
    export CONF_CC_OPTS_STAGE0="${CFLAGS}"
    # FIXME: Somehow this should be set to CFLAGS?
    # export CONF_CC_OPTS_STAGE1="${CFLAGS}"
    unset CFLAGS
    autoreconf
    ./configure --prefix=$PREFIX --with-gmp-includes=$PREFIX/include --with-gmp-libraries=$PREFIX/lib --with-ffi-includes=$PREFIX/include --with-ffi-libraries=$PREFIX/lib --build=$GHC_BUILD --target=$GHC_TARGET CC=$(echo ${ghc_target_arch}| sed 's/unknown/conda/g')-cc LD=$(echo ${ghc_target_arch}| sed 's/unknown/conda/g')-ld
    EXTRA_HC_OPTS=""
    for flag in ${LDFLAGS}; do
	EXTRA_HC_OPTS="${EXTRA_HC_OPTS} -optl${flag}"
    done
    make HADDOCK_DOCS=NO BUILD_SPHINX_HTML=NO BUILD_SPHINX_PDF=NO "EXTRA_HC_OPTS=${EXTRA_HC_OPTS}" -j${CPU_COUNT}
    make HADDOCK_DOCS=NO BUILD_SPHINX_HTML=NO BUILD_SPHINX_PDF=NO "EXTRA_HC_OPTS=${EXTRA_HC_OPTS}" install -j${CPU_COUNT}
  )
  # Delete profile-enabled static libraries, other distributions don't seem to ship them either and they are very heavy.
  #find $PREFIX/lib/ghc-${PKG_VERSION} -name '*_p.a' -delete
  #find $PREFIX/lib/ghc-${PKG_VERSION} -name '*.p_o' -delete
popd

mkdir -p "${PREFIX}/etc/conda/activate.d"
cp "${RECIPE_DIR}/activate.sh" "${PREFIX}/etc/conda/activate.d/${PKG_NAME}_activate.sh"

# Delete package cache as it is invalid on installation.
# This needs to be regenerated on activation.
sed -i -e "s/conda_target_arch/${conda_target_arch}/g" "${PREFIX}/etc/conda/activate.d/${PKG_NAME}_activate.sh"
GHC_BINARIES="ghc-${PKG_VERSION} ghc-pkg-${PKG_VERSION} ghci-${PKG_VERSION} hp2ps hpc hsc2hs runghc-${PKG_VERSION}"
GHC_DEL_LINKS="ghc ghci ghc-pkg runghc runhaskell"
if [[ "${ghc_target_arch}" == "${GHC_HOST}" ]]; then
  rm $PREFIX/lib/ghc-${PKG_VERSION}/package.conf.d/package.cache
  for exe in ${GHC_BINARIES}; do
    mv ${PREFIX}/bin/${exe} ${PREFIX}/bin/${conda_target_arch}-${exe}
  done
  for exe in ${GHC_DEL_LINKS}; do
    rm ${PREFIX}/bin/${exe}
  done
else
  rm $PREFIX/lib/${ghc_target_arch}-ghc-${PKG_VERSION}/package.conf.d/package.cache
  for exe in ${GHC_BINARIES}; do
    mv ${PREFIX}/bin/${ghc_target_arch}-${exe} ${PREFIX}/bin/${conda_target_arch}-${exe}
  done
  for exe in ${GHC_DEL_LINKS}; do
    rm ${PREFIX}/bin/${ghc_target_arch}-${exe}
  done
fi

# Regenerate symlinks
pushd ${PREFIX}/bin
  ln -s ${PREFIX}/bin/${conda_target_arch}-ghc-${PKG_VERSION} ${PREFIX}/bin/${conda_target_arch}-ghc
  ln -s ${PREFIX}/bin/${conda_target_arch}-ghci-${PKG_VERSION} ${PREFIX}/bin/${conda_target_arch}-ghci
  ln -s ${PREFIX}/bin/${conda_target_arch}-ghc-pkg-${PKG_VERSION} ${PREFIX}/bin/${conda_target_arch}-ghc-pkg
  ln -s ${PREFIX}/bin/${conda_target_arch}-runghc-${PKG_VERSION} ${PREFIX}/bin/${conda_target_arch}-runghc
  ln -s ${PREFIX}/bin/${conda_target_arch}-runghc ${PREFIX}/bin/${conda_target_arch}-runhaskell
popd
