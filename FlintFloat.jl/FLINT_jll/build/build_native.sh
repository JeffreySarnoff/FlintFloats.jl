#!/usr/bin/env bash
# Rebuild the bundled revision with locally installed dependency prefixes.
set -euo pipefail
if [[ $# -lt 3 || $# -gt 4 ]]; then
    echo "Usage: $0 GMP_PREFIX MPFR_PREFIX OPENBLAS32_PREFIX [JOBS]" >&2
    exit 2
fi
package_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
gmp_prefix=$(realpath "$1")
mpfr_prefix=$(realpath "$2")
blas_prefix=$(realpath "$3")
jobs=${4:-4}
work=$(mktemp -d "${TMPDIR:-/tmp}/flint-native.XXXXXXXX")
echo "Build directory: $work"
archive="$package_root/sources/flint-82c40b299084b92299c2d8dac464e39d6743fce4.tar.gz"
printf '%s  %s\n' c12ad132bd392a1471b84609be67537ba078d224277ade7ec2693c968d2eca4b "$archive" | sha256sum -c -
tar -xzf "$archive" -C "$work"
cd "$work/flint-82c40b299084b92299c2d8dac464e39d6743fce4"
./bootstrap.sh
./configure --prefix="$work/install" --disable-static --enable-shared \
    --with-gmp="$gmp_prefix" --with-mpfr="$mpfr_prefix" --with-blas="$blas_prefix"
make -j"$jobs"
make install
mkdir -p "$work/install/share/licenses/FLINT"
cp COPYING COPYING.LESSER "$work/install/share/licenses/FLINT/"
echo "Installed in $work/install"
echo "Run build/package_native.jl on that prefix to replace the native bundle."
