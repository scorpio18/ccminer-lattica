#!/usr/bin/env bash
# Build the HiveOS custom-miner package for ccminer-lattica.
# Layout HiveOS expects: a tarball whose top dir == CUSTOM_NAME, containing the
# `ccminer` binary + h-manifest.conf / h-config.sh / h-run.sh / h-stats.sh.
# Uses the portable static binary from build-release.sh.
set -e
NAME=ccminer-lattica
VER=$(grep -oP 'CUSTOM_VERSION=\K.*' hive/h-manifest.conf)
BIN="${BIN:-ccminer-cuda12.8-ubuntu20}"
[[ -f $BIN ]] || { echo "missing $BIN — run ./build-release.sh first"; exit 1; }

rm -rf /tmp/hivepkg && mkdir -p "/tmp/hivepkg/$NAME"
install -m755 "$BIN" "/tmp/hivepkg/$NAME/ccminer"
install -m755 hive/h-config.sh hive/h-run.sh hive/h-stats.sh "/tmp/hivepkg/$NAME/"
install -m644 hive/h-manifest.conf "/tmp/hivepkg/$NAME/"

# Bundle runtime libs HiveOS's minimal userland may lack (OpenSSL 1.1 + jansson),
# so ./ccminer never dies with "libcrypto.so.1.1: cannot open shared object file".
# h-run.sh prepends this lib/ dir to LD_LIBRARY_PATH. Pulled from the SAME image
# the binary was built in, so the ABI matches. libcurl stays a host dep (HiveOS's
# own ccminer uses it, so it's always present).
IMAGE="${IMAGE:-nvidia/cuda:12.8.1-devel-ubuntu20.04}"
mkdir -p "/tmp/hivepkg/$NAME/lib"
docker run --rm -v "/tmp/hivepkg/$NAME/lib":/out "$IMAGE" bash -c '
  set -e; export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null
  apt-get install -y -qq libssl1.1 libjansson4 >/dev/null 2>&1
  for f in libcrypto.so.1.1 libssl.so.1.1 libjansson.so.4; do
    cp -L "$(find /usr/lib /lib -name "$f" 2>/dev/null | head -1)" /out/
  done
  chmod 644 /out/*
'

OUT="$PWD/${NAME}-${VER}.tar.gz"
tar -czf "$OUT" -C /tmp/hivepkg "$NAME"
echo "built: $OUT"
tar -tzf "$OUT"
echo "size: $(du -h "$OUT" | cut -f1)"
