import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cpSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

// Real Godot import + protocol fixtures, independent of operator HOME/class cache.
// Only protocol sources copied; never copy private profiles, databases or live sockets.
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const godot = process.env.GODOT_BIN || '/home/jay/.local/bin/Godot_v4.6-stable_linux.x86_64';
const logs = join(root, 'src/net/fsod/.test-output');

test('Godot4.6 original FSoD wire codecs, directional RC4, bounds and TCP acknowledgements', { timeout: 150000 }, () => {
  const scratch = mkdtempSync(join(tmpdir(), 'fsod-network-build-'));
  mkdirSync(logs, { recursive: true });
  try {
    const project = join(scratch, 'project');
    const home = join(scratch, 'home');
    mkdirSync(home);
    mkdirSync(join(project, 'src/net'), { recursive: true });
    const protocolSource = join(root, 'src/net/fsod');
    cpSync(protocolSource, join(project, 'src/net/fsod'), { recursive: true, filter: source => {
      return !source.slice(protocolSource.length).split(sep).includes('.test-output');
    } });
    writeFileSync(join(project, 'project.godot'), 'config_version=5\n[application]\nconfig/name="FSoD Protocol Fixtures"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n');
    const env = { ...process.env, HOME: home, XDG_DATA_HOME: join(home, 'data'), XDG_CONFIG_HOME: join(home, 'config'), XDG_CACHE_HOME: join(home, 'cache'), TMPDIR: scratch };
    function run(name, argv, timeout) {
      const result = spawnSync(godot, argv, { cwd: project, env, encoding: 'utf8', timeout, maxBuffer: 4 * 1024 * 1024 });
      const output = `${result.stdout || ''}\n${result.stderr || ''}`;
      const path = join(logs, `${name}.log`);
      writeFileSync(path, output);
      assert.ifError(result.error);
      assert.equal(result.status, 0, `${name} rc=${result.status}; log: ${path}`);
      assert.doesNotMatch(output, /(?:SCRIPT ERROR|Parse Error|ERROR:|Failed to load)/i, `${name}; log: ${path}`);
      return output;
    }
    run('node-import', ['--headless', '--path', project, '--import'], 60000);
    const output = run('node-selftest', ['--headless', '--path', project, '-s', 'src/net/fsod/selftest.gd'], 60000);
    assert.match(output, /FSOD NETWORK PASS: \d+ checks, 0 failures/);
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
});
