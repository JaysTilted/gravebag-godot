import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync, spawn } from 'node:child_process';
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
const hash = data => createHash('sha256').update(data).digest('hex');
const original = path => execFileSync('git', ['-C', source, 'show', `${revision}:${path}`], { maxBuffer: 8 * 1024 * 1024 });
const changed = ['wServer/networking/Client.cs', 'wServer/realm/RealmManager.cs',
  'wServer/realm/NetworkTicker.cs', 'wServer/realm/entities/player/Player.cs', 'wServer/networking/Server.cs',
  'wServer/networking/handlers/HelloHandler.cs'];

function fixture() {
  const temp = mkdtempSync(join(tmpdir(), 'fsod-lifecycle-'));
  const runner = join(temp, 'backend');
  mkdirSync(runner);
  for (const file of ['backend.py', 'linux-isolation.patch', 'lifecycle.patch', 'dependencies.lock.json', 'MetadataIds.cs']) {
    copyFileSync(join(overlay, file), join(runner, file));
  }
  return { temp, runner };
}
function run(file, args, options = {}) {
  const result = spawnSync(file, args, { encoding: 'utf8', timeout: 150000, maxBuffer: 8 * 1024 * 1024, ...options });
  assert.equal(result.error, undefined, `${file}: ${result.error}`);
  assert.equal(result.status, 0, `${file}: ${result.stdout?.slice(-4000)}\n${result.stderr?.slice(-4000)}`);
  return result.stdout;
}
// The tested manager bodies are copied verbatim from the patched pinned source,
// NOT a fixture rewrite of teardown/registry behavior. Full build below also
// compiles the entire original manager and Player against the real dependencies.
function managerMethods(text) {
  const lifecycleStart = text.indexOf('        public Task Disconnect(Client client)');
  const lifecycleEnd = text.indexOf('        public Player FindPlayer(', lifecycleStart);
  const connectStart = text.indexOf('        public bool TryConnect(Client psr)');
  const connectEnd = text.indexOf('        private void OnWorldAdded(', connectStart);
  assert.ok(lifecycleStart >= 0 && lifecycleEnd > lifecycleStart && connectStart > 0 && connectEnd > connectStart);
  const stopStart = text.indexOf('        public void Stop()');
  assert.ok(stopStart > lifecycleEnd && stopStart < connectStart);
  return `using System;\nusing System.Collections.Generic;\nusing System.Linq;\nusing System.Threading;\nusing System.Threading.Tasks;\nusing db.JsonObjects;\nusing wServer.networking;\nnamespace wServer.realm { public partial class RealmManager {\n${text.slice(lifecycleStart, lifecycleEnd)}\n${text.slice(stopStart, connectEnd)}\n} }\n`;
}

