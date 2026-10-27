#!/bin/bash
# Gira DENTRO il container ubuntu:26.04. Avvia il vero Wheel Wizard (Linux, release 2.4.5)
# in un display virtuale per vedere in che stato arriva il launcher (nessun clic dal
# primo passaggio). Salva solo screenshot e albero delle cartelle di config, niente ISO.
set -x
export DEBIAN_FRONTEND=noninteractive
OUT=/work/shots/ww-real; mkdir -p "$OUT"
apt-get update -qq
apt-get install -y -qq xvfb imagemagick x11-utils xdotool openbox curl ca-certificates libicu-dev libfontconfig1 libx11-6 libice6 libsm6 libgl1 dolphin-emu >/dev/null
export HOME=/work/home; mkdir -p "$HOME"
curl -fsSL -o /work/WheelWizard_Linux https://github.com/TeamWheelWizard/WheelWizard/releases/download/2.4.5/WheelWizard_Linux
chmod +x /work/WheelWizard_Linux
sha256sum /work/WheelWizard_Linux | tee "$OUT/ww-sha256.txt"
export DISPLAY=:98
Xvfb :98 -screen 0 1280x800x24 & sleep 3; openbox >/dev/null 2>&1 & sleep 2
(cd /work && timeout 120 ./WheelWizard_Linux > "$OUT/ww-stdout.log" 2>&1 &)
for t in 20 45 75 100; do sleep $((t==20?20:25)); import -window root "$OUT/ww-$t.png" 2>&1; done
find "$HOME" -maxdepth 4 | head -80 > "$OUT/ww-home-tree.txt"
cut -c1-200 "$OUT/ww-stdout.log" | head -80 > "$OUT/ww-stdout-short.log"
pkill WheelWizard || true; pkill Xvfb || true
