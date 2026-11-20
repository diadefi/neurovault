"""Headless page-load/console checks only; never connect a wallet or click tx buttons."""
import argparse
from datetime import datetime, timezone
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import shutil
import threading

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
ap = argparse.ArgumentParser()
ap.add_argument('--local', action='store_true')
a = ap.parse_args()
server = None
if a.local:
    stage = ROOT / '.tools/site-review'
    shutil.copytree(ROOT / 'frontend', stage, dirs_exist_ok=True)
    shutil.copytree(ROOT / 'docs', stage / 'docs', dirs_exist_ok=True)
    class QuietHandler(SimpleHTTPRequestHandler):
        def log_message(self, *args):
            pass
    server = ThreadingHTTPServer(('127.0.0.1', 0), partial(QuietHandler, directory=str(stage)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = f'http://127.0.0.1:{server.server_port}/'
else:
    base = 'https://diadefi.github.io/neurovault/'

results, blocked = [], []
def guard(route):
    request = route.request
    if request.method == 'GET':
        route.continue_()
        return
    if request.method == 'POST':
        data = request.post_data_json
        data = data if isinstance(data, list) else [data]
        if all(d.get('method') in {'eth_chainId', 'eth_getBalance', 'eth_blockNumber', 'eth_call', 'eth_getCode', 'eth_getLogs', 'eth_getTransactionReceipt', 'eth_getBlockByNumber'} for d in data):
            route.continue_()
            return
    blocked.append({'method': request.method, 'url': request.url})
    route.abort()

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    context = browser.new_context(viewport={'width':1600,'height':900})
    context.route('**/*', guard)
    for name in ['index.html', 'operate.html', 'setup.html', 'docs/pitch.html']:
        page = context.new_page()
        errors, failed, bad_status = [], [], []
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.on('console', lambda m: errors.append(m.text) if m.type == 'error' else None)
        page.on('requestfailed', lambda req: failed.append({'url':req.url,'failure':req.failure}))
        page.on('response', lambda r: bad_status.append({'url':r.url,'status':r.status}) if r.status >= 400 else None)
        response = page.goto(base + name, wait_until='networkidle', timeout=60000)
        page.wait_for_timeout(3000)
        item = {'url':base+name, 'status':response.status, 'title':page.title(),
                'console_errors':errors,'failed_requests':failed,'http_errors':bad_status}
        if name == 'index.html':
            item['replay_steps'] = page.evaluate('replay.k')
            page.locator('#play').click()
        if name == 'operate.html':
            item['artifact_names'] = page.evaluate('Object.keys(window.NV_CONTRACTS)')
            item['network'] = page.evaluate('({rpc:NET.rpc,chainId:String(NET.chainId)})')
            item['wallet_connected'] = page.evaluate('owner !== null')
        if name == 'docs/pitch.html':
            item['slides'] = []
            for i in range(6):
                page.evaluate('(n)=>show(n)', i)
                page.screenshot(path=str(ROOT/'evidence'/f'pitch-slide-{i+1}.png'))
                item['slides'].append(page.evaluate("""()=>{const s=document.querySelector('.slide.active');
                    return {id:s.id,scrollHeight:s.scrollHeight,viewportHeight:innerHeight,
                    overflowX:document.documentElement.scrollWidth>innerWidth,
                    title:s.querySelector('h1,h2').textContent}}"""))
            page.keyboard.press('ArrowLeft')
            assert page.locator('#count').inner_text() == '5 / 6'
            page.keyboard.press('n')
            assert 'notes-on' in page.locator('body').get_attribute('class')
        else:
            page.screenshot(path=str(ROOT/'evidence'/f"{'local' if a.local else 'https'}-{name[:-5]}.png"), full_page=True)
        page.close()
        results.append(item)
    # Check the explicitly requested static assets as well as page scripts.
    assets = []
    for name in ['contracts.js','abi.js','vendor/ethers.umd.min.js']:
        r = context.request.get(base+name)
        assets.append({'url':base+name,'status':r.status,'bytes':len(r.body())})
    context.close()
    browser.close()
if server:
    server.shutdown()
report = {'checked_at_utc':datetime.now(timezone.utc).isoformat(), 'mode':'local' if a.local else 'HTTPS',
          'wallet_connected':False,'transactions_sent':0,'blocked_requests':blocked,'pages':results,'assets':assets}
target=ROOT/'evidence'/('browser-local.json' if a.local else 'browser-https.json')
target.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2),flush=True)
assert not blocked
assert all(r['status']==200 and not r['console_errors'] and not r['failed_requests'] and not r['http_errors'] for r in results)
assert all(r['status']==200 for r in assets)
