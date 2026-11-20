"""Merge user-recorded Arc setup and live result with the existing demo scenes.
Original recordings stay untouched. Requires local scene intermediates produced
by record-submission.py and the two explicitly supplied recordings.
"""
from pathlib import Path
import subprocess,json,hashlib
import imageio_ffmpeg

ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'.tools/live-merge';WORK.mkdir(parents=True,exist_ok=True)
SCENES=ROOT/'.tools/submission-video'
LONG=Path(r'C:\Users\mando\Videos\Screen Recordings\Screen Recording 2026-11-20 114340.mp4')
SHORT=Path(r'C:\Users\mando\Videos\Recording 2026-11-20 114503.mp4')
OUT=ROOT/'demo/neurovault-final-live-demo.mp4'
ff=imageio_ffmpeg.get_ffmpeg_exe()
def run(args):
 p=subprocess.run([ff,'-hide_banner','-y',*args],cwd=ROOT,capture_output=True,text=True)
 if p.returncode:raise RuntimeError(p.stderr[-5000:])

# name, source, source start, source length, output seconds
edits=[
 ('problem',SCENES/'problem.mp4',0,8,8),
 ('idea',SCENES/'idea.mp4',0,10,10),
 ('real-deployment',LONG,0,68,34),
 ('real-live-result',SHORT,30.8,14,14),
 ('replay',SCENES/'dashboard.mp4',0,80,60),
 ('invariants',SCENES/'invariants.mp4',0,14,14),
 ('closing',SCENES/'closing.mp4',0,10,10),
]
timeline=[];clock=0
for name,src,start,length,duration in edits:
 print('Encoding '+name,flush=True)
 # Retain the full wallet/browser frame; add neutral letterboxing where needed.
 scale='scale=1280:650:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:0:color=0xf4f2ee' if name.startswith('real-') else 'scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=0xf4f2ee'
 vf=f'setpts=(PTS-STARTPTS)*{duration/length},{scale},setsar=1,fps=25'
 run(['-ss',str(start),'-t',str(length),'-i',str(src),'-vf',vf,'-t',str(duration),'-an','-c:v','libx264','-preset','veryfast','-crf','20','-pix_fmt','yuv420p',str(WORK/f'{name}.mp4')])
 timeline.append({'scene':name,'start':clock,'end':clock+duration,'source':src.name,'sourceStart':start,'sourceLength':length,'speed':length/duration})
 clock+=duration
assert clock==150
(WORK/'concat.txt').write_text(''.join(f"file '{name}.mp4'\n" for name,*_ in edits))
run(['-f','concat','-safe','0','-i',str(WORK/'concat.txt'),'-c','copy',str(WORK/'joined.mp4')])
captions=[
 (0,8,'NeuroVault: adaptive stop rules without handing a bot the owner key.'),
 (8,18,'Multiple setup approvals today; later pokes need no owner signature.'),
 (18,37,'Actual Arc Testnet recording: contract deployment approvals in MetaMask. 2x speed.'),
 (37,52,'Actual owner setup: configure neuron settings and open the mock long. 2x speed.'),
 (52,66,'Live Arc result: mock price $2,010; ratcheted stop $1,969.80.'),
 (66,94,'Browser replay begins: synthetic prices, same neuron math, fixed 2% baseline.'),
 (94,115,'Volatility burst: neurons spike, target trail widens, existing stop never moves down.'),
 (115,126,'Replay outcome: the model closes and pauses. Wider trails can exit lower.'),
 (126,140,'Owner-only withdrawals. 30 tests. Oracle trust and keeper liveness still matter.'),
 (140,150,'Arc Testnet / mock venue / safer delegation, not price prediction.')]
filters=['drawbox=x=0:y=658:w=iw:h=62:color=0xf4f2ee:t=fill']
for i,(start,end,text) in enumerate(captions):
 (WORK/f'caption-{i}.txt').write_text(text,encoding='utf-8')
 filters.append(f"drawtext=fontfile='.tools/submission-video/font.ttf':textfile='.tools/live-merge/caption-{i}.txt':expansion=none:fontsize=20:fontcolor=0x262622:x=28:y=678:enable='gte(t,{start})*lt(t,{end})'")
run(['-i',str(WORK/'joined.mp4'),'-t','150','-vf',','.join(filters),'-an','-c:v','libx264','-preset','veryfast','-crf','20','-pix_fmt','yuv420p','-movflags','+faststart',str(OUT)])
run(['-v','error','-i',str(OUT),'-f','null','-'])
r=imageio_ffmpeg.read_frames(str(OUT));m=next(r);r.close()
assert 149<=m['duration']<=151 and m['size']==(1280,720),m
for sec in [20,45,62,100]:run(['-ss',str(sec),'-i',str(OUT),'-frames:v','1',str(WORK/f'final-{sec}.jpg')])
report={'duration':m['duration'],'size':m['size'],'codec':m['codec'],'audio':False,'timeline':timeline,'originalFilesUnmodified':True,'sourceRecordingsOrder':'longer deployment recording, then shorter live-result recording','bytes':OUT.stat().st_size,'sha256':hashlib.sha256(OUT.read_bytes()).hexdigest(),'notes':'Condensed edit. Waiting and later retry attempts excluded. Actual Arc footage and browser simulation labeled separately. No transactions sent by this edit.'}
(ROOT/'evidence/final-live-demo.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'file':str(OUT),'duration':m['duration'],'bytes':OUT.stat().st_size}),flush=True)
