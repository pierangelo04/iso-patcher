#!/bin/bash
# DENTRO ubuntu:26.04: solo diagnostica Dolphin (versione, supporto -e descrittore JSON)
export DEBIAN_FRONTEND=noninteractive
OUT=/work/shots/diag; mkdir -p "$OUT"
apt-get update -qq; apt-get install -y -qq dolphin-emu xvfb >/dev/null
export PATH=$PATH:/usr/games QT_QPA_PLATFORM=offscreen
{ apt-cache policy dolphin-emu | head -4; which dolphin-emu dolphin-emu-nogui; ls /usr/games; dolphin-emu --version 2>&1 | tail -3; dolphin-emu-nogui --version 2>&1 | tail -3; } > "$OUT/dolphin-diag.txt" 2>&1
strings $(which dolphin-emu) 2>/dev/null | grep -i -E 'dolphin-game-mod-descriptor|riivolution' | head -8 >> "$OUT/dolphin-diag.txt"
echo '{"baseFile":"/nonexistent.iso","displayName":"x","riivolution":{"patches":[]},"type":"dolphin-game-mod-descriptor","version":1}' > /tmp/t.json
Xvfb :99 -screen 0 640x480x24 & sleep 2; export DISPLAY=:99 QT_QPA_PLATFORM=xcb
timeout 20 dolphin-emu -u /tmp/u -b -e /tmp/t.json >> "$OUT/dolphin-diag.txt" 2>&1; echo "exit=$?" >> "$OUT/dolphin-diag.txt"
