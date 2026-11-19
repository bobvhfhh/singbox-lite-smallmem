import json
import os
import sys
import time
from pathlib import Path

pid = int(sys.argv[1])
duration = float(sys.argv[2])
name = sys.argv[3]
ticks = os.sysconf('SC_CLK_TCK')

def read():
    stat = Path(f'/proc/{pid}/stat').read_text().split()
    status = Path(f'/proc/{pid}/status').read_text().splitlines()
    rss = next(int(s.split()[1]) for s in status if s.startswith('VmRSS:'))
    return int(stat[13]) + int(stat[14]), rss

start_cpu, peak = read()
start = time.monotonic()
while time.monotonic() - start < duration:
    cpu, rss = read()
    peak = max(peak, rss)
    time.sleep(0.25)
elapsed = time.monotonic() - start
cpu, rss = read()
row = dict(name=name, seconds=round(elapsed, 2), rss_mib=round(rss/1024, 2), peak_rss_mib=round(peak/1024, 2), cpu_percent=round((cpu-start_cpu)/ticks/elapsed*100, 3))
print(json.dumps(row))
with open('/results/resources.jsonl', 'a') as out:
    out.write(json.dumps(row) + chr(10))
