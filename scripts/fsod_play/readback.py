#!/usr/bin/env python3
"""Single-probe visible game/readiness check. Caller owns bounded watch."""
import argparse
import json
import os
from pathlib import Path
import subprocess

from launch import backend_process
from verify import STATE, ERRORS, head, verify
import re


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--focus', action='store_true')
    args = parser.parse_args()
    try:
        if os.environ.get('DISPLAY') != ':1': raise ValueError('desktop display unavailable')
        launch = json.loads((STATE / 'play-launch.json').read_text())
        if launch['head'] != head(): raise ValueError('launch is stale')
        text = Path(launch['log']).read_text()
        if re.search(ERRORS, text, re.I): raise ValueError('client reported failure')
        if 'FSOD CLIENT READY ' not in text: raise ValueError('still waiting for original server local player and tiles')
        supervisor_namespace = Path(f'/proc/{backend_process()}/ns/net').readlink()
        lines = subprocess.check_output(['wmctrl', '-lp'], text=True, timeout=5).splitlines()
        for line in lines:
            columns = line.split()
            if len(columns) < 4 or 'GRAVEBAG' not in line: continue
            pid = int(columns[2])
            try:
                argv = Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')
                if b'--fsod-client' not in argv or str(STATE / 'client').encode() not in argv: continue
                if Path(f'/proc/{pid}/ns/net').readlink() != supervisor_namespace: continue
                status = Path(f'/proc/{pid}/status').read_text()
                if not re.search(r'^Uid:\s+1000\s+1000\s+1000\s+1000$', status, re.M):
                    raise ValueError('game did not drop operator privileges')
                window = columns[0]
                (STATE / 'play-window.json').write_text(json.dumps({'head': head(), 'pid': pid, 'window': window, 'log': launch['log']}, indent=2) + '\n')
                verify(require_window=True)
                if args.focus:
                    subprocess.run(['wmctrl', '-i', '-r', window, '-T', 'GRAVEBAG — ORIGINAL BACKEND'], check=True, timeout=5)
                    subprocess.run(['wmctrl', '-i', '-a', window], check=True, timeout=5)
                return
            except FileNotFoundError: continue
        raise ValueError('server client has no live visible window yet')
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        parser.exit(1, f'FSOD PLAY READBACK FAIL: {error}\n')


if __name__ == '__main__': main()
