import json
import re
import sys
from pathlib import Path

runtime_dir, fresh_dir, runtime_run, fresh_run, commit = sys.argv[1:]

def rows(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line]

summary = dict(tested_commit=commit, singbox='1.13.21', xray='26.11.9',
               cpu_limit=0.5, swap=False, cpu_percent_basis='100% = one logical CPU',
               runtime_run=runtime_run, fresh_run=fresh_run, cases=[], fresh_installation=[])
for path in sorted(Path(runtime_dir).glob('results-*')):
    match = re.fullmatch(r'results-(\d+)m-ipv4-([01])', path.name)
    if not match:
        continue
    events = {key: int(value) for key, value in (line.split() for line in (path / 'memory.events').read_text().splitlines())}
    summary['cases'].append(dict(memory_mib=int(match[1]), ipv4_only=bool(int(match[2])),
                                 resources=rows(path / 'resources.jsonl'), traffic=rows(path / 'traffic.jsonl'),
                                 creation=rows(path / 'phases.jsonl'), memory_events=events))
for path in sorted(Path(fresh_dir).glob('fresh-*')):
    events = {key: int(value) for key, value in (line.split() for line in (path / 'memory.events').read_text().splitlines())}
    summary['fresh_installation'].append(dict(artifact=path.name,
        container_peak_mib=round(int((path / 'memory.peak').read_text()) / 1024**2, 2),
        memory_events=events, phases=rows(next(path.glob('*-phases.jsonl')))))
print(json.dumps(summary, indent=2, ensure_ascii=False))
