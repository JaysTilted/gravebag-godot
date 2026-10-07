import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, mkdtempSync, mkdirSync, writeFileSync, copyFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const overlay = join(root, 'scripts/fsod_backend');
// Explicit immutable offline input, independent of HOME/plans/operator config.
const source = existsSync(join(root, 'references/fsod/wServer/wServer.csproj'))
  ? join(root, 'references/fsod') : '/home/jay/fsod-ref';
const revision = '6fd20aad4a7905b13f25389c68368a942a2b68cb';
const playerList = 'wServer/realm/entities/player/Player.List.cs';
const oldComparison = 'rdr.GetString("accId") == AccountId';
const canonicalCore = 'Convert.ToString(rdr.GetValue(rdr.GetOrdinal("accId")), CultureInfo.InvariantCulture)';
const canonicalComparison = `${canonicalCore} == AccountId`;
const hash = data => createHash('sha256').update(data).digest('hex');
const original = path => execFileSync('git', ['-C', source, 'show', `${revision}:${path}`], { maxBuffer: 8 * 1024 * 1024 });
const count = (text, needle) => text.split(needle).length - 1;
const windows = [
  'SELECT * FROM death WHERE (time >= DATE_SUB(NOW(), INTERVAL 1 WEEK)) ORDER BY totalFame DESC LIMIT 20;',
  'SELECT * FROM death WHERE (time >= DATE_SUB(NOW(), INTERVAL 1 MONTH)) ORDER BY totalFame DESC LIMIT 20;',
  'SELECT * FROM death WHERE TRUE ORDER BY totalFame DESC LIMIT 20;',
];

// The tested comparison is compiled from the fixture alongside the REAL
// patched file's canonical expression (text-bound below), never a rewrite of
// leaderboard SQL, ordering, glow/XP/fame/death math or exception flow.
function patchSection(fullPatch, header) {
  const lines = fullPatch.split('\n');
  const start = lines.findIndex(line => line === `--- a/${header}`);
  assert.ok(start >= 0, `overlay carries a ${header} hunk`);
  let end = lines.findIndex((line, index) => index > start && line.startsWith('--- a/'));
  if (end < 0) end = lines.length;
  return `${lines.slice(start, end).join('\n')}\n`;
}

