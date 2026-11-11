#!/bin/sh
# Compile and run the ABI probe against the pinned install tree.
# FLINT_PREFIX: install prefix with include/ and lib/  (default: local build tree)
# DEPS_PREFIX : prefix with gmp.h and mpfr.h
# BLAS_LIBDIR : directory with libopenblas.so (OpenBLAS32_jll artifact lib dir)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
FLINT_PREFIX=${FLINT_PREFIX:-/tmp/flintfloats-jll-build/install}
DEPS_PREFIX=${DEPS_PREFIX:-/tmp/flintfloats-jll-build/deps}
BLAS_LIBDIR=${BLAS_LIBDIR:-$HOME/.julia/artifacts/6e5f732be84dd0646a05c1e02767c276188c34ce/lib}
out=${1:-$here/layout.txt}
tmp=$(mktemp -d)
cc -O0 -std=c11 -I"$FLINT_PREFIX/include" -I"$DEPS_PREFIX/include" "$here/probe.c" \
   -L"$FLINT_PREFIX/lib" -Wl,-rpath,"$FLINT_PREFIX/lib" -L"$DEPS_PREFIX/lib" -Wl,-rpath,"$DEPS_PREFIX/lib" \
   -L"$BLAS_LIBDIR" -Wl,-rpath,"$BLAS_LIBDIR" -Wl,-rpath-link,"$BLAS_LIBDIR" -lflint -lmpfr -lgmp -o "$tmp/probe"
LD_LIBRARY_PATH="$BLAS_LIBDIR:$FLINT_PREFIX/lib:$DEPS_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$tmp/probe" > "$out"
rm -rf "$tmp"
