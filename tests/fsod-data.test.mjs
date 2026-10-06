// FSoD metadata export acceptance. No live server/operator HOME dependency.
// Upstream AGPLv3: ossimc82/fabiano-swagger-of-doom @ 6fd20aad4a7905b13f25389c68368a942a2b68cb.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, existsSync, mkdirSync, mkdtempSync, rmSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const tables = join(root, 'src/data/fsod');
const load = name => JSON.parse(readFileSync(join(tables, `${name}.json`), 'utf8'));
const manifest = load('manifest');

function run(argv, options = {}) {
  const result = spawnSync(argv[0], argv.slice(1), { cwd: root, encoding: 'utf8', timeout: 120000, maxBuffer: 32 * 1024 * 1024, ...options });
  assert.equal(result.error, undefined, result.error?.message);
  assert.equal(result.status, 0, `${argv.join(' ')} failed: ${result.stderr}\n${result.stdout}`);
  return result.stdout;
}

async function stagePinnedXml(temp) {
  const source = join(temp, 'source');
  mkdirSync(source);
  for (const entry of manifest.sources) {
    const canonical = join(root, 'references/fsod/db/data', entry.file);
    let bytes;
    if (existsSync(canonical)) {
      bytes = readFileSync(canonical);
    } else {
      // Fresh non-recursive clones need only four pinned metadata files,
      // not the upstream artwork/SWF. Never read another host worktree.
      const response = await fetch(`${manifest.upstream.replace('https://github.com/', 'https://raw.githubusercontent.com/')}/${manifest.source_revision}/db/data/${entry.file}`, { signal: AbortSignal.timeout(30000) });
      assert.equal(response.ok, true, `${entry.file}: pinned metadata HTTP ${response.status}`);
      bytes = Buffer.from(await response.arrayBuffer());
    }
    assert.equal(createHash('sha256').update(bytes).digest('hex'), entry.sha256, `${entry.file}: pinned source hash`);
    writeFileSync(join(source, entry.file), bytes);
  }
  return source;
}

test('all source constructors and duplicate/AutoAssign rules match isolated fixtures', () => {
  run(['python3', 'scripts/fsod_assets/test_extract.py']);
});

test('full export counts, indices, exclusions, starter class and equipment metadata', () => {
  assert.equal(manifest.source_revision, '6fd20aad4a7905b13f25389c68368a942a2b68cb');
  assert.equal(manifest.license, 'AGPLv3');
  assert.deepEqual(manifest.counts, {
    objects: 3831, object_descriptors: 2232, grounds: 333, items: 1281,
    player_classes: 14, portals: 57, pets: 130, pet_skins: 131,
    equipment_sets: 6, projectiles: 3831, projectile_descriptors: 1397, ignored_objects: 23,
  });
  for (const [name, count] of Object.entries(manifest.counts)) {
    if (name === 'projectile_descriptors' || name === 'ignored_objects') continue;
    assert.equal(Object.keys(load(name)).length, count, name);
  }
  const indices = load('indices');
  const objects = load('objects');
  const grounds = load('grounds');
  const items = load('items');
  const classes = load('player_classes');
  const projectiles = load('projectiles');
  const descs = load('object_descriptors');
  assert.equal(indices.IdToObjectType.wizard, 0x30e);
  assert.equal(indices.IdToObjectType['hobbit mage'], 0x617);
  assert.equal(indices.IdToTileType.grass, 0x48);
  assert.equal(indices.IdToTileType['grey circle'], 101); // Last source name wins, both types survive.
  assert.equal(grounds['97'].descriptor.ObjectId, 'Grey Circle');
  assert.equal(grounds['101'].descriptor.ObjectId, 'Grey Circle');
  assert.equal(objects['782'].class, 'Player');
  assert.deepEqual(classes['782'].SlotTypes, [17, 11, 14, 9, 0, 0, 0, 0, 0, 0, 0, 0]);
  assert.deepEqual(classes['782'].Equipment, [0xa97, 0xa2e, -1, -1, 0xa22, -1, -1, -1, -1, -1, -1, -1]);
  assert.deepEqual(classes['782'].Stats.MaxHitPoints, { initial: 100, max: 670 });
  assert.deepEqual(classes['782'].Stats.Attack, { initial: 12, max: 75 });
  assert.deepEqual(classes['782'].LevelIncrease[0], { stat: 'MaxHitPoints', min: 20, max: 30 });
  assert.equal(items[String(0xa97)].SlotType, 17);
  assert.equal(items[String(0xa97)].Tier, 0);
  assert.equal(descs[String(0x617)].Enemy, true);
  assert.equal(descs[String(0x617)].MaxHP, 200);
  assert.equal(descs[String(0x617)].Defense, 2);
  assert.equal(descs[String(0x617)].SpawnProbability, 0); // Source reads SpawnProbability, not SpawnProb.
  assert.deepEqual(projectiles[String(0x617)].map(p => [p.BulletType, p.MinDamage, p.MaxDamage]), [[0, 10, 10], [1, 10, 10], [2, 10, 10]]);
  assert.equal(grounds['72'].descriptor.Speed, 0); // No Speed tag: C# Single defaults to zero.
  assert.equal(grounds['72'].descriptor.NoWalk, false);
  assert.equal(load('equipment_sets')['2'].descriptor.BulletType, 'Great Geb Shot');
  assert.equal(load('equipment_sets')['2'].descriptor.SkinType, 0x745a);
  assert.deepEqual(load('equipment_sets')['2'].descriptor.StatsBoost[2], { stat: 20, amount: 8 });
  assert.equal(load('portals')[String(indices.IdToObjectType['the shatters'])].TimeoutTime, 70);
  assert.equal(Object.values(projectiles).reduce((count, values) => count + values.length, 0), 1397);
  assert.deepEqual(manifest.missing_references, []);
  assert.equal(manifest.duplicates.length, 1);
  const ignored = load('ignored_objects').records;
  assert.equal(ignored.length, 23);
  assert.equal(ignored.filter(record => record.reason === 'missing Class').length, 5);
  assert.equal(ignored.filter(record => record.reason === 'PetAbility').length, 9);
  assert.equal(ignored.filter(record => record.reason === 'PetBehavior').length, 9);
  assert.equal(manifest.auto_id_mode, 'fresh-server-defaults');
  assert.equal(manifest.runtime_auto_ids_supplied, false);
  assert.deepEqual(manifest.auto_assigned.map(record => record.type), [50000, 50001, 50002]);
  for (const [type, object] of Object.entries(objects)) {
    assert.equal(String(object.type), type);
    assert.equal(indices.ObjectTypeToId[type], object.id);
    assert.ok(object.xml.children.length > 0);
    for (const projectile of projectiles[type]) {
      assert.ok(Object.hasOwn(indices.IdToObjectType, projectile.ObjectId.toLowerCase()), projectile.ObjectId);
    }
  }
});