test('original numeric death.accId breaks GetString; overlay converts invariantly in all three windows', { timeout: 60000 }, () => {
  assert.equal(execFileSync('git', ['-C', source, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim(), revision);
  const before = original(playerList).toString();
  // Bug present upstream: three strict GetString reads of a numeric column.
  assert.equal(count(before, oldComparison), 3);
  assert.equal(count(before, canonicalCore), 0);
  for (const sql of windows) assert.ok(before.includes(sql), `original leaderboard SQL present: ${sql.slice(0, 48)}`);
  // death.accId is numeric in the pinned schema, which is why 8.4 throws.
  const schema = original('db/rotmgprod.sql').toString();
  const death = schema.slice(schema.indexOf('CREATE TABLE IF NOT EXISTS `death`'));
  assert.match(death.slice(0, 1200), /`accId` int\(11\) NOT NULL/);
  // No gameplay beyond the comparison may change: after removing exactly the
  // three old lines and adding exactly the two usings plus three canonical
  // lines, the file must otherwise be byte-identical.
  const fullPatch = readFileSync(join(overlay, 'linux-isolation.patch'), 'utf8');
  const section = patchSection(fullPatch, playerList);
  const temp = mkdtempSync(join(tmpdir(), 'fsod-numeric-'));
  try {
    const target = join(temp, playerList);
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, before);
    writeFileSync(join(temp, 'playerlist-only.patch'), section);
    const applied = spawnSync('patch', ['--batch', '--forward', '-p1', '-i', join(temp, 'playerlist-only.patch')],
      { cwd: temp, encoding: 'utf8' });
    assert.equal(applied.status, 0, applied.stderr);
    assert.doesNotMatch(applied.stdout, /fuzz|offset/i, 'hunk context matches exactly, no fuzz');
    const after = readFileSync(target, 'utf8');
    assert.equal(count(after, oldComparison), 0, 'no strict GetString("accId") remains');
    assert.equal(count(after, canonicalComparison), 3, 'all three windows use the invariant conversion');
    assert.equal(count(after, 'CultureInfo.InvariantCulture'), 3);
    assert.ok(after.includes('using System.Globalization;'));
    for (const sql of windows) assert.ok(after.includes(sql), `leaderboard SQL unchanged: ${sql.slice(0, 48)}`);
    assert.doesNotMatch(after, /catch|DELETE\s+FROM\s+`?death|TRUNCATE/i, 'no catch suppression, no death-row wipe');
    const strip = (text, olds, news) => {
      const kept = [];
      for (const line of text.split('\n')) {
        if (olds.includes(line) || news.includes(line)) continue;
        kept.push(line);
      }
      return kept.join('\n');
    };
    const oldLine = '                        if (rdr.GetString("accId") == AccountId) return true;';
    const newLine = `                        if (${canonicalComparison}) return true;`;
    assert.equal(
      strip(after, [], ['using System;', 'using System.Globalization;', newLine]),
      strip(before, [oldLine], []),
      'only the two usings and three comparison lines differ');
    // Compiled real C# proof: the fixture reproduces the 8.4 strict contract
    // (negative control throws) and the canonical expression matching safely.
    const fixture = readFileSync(join(overlay, 'tests/NumericAccountFixture.cs'), 'utf8');
    assert.ok(fixture.includes(canonicalCore), 'fixture proves the same canonical expression as the overlay');
    const exe = join(temp, 'NumericAccountFixture.exe');
    const compile = spawnSync('mcs', ['-out:' + exe, join(overlay, 'tests/NumericAccountFixture.cs')],
      { encoding: 'utf8', timeout: 30000 });
    assert.equal(compile.status, 0, compile.stderr);
    const proof = spawnSync('mono', [exe], { encoding: 'utf8', timeout: 30000 });
    assert.equal(proof.status, 0, proof.stderr);
    const match = proof.stdout.match(/compiled-original-numeric-accId: PASS \((\d+) cases; 3 windows x (\d+) cultures\)/);
    assert.ok(match, `fixture PASS line: ${proof.stdout.trim()}`);
    assert.ok(Number(match[1]) >= 100, 'match/mismatch/empty/boundary cases across every window');
    assert.ok(Number(match[2]) >= 3, 'invariant plus multiple ambient cultures');
    console.log(proof.stdout.trim());
    // Negative control: the same fixture with the ORIGINAL expression in the
    // patched position must fail, proving the probe detects the defect class.
    const regressed = fixture.replace(canonicalCore, 'rdr.GetString("accId")');
    assert.notEqual(regressed, fixture);
    writeFileSync(join(temp, 'NumericAccountRegressed.cs'), regressed);
    const regressedExe = join(temp, 'NumericAccountRegressed.exe');
    const regressedCompile = spawnSync('mcs', ['-out:' + regressedExe, join(temp, 'NumericAccountRegressed.cs')],
      { encoding: 'utf8', timeout: 30000 });
    assert.equal(regressedCompile.status, 0, regressedCompile.stderr);
    const regressedRun = spawnSync('mono', [regressedExe], { encoding: 'utf8', timeout: 30000 });
    assert.notEqual(regressedRun.status, 0, 'original GetString semantics cannot pass the numeric probe');
    console.log('compiled negative control: PASS; original GetString rejected on numeric accId');
  } finally { rmSync(temp, { recursive: true, force: true }); }
});

test('isolated full original build compiles the numeric overlay without touching parent state', { timeout: 240000 }, () => {
  // Parent may already be serving actual play. Read only immutable build
  // artifacts, never private profiles, DB files, sockets or changing exec logs.
  const parentSnapshot = () => ({
    controlSocketExists: existsSync(join(overlay, '.state/control.sock')),
    build: ['manifest.json', 'source/bin/Debug/wServer.exe', 'source/bin/Debug/db.dll', 'source/bin/Debug/autoId.cfg']
      .map(file => [file, existsSync(join(overlay, '.state', file)) ? hash(readFileSync(join(overlay, '.state', file))) : null]),
  });
  const before = parentSnapshot();
  const temp = mkdtempSync(join(tmpdir(), 'fsod-numeric-build-'));
  const runner = join(temp, 'backend');
  mkdirSync(runner);
  try {
    for (const file of ['backend.py', 'linux-isolation.patch', 'lifecycle.patch', 'dependencies.lock.json', 'MetadataIds.cs']) {
      copyFileSync(join(overlay, file), join(runner, file));
    }
    const run = (file, args, options = {}) => {
      const result = spawnSync(file, args, { encoding: 'utf8', timeout: 210000, maxBuffer: 8 * 1024 * 1024, ...options });
      assert.equal(result.error, undefined, `${file}: ${result.error}`);
      assert.equal(result.status, 0, `${file}: ${result.stdout?.slice(-4000)}\n${result.stderr?.slice(-4000)}`);
      return result.stdout;
    };
    const manifest = JSON.parse(run('python3', [join(runner, 'backend.py'), 'build',
      '--source', source, '--dependencies', '/home/jay/.nuget/packages']));
    assert.equal(manifest.build, 'pass');
    assert.equal(manifest.source_revision, revision);
    assert.equal(manifest.patch_sha256, hash(readFileSync(join(overlay, 'linux-isolation.patch'))));
    assert.equal(manifest.lifecycle_patch_sha256, hash(readFileSync(join(overlay, 'lifecycle.patch'))));
    const tree = join(runner, '.state/source');
    assert.ok(existsSync(join(tree, 'bin/Debug/wServer.exe')), 'patched wServer compiled');
    const built = readFileSync(join(tree, playerList), 'utf8');
    assert.equal(count(built, oldComparison), 0);
    assert.equal(count(built, canonicalComparison), 3);
    for (const sql of windows) assert.ok(built.includes(sql), 'built leaderboard SQL unchanged');
    assert.ok(!existsSync(join(runner, '.state/control.sock')), 'build only: no DB or runtime launched');
    assert.deepEqual(parentSnapshot(), before, 'parent runtime/build unchanged (whether running or stopped)');
    console.log('isolated original full build: PASS; numeric overlay compiled into wServer');
  } finally { rmSync(temp, { recursive: true, force: true }); }
});
