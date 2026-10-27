#!/bin/bash
# Gira DENTRO il container ubuntu:26.04. Uso: run-variant.sh <nome> <secondi>
# VERO Wheel Wizard 2.6.4 (release ufficiale) con config pre-seminata: e' WW a generare RR.json e a lanciare Dolphin. Salva solo log filtrati e screenshot.
set -x
V="$1"; SECS="$2"
W=/work/$V
OUT=/work/shots/$V
mkdir -p "$OUT" "$W/user/Config"
export DEBIAN_FRONTEND=noninteractive
# Dolphin 2512 (apt) e' vulnerabile (advisory GHSA-4q28-hhjv-hf3f, corretto in 2606a): NON usato. Flatpak ufficiale da Flathub.
apt-get update -qq
apt-get install -y -qq flatpak xvfb imagemagick x11-utils xdotool procps openbox python3 tesseract-ocr mesa-vulkan-drivers libgl1-mesa-dri tcpdump dnsutils libc-bin ca-certificates >/dev/null
flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --system -y --noninteractive flathub org.DolphinEmu.dolphin-emu > "$OUT/flatpak-install.log" 2>&1 || { echo "FLATPAK_INSTALL_FALLITO" > "$OUT/ABORT-dolphin.txt"; tail -5 "$OUT/flatpak-install.log"; exit 1; }
# flatpak run (bwrap) non funziona dentro Docker senza privilegi ulteriori: uso i file del Flatpak ufficiale (runtime KDE + app) in un chroot, senza nuovi privilegi
RT=$(ls -d /var/lib/flatpak/runtime/org.kde.Platform/x86_64/*/active/files | head -1)
APPD=/var/lib/flatpak/app/org.DolphinEmu.dolphin-emu/x86_64/stable/active/files
[ -d "$RT" ] && [ -x "$APPD/bin/dolphin-emu" ] || { echo "FLATPAK_FILES_ASSENTI RT=$RT" > "$OUT/ABORT-dolphin.txt"; ls "$APPD/bin" 2>&1 | head; exit 1; }
CH=/opt/ch; mkdir -p $CH/usr $CH/app $CH/dev $CH/proc $CH/sys $CH/tmp $CH/work $CH/run $CH/var
cp -a "$RT/etc" $CH/etc 2>/dev/null || mkdir -p $CH/etc
cp /etc/resolv.conf /etc/hosts $CH/etc/ 2>/dev/null
echo 'root:x:0:0:root:/work/home:/bin/bash' > $CH/etc/passwd; echo 'root:x:0:' > $CH/etc/group
mount --bind "$RT" $CH/usr && mount --bind "$APPD" $CH/app && mount --rbind /dev $CH/dev && mount -t proc proc $CH/proc && mount --bind /tmp $CH/tmp && mount --rbind /work $CH/work
GLD=$(ls -d /var/lib/flatpak/runtime/org.freedesktop.Platform.GL.default/x86_64/*/active/files 2>/dev/null | grep -v extra | head -1)
GLX=$(ls -d /var/lib/flatpak/runtime/org.freedesktop.Platform.GL.default/x86_64/*-extra/active/files 2>/dev/null | head -1)
if [ -n "$GLD" ]; then mkdir -p $CH/usr/lib/x86_64-linux-gnu/GL/default && mount --bind "$GLD" $CH/usr/lib/x86_64-linux-gnu/GL/default; fi
if [ -n "$GLX" ]; then mkdir -p $CH/usr/lib/x86_64-linux-gnu/GL/default-extra && mount --bind "$GLX" $CH/usr/lib/x86_64-linux-gnu/GL/default-extra; fi
for l in lib lib64 bin sbin; do ln -sfn usr/$l $CH/$l; done
printf '/app/lib\n/usr/lib/x86_64-linux-gnu/GL/default/lib\n/usr/lib/x86_64-linux-gnu/GL/default-extra/lib\n/usr/lib/x86_64-linux-gnu\n' > $CH/etc/ld.so.conf
for L in /usr/sbin/ldconfig /usr/bin/ldconfig /sbin/ldconfig; do [ -x $CH$L ] && { chroot $CH $L 2>&1 | tail -2; break; }; done
{ echo "GLD=$GLD GLX=$GLX"; ls $CH/usr/lib/x86_64-linux-gnu/GL/default 2>&1 | head; ls $CH/usr/lib/x86_64-linux-gnu/GL/default/lib 2>&1 | head -12; ls $CH/usr/lib/x86_64-linux-gnu/GL/default*/vulkan/icd.d 2>&1 | head; } > "$OUT/gl-dirs.txt"
mkdir -p /usr/games
cat > /usr/games/dolphin-emu <<'WRAP'
#!/bin/bash
mkdir -p /work/home
ICD=$(ls /opt/ch/usr/lib/x86_64-linux-gnu/GL/default*/vulkan/icd.d/*lvp*.json 2>/dev/null | head -1 | sed 's#^/opt/ch##')
exec chroot /opt/ch /usr/bin/env VK_ICD_FILENAMES=$ICD VK_DRIVER_FILES=$ICD HOME=/work/home LIBGL_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/GL/default/lib/dri:/usr/lib/x86_64-linux-gnu/GL/default-extra/lib/dri XDG_DATA_DIRS=/usr/lib/x86_64-linux-gnu/GL/default/share:/usr/share DISPLAY=${DISPLAY:-:99} XDG_RUNTIME_DIR=/tmp PATH=/app/bin:/usr/bin QT_QPA_PLATFORM=xcb LIBGL_ALWAYS_SOFTWARE=1 /app/bin/dolphin-emu "$@" 2>>/tmp/dolphin-stderr.txt
WRAP
chmod +x /usr/games/dolphin-emu
flatpak info org.DolphinEmu.dolphin-emu 2>&1 | grep -E 'Version|Commit|Origin' | tee "$OUT/version.txt"
DV=$(flatpak info org.DolphinEmu.dolphin-emu | awk '/Version:/{print $2}')
if [ "$(printf '%s\n' 2606a "$DV" | sort -V | head -1)" != "2606a" ]; then echo "DOLPHIN_VULNERABILE $DV" > "$OUT/ABORT-dolphin.txt"; exit 1; fi
export PATH=$PATH:/usr/games
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
VIDEO = True
HOST_GPU = True
COMMON = True
INI
ROOT=/work/$V/Load/Riivolution/WheelWizard
# Integrity evidence: all pack files before and after WW, hashes only.
(cd "$ROOT" && find RetroRewind6 -type f -print0 | sort -z | xargs -0 sha256sum) > "$OUT/asset-manifest-before.txt"
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
# Preflight: il Dolphin Flatpak deve riuscire a partire e dichiarare la versione (stessa chiamata che usa WW), altrimenti stop prima di WW
( /usr/games/dolphin-emu --version > "$OUT/dolphin-version-check.txt" 2>&1; echo "exit=$?" >> "$OUT/dolphin-version-check.txt" )
{ bwrap --version; flatpak --version; id; cat /proc/sys/kernel/unprivileged_userns_clone 2>&1; } >> "$OUT/dolphin-version-check.txt" 2>&1
if ! grep -q 'exit=0' "$OUT/dolphin-version-check.txt"; then echo "DOLPHIN_FLATPAK_NON_ESEGUIBILE" > "$OUT/ABORT-dolphin.txt"; exit 1; fi
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
python3 - <<'DRIVER'
p='/tmp/drive.py'
s=open(p).read().replace('xdotool key F10', 'true')
a=s.index('    if action == "-":')
b=s.index('    log.write(',a)
s=s[:a]+'''    if action == "-":
        unk += 1
        if unk >= 6:
            open(f"{OUT}/ABORT-unknown-ui.txt", "w").write(txt)
            break
    else:
        unk = 0
'''+s[b:]

s=s.replace('tmpl-caption-wfc.png', 'tmpl-caption-wfc-2609.png')
s=s.replace('log = open(f"{OUT}/drive.log", "w")', '''refs=json.load(open('/work/repo/tools/ww-overlay-test/ui-fingerprints.json'))
seen_states=set()
def known_ui(p):
    raw=sh(f"convert {p} -crop 640x480+320+164 +repage -colorspace Gray -resize 32x24! -depth 8 gray:-", text=False) if False else None
    run=subprocess.run(['convert',p,'-crop','640x480+320+164','+repage','-colorspace','Gray','-resize','32x24!','-depth','8','gray:-'],capture_output=True)
    vals=list(run.stdout)
    if len(vals)!=768: return None
    scores={k:(sum((x-y)**2 for x,y in zip(vals,v))/768)**.5 for k,v in refs.items()}
    k=min(scores,key=scores.get)
    return k if scores[k]<19 else None
log = open(f"{OUT}/drive.log", "w")''')
s=s.replace('    if has("Multiplayer") and wfcclicks < 3:', '''    state=known_ui(p)
    if state and state not in seen_states:
        seen_states.add(state)
        targets={'licenses':(505,320),'new-license':(640,430),'choose-mii':(640,430),'confirm-license':(640,430),'license-ready':(640,430),'guest-notice':(640,430)}
        click(*targets[state]); action='known-state:'+state
    elif has("Multiplayer") and wfcclicks < 3:''')

open(p,'w').write(s)
DRIVER
mkdir -p "$OUT/ww"
sleep 25; import -window root "$OUT/ww/01-start.png"
xdotool mousemove 516 587; sleep 1; xdotool mousedown 1; sleep 0.4; xdotool mouseup 1; sleep 5
import -window root "$OUT/ww/02-dopo-skip.png"
# Se compare il dialogo "Dolphin out of date" NON lo aggira: esce.
convert "$OUT/ww/02-dopo-skip.png" -resize 200% /tmp/o.png; tesseract /tmp/o.png /tmp/o --psm 11 >/dev/null 2>&1
if grep -a -i -E 'out of date|known security' /tmp/o.txt; then echo "DIALOGO_DOLPHIN_OUT_OF_DATE: stop, nessun bypass" > "$OUT/ww/ABORT-out-of-date.txt"; kill $DP 2>/dev/null; exit 1; fi
for i in 1 2 3 4 5 6 7 8; do
  sleep 10; import -window root "$OUT/ww/03-t$i.png"
  if pgrep -f 'app/bin/dolphin-emu' >/dev/null 2>&1; then echo "dolphin comparso dopo $i*10 s" > "$OUT/ww/dolphin-avviato.txt"; break; fi
done
if [ -f "$OUT/ww/dolphin-avviato.txt" ]; then
  # Known telemetry dialog: reject, never enable reporting.
  for n in 1 2 3 4 5; do
    MODAL=$(xdotool search --onlyvisible --name 'Allow Usage Statistics Reporting' 2>/dev/null | head -1)
    [ -z "$MODAL" ] && break
    xdotool windowactivate --sync "$MODAL"
    xdotool mousemove 837 479 click 1
    sleep 2
    import -window root "$OUT/ww/04-telemetry-$n.png"
  done
  if xdotool search --onlyvisible --name 'Allow Usage Statistics Reporting' >/dev/null 2>&1; then
    echo 'Telemetry dialog not dismissed, stop' > "$OUT/ABORT-ui.txt"
  else
    GAME=$(xdotool search --onlyvisible --name 'Dolphin 2609a.*Mario Kart Wii' 2>/dev/null | head -1)
    if [ -n "$GAME" ]; then
      xdotool windowsize "$GAME" 640 480
      xdotool windowactivate --sync "$GAME"
      # Align client area to the known template origin, not the outer frame.
      TX=320; TY=164
      for n in 1 2 3 4; do
        xdotool windowmove --sync "$GAME" "$TX" "$TY"; sleep 1
        GX=$(xwininfo -id "$GAME" | awk '/Absolute upper-left X:/{print $4}')
        GY=$(xwininfo -id "$GAME" | awk '/Absolute upper-left Y:/{print $4}')
        [ "$GX" = 320 ] && [ "$GY" = 164 ] && break
        TX=$((TX+320-GX)); TY=$((TY+164-GY))
      done
      if [ "$GX" != 320 ] || [ "$GY" != 164 ]; then
        echo "Geometry mismatch $GX $GY" > "$OUT/ABORT-ui.txt"; exit 1
      fi
      xwininfo -id "$GAME" | grep -E 'Absolute|Width:|Height:' > "$OUT/ww/window-geometry.txt"
      import -window root "$OUT/ww/05-game-aligned.png"
      python3 /tmp/drive.py "$SECS" 2>&1 | tail -3
    else
      echo 'Game render window not found, stop' > "$OUT/ABORT-ui.txt"
    fi
  fi
else
  echo "Dolphin NON avviato da WW entro 80 s dopo Skip" > "$OUT/ww/dolphin-NON-avviato.txt"
  pgrep -a dolphin > "$OUT/ww/pgrep-dolphin.txt" 2>&1
fi
kill $DP 2>/dev/null || true
sleep 2
[ -s "$W/dolphin.log" ] || cp "$W/user/Logs/dolphin.log" "$W/dolphin.log" 2>/dev/null
tail -40 /tmp/dolphin-stderr.txt 2>/dev/null | cut -c1-200 > "$OUT/dolphin-stderr.txt"
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
