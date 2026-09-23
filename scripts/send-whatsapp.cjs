// Invia il .wbfs appena buildato al gruppo WhatsApp "Mario Kart Wii".
// Eseguito dal job notify-whatsapp del workflow (dopo build con successo).
// - Sessione OpenWA persistente: sessionDataPath=.openwa-session, ripristinata
//   e salvata via actions/cache tra i run (key openwa-session-v1 /
//   openwa-session-v1-<run_id>).
// - Gruppo di destinazione: se il secret WA_GROUP_ID e' impostato lo usa
//   direttamente (override), altrimenti cerca tra i gruppi il nome
//   "Mario Kart Wii" (case-insensitive).
// - Prima autenticazione: il QR viene salvato in openwa-qr.png e caricato
//   come artifact del run (scansione entro ~5 minuti).

const fs = require('fs');
const path = require('path');
const { create, ev } = require('@open-wa/wa-automate');

const GROUP_NAME = 'mario kart wii';
const MAX_FILE_BYTES = 2 * 1024 * 1024 * 1024; // limite documenti WhatsApp

async function main() {
  const wbfsDir = path.join(process.cwd(), 'wbfs');
  const files = fs.existsSync(wbfsDir)
    ? fs.readdirSync(wbfsDir).filter((f) => f.toLowerCase().endsWith('.wbfs'))
    : [];
  if (files.length === 0) {
    throw new Error("Nessun file .wbfs trovato in ./wbfs/ (artifact non scaricato?).");
  }
  const wbfsPath = path.join(wbfsDir, files[0]);
  const size = fs.statSync(wbfsPath).size;
  console.log(`File da inviare: ${files[0]} (${(size / 1024 / 1024).toFixed(1)} MB)`);
  if (size > MAX_FILE_BYTES) {
    throw new Error(
      `Il file supera i 2 GB (limite documenti WhatsApp): invio impossibile. ` +
        `Il file resta disponibile come artifact del run e su MEGA.`
    );
  }

  // Salva il QR come PNG se serve (prima autenticazione / sessione scaduta)
  ev.on('qr.**', async (qrcode, sessionId) => {
    const buf = Buffer.from(qrcode.replace('data:image/png;base64,', ''), 'base64');
    fs.writeFileSync('openwa-qr.png', buf);
    console.log('QR di autenticazione salvato in openwa-qr.png (artifact openwa-qr).');
  });

  console.log('Avvio client OpenWA (sessione retro-rewind-sender)...');
  const client = await create({
    sessionId: 'retro-rewind-sender',
    headless: true,
    sessionDataPath: '.openwa-session',
    qrTimeout: 300, // 5 minuti per scansionare il QR
    authTimeout: 120,
    qrLogSkip: false,
    chromiumArgs: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage'],
  });

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

    const packVersion = process.env.PACK_VERSION || '?';
    const today = new Date().toISOString().slice(0, 10);
    const caption = `🎮 Retro Rewind aggiornato!\nPack v${packVersion} — build del ${today}\nISO patchata pronta per Dolphin e Wii.`;
    console.log(`Invio file a ${groupId}...`);
    await client.sendFile(groupId, wbfsPath, files[0], caption);
    console.log('File inviato al gruppo con successo.');
  } finally {
    await client.kill();
  }
}

main().catch((e) => {
  console.error('ERRORE invio WhatsApp:', e && e.message ? e.message : e);
  process.exit(1);
});
