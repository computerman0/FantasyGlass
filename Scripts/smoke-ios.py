#!/usr/bin/env python3
"""Monitor actual simulator app PIDs, independent of simctl console lifetime."""
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import time

destination, app_path = sys.argv[1:3]
match = re.search(r'(?:^|,)id=([^,]+)', destination)
if not match:
    raise SystemExit('Launch checks require an explicit simulator id in the destination.')
device = match[1]
with (Path(app_path) / 'Info.plist').open('rb') as info:
    bundle = plistlib.load(info)['CFBundleIdentifier']
output = Path(__file__).resolve().parent.parent / 'build' / 'launch-checks'
output.mkdir(parents=True, exist_ok=True)

def simctl(*args, **kwargs):
    try:
        return subprocess.run(['xcrun', 'simctl', *args], check=True, **kwargs)
    except subprocess.CalledProcessError as error:
        if error.stdout:
            print(error.stdout, file=sys.stderr, flush=True)
        if error.stderr:
            print(error.stderr, file=sys.stderr, flush=True)
        raise

def print_diagnostics(mode, started):
    for path in output.glob(f'{mode}*.log'):
        print(path.read_text(), file=sys.stderr, flush=True)
    reports = Path.home() / 'Library' / 'Logs' / 'DiagnosticReports'
    for path in reports.glob('FantasyGlass*'):
        if path.is_file() and path.stat().st_mtime >= started:
            shutil.copy2(path, output / path.name)
            print(f'Crash report saved: {path.name}', file=sys.stderr, flush=True)

simctl('install', device, app_path)
for mode in ['native', 'container']:
    environment = os.environ.copy()
    environment.pop('SIMCTL_CHILD_LC_HOME_PATH', None)
    environment.pop('SIMCTL_CHILD_LP_HOME_PATH', None)
    if mode == 'container':
        # This exercises our fallback, not LiveContainer's actual binary loader.
        environment['SIMCTL_CHILD_LC_HOME_PATH'] = '/tmp/fantasyglass-container-probe'
    started = time.time()
    try:
        result = simctl('launch', '--terminate-running-process',
            f'--stdout={output / f"{mode}.stdout.log"}',
            f'--stderr={output / f"{mode}.stderr.log"}',
            device, bundle, env=environment, text=True, capture_output=True)
    except subprocess.CalledProcessError as error:
        (output / f'{mode}.launch.log').write_text((error.stdout or '') + (error.stderr or ''))
        print_diagnostics(mode, started)
        subprocess.run(['xcrun', 'simctl', 'help', 'launch'], check=False)
        raise
    (output / f'{mode}.launch.log').write_text(result.stdout + result.stderr)
    match = re.search(r':\s*(\d+)\s*$', result.stdout)
    if not match:
        print_diagnostics(mode, started)
        raise RuntimeError(f'{mode}: simulator did not report an app PID')
    pid = int(match[1])
    try:
        for _ in range(12):
            time.sleep(1)
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                print_diagnostics(mode, started)
                raise RuntimeError(f'{mode}: app PID {pid} exited during launch')
        simctl('io', device, 'screenshot', str(output / f'{mode}.png'))
        print(f'{mode}: app PID {pid} remained alive for 12 seconds; screenshot captured.', flush=True)
    finally:
        subprocess.run(['xcrun', 'simctl', 'terminate', device, bundle], check=False)
