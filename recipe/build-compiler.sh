#!/bin/bash

# TODOs:
# * Check CONF_CC_OPTS_STAGE2
# * add ppc64le
# * add darwin in possible separate PR

set -x
if [[ "${target_platform}" == linux-* ]]; then
  # Enforce these flags to set from scratch
  unset CFLAGS
  unset CXXFLAGS
  unset LDFLAGS
  # First get the flags for the cross-compilation target
  echo Activate binutils
  source $CONDA_PREFIX/etc/conda/activate.d/activate-binutils_${ghc_target_platform}.sh
  echo Activate gcc
  source $CONDA_PREFIX/etc/conda/activate.d/activate-gcc_${ghc_target_platform}.sh
  echo Activate gxx
  source $CONDA_PREFIX/etc/conda/activate.d/activate-gxx_${ghc_target_platform}.sh
fi

export AR_GHC_TARGET="${AR}"
export CC_GHC_TARGET="${CC}"
export CFLAGS_GHC_TARGET="${CFLAGS//-fno-plt/}"
export LD_GHC_TARGET="${LD}"
export NM_GHC_TARGET="${NM}"
export STRIP_GHC_TARGET="${STRIP}"

if [[ "${ghc_target_platform}" == linux-* ]]; then
  export AR_GHC_TARGET=$(basename ${AR_GHC_TARGET})
  export CC_GHC_TARGET=$(basename ${CC_GHC_TARGET})
  export LD_GHC_TARGET=$(basename ${LD_GHC_TARGET})
  export NM_GHC_TARGET=$(basename ${NM_GHC_TARGET})
  export STRIP_GHC_TARGET=$(basename ${STRIP_GHC_TARGET})
fi

if [[ "${target_platform}" == linux-* ]]; then
  # Enforce these flags to set from scratch
  unset CFLAGS
  unset CXXFLAGS
  unset LDFLAGS
  # Ensure the correct target scripts are activated here.
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
      sed 's/#\(BuildFlavour = perf-cross\)/\1/' mk/build.mk.sample > mk/build.mk
      echo 'Stage1Only = YES' >> mk/build.mk
    else
      sed 's/#\(BuildFlavour = perf\)/\1/' mk/build.mk.sample > mk/build.mk
    fi
    export CONF_CC_OPTS_STAGE0="${CFLAGS}"
    export CONF_CC_OPTS_STAGE1="${CFLAGS_GHC_TARGET}"
    # FIXME: Does this work?
    # export CONF_CC_OPTS_STAGE2="${CFLAGS_GHC_TARGET}"
    unset CFLAGS
    autoreconf
    cp $RECIPE_DIR/cpp_wrapper.sh $PREFIX/bin/${conda_target_arch}-ghc_cpp_wrapper-${PKG_VERSION}
    sed -i "s;CPP;${CPP};g" $PREFIX/bin/${conda_target_arch}-ghc_cpp_wrapper-${PKG_VERSION}
    ./configure --prefix=$PREFIX --with-gmp-includes=$PREFIX/include --with-gmp-libraries=$PREFIX/lib --with-ffi-includes=$PREFIX/include --with-ffi-libraries=$PREFIX/lib --build=$GHC_BUILD --target=$GHC_TARGET CC="${CC_GHC_TARGET}" LD="${LD_GHC_TARGET}" NM="${NM_GHC_TARGET}" STRIP="${STRIP_GHC_TARGET}" CPP="$PREFIX/bin/${conda_target_arch}-ghc_cpp_wrapper-${PKG_VERSION}"
    EXTRA_HC_OPTS=""
    for flag in ${LDFLAGS}; do
	EXTRA_HC_OPTS="${EXTRA_HC_OPTS} -optl${flag}"
    done
    make HADDOCK_DOCS=NO BUILD_SPHINX_HTML=NO BUILD_SPHINX_PDF=NO "EXTRA_HC_OPTS=${EXTRA_HC_OPTS}" -j${CPU_COUNT}
    make HADDOCK_DOCS=NO BUILD_SPHINX_HTML=NO BUILD_SPHINX_PDF=NO "EXTRA_HC_OPTS=${EXTRA_HC_OPTS}" install -j${CPU_COUNT}
  )
