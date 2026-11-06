"""Rough audio analysis for picking/validating sounds without listening.
usage: python3 -I analyze.py [--env] files..."""
import sys, subprocess, numpy as np, os, re
SR = 44100
BARS = " .:-=+*#%@"
def load(path, sr=SR, ch=1):
    raw = subprocess.run(['ffmpeg','-v','error','-i',path,'-f','f32le','-ac',str(ch),'-ar',str(sr),'-'],capture_output=True).stdout
    x = np.frombuffer(raw, dtype=np.float32)
    return x.reshape(-1, ch) if ch > 1 else x
def lufs(path):
    r = subprocess.run(['ffmpeg','-hide_banner','-nostats','-i',path,'-af','ebur128=peak=true','-f','null','-'],capture_output=True,text=True).stderr
    I = re.findall(r'I:\s+(-?[\d.]+|-inf) LUFS', r); TP = re.findall(r'Peak:\s+(-?[\d.]+|-inf) dBFS', r); LRA=re.findall(r'LRA:\s+([\d.]+) LU', r)
    return (I[-1] if I else '?'), (TP[-1] if TP else '?'), (LRA[-1] if LRA else '?')
def analyze(path, env=False):
    x = load(path)
    if len(x) == 0: print(path, 'EMPTY'); return
    n = len(x); dur = n / SR
    pk = 20*np.log10(np.max(np.abs(x))+1e-12)
    X = np.abs(np.fft.rfft(x * np.hanning(n)))**2; f = np.fft.rfftfreq(n, 1/SR)
    tot = X.sum() + 1e-20
    bands = [(0,80),(80,250),(250,1000),(1000,4000),(4000,10000),(10000,22050)]
    bp = [100*X[(f>=a)&(f<b)].sum()/tot for a,b in bands]
    cen = (f*X).sum()/tot
    hop = int(SR*0.05); fr = np.sqrt(np.array([np.mean(x[i:i+hop]**2) for i in range(0, n-hop+1, hop)])+1e-12)
    db = 20*np.log10(fr)
    on = int(np.sum((db[1:]-db[:-1]) > 9))
    # silence at start/end (< -50 dB)
    act = np.where(db > max(db.max()-45, -60))[0]
    lead = act[0]*0.05 if len(act) else 0; tail = (len(db)-1-act[-1])*0.05 if len(act) else 0
    I, TP, LRA = lufs(path)
    print(f"{os.path.basename(path)[:44]:44s} {dur:6.2f}s pk{pk:6.1f} I{I:>6} TP{TP:>6} LRA{LRA:>4} cen{cen:6.0f} bands[{' '.join(f'{b:4.1f}' for b in bp)}] on{on:3d} lead{lead:.2f} tail{tail:.2f}")
    if env:
        m = db.max(); s = ''.join(BARS[min(9,max(0,int((d-m+45)/5)))] for d in db[:160])
        print('   env|'+s+'|')
if __name__ == '__main__':
    args = sys.argv[1:]; env = '--env' in args
    for p in args:
        if p != '--env': analyze(p, env)
