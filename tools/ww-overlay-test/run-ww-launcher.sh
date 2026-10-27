#!/bin/bash
# Gira DENTRO il container ubuntu:26.04. Uso: run-variant.sh <nome> <secondi>
# VERO Wheel Wizard 2.6.4 (release ufficiale) con config pre-seminata: e' WW a generare RR.json e a lanciare Dolphin. Salva solo log filtrati e screenshot.
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
# Config di Wheel Wizard pre-seminata (percorsi) e avvio automatico di RR all'avvio
mkdir -p /work/run/CT-MKWII
cat > /work/run/CT-MKWII/config.json <<CFG
{
  "DolphinLocation": "/usr/games/dolphin-emu",
  "UserFolderPath": "$W/user",
  "GameLocation": "/work/base.iso",
  "LaunchWithDolphin": false,
  "LaunchRrOnStartup": true,
  "ForceWiimote": false
}
CFG
# Dolphin cerca Load/ nella user dir: usa symlink verso la cartella della variante
ln -sfn "$W/Load" "$W/user/Load"
export LIBGL_ALWAYS_SOFTWARE=1 QT_QPA_PLATFORM=xcb DISPLAY=:99
Xvfb :99 -screen 0 1280x800x24 &
sleep 3; openbox >/dev/null 2>&1 & sleep 2
for h in q7x.duckdns.org nas.q7x.duckdns.org gpcm.q7x.duckdns.org nas.wiimmfi.de nas.rwfc.net; do echo "DNS $h: $(getent hosts $h | head -1)"; done | tee "$OUT/dns.txt"
(timeout $((SECS+120)) tcpdump -l -nn -i any "port 53 or host 95.135.208.187" > "$W/net.txt" 2>&1 &)
# Tutte le nuove connessioni TCP (SYN) e tutto il DNS, senza payload
(timeout $((SECS+120)) tcpdump -l -nn -i any "udp port 53 or (tcp[tcpflags] & tcp-syn != 0)" > "$W/syn.txt" 2>&1 &)
# Solo riga di richiesta/stato HTTP e Host sulla porta 80 (nessun corpo, nessun cookie)
(timeout $((SECS+120)) tcpdump -l -nn -i any -A -s 900 "tcp port 80" 2>/dev/null | grep -a -E '^(GET|POST|HEAD) |^HTTP/1|^Host:' | cut -c1-90 > "$W/http.txt" &)
export HOME=/work/home; mkdir -p "$HOME"
apt-get install -y -qq curl ca-certificates libicu-dev libfontconfig1 libx11-6 libice6 libsm6 libgl1 jq >/dev/null
curl -fsSL -o /work/run/WheelWizard_Linux https://github.com/TeamWheelWizard/WheelWizard/releases/download/v2.6.4/WheelWizard_Linux && chmod +x /work/run/WheelWizard_Linux
sha256sum /work/run/WheelWizard_Linux | cut -c1-64 > "$OUT/ww-sha256.txt"
export AVALONIA_GLOBAL_SCALE_FACTOR=1
(cd /work/run && ./WheelWizard_Linux > "$OUT/ww-stdout.log" 2>&1) &
DP=$!
# Controllo precoce: dopo 75s, se compare un dialogo di errore (file mancante ecc.) o non c'e' processo, esci subito.
( sleep 75; import -window root "$OUT/early.png"; convert "$OUT/early.png" -resize 200% /tmp/e.png; tesseract /tmp/e.png /tmp/e --psm 11 >/dev/null 2>&1; cp /tmp/e.txt "$OUT/early-ocr.txt" 2>/dev/null
  if grep -a -i -E 'does not exist|Critical' /tmp/e.txt; then echo ABORT_EARLY > "$OUT/ABORT.txt"; pkill -f drive.py; kill $DP 2>/dev/null; fi ) &