test('compiled original C# lifecycle forces save/dispose/logout/reconnect/packet/failure interleavings', { timeout: 180000 }, () => {
  const { temp } = fixture();
  try {
    assert.equal(run('git', ['-C', source, 'rev-parse', 'HEAD']).trim(), revision);
    for (const path of changed) {
      mkdirSync(dirname(join(temp, path)), { recursive: true });
      writeFileSync(join(temp, path), original(path));
    }
    run('patch', ['--batch', '--forward', '-p1', '-i', join(overlay, 'lifecycle.patch')], { cwd: temp });
    writeFileSync(join(temp, 'ManagerLifecycle.cs'), managerMethods(readFileSync(join(temp, changed[1]), 'utf8')));
    const exe = join(temp, 'LifecycleRegression.exe');
    run('mcs', ['-r:System.Drawing', '-out:' + exe, join(temp, changed[0]), join(temp, changed[2]),
      join(temp, changed[4]), join(temp, 'ManagerLifecycle.cs'), join(overlay, 'tests/LifecycleRegression.cs')]);
    const result = run('mono', [exe], { timeout: 30000 });
    assert.match(result, /compiled-original-lifecycle: PASS \(15 forced interleavings\)/);
    console.log(result.trim());
    // Negative controls prove that these compiled probes detect the original
    // classes of defect rather than merely compiling the happy path.
    const managerFile = join(temp, 'ManagerLifecycle.cs');
    const managerBaseline = readFileSync(managerFile, 'utf8');
    const pairRemove = 'return ((ICollection<KeyValuePair<string, Client>>)Clients).Remove(\n                new KeyValuePair<string, Client>(accountId, client));';
    assert.ok(managerBaseline.includes(pairRemove));
    // Death-recovery barrier: HELLO must join SAME-ACCOUNT departing save+unlock+removal
    // before CheckAccountInUse/registration; alive still rejects; no kick/unlock-before-save.
    assert.ok(managerBaseline.includes('DepartureTaskFor'), 'RealmManager.DepartureTaskFor joins departing save+unlock+removal');
    assert.ok(managerBaseline.includes('IsDeparting'), 'RealmManager peeks departing vs alive without kicking');
    assert.ok(readFileSync(join(temp, changed[0]), 'utf8').includes('IsDeparting'), 'Client.IsDeparting distinguishes departing vs alive');
    assert.ok(readFileSync(join(temp, changed[0]), 'utf8').includes('MarkDeathDeparting'), 'Client marks exact DEATH moment, never infers HP0, never kicks living');
    const helloPatched = readFileSync(join(temp, changed[5]), 'utf8');
    assert.ok(helloPatched.includes('DepartureTaskFor'), 'Hello joins departure before CheckAccountInUse');
    assert.ok(helloPatched.includes('CheckAccountInUse'), 'Hello still gates on CheckAccountInUse after departure');
    assert.ok(helloPatched.includes('Task.WhenAny') && helloPatched.includes('Task.Delay'), 'Hello departure wait bounded, never hangs logic/DB queues');
    assert.ok(helloPatched.includes('RunSessionAction'), 'Hello phases stay behind teardown barrier');
    const regressionText = readFileSync(join(overlay, 'tests/LifecycleRegression.cs'), 'utf8');
    assert.ok(regressionText.includes('DeathHelloBarrier') && regressionText.includes('HelloLiveReject') && regressionText.includes('HelloSaveFailLocked') && regressionText.includes('EarlyDeathHelloBeforeDisconnect'), 'death-HELLO while Save pending, live reject, save-fail locked, early DeathRow covered');
    writeFileSync(managerFile, managerBaseline.replace(pairRemove, 'Client removed; return Clients.TryRemove(accountId, out removed);'));
    const compile = () => run('mcs', ['-r:System.Drawing', '-out:' + exe, join(temp, changed[0]), join(temp, changed[2]),
      join(temp, changed[4]), managerFile, join(overlay, 'tests/LifecycleRegression.cs')]);
    compile();
    const wrongRemoval = spawnSync('mono', [exe], { encoding: 'utf8', timeout: 30000 });
    assert.equal(wrongRemoval.error, undefined);
    assert.notEqual(wrongRemoval.status, 0);
    assert.match(wrongRemoval.stderr, /old completion cannot remove newer same-account client/);
    writeFileSync(managerFile, managerBaseline);
    const clientFile = join(temp, changed[0]);
    const clientBaseline = readFileSync(clientFile, 'utf8');
    const deferredDispose = 'public void Dispose()\n        {\n            Disconnect();\n        }';
    assert.ok(clientBaseline.includes(deferredDispose));
    writeFileSync(clientFile, clientBaseline.replace(deferredDispose,
      'public void Dispose()\n        {\n            Account = null; Character = null; Player = null;\n            Disconnect();\n        }'));
    compile();
    const earlyDispose = spawnSync('mono', [exe], { encoding: 'utf8', timeout: 30000 });
    assert.equal(earlyDispose.error, undefined);
    assert.notEqual(earlyDispose.status, 0);
    assert.match(earlyDispose.stderr, /public Dispose defers field release/);
    writeFileSync(clientFile, clientBaseline);
    // Death-HELLO negative control: without the departure join (always null, never wait),
    // immediate DEATH new HELLO must fail its barrier instead of registering early.
    writeFileSync(managerFile, managerBaseline.replace('if (!previous.IsDeparting) return null;', 'return null;'));
    compile();
    const noJoin = spawnSync('mono', [exe], { encoding: 'utf8', timeout: 30000 });
    assert.equal(noJoin.error, undefined);
    assert.notEqual(noJoin.status, 0);
    assert.match(noJoin.stderr, /HELLO must join departing save/);
    writeFileSync(managerFile, managerBaseline);
    compile();
    console.log('compiled negative controls: PASS; key-only removal, early disposal, and missing departure join all rejected');
    // Player patch is lifecycle-only: two Tick teardown unlocks become Disconnect,
    // Death marks exact DEATH moment and tracks DeathRow via RunSessionAction so the
    // departing terminal Save joins after it. No Tick/Death gameplay, timer, LeaveWorld,
    // SaveToCharacter, AI or fields change; no death-row wipe.
    const playerPatched = readFileSync(join(temp, changed[3]), 'utf8');
    assert.ok(!playerPatched.includes('UnlockAccount'), 'no unlock-before-save, no kick');
    assert.ok(playerPatched.includes('Client.Disconnect();'), 'Tick teardowns transfer to lifecycle owner');
    assert.ok(playerPatched.includes('MarkDeathDeparting'), 'exact DEATH moment flagged, never HP0-inferred');
    assert.ok(playerPatched.includes('RunSessionAction'), 'DeathRow tracked behind teardown barrier');
    assert.ok(playerPatched.includes('db.Death(') && playerPatched.includes('SaveToCharacter()'), 'Death Save/Death mapping preserved');
    assert.ok(playerPatched.includes('DeathPacket') && playerPatched.includes('WorldTimer(1000') && playerPatched.includes('LeaveWorld'), 'original 1s timer/DeathPacket/LeaveWorld unchanged');
  } finally { rmSync(temp, { recursive: true, force: true }); }
});

