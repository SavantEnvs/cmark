#!/usr/bin/env bash
#
# mayhem/build.sh — build cmark's libFuzzer harness (upstream's fuzz/cmark-fuzz.c, the OSS-Fuzz
# `cmark_fuzzer`) with the project instrumented, plus the project's own test suite (normal flags).
# Idempotent and offline: cmake only configures/builds from the tree, nothing is fetched.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"
mkdir -p build   # `build` is gitignored upstream, so `git clean -ffdX` removes both trees below

# 1) The library, sanitized + DWARF-3, static so the harness links it directly. The fuzzer build adds
#    libFuzzer's coverage instrumentation (-fsanitize=fuzzer-no-link) to the library itself, otherwise
#    only the harness TU is instrumented and Mayhem sees a handful of edges; the standalone
#    reproducer's library has no coverage instrumentation (it links no libFuzzer runtime).
build_lib() { # build_lib <dir> <extra flags>
  cmake -S . -B "build/$1" -G Ninja \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF \
    -DCMAKE_C_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS $2" \
    -DCMAKE_CXX_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS $2"
  cmake --build "build/$1" -j"$MAYHEM_JOBS" --target cmark
}
build_lib fuzz "-fsanitize=fuzzer-no-link"
build_lib standalone ""

# 2) The harness twice (libFuzzer + standalone reproducer), LeakSanitizer off at build time.
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o build/fuzz/lsan_off.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o build/standalone/standalone_main.o

$CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE -I"$SRC/src" -I"$SRC/build/fuzz/src" \
  "$SRC/fuzz/cmark-fuzz.c" build/fuzz/lsan_off.o "$SRC/build/fuzz/src/libcmark.a" -o /mayhem/cmark_fuzzer
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -I"$SRC/src" -I"$SRC/build/standalone/src" \
  "$SRC/fuzz/cmark-fuzz.c" build/standalone/standalone_main.o build/fuzz/lsan_off.o \
  "$SRC/build/standalone/src/libcmark.a" -o /mayhem/cmark_fuzzer-standalone

# 3) The project's own test suite with NORMAL flags (shared library so the library spec tests run too).
cmake -S . -B build/tests -G Ninja \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON -DBUILD_TESTING=ON -DSPEC_TESTS=1 \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS"
cmake --build build/tests -j"$MAYHEM_JOBS"
