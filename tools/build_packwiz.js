// Regenerate packwiz mods/*.pw.toml from a CurseForge instance's mods/*.jar.
// Modrinth exact sha1 match -> Modrinth download; else CurseForge metadata mode (if distribution allowed).
// Metafile names are stable: a mod that already has a metafile (matched by Modrinth/CurseForge project id)
// keeps its filename across updates. Metafiles for jars no longer in the instance are deleted.
// Client-only: jar filename listed in clientOnlyFile, or the mod was client-only and its version changed
// (so updates stay client-only). The list is rewritten to the current client-only jar filenames.
// Exits 1 without touching anything if any jar can't be published or the Modrinth API fails.
// Usage: node build_packwiz.js <instanceDir> <packDir> <clientOnlyFile>
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const [inst, pack, listFile] = process.argv.slice(2);
if (!listFile) { console.error('usage: node build_packwiz.js <instanceDir> <packDir> <clientOnlyFile>'); process.exit(2); }
const die = m => { console.error('ERROR: ' + m); process.exit(1); };
const UA = { 'User-Agent': 'packwiz-pack-updater' };
const q = s => JSON.stringify(s);
const slug = s => s.toLowerCase().replace(/\.jar$/, '').replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

const listed = new Set(fs.readFileSync(listFile, 'utf8').split(/\r?\n/).map(s => s.trim()).filter(Boolean));
const d = JSON.parse(fs.readFileSync(path.join(inst, 'minecraftinstance.json'), 'utf8'));
const cfByFile = new Map(d.installedAddons.map(a => [a.installedFile.fileNameOnDisk || a.installedFile.fileName, a]));
const jars = fs.readdirSync(path.join(inst, 'mods')).filter(f => f.endsWith('.jar')).sort();
if (!jars.length) die('no jars in ' + path.join(inst, 'mods'));

// Existing metafiles: project key -> { name, side, ver }
const modsDir = path.join(pack, 'mods');
fs.mkdirSync(modsDir, { recursive: true });
const existing = new Map(), oldFiles = fs.readdirSync(modsDir).filter(f => f.endsWith('.pw.toml'));
for (const f of oldFiles) {
  const t = fs.readFileSync(path.join(modsDir, f), 'utf8');
  const ver = t.match(/^version = "(.*)"/m) || t.match(/^file-id = (\d+)/m);
  const info = { name: f, side: (t.match(/^side = "(\w+)"/m) || [])[1], ver: ver && ver[1] };
  const mr = t.match(/^mod-id = "(.*)"/m), cf = t.match(/^project-id = (\d+)/m);
  if (mr) existing.set('mr:' + mr[1], info);
  if (cf) existing.set('cf:' + cf[1], info);
}

(async () => {
  const rows = jars.map(f => ({ f, sha1: crypto.createHash('sha1').update(fs.readFileSync(path.join(inst, 'mods', f))).digest('hex') }));
  const r = await fetch('https://api.modrinth.com/v2/version_files', { method: 'POST',
    headers: { 'Content-Type': 'application/json', ...UA },
    body: JSON.stringify({ hashes: rows.map(x => x.sha1), algorithm: 'sha1' }) });
  if (!r.ok) die('Modrinth version_files HTTP ' + r.status);
  const mr = await r.json();
  const projIds = [...new Set(Object.values(mr).map(v => v.project_id))], projects = {};
  for (let i = 0; i < projIds.length; i += 100) {
    const pr = await fetch('https://api.modrinth.com/v2/projects?ids=' + encodeURIComponent(JSON.stringify(projIds.slice(i, i + 100))), { headers: UA });
    if (!pr.ok) die('Modrinth projects HTTP ' + pr.status);
    for (const p of await pr.json()) projects[p.id] = p;
  }

  const out = new Map(), clientJars = [], failed = [], stats = { modrinth: 0, curseforge: 0, client: 0 };
  for (const { f, sha1 } of rows) {
    const v = mr[sha1], a = cfByFile.get(f);
    const keys = [v && 'mr:' + v.project_id, a && 'cf:' + a.addonID].filter(Boolean);
    const prev = keys.map(k => existing.get(k)).find(Boolean);
    const ver = v ? v.id : a ? String(a.installedFile.id) : f;
    const client = listed.has(f) || (prev && prev.side === 'client' && prev.ver !== ver); // updates stay client-only
    const side = client ? 'client' : 'both';
    let toml, fresh;
    if (v) {
      const file = v.files.find(x => x.hashes.sha1 === sha1), p = projects[v.project_id] || {};
      toml = `name = ${q(p.title || f)}\nfilename = ${q(file.filename)}\nside = ${q(side)}\n\n[download]\nurl = ${q(file.url)}\nhash-format = "sha512"\nhash = ${q(file.hashes.sha512)}\n\n[update]\n[update.modrinth]\nmod-id = ${q(v.project_id)}\nversion = ${q(v.id)}\n`;
      fresh = p.slug; stats.modrinth++;
    } else if (a && a.allowModDistribution !== false) {
      toml = `name = ${q(a.name)}\nfilename = ${q(f)}\nside = ${q(side)}\n\n[download]\nhash-format = "sha1"\nhash = ${q(sha1)}\nmode = "metadata:curseforge"\n\n[update]\n[update.curseforge]\nfile-id = ${a.installedFile.id}\nproject-id = ${a.addonID}\n`;
      fresh = (a.webSiteURL || '').split('/').filter(Boolean).pop(); stats.curseforge++;
    } else { failed.push(f + (a ? ' (author blocks third-party downloads)' : ' (not on Modrinth, not a CurseForge install)')); continue; }
    let name = prev ? prev.name : slug(fresh || f) + '.pw.toml';
    if (!prev && (out.has(name) || oldFiles.includes(name))) name = slug(f) + '.pw.toml'; // name taken by another mod
    if (out.has(name)) die('two jars map to ' + name + ': ' + f);
    out.set(name, toml);
    if (client) { clientJars.push(f); stats.client++; }
  }
  if (failed.length) die('these mods cannot be published (remove them or replace with an allowed version):\n  ' + failed.join('\n  '));

  for (const [name, toml] of out) {
    const p = path.join(modsDir, name);
    if (!fs.existsSync(p) || fs.readFileSync(p, 'utf8') !== toml) fs.writeFileSync(p, toml);
  }
  for (const f of oldFiles) if (!out.has(f)) fs.unlinkSync(path.join(modsDir, f));
  fs.writeFileSync(listFile, clientJars.sort().join('\n') + '\n');
  console.log(JSON.stringify(stats));
})().catch(e => die(e.stack || e));
