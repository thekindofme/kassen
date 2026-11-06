"""Loop seam check: the jump from the last to the first sample vs. the 99.9th percentile step."""
import sys, numpy as np
from dsp import load
for p in sys.argv[1:]:
    x = load(p, 2)
    d = np.abs(np.diff(x, axis=0)).max(1)
    seam = np.abs(x[0] - x[-1]).max()
    print(f"{p.split('/')[-1]:28s} seam {seam:.4f}  p99.9 step {np.percentile(d, 99.9):.4f}  {'OK' if seam <= np.percentile(d, 99.9) else 'CHECK'}")
