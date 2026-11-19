import json
import sys
import time
from pathlib import Path
from resource_metrics import write_result

action, name = sys.argv[1:]
cpu = dict(line.split() for line in Path('/sys/fs/cgroup/cpu.stat').read_text().splitlines())
usage = int(cpu['usage_usec'])
now = time.monotonic()
state = Path('/results', f'{name}.phase-start.json')
if action == 'begin':
    state.write_text(json.dumps(dict(usage_usec=usage, time=now)))
elif action == 'end':
    before = json.loads(state.read_text())
    elapsed = now - before['time']
    cpu_seconds = (usage - before['usage_usec']) / 1e6
    write_result('phases.jsonl', dict(phase=name, seconds=round(elapsed, 3),
                                   container_cpu_seconds=round(cpu_seconds, 3),
                                   container_cpu_percent=round(cpu_seconds / elapsed * 100, 3)))
else:
    raise SystemExit(f'unknown phase action: {action}')
