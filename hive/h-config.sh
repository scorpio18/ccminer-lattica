#!/usr/bin/env bash
# Lattica (LTA) — sha3d (SHA3-256d PoW, single-SHA3 merkle). Flight sheet supplies
# wallet.worker (Wallet template), and pass; extra flags via "Extra config args"
# (e.g. -i <intensity>, or solo via -p m=solo / a solo.<rig> worker).
conf=" -a sha3d -o $CUSTOM_URL -u $CUSTOM_TEMPLATE"
[[ -z $CUSTOM_PASS ]] && conf+=" -p x" || conf+=" -p $CUSTOM_PASS"
[[ ! -z $CUSTOM_USER_CONFIG ]] && conf+=" $CUSTOM_USER_CONFIG"

echo "$conf"
echo "$conf" > $CUSTOM_CONFIG_FILENAME
