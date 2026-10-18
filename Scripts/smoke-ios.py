#!/usr/bin/env python3
"""Check that normal and container-mode cold launches stay alive on a simulator."""
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys

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
    return subprocess.run(['xcrun', 'simctl', *args], check=True, **kwargs)

simctl('install', device, app_path)
for mode in ['native', 'container']:
    environment = os.environ.copy()
    environment.pop('SIMCTL_CHILD_LC_HOME_PATH', None)
    environment.pop('SIMCTL_CHILD_LP_HOME_PATH', None)
    if mode == 'container':
        # Exercises our fallback only. This does not reproduce LiveContainer's loader.
        environment['SIMCTL_CHILD_LC_HOME_PATH'] = '/tmp/fantasyglass-container-probe'
    with (output / f'{mode}.log').open('w') as log:
        process = subprocess.Popen(
            ['xcrun', 'simctl', 'launch', '--terminate-running-process', '--console', device, bundle],
            env=environment, stdout=log, stderr=subprocess.STDOUT)
        try:
            try:
                code = process.wait(timeout=12)
            except subprocess.TimeoutExpired:
                simctl('io', device, 'screenshot', str(output / f'{mode}.png'))
                print(f'{mode}: app remained running for 12 seconds; screenshot captured.', flush=True)
            else:
                log.flush()
                print((output / f'{mode}.log').read_text(), file=sys.stderr, flush=True)
                raise RuntimeError(f'{mode}: app exited during launch (code {code}); inspect {mode}.log')
        finally:
            subprocess.run(['xcrun', 'simctl', 'terminate', device, bundle], check=False)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=5)
