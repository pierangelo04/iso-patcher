// Invia il .wbfs appena buildato al gruppo WhatsApp "Mario Kart Wii" via Baileys.
// - Gruppo di destinazione: se il secret WA_GROUP_ID e' impostato lo usa
//   direttamente, altrimenti cerca il gruppo per nome (case-insensitive).
// - Prima autenticazione: pairing code se il secret WA_PHONE_NUMBER e'
//   impostato (numero in formato internazionale, solo cifre, senza '+').
//   Il codice a 8 caratteri compare nei log e in pairing-code.txt (artifact):
//   va inserito sul telefono in WhatsApp > Dispositivi collegati >
//   "Collega un dispositivo" > "Collega con il numero di telefono".
// - Sessione persistente in .baileys-session/ (cache delle GitHub Action).
// - NESSUNA credenziale nel repo: numero e sessione stanno solo nei secrets
//   e nella cache delle Action.
// - WA_TEST_MODE=true: invia solo un messaggio di testo (test senza build).
const fs = require('fs');
const path = require('path');
const pino = require('pino');
const {
  makeWASocket,
  useMultiFileAuthState,
  DisconnectReason,
  fetchLatestBaileysVersion,
} = require('@whiskeysockets/baileys');

const GROUP_NAME = 'mario kart wii';
const SESSION_DIR = '.baileys-session';
const MAX_FILE_BYTES = 2 * 1024 * 1024 * 1024; // limite documenti WhatsApp
const PAIR_WINDOW_MS = 4.5 * 60 * 1000; // tempo per inserire il pairing code

function printCode(code) {
  const pretty = code.includes('-') ? code : `${code.slice(0, 4)}-${code.slice(4)}`;
  fs.writeFileSync('pairing-code.txt', `PAIRING CODE: ${pretty}\n`);
  console.log('==================================================');
  console.log(`  PAIRING CODE: ${pretty}`);
  console.log('==================================================');
  console.log('Inseriscilo in WhatsApp > Dispositivi collegati > Collega un dispositivo > "Collega con il numero di telefono".');
}

