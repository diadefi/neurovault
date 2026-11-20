# Backup browser replay

`backup-replay.mp4` is a 150-second, silent H.264 recording of the public `index.html` replay using Playwright. FFmpeg uses `libx264`, preset `veryfast`, CRF 21, `yuv420p`, and fast-start MP4 metadata. Recording-only captions explain what is visible; they do not change the model or the deployed app.

- 0:00–0:12: introduction, replay paused at the initial position.
- 0:12 onward: replay runs at speed **10** (ten one-minute samples per second).
- Around 0:35–0:40 (including initial page loading): the built-in volatility burst starts at **step 200**.
- The model automatically pauses when its position closes. The remaining recording holds that outcome while captions explain the authority boundary, limitations and mock scope. It is not frozen due to a recording error.
- The video contains no wallet connection, signatures or transactions, and is not evidence of live Arc execution. It has no narration; present over it or add your own voiceover before submission.

The Python 50-seed evaluation and the JavaScript replay use different seeded generators. Do not attribute the README's aggregate results to this one recorded path.

## Reproduce

```bash
python -m pip install playwright imageio-ffmpeg
python -m playwright install chromium
python tools/record-replay.py
```

Run from the repository root. The recorder reads the public HTTPS page, blocks all non-GET requests, and saves evidence to `evidence/backup-replay.json`. It records one real-time take and validates the resulting MP4 by decoding all frames with FFmpeg. Local temporary WebM and browser dependencies live under ignored `.tools/`.

Public video: <https://diadefi.github.io/neurovault/demo/backup-replay.mp4>
