import sys, numpy as np
from dsp import load, SR
for p in sys.argv[2:]:
    x = load(p, 1); h = int(float(sys.argv[1]) * SR)
    e = [20*np.log10(np.sqrt(np.mean(x[i:i+h]**2))+1e-9) for i in range(0, len(x)-h+1, h)]
    print(p.split('/')[-1], ' '.join(f'{v:.0f}' for v in e))
