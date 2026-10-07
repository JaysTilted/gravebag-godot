#!/usr/bin/env python3
"""Truthful local acceptance readback; no credentials, profiles or DB reads."""
import argparse
import hashlib
import json
import re
import shutil
import struct
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STATE = ROOT / 'scripts/fsod_backend/.state'
RECORD = STATE / 'play-acceptance.json'
PATTERNS = {
    'combat': r'FSOD LIVE COMBAT PASS realm=true original_server_xp=\d+ hp=\d+ ticks=\d+ frames=[1-9]\d*',
    'damage': r'FSOD LIVE DAMAGE PASS original_server_hp=\d+ maximum=\d+ realm=true',
    'loot': r'FSOD LIVE LOOT PASS original_server_item=\d+ inventory_slot=\d+ source_bag=\d+',
    'recovery': r'FSOD LIVE RECOVERY PASS dead_character_id=(\d+) new_character_id=(\d+) original_server=true',
}
FRAMES = {'combat': '04-original-combat.png', 'damage': '05-original-damage.png', 'loot': '06-original-loot.png', 'recovery': '07-original-recovery.png'}
ERRORS = r'SCRIPT ERROR|Parse Error|FSOD LIVE FAIL|FSOD CLIENT NOT READY|Unhandled Exception'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(*argv):
    return subprocess.check_output(argv, cwd=ROOT, text=True, timeout=20).strip()


def head():
    return command('git', 'rev-parse', 'HEAD')


def source_hashes():
    files = command('git', 'ls-files', 'src/client/fsod', 'src/game', 'src/net/fsod', 'src/net/fsod_inventory', 'project.godot', 'src/main.gd', 'scripts/fsod_backend/lifecycle.patch', 'scripts/fsod_backend/linux-isolation.patch', 'scripts/fsod_play').splitlines()
    return {file: sha(ROOT / file) for file in files}


def check_staging(hashes):
    for file, digest in hashes.items():
        if file.startswith('src/') or file == 'project.godot':
            staged = STATE / 'client' / file
            if not staged.is_file() or sha(staged) != digest:
                raise ValueError(f'staged client differs from tested source: {file}')


def runtime_hashes():
    manifest = json.loads((STATE / 'manifest.json').read_text())
    if manifest.get('source_revision') != '6fd20aad4a7905b13f25389c68368a942a2b68cb':
        raise ValueError('runtime is not the pinned whole original backend')
    for patch, key in [('linux-isolation.patch', 'patch_sha256'), ('lifecycle.patch', 'lifecycle_patch_sha256')]:
        if manifest.get(key) != sha(ROOT / 'scripts/fsod_backend' / patch):
            raise ValueError(f'runtime has not built current infrastructure overlay: {patch}')
    files = ['manifest.json', 'source/bin/Debug/autoId.cfg', 'source/bin/Debug/wServer.exe', 'source/bin/Debug/db.dll']
    return {file: sha(STATE / file) for file in files}


def png_dimensions(path):
    with path.open('rb') as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != b'\x89PNG\r\n\x1a\n' or header[12:16] != b'IHDR':
        raise ValueError('not a PNG frame')
    return struct.unpack('>II', header[16:24])


def validate_run(kind, result, log):
    if result.get('exit_code') != 0 or result.get('timed_out') is not False:
        raise ValueError(f'{kind}: process did not exit successfully within its bound')
    if re.search(ERRORS, log, re.I):
        raise ValueError(f'{kind}: gameplay/script failure present')
    if 'FSOD LIVE REALM ' not in log or not re.search(PATTERNS[kind], log):
        raise ValueError(f'{kind}: actual realm/result evidence missing')
    if kind == 'recovery':
        ids = re.search(PATTERNS[kind], log).groups()
        if ids[0] == ids[1] or 'FSOD LIVE DEATH original_server=true visited_realm=true' not in log:
            raise ValueError('recovery: death/new-character source evidence missing or old ID reused')
    if kind == 'loot' and 'FSOD LIVE LOOT REQUEST ' not in log:
        raise ValueError('loot: request/readback pair missing')
    if f'FSOD LIVE FRAME {Path(FRAMES[kind]).stem} 1280x720' not in log:
        raise ValueError(f'{kind}: real rendered capture evidence missing')


def stage():
    # Only code/resources: retain the authentic runtime's exported AutoAssign data.
    for directory in ('client', 'game', 'net'):
        shutil.copytree(ROOT / 'src' / directory, STATE / 'client/src' / directory, dirs_exist_ok=True)
    for file in ('project.godot', 'src/main.gd', 'src/main.gd.uid', 'src/main.tscn'):
        source = ROOT / file
        if source.is_file(): shutil.copy2(source, STATE / 'client' / file)
    hashes = source_hashes()
    check_staging(hashes)
    (STATE / 'play-stage.json').write_text(json.dumps({'head': head(), 'source_sha256': hashes, 'runtime_sha256': runtime_hashes(), 'started_at': time.time()}, indent=2) + '\n')
    print('FSOD PLAY STAGED: original runtime metadata retained, tested client source pinned')