test('normal backend build applies both overlays and compiles original projects without touching parent state',
  { timeout: 240000 }, () => {
    const { temp, runner } = fixture();
    try {
      const output = run('python3', [join(runner, 'backend.py'), 'build', '--source', source,
        '--dependencies', '/home/jay/.nuget/packages'], { timeout: 210000 });
      const manifest = JSON.parse(output);
      assert.equal(manifest.build, 'pass');
      assert.equal(manifest.source_revision, revision);
      assert.equal(manifest.lifecycle_patch_sha256, hash(readFileSync(join(overlay, 'lifecycle.patch'))));
      assert.equal(manifest.patch_sha256, hash(readFileSync(join(overlay, 'linux-isolation.patch'))));
      const tree = join(runner, '.state/source');
      for (const path of ['bin/Debug/wServer.exe', 'bin/Debug/server.exe', 'terrain/bin/Debug/terrain.exe']) {
        assert.ok(existsSync(join(tree, path)), path);
      }
      for (const path of ['DungeonGen/Generator.cs', 'DungeonGen/RoomCollision.cs', 'DungeonGen/Dungeon/Room.cs',
        'terrain/Biome.cs', 'terrain/Noise.cs', 'terrain/MapFeatures.cs', 'wServer/logic/db/BehaviorDb.PirateCave.cs',
        'wServer/realm/Oryx.cs', 'db/data/dat0.xml', 'wServer/realm/RealmPortalMonitor.cs',
        'wServer/networking/handlers/UsePortalHandler.cs']) {
        assert.equal(hash(readFileSync(join(tree, path))), hash(original(path)), `${path}: original content unchanged`);
      }
      assert.ok(!existsSync(join(runner, '.state/control.sock')), 'build only: no DB or runtime launched');
      console.log('isolated original full build: PASS; both overlay hashes recorded; 11 content/AI/portal sources unchanged');
    } finally { rmSync(temp, { recursive: true, force: true }); }
  });

test('stop is idempotent after crash-cleaned socket, verify reports not ready, and startup is not falsely stopped',
  { timeout: 15000 }, async () => {
    const { temp, runner } = fixture();
    const invoke = command => spawnSync('python3', [join(runner, 'backend.py'), command], {
      encoding: 'utf8', timeout: 5000,
    });
    let fakeLaunch;
    try {
      for (let i = 0; i < 2; i++) {
        const stopped = invoke('stop');
        assert.equal(stopped.status, 0, stopped.stderr);
        assert.deepEqual(JSON.parse(stopped.stdout), {
          stop: 'already_stopped', control: 'unavailable', supervisor_alive: false,
        });
      }
      const unavailable = invoke('verify');
      assert.equal(unavailable.status, 1);
      assert.equal(JSON.parse(unavailable.stdout).ready, false);
      assert.equal(unavailable.stderr, '', 'no misleading missing-file error');
      const state = join(runner, '.state');
      mkdirSync(state);
      // No listener or backend: bounded owned fixture whose argv models only
      // the supervisor identity check during the pre-control startup window.
      fakeLaunch = spawn('python3', ['-c', 'import sys; sys.stdin.read()', state, '/state/supervisor.py'],
        { stdio: ['pipe', 'ignore', 'ignore'] });
      await new Promise((resolve, reject) => { fakeLaunch.once('spawn', resolve); fakeLaunch.once('error', reject); });
      writeFileSync(join(state, 'launch.json'), JSON.stringify({ pid: fakeLaunch.pid }));
      const starting = invoke('stop');
      assert.equal(starting.status, 1);
      assert.deepEqual(JSON.parse(starting.stdout), {
        stop: 'unavailable', control: 'unavailable', supervisor_alive: true,
      });
      const notReady = invoke('verify');
      assert.equal(notReady.status, 1);
      assert.equal(JSON.parse(notReady.stdout).supervisor_alive, true);
      // Reused/stale PID without the exact state-bound argv is not our process.
      writeFileSync(join(state, 'launch.json'), JSON.stringify({ pid: process.pid }));
      assert.equal(JSON.parse(invoke('stop').stdout).stop, 'already_stopped');
    } finally {
      if (fakeLaunch && fakeLaunch.exitCode === null) {
        const exited = new Promise(resolve => fakeLaunch.once('exit', resolve));
        fakeLaunch.kill('SIGKILL');
        await exited;
      }
      rmSync(temp, { recursive: true, force: true });
    }
  });
