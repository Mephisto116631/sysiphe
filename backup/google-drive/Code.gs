/**
 * Sysiphe — sauvegarde quotidienne des données Supabase en CSV dans Google Drive.
 *
 * Installation (5 min, une fois) : voir backup/README.md, section « Google Drive ».
 * Fonctions à utiliser depuis l'éditeur Apps Script :
 *   - sauvegarder()        : fait une sauvegarde maintenant (à lancer une 1re fois à la main) ;
 *   - installerDeclencheur(): programme sauvegarder() tous les jours vers 3 h.
 */

const SUPABASE_URL = 'https://qzvfkscqcllfnoqywkwq.supabase.co';
const DOSSIER = 'Sysiphe sauvegardes';
const GARDER_JOURS = 60;
const PAGE = 1000; // Supabase renvoie au plus 1000 lignes par requête

// Table → colonnes de tri (stables, pour paginer sans trou ni doublon).
const TABLES = {
  perfs: 'id',
  profiles: 'id',
  user_settings: 'user_id',
  profile_members: 'auth_uid,profile_id',
};

function sauvegarder() {
  const cle = PropertiesService.getScriptProperties().getProperty('SUPABASE_SERVICE_KEY');
  if (!cle) {
    throw new Error('Clé manquante : Paramètres du projet > Propriétés du script > ' +
        'SUPABASE_SERVICE_KEY = clé service_role de Supabase.');
  }
  const dossier = dossier_();
  const jour = Utilities.formatDate(new Date(), 'Europe/Paris', 'yyyy-MM-dd');
  const bilan = [];
  for (const table of Object.keys(TABLES)) {
    const lignes = lireTable_(table, TABLES[table], cle);
    const nom = `${table}-${jour}.csv`;
    // Relancer le même jour remplace le fichier au lieu d'en créer un 2e.
    const anciens = dossier.getFilesByName(nom);
    while (anciens.hasNext()) anciens.next().setTrashed(true);
    dossier.createFile(nom, versCsv_(lignes), MimeType.CSV);
    bilan.push(`${table} ${lignes.length}`);
  }
  const supprimes = purger_(dossier, GARDER_JOURS);
  console.log(`OK ${jour} : ${bilan.join(', ')}` +
      (supprimes ? ` ; ${supprimes} ancien(s) fichier(s) supprimé(s)` : ''));
}

function installerDeclencheur() {
  for (const t of ScriptApp.getProjectTriggers()) {
    if (t.getHandlerFunction() === 'sauvegarder') ScriptApp.deleteTrigger(t);
  }
  ScriptApp.newTrigger('sauvegarder').timeBased().everyDays(1).atHour(3).create();
  console.log('Sauvegarde programmée tous les jours vers 3 h.');
}

/** Toutes les lignes d'une table, page par page. */
function lireTable_(table, ordre, cle) {
  const lignes = [];
  for (let debut = 0; ; debut += PAGE) {
    const url = `${SUPABASE_URL}/rest/v1/${table}?select=*` +
        `&order=${ordre.split(',').map((c) => c + '.asc').join(',')}` +
        `&limit=${PAGE}&offset=${debut}`;
    const rep = UrlFetchApp.fetch(url, {
      headers: { apikey: cle, Authorization: `Bearer ${cle}` },
      muteHttpExceptions: true,
    });
    if (rep.getResponseCode() !== 200) {
      throw new Error(`${table} : HTTP ${rep.getResponseCode()} — ${rep.getContentText()}`);
    }
    const page = JSON.parse(rep.getContentText());
    lignes.push(...page);
    if (page.length < PAGE) return lignes;
  }
}

/** CSV (virgules, guillemets si besoin), colonnes = union des clés dans l'ordre d'apparition. */
function versCsv_(lignes) {
  const colonnes = [];
  for (const l of lignes) {
    for (const c of Object.keys(l)) if (!colonnes.includes(c)) colonnes.push(c);
  }
  const cellule = (v) => {
    if (v === null || v === undefined) return '';
    const s = typeof v === 'object' ? JSON.stringify(v) : String(v);
    return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return [colonnes.join(','), ...lignes.map((l) => colonnes.map((c) => cellule(l[c])).join(','))]
      .join('\n') + '\n';
}

/** Met à la corbeille les sauvegardes de plus de [jours] jours (d'après la date du nom). */
function purger_(dossier, jours) {
  const limite = new Date(Date.now() - jours * 86400000);
  const fichiers = dossier.getFiles();
  let n = 0;
  while (fichiers.hasNext()) {
    const f = fichiers.next();
    const m = /-(\d{4})-(\d{2})-(\d{2})\.csv$/.exec(f.getName());
    if (m && new Date(+m[1], +m[2] - 1, +m[3]) < limite) {
      f.setTrashed(true);
      n++;
    }
  }
  return n;
}

function dossier_() {
  const it = DriveApp.getFoldersByName(DOSSIER);
  return it.hasNext() ? it.next() : DriveApp.createFolder(DOSSIER);
}