test('full pinned XML deterministic regeneration and explicit runtime AutoAssign reconciliation', async () => {
  const temp = mkdtempSync(join(tmpdir(), 'fsod-data-test-'));
  try {
    const source = await stagePinnedXml(temp);
    const output = join(temp, 'generated');
    run(['python3', 'scripts/fsod_assets/extract.py', '--source', source, '--output', output]);
    for (const filename of readdirSync(tables).filter(name => name.endsWith('.json'))) {
      assert.deepEqual(readFileSync(join(output, filename)), readFileSync(join(tables, filename)), `${filename}: regeneration`);
    }
    run(['python3', 'scripts/fsod_assets/extract.py', '--source', source, '--output', output, '--check']);
    // Second complete build must be byte-identical, independent of output path/HOME.
    const second = join(temp, 'second');
    run(['python3', 'scripts/fsod_assets/extract.py', '--source', source, '--output', second]);
    for (const filename of readdirSync(output)) {
      assert.deepEqual(readFileSync(join(output, filename)), readFileSync(join(second, filename)), `${filename}: second build`);
    }
    const cfg = join(temp, 'autoId.cfg');
    const lines = manifest.auto_assigned.map((record, index) => `${record.id}:${51010 + index}`);
    writeFileSync(cfg, ['# Isolated runtime-ID fixture', 'nextSigned:52000', 'nextFull:59000', ...lines].join('\n') + '\n');
    const reconciled = join(temp, 'reconciled');
    run(['python3', 'scripts/fsod_assets/extract.py', '--source', source, '--output', reconciled, '--auto-id-config', cfg]);
    const result = JSON.parse(readFileSync(join(reconciled, 'manifest.json')));
    assert.equal(result.auto_id_mode, 'runtime-autoId.cfg');
    assert.equal(result.runtime_auto_ids_supplied, true);
    assert.deepEqual(result.auto_assigned.map(record => record.type), [51010, 51011, 51012]);
    const updated = JSON.parse(readFileSync(join(reconciled, 'objects.json')));
    for (const type of [51010, 51011, 51012]) assert.ok(Object.hasOwn(updated, String(type)));
    for (const type of [50000, 50001, 50002]) assert.equal(Object.hasOwn(updated, String(type)), false);
  } finally {
    rmSync(temp, { recursive: true, force: true });
  }
});
