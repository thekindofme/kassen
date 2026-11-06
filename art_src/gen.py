#!/usr/bin/env python3
"""Generate raw art via `codex exec` image generation. Usage: gen.py [-j N] [--force] [name-prefix ...]"""
import subprocess, sys, os, concurrent.futures as cf, time, argparse
sys.path.insert(0, os.path.dirname(__file__))
from manifest import ASSETS

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "raw")
LOG = os.path.join(HERE, "logs")
os.makedirs(RAW, exist_ok=True); os.makedirs(LOG, exist_ok=True)

SIZE = {"sheet": "wide landscape (1536x1024 or wider)", "art": "wide landscape 16:9 (1536x1024)",
        "tex": "square 1024x1024", "prop": "wide landscape (1536x1024)", "icon": "square 1024x1024"}

def gen(name, extra=""):
    kind, prompt = ASSETS[name]
    out = os.path.join(RAW, f"{name}.png")
    instr = (f"Use your image generation tool to create exactly ONE image ({SIZE[kind]}). Prompt:\n\n{prompt}{extra}\n\n"
             f"Then copy the generated PNG file into the current working directory with the file name {name}.png . "
             f"Do not create any other files. Do not edit the image.")
    for attempt in range(3):
        t = time.time()
        with open(os.path.join(LOG, f"{name}.log"), "w") as lf:
            subprocess.run(["codex", "exec", "--skip-git-repo-check", "-s", "workspace-write", "-C", RAW, instr],
                           stdout=lf, stderr=subprocess.STDOUT, timeout=900)
        if os.path.exists(out) and os.path.getsize(out) > 10000:
            return f"ok   {name} ({time.time()-t:.0f}s)"
    return f"FAIL {name}"

if __name__ == "__main__":
    ap = argparse.ArgumentParser(); ap.add_argument("-j", type=int, default=4); ap.add_argument("--force", action="store_true")
    ap.add_argument("--extra", default=""); ap.add_argument("names", nargs="*")
    a = ap.parse_args()
    todo = [n for n in ASSETS if (not a.names or any(n.startswith(p) for p in a.names))]
    if a.force:
        for n in todo:
            p = os.path.join(RAW, f"{n}.png")
            if os.path.exists(p): os.rename(p, p + f".old{int(time.time())}")
    todo = [n for n in todo if not os.path.exists(os.path.join(RAW, f"{n}.png"))]
    print(f"generating {len(todo)} assets with -j{a.j}", flush=True)
    with cf.ThreadPoolExecutor(a.j) as ex:
        for r in ex.map(lambda n: gen(n, a.extra), todo):
            print(r, flush=True)
