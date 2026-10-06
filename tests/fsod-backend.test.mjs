import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, watch } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const state = join(root, 'scripts/fsod_backend/.state');
const runner = join(root, 'scripts/fsod_backend/backend.py');
// Explicit, pinned offline fixtures; HOME is not used for packages, plans,
// config or operator data. Integrated trees prefer their pinned submodule.
const source = existsSync(join(root, 'references/fsod/wServer/wServer.csproj'))
  ? join(root, 'references/fsod') : '/home/jay/fsod-ref';
const dependencies = '/home/jay/.nuget/packages';
const revision = '6fd20aad4a7905b13f25389c68368a942a2b68cb';
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const invoke = (command, args = [], timeout = 150000) => JSON.parse(execFileSync(
  'python3', [runner, command, ...args], { cwd: root, timeout, encoding: 'utf8', maxBuffer: 1024 * 1024 }
));

// Event-driven file notifications, not sleep/poll readiness loops. Every wait
// is bounded by both deadline and event count, and watchers always close.
function fileCondition(condition, timeoutMs, maxEvents) {
  return new Promise((resolve, reject) => {
    let events = 0;
    const finish = error => {
      clearTimeout(timer);
      watcher.close();
      if (error) reject(error); else resolve();
    };
    const check = () => {
      if (condition()) finish();
      else if (++events >= maxEvents) finish(new Error('file-event cap reached'));
    };
    const watcher = watch(state, check);
    const timer = setTimeout(() => finish(new Error('file-event deadline reached')), timeoutMs);
    check();
  });
}

test('original complete FSoD backend builds, initializes isolated DB, registers and reads account, runs full realm, stops',
  { timeout: 300000 }, async () => {
    const built = invoke('build', ['--source', source, '--dependencies', dependencies]);
    assert.equal(built.build, 'pass');
    assert.equal(built.source_revision, revision);
    assert.deepEqual(built.projects, ['wServer/wServer.csproj', 'server/server.csproj', 'terrain/terrain.csproj']);
    for (const name of ['wServer.exe', 'server.exe', 'db.dll', 'DungeonGen.dll']) {
      assert.ok(existsSync(join(state, 'source/bin/Debug', name)), name);
    }
    assert.ok(existsSync(join(state, 'source/terrain/bin/Debug/terrain.exe')));
    // Algorithm/content source remains byte-identical, including provenance.
    for (const path of ['DungeonGen/Generator.cs', 'DungeonGen/RoomCollision.cs',
      'DungeonGen/Dungeon/Room.cs', 'terrain/Biome.cs', 'terrain/Noise.cs',
      'terrain/MapFeatures.cs', 'wServer/logic/db/BehaviorDb.PirateCave.cs',
      'wServer/realm/Oryx.cs', 'db/data/dat0.xml']) {
      const original = execFileSync('git', ['-C', source, 'show', `${revision}:${path}`], { maxBuffer: 8 * 1024 * 1024 });
      assert.equal(sha(readFileSync(join(state, 'source', path))), sha(original), path);
    }
    assert.ok(existsSync(join(state, 'source/bin/Debug/autoId.cfg')), 'original XmlData persisted authentic IDs before server start');
    const schema = readFileSync(join(state, 'schema.sql'), 'utf8');
    assert.equal((schema.match(/CREATE TABLE/gi) || []).length, 19);
    assert.doesNotMatch(schema, /INSERT\s+INTO/i, 'no original dumped accounts or payment data');
    const lock = JSON.parse(readFileSync(join(root, 'scripts/fsod_backend/dependencies.lock.json')));
    for (const entry of lock.assemblies) {
      assert.equal(sha(readFileSync(join(state, 'source/.dependencies', entry.relative_dll.split('/').at(-1)))), entry.sha256);
    }
    const bootstrap = invoke('bootstrap');
    assert.ok(['pass', 'already_initialized'].includes(bootstrap.bootstrap));
    let started = false;
    try {
      const launch = invoke('start', ['--ttl', '180']);
      started = true;
      assert.equal(launch.start, 'launched');
      assert.equal(launch.deadline_seconds, 180);
      await fileCondition(() => existsSync(join(state, 'ready-hint')), 90000, 512);
      const verified = invoke('verify', [], 15000);
      assert.equal(verified.ready, true);
      assert.deepEqual(verified.alive, { database: true, server: true, wServer: true });
      assert.equal(verified.network, 'private-loopback-only');
      assert.equal(verified.schema_tables, 19);
      assert.equal(verified.account_response_is_chars, true);
      assert.equal(verified.policy_response, true);
      assert.equal(verified.original_realm_initialized, true);
      const realmLog = readFileSync(join(state, 'wServer-runtime.log'), 'utf8');
      assert.match(realmLog, /Loading behavior for 'UndeadLair'\(47\/47\)/);
      for (const dungeon of ['Abyss of Demons', 'Mad Lab', 'Pirate Cave']) {
        assert.ok(realmLog.includes(`Generating cache for dungeon: ${dungeon}`));
      }
      assert.match(realmLog, /2232 Objects/);
      assert.match(realmLog, /Spawning minions/);
      assert.match(realmLog, /Set pieces applied/);
      assert.doesNotMatch(realmLog, /ColoredConsoleAppender|FATAL UNHANDLED|GetConsoleOutputCP/);
      const caller = invoke('exec', ['--timeout', '15', '--', 'python3', '-c',
        'import json,urllib.request,xml.etree.ElementTree as E; p=urllib.request.urlopen("http://127.0.0.1:18080/char/list?guid=fsod-fixture%40gmail.invalid&password=local-only").read(); print(json.dumps({"namespaceHttp":E.fromstring(p).tag=="Chars","routes":len(open("/proc/net/route").read().splitlines())-1}))']);
      assert.equal(caller.exec, 'launched');
      const callerResult = join(state, `exec-${caller.id}.json`);
      await fileCondition(() => existsSync(callerResult), 20000, 128);
      assert.equal(JSON.parse(readFileSync(callerResult)).exit_code, 0);
      const callerProof = JSON.parse(readFileSync(join(state, `exec-${caller.id}.log`)));
      assert.deepEqual(callerProof, { namespaceHttp: true, routes: 0 });
      console.log(JSON.stringify({ fullBackend: 'pass', runtime: verified, namespaceCaller: callerProof, preservedAlgorithms: 10 }));
    } finally {
      if (started && existsSync(join(state, 'control.sock'))) {
        assert.equal(invoke('stop', [], 15000).stop, 'accepted');
        await fileCondition(() => !existsSync(join(state, 'control.sock')), 15000, 128);
      }
    }
    assert.ok(!existsSync(join(state, 'control.sock')), 'no owned runtime left running');
  });
