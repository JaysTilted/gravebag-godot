import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const source = resolve(process.env.FSOD_SOURCE || resolve(root, 'references/fsod'));
const bin = resolve(source, 'bin/Debug');
function run(command, args, options = {}) {
  const result = spawnSync(command, args, { encoding: 'utf8', timeout: 120000, ...options });
  assert.ifError(result.error);
  assert.equal(result.status, 0, `${command} failed: ${result.stdout}\n${result.stderr}`);
  return result.stdout;
}

test('original backend writers produce exact client golden payloads', () => {
  assert.ok(existsSync(resolve(source, 'wServer/wServer.csproj')), 'restore pinned backend submodule first');
  // Compile original source rather than trust a bundled/preexisting executable.
  run('xbuild', ['wServer/wServer.csproj', '/p:Configuration=Debug', '/verbosity:minimal'], { cwd: source });
  const scratch = mkdtempSync(resolve(tmpdir(), 'gravebag-oracle-'));
  try {
    const exe = resolve(scratch, 'Oracle.exe');
    run('mcs', [`-out:${exe}`, `-r:${resolve(bin, 'wServer.exe')}`, `-r:${resolve(bin, 'db.dll')}`, resolve(root, 'scripts/fsod_protocol_oracle/Oracle.cs')]);
    const output = run('mono', [exe], { env: { ...process.env, MONO_PATH: bin } });
    const cases = Object.fromEntries(output.trim().split('\n').map(line => {
      const [name, id, hex] = line.trim().split('\t');
      return [name, { id: Number(id), hex }];
    }));
    const expected = {
      map_info_xml32: { id: 65, hex: '000000640000005000054e6578757300084752415645424147000030390000000000000001010000010000000a3c4f626a656374732f3e00010000000a3c47726f756e64732f3e' },
      new_tick_utf_stats: { id: 80, hex: '00000007000000c80001000004d241480000c0500000000701000000571f00084772617665626167260002343236000234333e00054e65787573520004736b696e0000000064' },
      update_objects: { id: 7, hex: '0001000c000901230001030e000004d241480000c0500000000701000000571f00084772617665626167260002343236000234333e00054e65787573520004736b696e000000006400020000002c0000002d' },
    };
    assert.deepEqual(cases, expected);
    // XML arrays really use 32-bit lengths; ObjectStats UTF IDs are source WRITE semantics.
    assert.ok(cases.map_info_xml32.hex.includes('0000000a3c4f626a656374732f3e'));
    assert.ok(cases.new_tick_utf_stats.hex.includes('260002343236000234333e00054e65787573520004736b696e'));
  } finally { rmSync(scratch, { recursive: true, force: true }); }
});
