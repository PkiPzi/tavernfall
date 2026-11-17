#!/usr/bin/env python3
"""Print the bounding box (metres) of .glb files: glbsize.py a.glb b.glb ..."""
import json, struct, sys
for f in sys.argv[1:]:
    d = open(f, "rb").read(); n = struct.unpack("<I", d[12:16])[0]; j = json.loads(d[20:20 + n])
    lo, hi = [9e9] * 3, [-9e9] * 3
    for m in j["meshes"]:
        for p in m["primitives"]:
            a = j["accessors"][p["attributes"]["POSITION"]]
            lo = [min(x, y) for x, y in zip(lo, a["min"])]; hi = [max(x, y) for x, y in zip(hi, a["max"])]
    print("%-52s w%.1f h%.1f d%.1f  y0 %.2f" % (f.split("/")[-1][:-4], hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2], lo[1]))
