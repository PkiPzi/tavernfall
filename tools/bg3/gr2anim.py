"""Granny animation curves -> glTF animation channels.

Curve layouts follow Norbyte's LSLib (AnimationCurve formats). Spline control points are
written as plain keyframes at their knot times, which is what LSLib's exporter does too.
"""
import numpy as np

S = 1.4142135
SCALE = np.array([S, S / 2, S / 4, S / 4, S / 4, S / 8, S / 8, S / 8], np.float32)
SCALE = np.concatenate([SCALE, -SCALE])
OFFSET = np.array([-S / 2, -S / 4, -0.53033006, -S / 8, S / 8, -S / 8, -S / 16, 0.0], np.float32)
OFFSET = np.concatenate([OFFSET, -OFFSET])


FLIP_V = np.array([1, 1, -1], np.float32)
FLIP_Q = np.array([-1, -1, 1, 1], np.float32)


def _knot_scale(trunc):
    return np.array([int(trunc) << 16], np.uint32).view(np.float32)[0]


def _raw(c, key="KnotsControls"):
    a = c[key]
    return np.frombuffer(a.tobytes(), a.dtype[0].base) if len(a) else np.zeros(0, np.float32)


def keys(curve, dim):
    """-> (times, values[n, dim]) or None for an identity curve."""
    c = curve["CurveData"]
    kind = next(k for k in c if k.startswith("CurveDataHeader"))[len("CurveDataHeader_"):]
    if kind == "DaIdentity":
        return None
    if kind in ("D3Constant32f", "D4Constant32f", "DaConstant32f"):
        return np.zeros(1, np.float32), np.array(c["Controls"], np.float32).reshape(1, -1)[:, :dim]
    if kind == "DaK32fC32f":
        k = _raw(c, "Knots").astype(np.float32)
        return k, _raw(c, "Controls").astype(np.float32).reshape(len(k), -1)[:, :dim]
    raw = _raw(c)
    if kind in ("D4nK16uC15u", "D4nK8uC7u"):
        bits = 16 if "16u" in kind else 8
        top, mask = 1 << (bits - 1), (1 << (bits - 1)) - 1
        n = len(raw) // 4
        t = raw[:n].astype(np.float32) / c["OneOverKnotScale"]
        a, b, cc = raw[n:].reshape(n, 3).astype(np.int64).T
        sel = [(c["ScaleOffsetTableEntries"] >> (i * 4)) & 15 for i in range(4)]
        scale, offset = SCALE[sel] / mask, OFFSET[sel]
        s1 = ((b & top) >> (bits - 2)) | ((cc & top) >> (bits - 1))
        out = np.zeros((n, 4), np.float32)
        rows, total = np.arange(n), np.zeros(n, np.float32)
        for part, step in ((a, 1), (b, 2), (cc, 3)):
            s = (s1 + step) & 3
            val = (part & mask) * scale[s] + offset[s]
            out[rows, s] = val
            total += val * val
        d = np.sqrt(np.maximum(1 - total, 0))
        out[rows, s1] = np.where(a & top, -d, d)
        return t, out
    if kind in ("D3K16uC16u", "D3K8uC8u", "D3I1K16uC16u", "D3I1K8uC8u"):
        one = "I1" in kind
        n = len(raw) // (2 if one else 4)
        t = raw[:n].astype(np.float32) / _knot_scale(c["OneOverKnotScaleTrunc"])
        ctl = raw[n:].astype(np.float32).reshape(n, 1 if one else 3)
        return t, ctl * np.array(c["ControlScales"], np.float32) + np.array(c["ControlOffsets"], np.float32)
    raise ValueError(f"curve format {kind} not handled")


def add(g, bone_index, name, root):
    """Append the animation in `root` (a loaded .gr2) to Glb `g`."""
    samplers, channels = [], []
    duration = root["Animations"][0]["Duration"] if root["Animations"] else 0.0
    for group in root["TrackGroups"]:
        for track in group["TransformTracks"]:
            node = bone_index.get(track["Name"])
            if node is None:
                continue
            for path, field, dim, ident in (("rotation", "OrientationCurve", 4, [0, 0, 0, 1]), ("translation", "PositionCurve", 3, [0, 0, 0])):
                k = keys(track[field], dim)
                t, v = k if k else (np.zeros(1, np.float32), np.array([ident], np.float32))
                v = v * (FLIP_Q if path == "rotation" else FLIP_V)  # same Z mirror as gr2gltf
                if path == "rotation":
                    v = v / np.maximum(np.linalg.norm(v, axis=1, keepdims=True), 1e-8)
                    for i in range(1, len(v)):  # keep neighbours on the same side so blending takes the short way
                        if np.dot(v[i], v[i - 1]) < 0:
                            v[i] = -v[i]
                t, first = np.unique(t, return_index=True)  # glTF wants strictly increasing times
                v = v[first]
                t = np.minimum(t.astype(np.float32), np.float32(max(duration, 0.0))) if len(t) > 1 else t.astype(np.float32)
                samplers.append({"input": g.accessor(t, "SCALAR", minmax=True), "output": g.accessor(v.astype(np.float32), "VEC4" if dim == 4 else "VEC3"),
                                 "interpolation": "LINEAR"})
                channels.append({"sampler": len(samplers) - 1, "target": {"node": node, "path": path}})
    if channels:
        g.j.setdefault("animations", []).append({"name": name, "samplers": samplers, "channels": channels})
