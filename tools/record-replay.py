"""Record the public browser-only replay; no wallet connection or transactions.

Requires: pip install playwright imageio-ffmpeg; playwright install chromium
Run from the repo: python tools/record-replay.py
"""
import json
import os
from pathlib import Path
import subprocess
import time

from playwright.sync_api import sync_playwright
import imageio_ffmpeg

ROOT = Path(__file__).resolve().parents[1]
URL = "https://diadefi.github.io/neurovault/index.html"
OUT = ROOT / "demo"
OUT.mkdir(exist_ok=True)
RAW = ROOT / ".tools" / "recording"
RAW.mkdir(parents=True, exist_ok=True)
errors, snapshots = [], []


def caption(page, title, detail):
    page.evaluate("""([title,detail])=>{
      let el=document.getElementById('recording-caption');
      if(!el){el=document.createElement('div');el.id='recording-caption';
      Object.assign(el.style,{position:'fixed',left:'22px',right:'22px',bottom:'14px',
      padding:'15px 20px',background:'#0b0e14f5',border:'1px solid #62e3ab',
      borderRadius:'10px',zIndex:1000,font:'18px/1.45 system-ui',color:'#edf2f8'});
      document.body.append(el);}
      el.replaceChildren();const b=document.createElement('strong');b.textContent=title;
      const d=document.createElement('div');d.textContent=detail;d.style.color='#b9c6d8';
      el.append(b,d);
    }""", [title, detail])


with sync_playwright() as pw:
    browser = pw.chromium.launch(headless=True)
    context = browser.new_context(viewport={"width": 1600, "height": 1000},
                                  record_video_dir=str(RAW),
                                  record_video_size={"width": 1600, "height": 1000})
    # The replay needs only static assets. Prevent any POST/RPC/wallet interaction.
    context.route("**/*", lambda route: route.continue_() if route.request.method == "GET" else route.abort())
    page = context.new_page()
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.on("console", lambda msg: errors.append(msg.text) if msg.type == "error" else None)
    response = page.goto(URL, wait_until="networkidle")
    assert response.status == 200
    page.locator('#play').click()  # Pause for introduction; never connect a wallet.
    page.locator('#reset').click()
    page.locator('#speed').select_option('10')
    start = time.monotonic()
    caption(page, 'NeuroVault — browser replay / synthetic prices / no transactions',
            'Owner-authorized rules. Three on-chain neurons. No hot owner key for stop updates.')
    schedule = [
        (12, 'Reading the chart', 'Blue: price. Red: adaptive stop. Gray: fixed 2% trailing stop. Playback speed: 10 samples/second.'),
        (27, 'Calm market → scripted burst at step 200', 'Each sample advances 60 simulated seconds. The burst is built into this seeded replay.'),
        (36, 'Watch the spike raster and regime', 'Spikes select a wider target trail. The existing long stop can only rise or stay unchanged.'),
        (60, 'A constrained caller', 'poke() supplies no price or withdrawal destination. The oracle, owner settings and call timing drive the result.'),
        (85, 'Inspect the result', 'If the replay pauses on a stop, that is the real model outcome. A stop trigger does not guarantee a fill price.'),
        (105, 'The tradeoff', 'Adaptive stops can survive shakeouts, but can exit lower. This replay is a demonstration, not a profit forecast.'),
        (125, 'What is live — and what is mocked', 'Arc contracts are deployed. Prices and collateral are mocks. Setup uses multiple signatures; Shoreline-1 is a stub.'),
        (140, 'NeuroVault / Darshan & Sebastian', 'Unaudited testnet prototype. Owner-only withdrawals. Safer delegation, not price prediction. github.com/diadefi/neurovault'),
    ]
    idx, last_report = 0, -1
    while time.monotonic() - start < 150:
        elapsed = time.monotonic() - start
        if idx < len(schedule) and elapsed >= schedule[idx][0]:
            at, title, detail = schedule[idx]
            caption(page, title, detail)
            if at == 12:
                page.locator('#play').click()
            idx += 1
        bucket = int(elapsed // 5)
        if bucket != last_report:
            state = page.evaluate("""()=>({step:replay.k,autoBurstDone:replay.autoBurstDone,
              playing:replay.playing,active:replay.vault.active,regime:replay.vault.regime,
              price:document.getElementById('kPrice').textContent,
              stop:document.getElementById('kStop').textContent,
              position:document.getElementById('kPos').textContent,
              detail:document.getElementById('kPosS').textContent})""")
            snapshots.append({"elapsed_seconds": round(elapsed, 2), **state})
            if bucket % 6 == 0:
                print(json.dumps(snapshots[-1]), flush=True)
            last_report = bucket
        page.wait_for_timeout(200)
    page.screenshot(path=str(ROOT / 'evidence' / 'backup-replay-final.png'))
    video = page.video
    context.close()
    source = video.path()
    browser.close()

assert any(s['autoBurstDone'] for s in snapshots), 'Scripted burst was not recorded'
assert not errors, errors
target = OUT / 'backup-replay.mp4'
ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
command = [ffmpeg, '-y', '-i', str(source), '-t', '150', '-an', '-c:v', 'libx264',
           '-preset', 'veryfast', '-crf', '21', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(target)]
result = subprocess.run(command, capture_output=True, text=True)
if result.returncode:
    raise RuntimeError(result.stderr)
check = subprocess.run([ffmpeg, '-v', 'error', '-i', str(target), '-f', 'null', '-'], capture_output=True, text=True)
assert check.returncode == 0 and not check.stderr, check.stderr
metadata = imageio_ffmpeg.read_frames(str(target))
info = next(metadata)
metadata.close()
assert 149 <= info['duration'] <= 151, info
evidence = {"url": URL, "mode": "browser replay, no wallet", "speed": 10,
            "duration_seconds": info['duration'], "codec": info['codec'], "size": info['size'],
            "encoding": "H.264 / libx264 / preset veryfast / CRF 21 / yuv420p / faststart",
            "audio": "none; recording-only explanatory captions, no narration",
            "console_errors": errors, "snapshots": snapshots,
            "file_bytes": target.stat().st_size, "source_post_requests_allowed": False}
(ROOT / 'evidence' / 'backup-replay.json').write_text(json.dumps(evidence, indent=2) + '\n')
print(json.dumps({"output": str(target), "duration": info['duration'], "codec": info['codec'], "bytes": target.stat().st_size}), flush=True)
