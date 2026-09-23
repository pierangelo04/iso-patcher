// Invia il .wbfs appena buildato al gruppo WhatsApp "Mario Kart Wii".
// Eseguito dal job notify-whatsapp del workflow (dopo build con successo).
// - Sessione OpenWA persistente: sessionDataPath=.openwa-session, ripristinata
//   e salvata via actions/cache tra i run (key openwa-session-v1 /
//   openwa-session-v1-<run_id>).
// - Gruppo di destinazione: se il secret WA_GROUP_ID e' impostato lo usa
//   direttamente (override), altrimenti cerca tra i gruppi il nome
//   "Mario Kart Wii" (case-insensitive).
// - Prima autenticazione: pairing code se il secret WA_PHONE_NUMBER e'
//   impostato (numero in formato internazionale, solo cifre, es. 393331234567):
//   il codice a 8 caratteri viene stampato nei log, salvato in
//   pairing-code.txt (artifact) e va inserito sul telefono in
//   WhatsApp > Dispositivi collegati > Collega un dispositivo >
//   "Collega con il numero di telefono". Senza WA_PHONE_NUMBER si usa il QR
//   (openwa-qr.png, artifact openwa-qr, scansione entro ~5 minuti).
// - NESSUNA credenziale nel repo: numero di telefono e sessione vivono solo
//   nei secrets GitHub (WA_PHONE_NUMBER) e nella cache delle Action
//   (.openwa-session), mai committati.

const fs = require('fs');
const path = require('path');
const { create, ev } = require('@open-wa/wa-automate');

const GROUP_NAME = 'mario kart wii';
const MAX_FILE_BYTES = 2 * 1024 * 1024 * 1024; // limite documenti WhatsApp

// Estrae il codice a 8 caratteri dal payload dell'evento linkCode
// (il formato esatto puo' variare tra le versioni della libreria).
function extractCode(payload) {
  if (!payload) return null;
  if (typeof payload === 'string') {
    const m = payload.replace(/-/g, '').match(/[A-Z0-9]{8}/i);
    return m ? m[0].toUpperCase() : null;
  }
  for (const k of ['linkCode', 'code', 'pairingCode']) {
    if (typeof payload[k] === 'string') return extractCode(payload[k]);
  }
  return extractCode(JSON.stringify(payload));
}

async function main() {
  // WA_TEST_MODE=true: nessun file, solo un messaggio di testo di prova.
  const testMode = process.env.WA_TEST_MODE === 'true';
  let wbfsPath = null;
  let fileName = null;
  if (!testMode) {
    const wbfsDir = path.join(process.cwd(), 'wbfs');
    const files = fs.existsSync(wbfsDir)
      ? fs.readdirSync(wbfsDir).filter((f) => f.toLowerCase().endsWith('.wbfs'))
      : [];
    if (files.length === 0) {
      throw new Error("Nessun file .wbfs trovato in ./wbfs/ (artifact non scaricato?).");
    }
    fileName = files[0];
    wbfsPath = path.join(wbfsDir, fileName);
    const size = fs.statSync(wbfsPath).size;
    console.log(`File da inviare: ${fileName} (${(size / 1024 / 1024).toFixed(1)} MB)`);
    if (size > MAX_FILE_BYTES) {
      throw new Error(
        `Il file supera i 2 GB (limite documenti WhatsApp): invio impossibile. ` +
          `Il file resta disponibile come artifact del run e su MEGA.`
      );
    }
  } else {
    console.log('Modalita TEST: verra inviato solo un messaggio di testo.');
  }

  // Salva il QR come PNG se serve (prima autenticazione / sessione scaduta)
  ev.on('qr.**', async (qrcode, sessionId) => {
    const buf = Buffer.from(qrcode.replace('data:image/png;base64,', ''), 'base64');
    fs.writeFileSync('openwa-qr.png', buf);
    console.log('QR di autenticazione salvato in openwa-qr.png (artifact openwa-qr).');
  });

  console.log('Avvio client OpenWA (sessione retro-rewind-sender)...');
  const phoneNumber = (process.env.WA_PHONE_NUMBER || '').replace(/\D/g, '');
  const createConfig = {
    sessionId: 'retro-rewind-sender',
    headless: true,
    sessionDataPath: '.openwa-session',
    qrTimeout: 300, // 5 minuti per QR / pairing code
    authTimeout: 120,
    qrLogSkip: false,
    chromiumArgs: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage'],
  };
  if (phoneNumber) {
    // Pairing code invece del QR: il numero arriva dal secret WA_PHONE_NUMBER,
    // mai scritto nel repo.
    createConfig.linkCode = phoneNumber;
    console.log(`Pairing code richiesto per il numero ****${phoneNumber.slice(-4)}: ` +
      `inserisci il codice a 8 caratteri in WhatsApp > Dispositivi collegati > ` +
      `Collega un dispositivo > "Collega con il numero di telefono".`);
    ev.on('launch.auth.linkCode.generated', (payload) => {
      const code = extractCode(payload);
      if (code) {
        fs.writeFileSync('pairing-code.txt', `PAIRING CODE: ${code}\n`);
        console.log('==================================================');
        console.log(`  PAIRING CODE: ${code}`);
        console.log('==================================================');
      } else {
        console.log('Evento linkCode ricevuto (formato non riconosciuto):',
          JSON.stringify(payload).slice(0, 200));
      }
    });
  }
  const client = await create(createConfig);

  try {
    const override = (process.env.WA_GROUP_ID || '').trim();
    let groupId = override;
    if (groupId) {
      console.log('Uso WA_GROUP_ID dal secret (override).');
    } else {
      console.log('Ricerca del gruppo "Mario Kart Wii" tra i gruppi...');
      const groups = await client.getAllGroups(false);
      const found = groups.find((g) => (g.name || '').trim().toLowerCase() === GROUP_NAME);
      if (!found) {
        const names = (groups || []).map((g) => g.name).filter(Boolean).join(', ') || '(nessun gruppo)';
        throw new Error(
          `Gruppo "Mario Kart Wii" non trovato. Gruppi visibili: ${names}. ` +
            `Controlla il nome esatto del gruppo oppure imposta il secret WA_GROUP_ID ` +
            `del repo con l'ID del gruppo (formato 1234567890-1234567890@g.us).`
        );
      }
      groupId = found.id;
      console.log(`Gruppo trovato: "${found.name}" (${groupId})`);
    }

    if (testMode) {
      console.log(`Invio messaggio di TEST a ${groupId}...`);
      await client.sendText(groupId, '🧪 Test notifica Retro Rewind: il bot WhatsApp funziona ✅');
      console.log('Messaggio di test inviato al gruppo.');
    } else {
      const packVersion = process.env.PACK_VERSION || '?';
      const today = new Date().toISOString().slice(0, 10);
      const caption = `🎮 Retro Rewind aggiornato!\nPack v${packVersion} — build del ${today}\nISO patchata pronta per Dolphin e Wii.`;
      console.log(`Invio file a ${groupId}...`);
      await client.sendFile(groupId, wbfsPath, fileName, caption);
      console.log('File inviato al gruppo con successo.');
    }
  } finally {
    await client.kill();
  }
}

main().catch((e) => {
  console.error('ERRORE invio WhatsApp:', e && e.message ? e.message : e);
  process.exit(1);
});

