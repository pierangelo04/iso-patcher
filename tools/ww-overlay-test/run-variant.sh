#!/bin/bash
# Gira DENTRO il container ubuntu:26.04. Uso: run-variant.sh <nome> <secondi>
# Avvia Dolphin con un RR.json identico a quello che genera Wheel Wizard (replica,
# NON il launcher WW), con la base ufficiale. Salva solo log filtrati e screenshot.
set -x
V="$1"; SECS="$2"
W=/work/$V
OUT=/work/shots/$V
mkdir -p "$OUT" "$W/user/Config"
export DEBIAN_FRONTEND=noninteractive
if ! command -v dolphin-emu >/dev/null; then
  apt-get update -qq
  apt-get install -y -qq dolphin-emu xvfb imagemagick x11-utils xdotool procps openbox python3 tesseract-ocr mesa-vulkan-drivers libgl1-mesa-dri tcpdump dnsutils libc-bin >/dev/null
fi
export PATH=$PATH:/usr/games
dolphin-emu --version 2>&1 | head -2 | tee "$OUT/version.txt"
cat > "$W/user/Config/Dolphin.ini" <<'INI'
[Core]
GFXBackend = Vulkan
CPUCore = 1
DSPHLE = True
EmulationSpeed = 1.0
SkipIPL = True
[DSP]
Backend = No Audio Output
[Interface]
ConfirmStop = False
INI
cat > "$W/user/Config/Logger.ini" <<'INI'
[Options]
WriteToFile = True
Verbosity = 5
WriteToConsole = True
[Logs]
OSREPORT = True
BOOT = True
IOS_NET = True
IOS_SSL = True
IOS_WC24 = True
COMMON = True
INI
ROOT=/work/$V/Load/Riivolution/WheelWizard
cat > "$W/RR.json" <<JSON
{
  "base-file": "/work/base.iso",
  "display-name": "RR",
  "riivolution": {
    "patches": [
      {
        "options": [
          {"choice": 1, "option-name": "Pack", "section-name": "Retro Rewind"},
          {"choice": 0, "option-name": "My Stuff", "section-name": "Retro Rewind"}
        ],
        "root": "$ROOT",
        "xml": "$ROOT/riivolution/RetroRewind6.xml"
      }
    ]
  },
  "type": "dolphin-game-mod-descriptor",
  "version": 1
}
JSON
# Dolphin cerca Load/ nella user dir: usa symlink verso la cartella della variante
ln -sfn "$W/Load" "$W/user/Load"
export LIBGL_ALWAYS_SOFTWARE=1 QT_QPA_PLATFORM=xcb DISPLAY=:99
Xvfb :99 -screen 0 1280x800x24 &
sleep 3; openbox >/dev/null 2>&1 & sleep 2
for h in q7x.duckdns.org nas.q7x.duckdns.org gpcm.q7x.duckdns.org nas.wiimmfi.de nas.rwfc.net; do echo "DNS $h: $(getent hosts $h | head -1)"; done | tee "$OUT/dns.txt"
(timeout $((SECS+120)) tcpdump -l -nn -i any "port 53 or host 95.135.208.187" > "$W/net.txt" 2>&1 &)
dolphin-emu -u "$W/user" -b -v Vulkan -e "$W/RR.json" --config=Dolphin.Core.EnableCheats=False --config=Achievements.Achievements.Enabled=False > "$W/dolphin.log" 2>&1 &
DP=$!
# Controllo precoce: dopo 75s, se compare un dialogo di errore (file mancante ecc.) o non c'e' processo, esci subito.
( sleep 75; import -window root "$OUT/early.png"; convert "$OUT/early.png" -resize 200% /tmp/e.png; tesseract /tmp/e.png /tmp/e --psm 11 >/dev/null 2>&1; cp /tmp/e.txt "$OUT/early-ocr.txt" 2>/dev/null
  if grep -a -i -E 'does not exist|Warning|Error|Critical' /tmp/e.txt; then echo ABORT_EARLY > "$OUT/ABORT.txt"; pkill -f drive.py; kill $DP 2>/dev/null; fi ) &
sed -e "s#/work/shots#$OUT#" -e 's#search --name RMCPTO#search --name Mario#' /work/repo/tools/dolphin/drive.py > /tmp/drive.py
python3 /tmp/drive.py "$SECS" 2>&1 | tail -3
kill $DP 2>/dev/null || true
sleep 2
# Log filtrati (nessun percorso privato, nessun contenuto del disco)
grep -a -i -E 'riivolution|patch|descriptor|wfc|rwfc|q7x|duckdns|dns|IOS_NET|SSL|NHTTP|nas\.|gpcm|error|failed|version' "$W/dolphin.log" | cut -c1-220 | head -250 > "$OUT/dolphin-filtered.log"
wc -l "$W/dolphin.log" > "$OUT/dolphin-lines.txt"
grep -a -E 'q7x|rwfc|wiimmfi|95\.135\.208\.187|\.duckdns' "$W/net.txt" | awk '{print $1, $2, $3, $4, $5, $6, $7, $8}' | head -80 > "$OUT/net-filtered.txt"
grep -a -c . "$W/net.txt" > "$OUT/net-lines.txt"
# Cosa ha caricato Dolphin: nome del file Code.pul effettivamente letto non e' visibile; segnala presenza strutture
ls -la "$ROOT/riivolution" "$ROOT/RetroRewind6/Binaries" > "$OUT/tree-binaries.txt" 2>&1
sha256sum "$ROOT/riivolution/RetroRewind6.xml" "$ROOT/RetroRewind6/Binaries/"Code.pul* > "$OUT/hashes.txt" 2>&1
pkill Xvfb || true
