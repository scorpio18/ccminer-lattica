#!/usr/bin/env bash
# Build a self-contained generic-Linux package for ccminer-lattica.
# The tarball contains: the static-cudart ccminer binary, bundled OpenSSL 1.1 +
# jansson libs, a run wrapper that sets LD_LIBRARY_PATH, and a README. A miner
# needs ONLY an NVIDIA GPU driver (CUDA 12.8+) — no toolkit, no apt installs.
set -e
NAME=ccminer-lattica
VER=$(grep -oP 'CUSTOM_VERSION=\K.*' hive/h-manifest.conf)
BIN="${BIN:-ccminer-cuda12.8-ubuntu20}"
IMAGE="${IMAGE:-nvidia/cuda:12.8.1-devel-ubuntu20.04}"
[[ -f $BIN ]] || { echo "missing $BIN — run ./build-release.sh first"; exit 1; }

PKG=/tmp/ltapkg/$NAME
rm -rf /tmp/ltapkg && mkdir -p "$PKG/lib"
install -m755 "$BIN" "$PKG/ccminer"

# Bundle ONLY OpenSSL 1.1 + jansson (pulled from the SAME image the binary was
# built in, so the ABI matches). We deliberately do NOT bundle libcurl: the
# 20.04 libcurl.so.4 has a DT_NEEDED on libldap_r-2.4/libsasl2 etc. that modern
# distros (and this build host) lack, so the bundled copy fails to load. libcurl4
# is present on effectively every miner host (incl. HiveOS), so use the host's —
# only OpenSSL 1.1 is genuinely missing on modern (OpenSSL 3) distros. Same
# choice CSD's HiveOS package makes.
docker run --rm -v "$PKG/lib":/out "$IMAGE" bash -c '
  set -e; export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null
  apt-get install -y -qq libssl1.1 libjansson4 >/dev/null 2>&1
  for f in libcrypto.so.1.1 libssl.so.1.1 libjansson.so.4; do
    cp -L "$(find /usr/lib /lib -name "$f" 2>/dev/null | head -1)" /out/ 2>/dev/null || true
  done
  chmod 644 /out/* '

cat > "$PKG/run.sh" <<'RUN'
#!/usr/bin/env bash
# ccminer-lattica launcher. Edit WALLET (and REGION) then: ./run.sh
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
WALLET="${WALLET:-lta1qYOUR_WALLET_ADDRESS}"
REGION="${REGION:-eu}"          # eu | us | na | sg | ru
POOL="${POOL:-stratum+tcp://${REGION}.coin-miners.info:4444}"
export LD_LIBRARY_PATH="$(pwd)/lib:$LD_LIBRARY_PATH"
exec ./ccminer -a sha3d -o "$POOL" -u "$WALLET" -p x "$@"
RUN
chmod +x "$PKG/run.sh"

cat > "$PKG/README.txt" <<README
ccminer-lattica ${VER} — GPU miner for Lattica (LTA), algo sha3d.

Requirements: an NVIDIA GPU (RTX 3000/4000/5000 — sm_86/89/120) and a recent
driver (CUDA 12.8+). Nothing else to install — libs are bundled.

Run:
  WALLET=lta1q<your address> ./run.sh
or directly:
  LD_LIBRARY_PATH=./lib ./ccminer -a sha3d \\
    -o stratum+tcp://eu.coin-miners.info:4444 -u lta1q<your address> -p x

Pools: eu / us / na / sg / ru . coin-miners.info : 4444
README

OUT="$PWD/${NAME}-linux-${VER}.tar.gz"
tar -czf "$OUT" -C /tmp/ltapkg "$NAME"
echo "built: $OUT ($(du -h "$OUT" | cut -f1))"
tar -tzf "$OUT"
