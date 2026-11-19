import hashlib
import http.server
import json
import os
import ssl
import subprocess
import threading
import time
from pathlib import Path

sb_dir = Path('/usr/local/etc/sing-box')
x_dir = Path('/usr/local/etc/xray')
sb = json.loads((sb_dir/'config.json').read_text())
xray = json.loads((x_dir/'config.json').read_text())
sb_meta = json.loads((sb_dir/'metadata.json').read_text())
x_meta = json.loads((x_dir/'metadata.json').read_text())
clients = Path('/opt/test-clients')
clients.mkdir(exist_ok=True)
payload = b'smallmem-verified' * 16384

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
    def log_message(self, *_):
        pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 28080), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
target_log = open('/results/tls-target.log', 'w')
target = subprocess.Popen(['openssl', 's_server', '-accept', '443', '-cert', str(sb_dir/'anytls-in-21002.pem'), '-key', str(sb_dir/'anytls-in-21002.key'), '-tls1_3', '-groups', 'X25519', '-alpn', 'h2', '-www'], stdout=target_log, stderr=target_log)
env = dict(os.environ, GOGC='100', GOMAXPROCS='1', GOMEMLIMIT='40MiB')
cases = []
for inbound in sb['inbounds']:
    kind = inbound['type']
    outbound = dict(type=kind, tag='proxy', server='127.0.0.1', server_port=inbound['listen_port'])
    if kind == 'vless':
        meta = sb_meta[inbound['tag']]
        outbound.update(uuid=inbound['users'][0]['uuid'], flow='xtls-rprx-vision', tls=dict(enabled=True, server_name='localhost', utls=dict(enabled=True, fingerprint='chrome'), reality=dict(enabled=True, public_key=meta['publicKey'], short_id=meta['shortId'])))
    elif kind == 'anytls':
        outbound.update(password=inbound['users'][0]['password'], tls=dict(enabled=True, server_name='localhost', insecure=True, alpn=['http/1.1']))
    else:
        outbound.update(uuid=inbound['users'][0]['uuid'], password=inbound['users'][0]['password'], congestion_control='bbr', tls=dict(enabled=True, server_name='localhost', insecure=True, alpn=['h3']))
    cases.append((f'singbox-{kind}', '/opt/cores/sing-box', dict(log=dict(level='error'), inbounds=[dict(type='socks', listen='127.0.0.1', listen_port=23001)], outbounds=[outbound]), int(Path('/run/singboxlite/sing-box.pid').read_text())))
for inbound in xray['inbounds']:
    stream = inbound['streamSettings']
    if stream['security'] == 'reality':
        meta = x_meta[inbound['tag']]
        config = dict(log=dict(loglevel='debug'), inbounds=[dict(listen='127.0.0.1', port=23001, protocol='socks', settings=dict(auth='noauth'))], outbounds=[dict(protocol='vless', settings=dict(vnext=[dict(address='127.0.0.1', port=inbound['port'], users=[dict(id=inbound['settings']['clients'][0]['id'], encryption='none', flow='xtls-rprx-vision')])]), streamSettings=dict(network='tcp', security='reality', realitySettings=dict(show=True, serverName='localhost', fingerprint='chrome', password=meta['publicKey'], shortId=meta['shortId'])))])
        binary = '/opt/cores/xray'
        name = 'xray-reality'
    else:
        cert_path = stream['tlsSettings']['certificates'][0]['certificateFile']
        fingerprint = hashlib.sha256(ssl.PEM_cert_to_DER_cert(Path(cert_path).read_text())).hexdigest()
        config = dict(log=dict(loglevel='error'), inbounds=[dict(listen='127.0.0.1', port=23001, protocol='socks', settings=dict(auth='noauth'))], outbounds=[dict(protocol='vless', settings=dict(vnext=[dict(address='127.0.0.1', port=inbound['port'], users=[dict(id=inbound['settings']['clients'][0]['id'], encryption='none')])]), streamSettings=dict(network='xhttp', security='tls', tlsSettings=dict(serverName='localhost', alpn=['h2'], pinnedPeerCertSha256=fingerprint), xhttpSettings=stream['xhttpSettings']))])
        binary = '/opt/cores/xray'
        name = 'xray-xhttp-h2'
    cases.append((name, binary, config, int(Path('/run/singboxlite/xray.pid').read_text())))

try:
    for name, binary, config, pid in cases:
        path = clients / f'{name}.json'
        path.write_text(json.dumps(config))
        with (clients/f'{name}.log').open('w') as log:
            client = subprocess.Popen([binary, 'run', '-c', str(path)], stdout=log, stderr=log, env=env)
            try:
                time.sleep(1)
                if client.poll() is not None:
                    raise RuntimeError(f'{name}: client exited; {(clients/f"{name}.log").read_text()}')
                sampler = subprocess.Popen(['python3', '/work/tests/resource-sample.py', str(pid), '5', f'{name}-traffic'])
                transferred = 0
                start = time.monotonic()
                requests = 0
                while time.monotonic() - start < 5:
                    result = subprocess.run(['curl', '--fail', '--silent', '--show-error', '--max-time', '8', '--limit-rate', '1M', '--noproxy', '', '--socks5-hostname', '127.0.0.1:23001', 'http://127.0.0.1:28080/payload'], capture_output=True)
                    if result.returncode or result.stdout != payload:
                        raise RuntimeError(f'{name}: transfer failed: {result.stderr.decode()} {(clients/f"{name}.log").read_text()}')
                    transferred += len(result.stdout)
                    requests += 1
                if sampler.wait() != 0:
                    raise RuntimeError(f'{name}: resource sample failed')
                row = dict(protocol=name, requests=requests, bytes=transferred, seconds=round(time.monotonic()-start, 2))
                with open('/results/traffic.jsonl', 'a') as out:
                    out.write(json.dumps(row) + chr(10))
                print(f'PASS: {name}, {transferred} bytes verified')
            finally:
                client.terminate()
                client.wait(timeout=5)
finally:
    target.terminate()
    target.wait(timeout=5)
    server.shutdown()
    target_log.close()