def collect(args):
    hashes = source_hashes()
    check_staging(hashes)
    staged = json.loads((STATE / 'play-stage.json').read_text())
    if staged['head'] != head() or staged['source_sha256'] != hashes or staged['runtime_sha256'] != runtime_hashes():
        raise ValueError('client changed since staging; replay the tested build')
    records = {}
    for kind in PATTERNS:
        identifier = getattr(args, kind)
        if not re.fullmatch('[0-9a-f]{32}', identifier):
            raise ValueError('invalid original-server exec ID')
        result_path = STATE / f'exec-{identifier}.json'
        log_path = STATE / f'exec-{identifier}.log'
        if min(result_path.stat().st_mtime, log_path.stat().st_mtime) < staged['started_at']:
            raise ValueError(f'{kind}: cannot reuse an older build/runtime proof')
        result = json.loads(result_path.read_text())
        log = log_path.read_text()
        validate_run(kind, result, log)
        frame = STATE / 'live-frames' / FRAMES[kind]
        if frame.stat().st_mtime < staged['started_at']:
            raise ValueError(f'{kind}: stale rendered frame')
        if png_dimensions(frame) != (1280, 720):
            raise ValueError(f'{kind}: unexpected render dimensions')
        destination = STATE / 'play-proof' / head() / FRAMES[kind]
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(frame, destination)
        records[kind] = {'id': identifier, 'log_sha256': sha(log_path), 'result_sha256': sha(result_path), 'frame': str(destination.relative_to(STATE)), 'frame_sha256': sha(destination)}
    receipt = {'head': head(), 'source_sha256': hashes, 'runtime_sha256': runtime_hashes(), 'runs': records}
    RECORD.write_text(json.dumps(receipt, indent=2) + '\n')
    print('FSOD PLAY RUNTIME RECORDED: real combat, damage, loot, death/new-character recovery and 4 rendered frames')


def verify(require_window=False):
    receipt = json.loads(RECORD.read_text())
    if receipt['head'] != head() or receipt['source_sha256'] != source_hashes():
        raise ValueError('runtime evidence is stale against current exact source/HEAD')
    check_staging(receipt['source_sha256'])
    if receipt['runtime_sha256'] != runtime_hashes():
        raise ValueError('runtime binaries/overlay/ID data changed since acceptance')
    if set(receipt['runs']) != set(PATTERNS):
        raise ValueError('missing runtime acceptance family')
    for kind, record in receipt['runs'].items():
        identifier = record['id']
        if not re.fullmatch('[0-9a-f]{32}', identifier):
            raise ValueError('invalid stored run ID')
        log = STATE / f'exec-{identifier}.log'
        result = STATE / f'exec-{identifier}.json'
        if sha(log) != record['log_sha256'] or sha(result) != record['result_sha256']:
            raise ValueError('changed runtime evidence')
        validate_run(kind, json.loads(result.read_text()), log.read_text())
        frame = STATE / record['frame']
        if not frame.resolve().is_relative_to(STATE.resolve()) or sha(frame) != record['frame_sha256'] or png_dimensions(frame) != (1280, 720):
            raise ValueError('missing or altered real rendered frame')
    if require_window:
        launch = json.loads((STATE / 'play-window.json').read_text())
        if launch['head'] != head():
            raise ValueError('window launched from stale build')
        log = Path(launch['log'])
        text = log.read_text()
        states = re.findall(r'^FSOD CLIENT STATE (\w+)$', text, re.M)
        ready = re.search(r'FSOD CLIENT READY player_id=\d+ character_id=\d+ hp=[1-9]\d* entities=[1-9]\d* tiles=[1-9]\d*', text)
        if 'FSOD CLIENT PLAYING' not in text or not ready or not states or states[-1] != 'playing' or re.search(ERRORS, text, re.I):
            raise ValueError('window has not reached current server-authorized local-player/tile readiness')
        pid = int(launch['pid'])
        argv = Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')
        if b'--fsod-client' not in argv or str(STATE / 'client').encode() not in argv:
            raise ValueError('recorded game process is not the intended running client')
        namespace = Path(f'/proc/{pid}/ns/net').readlink()
        if namespace == Path('/proc/self/ns/net').readlink():
            raise ValueError('game is not in isolated backend network namespace')
        lines = command('wmctrl', '-lp').splitlines()
        if not any(int(line.split()[2]) == pid and 'GRAVEBAG' in line for line in lines if len(line.split()) >= 4):
            raise ValueError('running game has no visible desktop window')
        backend = json.loads(command('python3', str(ROOT / 'scripts/fsod_backend/backend.py'), 'verify'))
        if backend.get('ready') is not True:
            raise ValueError('original backend is not currently ready')
    print('FSOD PLAYABLE PASS: exact tested build, original realm combat/damage/loot/recovery, rendered-frame artifacts' + (', visible server-authorized window' if require_window else ''))


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='action', required=True)
    sub.add_parser('stage')
    collect_parser = sub.add_parser('collect')
    for kind in PATTERNS:
        collect_parser.add_argument('--' + kind, required=True)
    verify_parser = sub.add_parser('verify')
    verify_parser.add_argument('--window', action='store_true')
    args = parser.parse_args()
    try:
        if args.action == 'stage': stage()
        elif args.action == 'collect': collect(args)
        else: verify(args.window)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        parser.exit(1, f'FSOD PLAYABLE FAIL: {error}\n')


if __name__ == '__main__': main()
