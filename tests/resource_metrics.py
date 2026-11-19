import json
import os
import threading
import time
from pathlib import Path


def process_snapshot(pid):
    # comm 字段可以包含空格；从最后一个右括号之后解析数值字段。
    fields = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
    status = Path(f'/proc/{pid}/status').read_text().splitlines()
    rss = next(int(line.split()[1]) for line in status if line.startswith('VmRSS:'))
    return int(fields[11]) + int(fields[12]), rss


class ProcessSampler:
    def __init__(self, pid, name):
        self.pid = pid
        self.name = name
        self.done = threading.Event()
        self.error = None

    def start(self):
        self.start_cpu, self.peak = process_snapshot(self.pid)
        self.started = time.monotonic()
        self.worker = threading.Thread(target=self._sample, daemon=True)
        self.worker.start()
        return self

    def _sample(self):
        try:
            while not self.done.wait(0.25):
                _, rss = process_snapshot(self.pid)
                self.peak = max(self.peak, rss)
        except Exception as error:
            self.error = error

    def finish(self):
        self.done.set()
        self.worker.join()
        if self.error:
            raise self.error
        cpu, rss = process_snapshot(self.pid)
        elapsed = time.monotonic() - self.started
        return dict(name=self.name, seconds=round(elapsed, 3),
                    rss_mib=round(rss / 1024, 2),
                    peak_rss_mib=round(max(self.peak, rss) / 1024, 2),
                    cpu_percent=round((cpu - self.start_cpu) / os.sysconf('SC_CLK_TCK') / elapsed * 100, 3))


def write_result(filename, row):
    with Path('/results', filename).open('a') as output:
        output.write(json.dumps(row) + '\n')
    print(json.dumps(row), flush=True)