sed -e "s#/work/shots#$OUT#" -e 's#search --name RMCPTO#search --name Mario#' /work/repo/tools/dolphin/drive.py > /tmp/drive.py
# Fase WW: dialogo "Mii Rendering Setup" (Skip a ~516,587 in 2.6.4), poi Home; screenshot a intervalli, nessun clic alla cieca
mkdir -p "$OUT/ww"
sleep 25; import -window root "$OUT/ww/01-start.png"
xdotool mousemove 516 587; sleep 1; xdotool mousedown 1; sleep 0.4; xdotool mouseup 1; sleep 5
import -window root "$OUT/ww/02-dopo-skip.png"
for i in 1 2 3 4 5 6 7 8; do
  sleep 10; import -window root "$OUT/ww/03-t$i.png"
  if xdotool search --name Mario >/dev/null 2>&1; then echo "dolphin comparso dopo $i*10 s" > "$OUT/ww/dolphin-avviato.txt"; break; fi
done
if [ -f "$OUT/ww/dolphin-avviato.txt" ]; then
  python3 /tmp/drive.py "$SECS" 2>&1 | tail -3
else
  echo "Dolphin NON avviato da WW entro 80 s dopo Skip" > "$OUT/ww/dolphin-NON-avviato.txt"
  pgrep -a dolphin > "$OUT/ww/pgrep-dolphin.txt" 2>&1
fi
kill $DP 2>/dev/null || true
sleep 2
# Log filtrati (nessun percorso privato, nessun contenuto del disco)
grep -a -i -E 'riivolution|patch|descriptor|wfc|rwfc|q7x|duckdns|dns|IOS_NET|SSL|NHTTP|nas\.|gpcm|error|failed|version' "$W/dolphin.log" | cut -c1-220 | head -250 > "$OUT/dolphin-filtered.log"
wc -l "$W/dolphin.log" > "$OUT/dolphin-lines.txt"
grep -a -E 'q7x|rwfc|wiimmfi|95\.135\.208\.187|\.duckdns' "$W/net.txt" | awk '{print $1, $2, $3, $4, $5, $6, $7, $8}' | head -80 > "$OUT/net-filtered.txt"
grep -a -c . "$W/net.txt" > "$OUT/net-lines.txt"
grep -a -v -E '^\s*$' "$W/syn.txt" | grep -a -E 'Flags \[S\]|\[S\.\]|A\?|A [0-9]|CNAME' | grep -a -v -E ' > 172\.17\.0\.2\.[0-9]+: [0-9]+ [0-9]' | cut -c1-200 | head -300 > "$OUT/syn-dns.txt"
sed -E 's#(POST|GET) (/[^ ?]{0,60})[^ ]*#\1 \2#' "$W/http.txt" | sort | uniq -c | sort -rn | head -60 > "$OUT/http-summary.txt"
grep -a -o -E 'IOCTL_SO_GETHOSTBYNAME Address: [^,]+|IOCTL_SO_CONNECT \([0-9a-f]+, [0-9.:]+\) = [-0-9]+' "$W/dolphin.log" | sort | uniq -c | sort -rn | head -80 > "$OUT/sockets-all.txt"
find "$W/user/Config" -name "WiimoteNew.ini" -exec grep -a -E "^\[Wiimote1\]|Source|^Buttons/A|^D-Pad|^IR/|Extension" {} \; > "$OUT/wiimote-profile.txt" 2>&1
# Cosa ha caricato Dolphin: nome del file Code.pul effettivamente letto non e' visibile; segnala presenza strutture
ls -la "$ROOT/riivolution" "$ROOT/RetroRewind6/Binaries" > "$OUT/tree-binaries.txt" 2>&1
sha256sum "$ROOT/riivolution/RetroRewind6.xml" "$ROOT/RetroRewind6/Binaries/"Code.pul* > "$OUT/hashes.txt" 2>&1
find /work/run "$W/user" /work/home -name 'RR.json' 2>/dev/null | head -3 > "$OUT/rrjson-path.txt"
for f in $(find /work/run/CT-MKWII "$W/user" "$W/Load" -name 'RR.json' 2>/dev/null | head -1); do jq -c 'del(.["base-file"])' "$f" 2>/dev/null > "$OUT/rrjson-generato-da-WW.json" || cat "$f" | sed 's#"base-file".*##' > "$OUT/rrjson-generato-da-WW.json"; done
cut -c1-200 /work/run/CT-MKWII/logs/*.txt 2>/dev/null | tail -60 > "$OUT/ww-log.txt"
pkill WheelWizard || true; pkill Xvfb || true
