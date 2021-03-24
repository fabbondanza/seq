#!/usr/bin/env bash

set -e

export CC="${CC}"
export CXX="${CXX}"
export USE_ZLIBNG="${USE_ZLIBNG:-1}"

export INSTALLDIR="${PWD}/deps"
export SRCDIR="${PWD}/deps_src"
mkdir -p "${INSTALLDIR}" "${SRCDIR}"

export LD_LIBRARY_PATH="${INSTALLDIR}/lib:${LD_LIBRARY_PATH}"
export LIBRARY_PATH="${INSTALLDIR}/lib:${LIBRARY_PATH}"
export CPATH="${INSTALLDIR}/include:${CPATH}"

die() { echo "$*" 1>&2 ; exit 1; }

export JOBS=1
if [ -n "${1}" ]; then export JOBS="${1}"; fi
echo "Using ${JOBS} cores..."

# Tapir
if [ ! -d "${SRCDIR}/Tapir-LLVM" ]; then
  git clone --depth 1 -b release_60-release https://github.com/seq-lang/Tapir-LLVM "${SRCDIR}/Tapir-LLVM"
  mkdir -p "${SRCDIR}/Tapir-LLVM/build"
  cd "${SRCDIR}/Tapir-LLVM/build"
  cmake .. \
     -DLLVM_INCLUDE_TESTS=OFF \
     -DLLVM_ENABLE_RTTI=ON \
     -DCMAKE_BUILD_TYPE=Release \
     -DLLVM_TARGETS_TO_BUILD=host \
     -DLLVM_ENABLE_ZLIB=OFF \
     -DLLVM_ENABLE_TERMINFO=OFF \
     -DCMAKE_C_COMPILER="${CC}" \
     -DCMAKE_CXX_COMPILER="${CXX}" \
     -DCMAKE_INSTALL_PREFIX="${INSTALLDIR}"
  make -j "${JOBS}"
  make install
  "${INSTALLDIR}/bin/llvm-config" --cmakedir
fi

# OCaml
if [ ! -d "${SRCDIR}/ocaml-4.07.1" ]; then
  curl -L https://github.com/ocaml/ocaml/archive/4.07.1.tar.gz | tar zxf - -C "${SRCDIR}"
  cd "${SRCDIR}/ocaml-4.07.1"
  ./configure \
      -cc "${CC} -Wno-implicit-function-declaration" \
      -fPIC \
      -no-pthread \
      -no-debugger \
      -no-debug-runtime \
      -prefix "${INSTALLDIR}"
  make -j "${JOBS}" world.opt
  make install
  export PATH="${INSTALLDIR}/bin:${PATH}"
  curl -L https://github.com/ocaml/ocamlbuild/archive/0.12.0.tar.gz | tar zxf - -C "${SRCDIR}"
  cd "${SRCDIR}/ocamlbuild-0.12.0"
  make configure \
    PREFIX="${INSTALLDIR}" \
    OCAMLBUILD_BINDIR="${INSTALLDIR}/bin" \
    OCAMLBUILD_LIBDIR="${INSTALLDIR}/lib" \
    OCAMLBUILD_MANDIR="${INSTALLDIR}/man"
  make -j "${JOBS}"
  make install
  "${INSTALLDIR}/bin/ocaml" -version
  "${INSTALLDIR}/bin/ocamlbuild" -version
fi

# Menhir
curl -L https://gitlab.inria.fr/fpottier/menhir/-/archive/20190924/menhir-20190924.tar.gz | tar zxf - -C "${SRCDIR}"
cd "${SRCDIR}/menhir-20190924"
make PREFIX="${INSTALLDIR}" all -j "${JOBS}"
make PREFIX="${INSTALLDIR}" install
"${INSTALLDIR}/bin/menhir" --version
[ ! -f "${INSTALLDIR}/share/menhir/menhirLib.cmx" ] && die "Menhir library not found"

