import sys
import time
from resource_metrics import ProcessSampler, write_result

pid = int(sys.argv[1])
duration = float(sys.argv[2])
name = sys.argv[3]
sampler = ProcessSampler(pid, name).start()
time.sleep(duration)
row = sampler.finish()
write_result('resources.jsonl', row)
if len(sys.argv) > 4 and row['cpu_percent'] > float(sys.argv[4]):
    raise SystemExit(f'{name}: CPU {row["cpu_percent"]}% exceeds {sys.argv[4]}% of one core')
