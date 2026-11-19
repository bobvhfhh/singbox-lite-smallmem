import os
import json
import pty
import re
import select
import subprocess
import sys
import time
from pathlib import Path

container = sys.argv[1]
core = sys.argv[2]
out = Path('fresh-results')
out.mkdir(exist_ok=True)
log = (out / f'{core}-menu.log').open('wb')
master, slave = pty.openpty()
process = subprocess.Popen(['docker', 'exec', '-it', '-e', 'TERM=xterm', container, 'bash', '/work/install.sh', '--source', '/work'], stdin=slave, stdout=slave, stderr=slave, close_fds=True)
os.close(slave)
buffer = ''

def cpu_snapshot():
    text = subprocess.check_output(['docker', 'exec', container, 'cat', '/sys/fs/cgroup/cpu.stat'], text=True)
    return time.monotonic(), int(dict(line.split() for line in text.splitlines())['usage_usec'])

def finish_phase(name, before):
    now, usage = cpu_snapshot()
    elapsed = now - before[0]
    cpu_seconds = (usage - before[1]) / 1e6
    row = dict(phase=name, seconds=round(elapsed, 3), container_cpu_seconds=round(cpu_seconds, 3),
               container_cpu_percent=round(cpu_seconds / elapsed * 100, 3))
    with (out / f'{core}-phases.jsonl').open('a') as output:
        output.write(json.dumps(row) + '\n')

phase_started = cpu_snapshot()

def expect(pattern, timeout=240):
    global buffer
    deadline = time.monotonic() + timeout
    while True:
        match = re.search(pattern, buffer)
        if match:
            buffer = buffer[match.end():]
            return
        if time.monotonic() >= deadline:
            raise RuntimeError(f'timeout waiting for {pattern}: {buffer[-2500:]}')
        ready, _, _ = select.select([master], [], [], 1)
        if ready:
            try:
                data = os.read(master, 65536)
            except OSError:
                data = b''
            if not data:
                raise RuntimeError(f'menu exited waiting for {pattern}: {buffer[-2500:]}')
            log.write(data)
            log.flush()
            buffer += re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', data.decode('utf-8', errors='replace'))

def send(value):
    os.write(master, (value + chr(10)).encode())

try:
    expect(r'请输入选项 \[0-19\]:')
    finish_phase('installer-and-first-menu', phase_started)
    phase_started = cpu_snapshot()
    if core == 'singbox':
        send('15')
        expect(r'请选择 \[0-2\]:')
        send('1')
        expect(r'按任意键返回主菜单', 360)
        os.write(master, b'x')
        expect(r'请输入选项 \[0-19\]:')
        finish_phase('install-singbox-core', phase_started)
        for choice, port in [('1', '21001'), ('2', '21002'), ('3', '21003')]:
            phase_started = cpu_snapshot()
            send('1')
            expect(r'请输入选项 \[0-3\]:')
            send(choice)
            expect(r'请输入服务器IP地址.*:')
            send('127.0.0.1')
            if choice == '1':
                expect(r'请输入伪装域名.*:')
                send('www.amd.com')
            expect(r'请输入监听端口:')
            send(port)
            if choice != '1':
                expect(r'请输入伪装域名.*:')
                send('localhost')
            if choice == '2':
                expect(r'请输入密码.*:')
                send('')
            expect(r'请输入.*节点名称.*:')
            send('')
            if choice == '2':
                expect(r'请选择 \[1-2\].*:')
                send('1')
            expect(r'按任意键返回主菜单', 120)
            os.write(master, b'x')
            expect(r'请输入选项 \[0-19\]:')
            finish_phase(f'create-singbox-{choice}', phase_started)
    else:
        send('16')
        expect(r'按任意键返回主菜单', 360)
        os.write(master, b'x')
        expect(r'请输入选项 \[0-19\]:')
        finish_phase('install-xray-core', phase_started)
        send('19')
        expect(r'请选择 \[0-99\]:', 120)
        for choice, port in [('1', '22001'), ('2', '22002')]:
            phase_started = cpu_snapshot()
            send('6')
            expect(r'请选择 \[0-2\]:')
            send(choice)
            expect(r'请输入服务器IP.*:')
            send('127.0.0.1')
            expect(r'请输入监听端口:')
            send(port)
            expect(r'请输入.*(SNI|域名).*:')
            send('www.amd.com' if choice == '1' else 'localhost')
            if choice == '2':
                expect(r'请输入 H2 路径.*:')
                send('/smallmem')
            expect(r'请输入节点名称.*:')
            send('')
            expect(r'按回车键继续', 120)
            send('')
            expect(r'请选择 \[0-2\]:')
            send('0')
            expect(r'请选择 \[0-99\]:')
            finish_phase(f'create-xray-{choice}', phase_started)
        send('0')
        expect(r'按任意键返回主菜单')
        os.write(master, b'x')
        expect(r'请输入选项 \[0-19\]:')
    send('0')
    process.wait(timeout=20)
    if process.returncode:
        raise RuntimeError(f'menu exit code {process.returncode}')
    subprocess.run(['docker', 'exec', container, 'bash', '-c', 'test -x /usr/local/bin/' + ('sing-box' if core == 'singbox' else 'xray')], check=True)
    if core == 'singbox':
        subprocess.run(['docker', 'exec', container, 'jq', '-e', '.inbounds|length==3', '/usr/local/etc/sing-box/config.json'], check=True)
        subprocess.run(['docker', 'exec', container, 'bash', '-c', 'kill -0 "$(cat /run/singboxlite/sing-box.pid)"'], check=True)
    else:
        subprocess.run(['docker', 'exec', container, 'jq', '-e', '.inbounds|length==2', '/usr/local/etc/xray/config.json'], check=True)
        subprocess.run(['docker', 'exec', container, 'bash', '-c', 'kill -0 "$(cat /run/singboxlite/xray.pid)"'], check=True)
    phase_started = cpu_snapshot()
    subprocess.run(['docker', 'exec', '-i', container, 'sb'], input=b'0\n', timeout=90, stdout=subprocess.DEVNULL, check=True)
    finish_phase('repeat-menu-launch-and-exit', phase_started)
    print(f'PASS: clean {core} installation through real installer and menus')
finally:
    if process.poll() is None:
        process.terminate()
    os.close(master)
    log.close()