async function main() {
  const testMode = process.env.WA_TEST_MODE === 'true';
  let wbfsPath = null;
  let fileName = null;
  if (!testMode) {
    const wbfsDir = path.join(process.cwd(), 'wbfs');
    const files = fs.existsSync(wbfsDir)
      ? fs.readdirSync(wbfsDir).filter((f) => f.toLowerCase().endsWith('.wbfs'))
      : [];
    if (files.length === 0) {
      throw new Error('Nessun file .wbfs trovato in ./wbfs/ (artifact non scaricato?).');
    }
    fileName = files[0];
    wbfsPath = path.join(wbfsDir, fileName);
    const size = fs.statSync(wbfsPath).size;
    console.log(`File da inviare: ${fileName} (${(size / 1024 / 1024).toFixed(1)} MB)`);
    if (size > MAX_FILE_BYTES) {
      throw new Error(
        'Il file supera i 2 GB (limite documenti WhatsApp): invio impossibile. ' +
        'Il file resta disponibile come artifact del run e su MEGA.'
      );
    }
  } else {
    console.log('Modalita TEST: verra inviato solo un messaggio di testo.');
  }

  const phoneNumber = (process.env.WA_PHONE_NUMBER || '').replace(/\D/g, '');
  if (!phoneNumber) {
    throw new Error('Secret WA_PHONE_NUMBER mancante: serve il numero (solo cifre) per il pairing code.');
  }

  const { state, saveCreds } = await useMultiFileAuthState(SESSION_DIR);
  const { version } = await fetchLatestBaileysVersion();
  const sock = makeWASocket({
    version,
    auth: state,
    logger: pino({ level: 'silent' }),
    printQRInTerminal: false,
    syncFullHistory: false,
    browser: ['RetroRewind', 'Chrome', '1.0'],
  });
  sock.ev.on('creds.update', saveCreds);

  // Attende la connessione; se serve il pairing, stampa (e rinnova) il codice.
  const connected = await new Promise((resolve, reject) => {
    let done = false;
    let refresh = null;
    const finish = (v) => { if (!done) { done = true; if (refresh) clearInterval(refresh); resolve(v); } };
    sock.ev.on('connection.update', (u) => {
      const { connection, lastDisconnect } = u;
      if (connection === 'open') return finish(true);
      if (connection === 'close') {
        const sc = lastDisconnect && lastDisconnect.error && lastDisconnect.error.output
          ? lastDisconnect.error.output.statusCode : null;
        if (sc === DisconnectReason.loggedOut || sc === DisconnectReason.badSession) {
          if (!done) {
            done = true; if (refresh) clearInterval(refresh);
            reject(new Error('Sessione WhatsApp non valida (logout). Riesegui il workflow per rifare il pairing da zero.'));
          }
        }
      }
    });
    (async () => {
      try {
        if (!sock.authState.creds.registered) {
          printCode(await sock.requestPairingCode(phoneNumber));
          // Il codice scade in fretta: lo rigeneriamo ogni 90 secondi.
          refresh = setInterval(async () => {
            if (done) return;
            try { printCode(await sock.requestPairingCode(phoneNumber)); } catch (_) { /* ignora */ }
          }, 90000);
        } else {
          console.log('Sessione esistente trovata, connessione in corso...');
        }
        setTimeout(() => finish(false), PAIR_WINDOW_MS);
      } catch (e) { if (!done) { done = true; reject(e); } }
    })();
  });
  if (!connected) {
    throw new Error('Timeout: pairing code non inserito entro 4,5 minuti.');
  }
  console.log('Connesso a WhatsApp.');
  await new Promise((r) => setTimeout(r, 2000));
  await saveCreds();

  try {
    const override = (process.env.WA_GROUP_ID || '').trim();
    let groupId = override;
    if (groupId) {
      console.log('Uso WA_GROUP_ID dal secret (override).');
    } else {
      console.log('Ricerca del gruppo "Mario Kart Wii" tra i gruppi...');
      const groups = await sock.groupFetchAllParticipating();
      const found = Object.values(groups).find(
        (g) => (g.subject || '').trim().toLowerCase() === GROUP_NAME
      );
      if (!found) {
        const names = Object.values(groups).map((g) => g.subject).filter(Boolean).join(', ') || '(nessun gruppo)';
        throw new Error(
          `Gruppo "Mario Kart Wii" non trovato. Gruppi visibili: ${names}. ` +
          'Controlla il nome esatto del gruppo oppure imposta il secret WA_GROUP_ID ' +
          'del repo con l\u2019ID del gruppo (formato 1234567890-1234567890@g.us).'
        );
      }
      groupId = found.id;
      console.log(`Gruppo trovato: "${found.subject}" (${groupId})`);
    }

    if (testMode) {
      console.log(`Invio messaggio di TEST a ${groupId}...`);
      await sock.sendMessage(groupId, { text: '\uD83E\uDDEA Test notifica Retro Rewind: il bot WhatsApp funziona \u2705' });
      console.log('Messaggio di test inviato al gruppo.');
    } else {
      const packVersion = process.env.PACK_VERSION || '?';
      const today = new Date().toISOString().slice(0, 10);
      const caption = `\uD83C\uDFAE Retro Rewind aggiornato!\nPack v${packVersion} \u2014 build del ${today}\nISO patchata pronta per Dolphin e Wii.`;
      console.log(`Invio file a ${groupId}...`);
      await sock.sendMessage(groupId, {
        document: fs.readFileSync(wbfsPath),
        fileName,
        mimetype: 'application/octet-stream',
        caption,
      });
      console.log('File inviato al gruppo con successo.');
    }
  } finally {
    try { sock.end(); } catch (_) { /* ignora */ }
  }
}

main().catch((e) => {
  console.error('ERRORE invio WhatsApp:', e && e.message ? e.message : e);
  process.exit(1);
});
