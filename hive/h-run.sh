#!/usr/bin/env bash
# ccminer-lattica (Compute Substrate / sha256d-csd) HiveOS runner.
# Based on HiveOS's stock ccminer h-run.sh, but with a *targeted* single-instance
# guard: we clean up only a stale instance of THIS miner (matched by its API
# port) instead of the stock `ps aux | grep ./ccminer` + `exit 1`, which matched
# any ccminer on the rig and wedged HiveOS into an "already running" restart loop.

cd "$(dirname "$0")"
. h-manifest.conf

# Kill only a stale instance of *this* miner, matched by its unique API port, so
# a leftover process can't block startup. Keep the kill on its own line (never in
# a compound with pkill -f).
if pgrep -f "ccminer -b 127.0.0.1:${MINER_API_PORT}" >/dev/null 2>&1; then
	pkill -f "ccminer -b 127.0.0.1:${MINER_API_PORT}"
	sleep 3
fi

# Best-effort release of TIME_WAIT sockets on the API port (tools may be absent).
if command -v killcx >/dev/null 2>&1 && command -v netstat >/dev/null 2>&1; then
	while true; do
		for con in $(netstat -anp 2>/dev/null | grep TIME_WAIT | grep "$MINER_API_PORT" | awk '{print $5}'); do
			killcx "$con" lo
		done
		netstat -anp 2>/dev/null | grep TIME_WAIT | grep "$MINER_API_PORT" >/dev/null && continue || break
	done
fi

CUSTOM_LOG_BASEDIR="$(dirname "$CUSTOM_LOG_BASENAME")"
[[ ! -d $CUSTOM_LOG_BASEDIR ]] && mkdir -p "$CUSTOM_LOG_BASEDIR"

# Prefer libraries bundled with this package (OpenSSL 1.1 + jansson, which
# HiveOS's minimal userland may not ship) so ./ccminer can't fail with
# "libcrypto.so.1.1: cannot open shared object file". $(pwd) is the miner dir
# (we cd'd to it above).
export LD_LIBRARY_PATH="$(pwd)/lib:$LD_LIBRARY_PATH:/hive/lib"
./ccminer -b 127.0.0.1:$MINER_API_PORT $(< "$CUSTOM_CONFIG_FILENAME") 2>&1 | tee --append "${CUSTOM_LOG_BASENAME}.log"
