#!/usr/bin/env python3
"""Pilota Dolphin in un display virtuale: legge lo schermo con OCR e clicca."""
import subprocess, time, sys, os, re, json
SECS = int(sys.argv[1]) if len(sys.argv) > 1 else 600
OUT = "/work/shots"
X0, Y0, W, H = 320, 164, 640, 484
def sh(cmd, **kw):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True, **kw).stdout
def wid():
    return sh("xdotool search --name RMCPTO | head -1").strip()
def click(x, y):
    w = wid()
    if w: sh(f"xdotool windowfocus {w}")
    sh(f"xdotool mousemove {x} {y}"); time.sleep(0.4)
    sh("xdotool mousedown 1"); time.sleep(0.5); sh("xdotool mouseup 1")
def shot(n):
    p = f"{OUT}/s-{n:03d}.png"
    sh(f"import -window root {p}")
    return p
def ocr(p):
    sh(f"convert {p} -crop {W}x{H}+{X0}+{Y0} +repage -resize 200% /tmp/c.png")
    tsv = sh("tesseract /tmp/c.png /tmp/o --psm 11 tsv 2>/dev/null; cat /tmp/o.tsv")
    words = []
    for line in tsv.splitlines()[1:]:
        f = line.split("\t")
        if len(f) < 12 or not f[11].strip(): continue
        try: words.append((f[11].strip(), X0 + int(f[6]) / 2 + int(f[8]) / 4, Y0 + int(f[7]) / 2 + int(f[9]) / 4, float(f[10])))
        except ValueError: pass
    return words
def find(words, w):
    for t, x, y, c in words:
        if t.lower().strip(".,!?") == w.lower(): return int(x), int(y)
    return None
def tmatch(p):
    sh(f"convert {p} -crop 400x110+440+425 +repage /tmp/x.png")
    o = sh("compare -metric RMSE /tmp/x.png /work/repo/tools/ww-overlay-test/tmpl-consenso.png null: 2>&1")
    try: return float(o.split()[0]) < 10000
    except Exception: return False
log = open(f"{OUT}/drive.log", "w")
time.sleep(40)
w = wid(); sh(f"xdotool windowfocus {w}; xdotool key F10")   # parte in pausa
t0 = time.time(); n = 0; last = ""; mainclicks = 0; wfcclicks = 0; permits = 0; unk = 0; online = False
while time.time() - t0 < SECS:
    n += 1
    p = shot(n)
    words = ocr(p)
    txt = " ".join(t for t, *_ in words)
    action = "-"
    def has(s): return s.lower() in txt.lower()
    if has("Multiplayer") and wfcclicks < 3:
        wfcclicks += 1; online = True
        POS = [(600,480),(600,480),(600,482)]
        x, y = POS[(wfcclicks-1) % len(POS)]
        if SECS <= 200:   # PREFLIGHT: solo frecce + frame di evidenziazione, nessun A
            f = open(f"{OUT}/focus.txt", "a")
            f.write("focus: " + sh("xdotool getwindowfocus getwindowname") + "\n")
            shot(300+n)
            for i, k in enumerate(["Down", "Right", "Left", "Up", "Down"]):
                sh(f"xdotool key --delay 200 {k}"); time.sleep(4); shot(310+i)
                f.write(f"dopo {k}: shot s-{310+i}\n"); f.flush()
            action = "PREFLIGHT frecce"; wfcclicks = 3
            log.write(json.dumps({"n": n, "t": int(time.time() - t0), "action": action, "text": ""}) + "\n"); log.flush()
            break
        KEYS = ["Down"]
        for k in KEYS:
            sh(f"xdotool key {k}"); time.sleep(3)
        shot(400+n)
        sh("xdotool mousedown 1"); time.sleep(1.5); sh("xdotool mouseup 1"); time.sleep(2); shot(500+n); time.sleep(6); shot(600+n); action = f"click Retro WFC {x},{y}"
    elif (has("Prohibit") or tmatch(p)) and permits < 3:
        permits += 1
        sh("xdotool key Up"); time.sleep(3); shot(700+n)
        sh("xdotool mousedown 1"); time.sleep(1.5); sh("xdotool mouseup 1"); time.sleep(3); shot(800+n); time.sleep(5); shot(900+n)
        action = f"Permit via Up + A (tentativo {permits})"
    elif has("Main Menu") and find(words, "WFC"):
        x, y = find(words, "WFC"); click(x, y); action = f"click WFC {x},{y}"
    elif has("sure") and has("OK"):
        yy = find(words, "Yes")
        x, y = yy if yy else (640, 440)
        click(x, y); action = f"click Yes {x},{y}"
    elif find(words, "Next"):
        x, y = find(words, "Next"); click(x, y); action = f"click Next {x},{y}"
    elif find(words, "OK") and not has("Time Trial"):
        x, y = find(words, "OK"); click(x, y); action = f"click OK {x},{y}"
    elif online and wfcclicks < 3 and has("Grand Prix") and has("Back"):
        click(415, 548); time.sleep(6); action = "Back da Single Player, riprova WFC"
    elif online and not (has("sure") or has("Yes") or has("agree") or has("Agree")):
        action = "wait online"
    elif has("Settings") and has("Back") and mainclicks < 6:
        mainclicks += 1
        click(505, 320); action = "click slot licenza 1 (RR)"
    elif has("Press") and has("Button"):
        click(640, 400); action = "click title"
    elif has("Licence") or has("licence"):
        click(640, 400); action = "click licence"
    elif has("Single Player") and not has("Main Menu"):
        yy = find(words, "Back")
        if yy: click(*yy); action = "click Back (percorso sbagliato)"
    if permits >= 3 and tmatch(p):
        stuck = globals().get("stuck", 0) + 1; globals()["stuck"] = stuck
        if stuck >= 3:
            open(f"{OUT}/STUCK.txt", "w").write("ancora sulla domanda Permit/Prohibit dopo 3 tentativi\n")
            log.write(json.dumps({"n": n, "t": int(time.time() - t0), "action": "STUCK stop", "text": ""}) + "\n"); log.flush()
            break
    if action == "-":
        unk += 1
        if unk == 3:
            click(505, 320); action = "fallback: slot licenza 1"
        elif unk > 3 and unk % 3 == 0:
            click(640, 430); action = "fallback: click OK/centro"
    else:
        unk = 0
    log.write(json.dumps({"n": n, "t": int(time.time() - t0), "action": action, "text": txt[:300]}) + "\n"); log.flush()
    time.sleep(4)
