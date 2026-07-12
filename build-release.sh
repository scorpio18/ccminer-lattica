#!/usr/bin/env bash
# Reproducible portable release build for ccminer-csd.
#
# Builds inside CUDA 12.8 + Ubuntu 20.04 with STATIC cudart, producing a binary
# that:
#   - runs on any NVIDIA driver for CUDA 12.8+ AND 13.x (12.8 baseline, forward
#     driver compatibility), needing only the driver on the rig (no toolkit),
#   - needs glibc >= 2.31 (Ubuntu 20.04, which is what HiveOS Linux is based on,
#     plus Debian 11+, RHEL/Rocky 8+, and everything newer),
#   - targets RTX 3000 (sm_86), 4000 (sm_89), 5000 (sm_120).
# Requires only Docker on the build host (no GPU needed to compile).
#
# HiveOS note: HiveOS is Ubuntu 20.04 based (glibc 2.31); a 22.04 build (glibc
# 2.34) fails to launch there with "GLIBC_2.34 not found". Build on 20.04.
set -e
IMAGE="${IMAGE:-nvidia/cuda:12.8.1-devel-ubuntu20.04}"
OUT="${OUT:-ccminer-cuda12.8-ubuntu20}"
docker run --rm -v "$PWD":/src "$IMAGE" bash -c '
  set -e; export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null
  apt-get install -y -qq build-essential automake autoconf libtool pkg-config \
    libcurl4-openssl-dev libssl-dev libjansson-dev >/dev/null
  cp -a /src /build && cd /build
  # Drop any stale committed objects: the repo ships .o built on a newer
  # glibc/gcc (__isoc23_sscanf, __throw_bad_array_new_length) that will NOT
  # link against Ubuntu 20.04. Force a clean recompile in this image.
  find . -name "*.o" -delete; find . -name "*.Po" -delete 2>/dev/null || true
  ./autogen.sh >/dev/null 2>&1
  ./configure --with-cuda=/usr/local/cuda --with-nvml=/usr/lib >/dev/null
  make -j"$(nproc)"
  cp /build/ccminer /src/'"$OUT"'
'
echo "built: $OUT"
file "$OUT" | cut -d, -f1-2
echo "cudart static: $(ldd "$OUT" | grep -qi cudart && echo NO || echo YES)"
echo "arches: $(cuobjdump "$OUT" 2>/dev/null | grep -oE 'sm_[0-9]+' | sort -u | tr '\n' ' ')"
