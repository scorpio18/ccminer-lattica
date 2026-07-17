#!/usr/bin/env bash
# Build a self-contained generic-Linux package for ccminer-lattica.
# The tarball contains: the ccminer binary (static cudart + static OpenSSL +
# static jansson since 1.1 — runs directly, no LD_LIBRARY_PATH), a run wrapper,
# and a README. A miner needs ONLY an NVIDIA GPU driver (CUDA 12.8+) and the
# ubiquitous libcurl — no toolkit, no apt installs.
set -e
NAME=ccminer-lattica
VER=$(grep -oP 'CUSTOM_VERSION=\K.*' hive/h-manifest.conf)
BIN="${BIN:-ccminer-cuda12.8-ubuntu20}"
IMAGE="${IMAGE:-nvidia/cuda:12.8.1-devel-ubuntu20.04}"
[[ -f $BIN ]] || { echo "missing $BIN — run ./build-release.sh first"; exit 1; }

PKG=/tmp/ltapkg/$NAME
rm -rf /tmp/ltapkg && mkdir -p "$PKG"
install -m755 "$BIN" "$PKG/ccminer"

cat > "$PKG/run.sh" <<'RUN'
#!/usr/bin/env bash
# ccminer-lattica launcher. Edit WALLET (and REGION) then: ./run.sh
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
WALLET="${WALLET:-lta1qYOUR_WALLET_ADDRESS}"
REGION="${REGION:-eu}"          # eu | us | na | sg | ru | vn
POOL="${POOL:-stratum+tcp://${REGION}.coin-miners.info:8590}"
exec ./ccminer -a sha3d -o "$POOL" -u "$WALLET" -p x "$@"
RUN
chmod +x "$PKG/run.sh"

cat > "$PKG/README.txt" <<README
ccminer-lattica ${VER} — GPU miner for Lattica (LTA), algo sha3d.

Requirements: an NVIDIA GPU (RTX 2000/3000/4000/5000 — sm_75/86/89/120) and a recent
driver (CUDA 12.8+). Nothing else to install — OpenSSL/jansson are linked in;
./ccminer runs directly.

Run:
  WALLET=lta1q<your address> ./run.sh
or directly:
  ./ccminer -a sha3d -o stratum+tcp://eu.coin-miners.info:8590 \\
    -u lta1q<your address> -p x

Pools: eu / us / na / sg / ru / vn . coin-miners.info : 8590
README

OUT="$PWD/${NAME}-linux-${VER}.tar.gz"
tar -czf "$OUT" -C /tmp/ltapkg "$NAME"
echo "built: $OUT ($(du -h "$OUT" | cut -f1))"
tar -tzf "$OUT"
