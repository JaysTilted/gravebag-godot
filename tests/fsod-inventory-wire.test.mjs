// SPDX-License-Identifier: AGPL-3.0-only
// Adapter for the FSoD 6fd20aad4a7905b13f25389c68368a942a2b68cb wire fixtures.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const installedGodot = '/home/jay/.local/bin/Godot_v4.6-stable_linux.x86_64';
const godot = process.env.GODOT_BIN ?? (existsSync(installedGodot)
  ? installedGodot : 'Godot_v4.6-stable_linux.x86_64');

test('FSoD outgoing gameplay payload golden fixtures in isolated Godot project', { timeout: 120000 }, () => {
  const scratch = mkdtempSync(join(tmpdir(), 'fsod-inventory-wire-'));
  try {
    const project = join(scratch, 'project');
    const home = join(scratch, 'home');
    mkdirSync(project);
    mkdirSync(home);
    // No account data, host import cache, or operator HOME is part of this fixture.
    cpSync(join(root, 'project.godot'), join(project, 'project.godot'));
    cpSync(join(root, 'src'), join(project, 'src'), { recursive: true });
    const env = { ...process.env, HOME: home, XDG_CONFIG_HOME: join(home, '.config'),
      XDG_DATA_HOME: join(home, '.local/share'), XDG_CACHE_HOME: join(home, '.cache') };
    const run = (args, timeout) => {
      const result = spawnSync(godot, args, { cwd: project, env, encoding: 'utf8',
        timeout, killSignal: 'SIGKILL', maxBuffer: 4 * 1024 * 1024 });
      const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
      assert.equal(result.error, undefined, `Godot execution failed: ${result.error}\n${output}`);
      assert.equal(result.signal, null, `Godot terminated: ${result.signal}\n${output}`);
      assert.equal(result.status, 0, `Godot exit ${result.status}\n${output}`);
      assert.doesNotMatch(output, /SCRIPT ERROR|Parse Error|Failed to load|SELFTEST FAIL/i);
      return output;
    };
    run(['--headless', '--path', project, '--import'], 60000);
    const output = run(['--headless', '--path', project, '-s',
      'res://src/net/fsod_inventory/selftest.gd'], 30000);
    assert.match(output, /FSOD INVENTORY WIRE SELFTEST PASS: \d+ checks, 39 packet families/);
    console.log(output.trim());
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
});
