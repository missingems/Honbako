#!/usr/bin/env python3
"""Start/stop only the isolated localhost review fixture processes."""
import argparse
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT / 'runtime'
PIDS = RUNTIME / 'processes.json'
JAVA = Path('/opt/homebrew/opt/openjdk/bin/java')
PORTS = {'komga': 39101, 'kavita': 39102, 'suwayomi': 39103, 'gateway': 39104}

def owned_process(pid):
    result = subprocess.run(['ps', '-p', str(pid), '-o', 'command='], text=True, capture_output=True)
    return result.returncode == 0 and str(RUNTIME) in result.stdout

def reachable(port):
    try:
        with socket.create_connection(('127.0.0.1', port), timeout=.2): return True
    except OSError: return False

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['start', 'status', 'stop'])
    parser.add_argument('--provider', choices=PORTS)
    args = parser.parse_args()
    state = json.loads(PIDS.read_text()) if PIDS.exists() else {}
    providers = [args.provider] if args.provider else list(PORTS)
    for name in providers:
        record = state.get(name, {})
        running = bool(record.get('pid') and owned_process(record['pid']))
        if args.action == 'stop' and running:
            os.kill(record['pid'], signal.SIGTERM)
            for _ in range(100):
                if not owned_process(record['pid']): break
                time.sleep(.1)
            if owned_process(record['pid']): raise RuntimeError(name + ': still shutting down; no force kill was sent')
            state.pop(name, None)
        elif args.action == 'start' and not running:
            if reachable(PORTS[name]): raise RuntimeError(name + ': fixture port already in use; refusing to affect another server')
            if name == 'komga':
                cmd = [str(JAVA), '-Xms32m', '-Xmx512m', '-XX:ActiveProcessorCount=2', '-jar', str(RUNTIME/'komga-1.29.2.jar'), '--komga.config-dir='+str(RUNTIME/'komga'), '--server.address=127.0.0.1', '--server.port=39101']
                cwd = RUNTIME/'komga'
            elif name == 'suwayomi':
                cmd = [str(JAVA), '-Xms32m', '-Xmx512m', '-XX:ActiveProcessorCount=2', '-Djava.awt.headless=true', '-Dsuwayomi.tachidesk.config.server.rootDir='+str(RUNTIME/'suwayomi'), '-jar', str(RUNTIME/'Suwayomi-Server-v2.4.2366.jar')]
                cwd = RUNTIME/'suwayomi'
            elif name == 'gateway':
                cmd = [sys.executable, str(ROOT/'suwayomi_gateway.py'), '--runtime', str(RUNTIME)]
                cwd = ROOT
            else:
                cmd = [str(RUNTIME/'Kavita/Kavita')]
                cwd = RUNTIME/'Kavita'
            env = os.environ.copy()
            env['DOTNET_PROCESSOR_COUNT'] = '2'
            with (RUNTIME/(name+'.log')).open('ab') as log:
                process = subprocess.Popen(cmd, cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            state[name] = {'pid': process.pid, 'port': PORTS[name], 'bind': '127.0.0.1', 'started': time.time()}
            PIDS.write_text(json.dumps(state, indent=2)+'\n'); PIDS.chmod(0o600)
            for _ in range(150):
                if reachable(PORTS[name]) or not owned_process(process.pid): break
                time.sleep(.1)
        record = state.get(name, {})
        print(json.dumps({'provider': name, 'running': bool(record.get('pid') and owned_process(record['pid'])), 'listening_localhost': reachable(PORTS[name]), 'port': PORTS[name]}), flush=True)
    PIDS.write_text(json.dumps(state, indent=2)+'\n'); PIDS.chmod(0o600)

if __name__ == '__main__': main()
