"""Five-scene 720p submission film. Browser replay only; all POST requests blocked.
Requires Playwright Chromium and imageio-ffmpeg. Run from repository root.
"""
from pathlib import Path
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import hashlib
import json
import shutil
import subprocess
import threading
import time

from playwright.sync_api import sync_playwright
import imageio_ffmpeg

ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'.tools/submission-video'
WORK.mkdir(parents=True,exist_ok=True)
OUT=ROOT/'demo/neurovault-submission-720p.mp4'
SCREEN=ROOT/'evidence/submission-video'
SCREEN.mkdir(parents=True,exist_ok=True)
class Quiet(SimpleHTTPRequestHandler):
    def log_message(self,*args): pass
server=ThreadingHTTPServer(('127.0.0.1',0),partial(Quiet,directory=str(ROOT)))
threading.Thread(target=server.serve_forever,daemon=True).start()
base=f'http://127.0.0.1:{server.server_port}/'
styles='''*{box-sizing:border-box}body{margin:0;background:#f4f2ee;color:#262622;font:24px/1.4 system-ui,sans-serif}main{padding:58px 64px 85px;width:1280px;height:720px}header{font-size:17px;border-bottom:1px solid #ccc8c0;padding-bottom:15px;margin-bottom:42px;color:#68665f}h1{font-size:58px;line-height:1.1;letter-spacing:-2px;margin:0 0 30px;font-weight:650}h2{font-size:34px;line-height:1.2;margin:0 0 20px}p{max-width:1060px;margin:18px 0}.accent{color:#8c482f}.sub{font-size:19px;color:#68665f}.small{font-size:17px;color:#68665f}ul{list-style:none;padding:0;margin:0}li{padding:12px 0;border-bottom:1px solid #ccc8c0;font-size:27px}code{font-family:Consolas,monospace;font-size:.9em}.row{display:flex;gap:48px}.row>div{flex:1}.rule{border-top:2px solid #8c482f;padding-top:18px}.bottom{position:absolute;left:64px;bottom:100px;font-size:17px;color:#68665f}'''
cards={
 'problem':'''<header>NeuroVault / The problem</header><h1>Keep owner authority<br>off the trading bot.</h1><div class="row"><div class="rule"><h2>Cold wallet</h2><p>Discretionary changes require<br>another owner approval.</p></div><div class="rule"><h2>Trading bot</h2><p>Broad wallet permissions<br>put account authority online.</p></div></div><p class="bottom">Darshan &amp; Sebastian · DeFi and Onchain Applications</p>''',
 'idea':'''<header>NeuroVault / The idea</header><h1>Authorize the rules.<br><span class="accent">Automate the stop.</span></h1><p>Three on-chain spiking neurons adjust a trailing distance.</p><p>Anyone calls <code>poke()</code>. No hot owner key is needed.</p><p><strong>The established stop only tightens.</strong></p><p class="small">A wider target can hold the stop in place; it cannot lower an existing long stop.</p>''',
 'invariants':'''<header>NeuroVault / Safety invariants</header><h1>Bounded caller authority.</h1><ul><li>Only the owner withdraws — always to the owner.</li><li>The stop only tightens while the position is active.</li><li><code>poke()</code> takes no price or recipient input.</li><li><strong>30 passing tests</strong> · 256 long + 256 short fuzz paths.</li></ul><p class="small">Expanded from the initial 21-test suite. Unreviewed risks remain: oracle control,<br>caller timing, keeper liveness and execution gaps. Fuzzing is not a formal proof.</p>''',
 'closing':'''<header>NeuroVault / Arc Testnet</header><h1 style="font-size:74px;margin-top:55px">NeuroVault:<br><span class="accent">sign once, sleep.</span></h1><p>On-chain risk rules. Owner-bound withdrawals.</p><p class="sub">Vision: one authorization. This prototype uses multiple setup approvals;<br>subsequent pokes need no owner signature.</p><p class="bottom">github.com/diadefi/neurovault · Mock venue · Unaudited testnet code</p>'''
}
for name,content in cards.items():
    (WORK/f'{name}.html').write_text(f'<!doctype html><html><head><meta charset="utf-8"><link rel="icon" href="data:,"><style>{styles}</style></head><body><main>{content}</main></body></html>',encoding='utf-8')
