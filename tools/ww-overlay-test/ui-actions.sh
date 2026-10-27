#!/bin/bash
# DENTRO ubuntu:26.04: avvia il vero WheelWizard_Linux 2.4.5 e esegue clic/screenshot.
export DEBIAN_FRONTEND=noninteractive
OUT=/work/shots/ui; mkdir -p "$OUT"
apt-get update -qq
apt-get install -y -qq xvfb imagemagick x11-utils xdotool openbox curl ca-certificates libicu-dev libfontconfig1 libx11-6 libx11-dev libice6 libsm6 libgl1 dolphin-emu >/dev/null
export HOME=/work/home; mkdir -p "$HOME" /work/run
curl -fsSL -o /work/run/WheelWizard_Linux https://github.com/TeamWheelWizard/WheelWizard/releases/download/2.4.5/WheelWizard_Linux
chmod +x /work/run/WheelWizard_Linux
export DISPLAY=:98 AVALONIA_GLOBAL_SCALE_FACTOR=1
Xvfb :98 -screen 0 1280x800x24 & sleep 3; openbox >/dev/null 2>&1 & sleep 2
(cd /work/run && ./WheelWizard_Linux > "$OUT/ww-stdout.log" 2>&1 &)
shot(){ import -window root "$OUT/$1.png"; }
click(){ xdotool mousemove $1 $2; sleep 0.4; xdotool click 1; sleep ${3:-3}; }
sleep 20; shot 01-start
click 637 596 6; shot 02-after-skip
sleep 10; shot 03-wait
find /work/home /work/run /work/CT-MKWII -maxdepth 3 -not -path '*/.net/*' 2>/dev/null | head -60 > "$OUT/tree.txt"
cut -c1-220 "$OUT/ww-stdout.log" | grep -a -v 'cannot open shared' | tail -40 > "$OUT/ww-log-tail.txt"
pkill WheelWizard; pkill Xvfb
