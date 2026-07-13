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

# No bundled libs since 1.1: OpenSSL + jansson are linked STATICALLY into the
# binary (see build-release.sh), so ./ccminer runs directly on any host — only
# libcurl (ubiquitous, incl. HiveOS) and glibc >= 2.31 are needed.

OUT="$PWD/${NAME}-${VER}.tar.gz"
tar -czf "$OUT" -C /tmp/hivepkg "$NAME"
echo "built: $OUT"
tar -tzf "$OUT"
echo "size: $(du -h "$OUT" | cut -f1)"