if [ "${USE_ZLIBNG}" = '1' ] ; then
    # zlib-ng
    curl -L https://github.com/zlib-ng/zlib-ng/archive/2.0.1.tar.gz | tar zxf - -C "${SRCDIR}"
    cd "${SRCDIR}/zlib-ng-2.0.1"
    CFLAGS="-fPIC -DNO_QUICK_STRATEGY" ./configure \
        --64 \
        --zlib-compat \
        --prefix="${INSTALLDIR}"
    make -j "${JOBS}"
    make install
    [ ! -f "${INSTALLDIR}/lib/libz.a" ] && die "zlib (zlib-ng) library not found"
else
    # zlib
    curl -L https://zlib.net/zlib-1.2.11.tar.gz | tar zxf - -C "${SRCDIR}"
    cd "${SRCDIR}/zlib-1.2.11"
    CFLAGS=-fPIC ./configure \
        --64 \
        --static \
        --shared \
        --prefix="${INSTALLDIR}"
    make -j "${JOBS}"
    make install
    [ ! -f "${INSTALLDIR}/lib/libz.a" ] && die "zlib library not found"
fi

# libdeflate
curl -L https://github.com/ebiggers/libdeflate/archive/refs/tags/v1.7.tar.gz | tar zxf - -C "${SRCDIR}"
cd "${SRCDIR}/libdeflate-1.7"
make -j "${JOBS}" PREFIX="${INSTALLDIR}"
make install PREFIX="${INSTALLDIR}"

# bdwgc
curl -L https://github.com/ivmai/bdwgc/releases/download/v8.0.4/gc-8.0.4.tar.gz | tar zxf - -C "${SRCDIR}"
cd "${SRCDIR}/gc-8.0.4"
./configure \
    CFLAGS=-fPIC \
    --enable-threads=posix \
    --enable-large-config \
    --enable-thread-local-alloc \
    --prefix="${INSTALLDIR}"
    # --enable-handle-fork=yes --disable-shared --enable-static
make -j "${JOBS}" LDFLAGS=-static
make install
[ ! -f "${INSTALLDIR}/lib/libgc.a" ] && die "gc library not found"

# htslib
curl -L https://github.com/samtools/htslib/releases/download/1.12/htslib-1.12.tar.bz2 | tar jxf - -C "${SRCDIR}"
cd "${SRCDIR}/htslib-1.12"
# Get needed fix so HTSlib works with zlib-ng: https://github.com/samtools/htslib/compare/develop...jkbonfield:zlib-ng-fix
curl -L -O https://raw.githubusercontent.com/jkbonfield/htslib/715056cdd3f85855a503ac932f58e84b92c7dd0e/bgzf.c
./configure \
    CFLAGS="-fPIC" \
    --disable-libcurl \
    --prefix="${INSTALLDIR}"
make -j "${JOBS}"
make install
[ ! -f "${INSTALLDIR}/lib/libhts.a" ] && die "htslib library not found"

# openmp
git clone https://github.com/llvm-mirror/openmp -b release_60 "${SRCDIR}/openmp"
mkdir -p "${SRCDIR}/openmp/build"
cd "${SRCDIR}/openmp/build"
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="${CC}" \
    -DCMAKE_CXX_COMPILER="${CXX}" \
    -DCMAKE_INSTALL_PREFIX="${INSTALLDIR}" \
    -DOPENMP_ENABLE_LIBOMPTARGET=0
make -j "${JOBS}"
make install
# [ ! -f "${INSTALLDIR}/lib/libomp.so" ] && die "openmp library not found"

# libbacktrace
git clone https://github.com/seq-lang/libbacktrace "${SRCDIR}/libbacktrace"
cd "${SRCDIR}/libbacktrace"
CFLAGS="-fPIC" ./configure --prefix="${INSTALLDIR}"
make -j "${JOBS}"
make install
[ ! -f "${INSTALLDIR}/lib/libbacktrace.a" ] && die "libbacktrace library not found"

echo "Dependency generation done: ${INSTALLDIR}"