popd

mkdir -p "${PREFIX}/etc/conda/activate.d"
cp "${RECIPE_DIR}/activate.sh" "${PREFIX}/etc/conda/activate.d/${PKG_NAME}_${PKG_VERSION}_activate.sh"

sed -i -e "s/conda_target_arch/${conda_target_arch}/g" "${PREFIX}/etc/conda/activate.d/${PKG_NAME}_${PKG_VERSION}_activate.sh"
sed -i -e "s/PKG_VERSION/${PKG_VERSION}/g" "${PREFIX}/etc/conda/activate.d/${PKG_NAME}_${PKG_VERSION}_activate.sh"
GHC_BINARIES="ghc-${PKG_VERSION} ghc-pkg-${PKG_VERSION} ghci-${PKG_VERSION} runghc-${PKG_VERSION}"
GHC_DEL_LINKS="ghc ghci ghc-pkg runghc runhaskell"
GHC_MOVED_BINARIES="hp2ps hpc hsc2hs"

mkdir -p ${SRC_DIR}/moved_binaries
if [[ "${ghc_target_arch}" == "${GHC_HOST}" ]]; then
  # Delete package cache as it is invalid on installation.
  # This needs to be regenerated on activation.
  rm $PREFIX/lib/ghc-${PKG_VERSION}/package.conf.d/package.cache
  for exe in ${GHC_BINARIES}; do
    mv ${PREFIX}/bin/${exe} ${PREFIX}/bin/${conda_target_arch}-${exe}
  done
  for exe in ${GHC_DEL_LINKS}; do
    rm ${PREFIX}/bin/${exe}
  done
  for exe in ${GHC_MOVED_BINARIES}; do
    mv ${PREFIX}/bin/${exe} ${SRC_DIR}/moved_binaries/${conda_target_arch}-${exe}
  done
  ln -s ${PREFIX}/lib/ghc-${PKG_VERSION} ${PREFIX}/lib/${conda_target_arch}-ghc-${PKG_VERSION}
  # Delete profile-enabled static libraries, other distributions don't seem to ship them either and they are very heavy.
  find $PREFIX/lib/ghc-${PKG_VERSION} -name '*_p.a' -delete
  find $PREFIX/lib/ghc-${PKG_VERSION} -name '*.p_o' -delete
else
  rm $PREFIX/lib/${ghc_target_arch}-ghc-${PKG_VERSION}/package.conf.d/package.cache
  for exe in ${GHC_BINARIES}; do
    mv ${PREFIX}/bin/${ghc_target_arch}-${exe} ${PREFIX}/bin/${conda_target_arch}-${exe}
  done
  for exe in ${GHC_DEL_LINKS}; do
    rm ${PREFIX}/bin/${ghc_target_arch}-${exe}
  done
  for exe in ${GHC_MOVED_BINARIES}; do
    mv ${PREFIX}/bin/${ghc_target_arch}-${exe} ${SRC_DIR}/moved_binaries/${conda_target_arch}-${exe}
  done
  ln -s ${PREFIX}/lib/${ghc_target_arch}-ghc-${PKG_VERSION} ${PREFIX}/lib/${conda_target_arch}-ghc-${PKG_VERSION}
  # Delete profile-enabled static libraries, other distributions don't seem to ship them either and they are very heavy.
  find $PREFIX/lib/${ghc_target_arch}-ghc-${PKG_VERSION} -name '*_p.a' -delete
  find $PREFIX/lib/${ghc_target_arch}-ghc-${PKG_VERSION} -name '*.p_o' -delete
fi