errors=[];states=[];clips=[]
durations=[('problem',20),('idea',20),('dashboard',80),('invariants',20),('closing',10)]
with sync_playwright() as pw:
    browser=pw.chromium.launch(headless=True)
    for name,duration in durations:
        context=browser.new_context(viewport={'width':1280,'height':720},record_video_dir=str(WORK/'raw'),record_video_size={'width':1280,'height':720})
        context.route('**/*',lambda route:route.continue_() if route.request.method=='GET' else route.abort())
        page=context.new_page()
        page.on('pageerror',lambda e:errors.append(str(e)))
        page.on('console',lambda m:errors.append(m.text) if m.type=='error' else None)
        path='frontend/index.html' if name=='dashboard' else f'.tools/submission-video/{name}.html'
        page.goto(base+path,wait_until='networkidle')
        if name=='dashboard':
            page.locator('#play').click()
            page.locator('#reset').click()
            page.locator('#speed').select_option('5')
            page.locator('#play').click()
        print(f'Recording {name}: {duration}s',flush=True)
        start=time.monotonic();last_sample=-1
        while time.monotonic()-start<duration:
            elapsed=time.monotonic()-start
            bucket=int(elapsed//5)
            if bucket!=last_sample:
                last_sample=bucket
                if name=='dashboard':
                    state=page.evaluate('''()=>({step:replay.k,burst:replay.autoBurstDone,regime:replay.vault.regime,stop:replay.vault.stop.toString(),active:replay.vault.active,spikes:view.series.reduce((n,r)=>n+r.spikes.length,0),trail:Number(PARAMS.trailBps[replay.vault.regime]),price:document.getElementById('kPrice').textContent})''')
                    states.append({'elapsed':round(elapsed,2),**state})
                    if bucket in [2,9,13]:page.screenshot(path=str(SCREEN/f'dashboard-{bucket}.png'))
                elif bucket==1:page.screenshot(path=str(SCREEN/f'{name}.png'))
            page.wait_for_timeout(100)
        video=page.video
        context.close()
        clips.append((name,duration,str(video.path())))
    browser.close()
server.shutdown()
assert not errors,errors
assert any(s['burst'] for s in states)
assert any(s['regime']>0 for s in states)
assert any(s['spikes']>0 for s in states)
assert all(int(b['stop'])>=int(a['stop']) for a,b in zip(states,states[1:])), 'Stop moved down'
ffmpeg=imageio_ffmpeg.get_ffmpeg_exe()
def run(args):
    p=subprocess.run([ffmpeg,'-hide_banner','-y',*args],cwd=ROOT,capture_output=True,text=True)
    if p.returncode:raise RuntimeError(p.stderr[-6000:])
for name,duration,path in clips:
    # Take the last exact scene duration: exclude navigation/initial loading frames.
    run(['-sseof',str(-duration),'-i',path,'-t',str(duration),'-vf','fps=25,scale=1280:720','-an','-c:v','libx264','-preset','veryfast','-crf','20','-pix_fmt','yuv420p',str(WORK/f'{name}.mp4')])
concat=WORK/'concat.txt'
concat.write_text(''.join(f"file '{name}.mp4'\n" for name,_,_ in clips))
run(['-f','concat','-safe','0','-i',str(concat),'-c','copy',str(WORK/'joined.mp4')])
captions=[
 (0,20,'Existing stops automate execution. NeuroVault adds an adaptive policy.'),
 (20,40,'Prototype: multiple setup signatures. No owner signature is needed for later pokes.'),
 (40,78,'Browser simulation / synthetic prices / 5 samples per second / no transactions.'),
 (78,104,'Spikes widen the target trail. The existing long stop never moves down.'),
 (104,120,'The model pauses when stopped. Adaptive trails can survive shakeouts, but exit lower.'),
 (120,140,'No withdrawal rights for callers. Oracle trust, timing and liveness still matter.'),
 (140,150,'Arc Testnet / mock venue / multiple setup approvals today / no hot owner key for pokes.')]
shutil.copyfile('C:/Windows/Fonts/segoeui.ttf',WORK/'font.ttf')
filters=['drawbox=x=0:y=658:w=iw:h=62:color=0xf4f2ee:t=fill']
for i,(start,end,text) in enumerate(captions):
    (WORK/f'caption-{i}.txt').write_text(text,encoding='utf-8')
    filters.append(f"drawtext=fontfile='.tools/submission-video/font.ttf':textfile='.tools/submission-video/caption-{i}.txt':fontsize=20:fontcolor=0x262622:x=28:y=678:enable='gte(t,{start})*lt(t,{end})'")
run(['-i',str(WORK/'joined.mp4'),'-t','150','-vf',','.join(filters),'-an','-c:v','libx264','-preset','veryfast','-crf','20','-pix_fmt','yuv420p','-movflags','+faststart',str(OUT)])
run(['-v','error','-i',str(OUT),'-f','null','-'])
frames=imageio_ffmpeg.read_frames(str(OUT));metadata=next(frames);frames.close()
assert 149<=metadata['duration']<=151,metadata
assert metadata['size']==(1280,720),metadata
for sec in [5,25,55,90,125,145]:
    run(['-ss',str(sec),'-i',str(OUT),'-frames:v','1',str(SCREEN/f'final-{sec}.png')])
evidence={'duration':metadata['duration'],'size':metadata['size'],'codec':metadata['codec'],'audio':False,'captions':'FFmpeg drawtext burned into frames','scenes':durations,'consoleErrors':errors,'transactionsSent':0,'allNonGetRequestsBlocked':True,'replaySpeed':5,'states':states,'bytes':OUT.stat().st_size,'sha256':hashlib.sha256(OUT.read_bytes()).hexdigest()}
(ROOT/'evidence/submission-video.json').write_text(json.dumps(evidence,indent=2)+'\n')
print(json.dumps({'output':str(OUT),'duration':metadata['duration'],'bytes':OUT.stat().st_size}),flush=True)
