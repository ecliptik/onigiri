#!/usr/bin/env python3
"""Tab-bar highlight tracker for a simctl screen recording of testTabBarAnimationProbe.

usage: scripts/analyze-tab-probe.py <recording.mp4> <outdir> [t_start t_end]

Record with `xcrun simctl io <udid> recordVideo --codec h264 out.mp4` (or a
phone screen recording) while TEST_RUNNER_TAB_PROBE=1 runs
testTabBarAnimationProbe; see plans/PLAN-tab-bar-jank.md. Needs Pillow
(`pip3 install pillow`) and ffmpeg.
Extracts frames (tab-bar crop, VFR timestamps preserved), tracks the orange
highlight's x-centroid per frame, auto-calibrates the four settled icon
x-positions, labels each frame, and prints (a) the settled/transition
segment log and (b) for every transition landing on the leftmost tab, the
dwell time spent within each intermediate icon's band and the total
tap-to-settle time — the numbers that matter for the stick.
"""
import glob, os, subprocess, sys
from PIL import Image

video, outdir = sys.argv[1], sys.argv[2]
t0 = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
t1 = float(sys.argv[4]) if len(sys.argv) > 4 else 1e9
os.makedirs(outdir, exist_ok=True)
for f in glob.glob(f"{outdir}/f_*.png"):
    os.remove(f)

# Crop: bottom 372px of a 2622-tall frame contains the whole bar; scale
# proportionally for other heights.
probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
    "-show_entries", "stream=width,height", "-of", "csv=p=0", video],
    capture_output=True, text=True).stdout.strip().split(",")
W, H = int(probe[0]), int(probe[1])
ch = int(H * 372 / 2622); cy = H - ch
sel = f"select='between(t,{t0},{t1})',crop={W}:{ch}:0:{cy},showinfo"
p = subprocess.run(["ffmpeg", "-y", "-i", video, "-vf", sel, "-fps_mode",
    "passthrough", f"{outdir}/f_%05d.png"], capture_output=True, text=True)
pts = [float(l.split("pts_time:")[1].split()[0]) for l in p.stderr.splitlines()
       if "pts_time:" in l]
files = sorted(glob.glob(f"{outdir}/f_*.png"))
assert len(files) == len(pts), (len(files), len(pts))

def track(f):
    im = Image.open(f).convert("RGB"); px = im.load(); w, h = im.size
    col = [0] * w
    for x in range(0, w, 3):
        s = 0
        for y in range(0, h, 5):
            r, g, b = px[x, y]
            if r > 120 and (r - b) > 40:
                s += (r - b)
        col[x] = s
    tot = sum(col)
    return tot, (sum(x * s for x, s in enumerate(col)) / tot if tot else -1)

rows = []
for f, t in zip(files, pts):
    tot, c = track(f)
    rows.append((t, tot, c))

# Auto-calibrate icon centres: cluster centroids of "still" frames.
still = [c for i, (t, tot, c) in enumerate(rows)
         if tot > 3000 and i > 0 and i < len(rows) - 1
         and abs(rows[i - 1][2] - c) < 2 and abs(rows[i + 1][2] - c) < 2]
centres = []
for c in sorted(still):
    if not centres or c - centres[-1][-1] > 80:
        centres.append([c])
    else:
        centres[-1].append(c)
centres = [sum(g) / len(g) for g in centres if len(g) >= 6]
names = ["Today", "Foods", "Goal", "Calendar", "Add"][:len(centres)]
tabs = dict(zip(names, centres))
print("icon centres:", {k: round(v) for k, v in tabs.items()})

def label(c):
    n, x = min(tabs.items(), key=lambda kv: abs(kv[1] - c))
    return n if abs(x - c) < 60 else None

# Segment log
segs = []
for t, tot, c in rows:
    l = label(c) if tot > 3000 else None
    if segs and segs[-1][2] == l:
        segs[-1][1] = t
    else:
        segs.append([t, t, l])
print("\nsettled segments (>= 0.25s):")
for a, b, l in segs:
    if l and b - a >= 0.25:
        print(f"  {a:8.3f} - {b:8.3f}  {b - a:5.3f}s  {l}")

# Transitions landing on Today: from the previous settled tab.
print("\ntransitions landing on Today:")
settled = [(a, b, l) for a, b, l in segs if l and b - a >= 0.25]
for i in range(1, len(settled)):
    a0, b0, l0 = settled[i - 1]; a1, b1, l1 = settled[i]
    if l1 != "Today":
        continue
    win = [(t, tot, c) for t, tot, c in rows if b0 <= t <= a1 and tot > 3000]
    dwell = {}
    for t_, tot_, c_ in win:
        l_ = label(c_)
        if l_ and l_ not in (l0,):
            dwell[l_] = dwell.get(l_, 0) + 1
    # per-label dwell as time: count consecutive samples * median frame gap
    gaps = [win[k + 1][0] - win[k][0] for k in range(len(win) - 1)]
    gap = sorted(gaps)[len(gaps) // 2] if gaps else 0
    print(f"  {l0}->Today  motion {b0:.3f}->{a1:.3f}  total {a1 - b0:.3f}s  "
          f"frames {len(win)}  median gap {gap * 1000:.0f}ms  "
          f"dwell(frames): {dwell}")
    for t_, tot_, c_ in win:
        print(f"      t={t_:.3f}  x={c_:6.1f}  {label(c_) or ''}")
