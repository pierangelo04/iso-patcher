# iso-patcher
Kote's ISO patcher for Retro Rewind
This will allows the user to patch Mario Kart Wii game back up to add the mod-pack "Retro Rewind" for use on USB Loader or Dolphin emulator.

## Build automatica (GitHub Actions)

Il workflow `.github/workflows/build-retro-rewind.yml` compila ogni giorno (se ci
sono aggiornamenti di pack/builder) e a richiesta (`Actions > Run workflow >
force: true`) DUE file dalla stessa build PAL (GameID `RMCPTO`, server RetroWFC):

- `MarioKart-RetroRewind-PAL.iso` → **Dolphin** (PC/Mac/Android/iOS)
- `RMCPTO.wbfs` → **Wii / Wii U (vWii)** via USB Loader GX / WiiFlow
  (copiare in `/wbfs/RMCPTO.wbfs` sulla USB)

I file finiscono come artifact della run e (se configurati i secret
`MEGA_USERNAME`/`MEGA_PASSWORD`) nella cartella MEGA `/RetroRewind/`.
La ISO base (`RMCP01` PAL) viene letta dalla cartella MEGA `/iso-originale/`.
Il builder usato e' quello ufficiale aggiornato
("Wiimm Edition for v6.12.5 and above", Kamek Loader v2), non quello obsoleto
su GitHub che causava `FATAL ERROR: Incompatible file (version 2)`.

## Uso su Dolphin

1. Apri `MarioKart-RetroRewind-PAL.iso` con Dolphin.
2. Disattiva i cheat: Config > Generale > togli "Enable Cheats".
3. Non usare ISO patchate per Wiimmfi e non attivare Retro Achievements.
4. Se vedi "invalid reads": Config > Avanzate > Emulated Memory Size Override,
   alza solo MEM2 a 128 MB.
5. Online = RetroWFC (niente VPN/Proxy/iCloud Private Relay); per problemi di
   connessione vedi la wiki (errori 20103/20110/22010...).

## Uso su Wii / Wii U (vWii)

1. Copia `RMCPTO.wbfs` in `/wbfs/RMCPTO.wbfs` sulla USB
   (se FAT32 e il file supera 4 GB, fallo convertire/splittare a
   Wii Backup Manager / Tiny Wii Backup Manager).
2. Installa il forwarder di Kote (http://bit.ly/3J4auhe) con un WAD manager.
3. Nel loader: cheat e funzionalita' cheat DISATTIVATE, nessuna patch Wiimmfi.
4. Avvia il loader dal System Menu (forwarder/canale), NON dall'Homebrew
   Channel (resta codice in RAM e causa "Disable all cheatcodes").
5. Se il forwarder torna al menu Wii: avvia prima il gioco normalmente dal
   loader una volta, poi usa il forwarder.

Limiti noti delle ISO patchate (uguali per Dolphin e Wii): le impostazioni non
si salvano e cambiare lingua in gioco puo' crashare.

Prerequisite are to have Wiimm ISO Tools installed before use and to suply the pack "Retro Rewind" and a copy of Mario Kart Wii as ISO or WBFS format.

Instructions for use 

Windows (From Windows 7 onwards)

1.) Install wit and szs tools: (Omit this step if you have it installed already)

https://wit.wiimm.de 

https://szs.wiimm.de 

Restart Computer

2.) Copy a backup of the original "Mario Kart Wii" in this directory.
    Supported image formats: iso, wbfs, wdf, wia, ciso

3.) Click on create-rr-xxx.bat xxx=region of the game

4.) Wait until process complete

5.) You found the new image in the sub directory 'new-image'

For Linux and MAC

1.) Install wit tools: https://wit.wiimm.de/  Then restart (Omit this if it is installed)

2.) Copy the Retro Rewind pack into this directory (only 'RetroRewind6/...' is needed).

3.) Copy a backup of the original "Mario Kart Wii" in this directory.
    Supported image formats: iso, wbfs, wdf, wia, ciso

4.) Linux and Mac users only: Execute: chmod a+x *.sh

5.) Call one of these scripts to select the output format: (Omit if you want the .wbfs format)

      set-image-type-ISO.sh   : Linux+Mac: Set output format to plain ISO
      set-image-type-WBFS.sh  : Linux+Mac: Set output format to WBFS
      set-image-type-WDF.sh   : Linux+Mac: Set output format to WDF

6.) Call one of these scripts:

      create-rr-pal.sh  : Linux and Mac users, create a PAL version
      create-rr-usa.sh  : Linux and Mac users, create a NTSC/USA version
      create-rr-jpn.sh  : Linux and Mac users, create a NTSC/JAPAN version

    The scripts will create a new image of selected type.

7.) You will find the new image in the sub directory 'new-image'.

Troubleshooting

"Disable all cheatcodes" error.

This can happens if you try to load a patched Retro Rewind wbfs on USB Loader the normal way, this is because USB Loader uses more RAM than loading it from Riivolution or Retro Rewind channel.

To fix it you must use a Forwarder channel to load the patched wbfs. I have a collection of forwarder channels for Retro Rewind here: http://bit.ly/3J4auhe

Forwarder returning to Wii menu.

To my understanding how the Wii works in software, the game must be played at least once so the Wii recognizes what is trying to play.
Essentially to fix it you must load the game normally then you can use the forwarder.
If the forwarder keeps returning to Wii menu make sure your USB Loader is set up correctly and using the same label as you used when you patched the game. Also only Wiiflow supports loading from SD Cards so keep that in mind.

Errors during operations

Any crashes that occurs without a dump like loading to a blackscreen seems that something went wrong during the patching process. Contact Kote3767 if there are any issues.

If the game crashes with a code dump, the crash report is saved in the Wii nand at "shared2/Pulsar/Retrorewind6/crash.pul"
To extract it you can use WiiXplorer or FSTOOLBOX and then you can go to Retro Rewind discord server to ask.
