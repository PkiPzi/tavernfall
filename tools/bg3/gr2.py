"""Read Baldur's Gate 3 Granny files (.gr2, 64-bit little endian, version 7).

load(data) returns the root object as nested dicts/lists. Arrays of plain structs
(vertices, indices, curve data) come back as numpy structured arrays.

  python gr2.py dump <file.gr2>      print the object tree
"""
import ctypes, os, struct, subprocess, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
MAGIC = bytes.fromhex("E59B495E6F631F14" "1E13EBA990BEEDC4")

# type id -> numpy dtype for plain values
PLAIN = {10: "<f4", 11: "i1", 12: "u1", 13: "i1", 14: "u1", 15: "<i2", 16: "<u2",
         17: "<i2", 18: "<u2", 19: "<i4", 20: "<u4", 21: "<f2"}
TRANSFORM = np.dtype([("flags", "<u4"), ("t", "<f4", 3), ("r", "<f4", 4), ("s", "<f4", (3, 3))])
SIZES = {2: 8, 3: 12, 4: 12, 5: 16, 7: 20, 8: 8, 9: 68, 22: 8}


def codecs():
    lib = os.path.join(HERE, "libcodecs.so")
    src = os.path.join(HERE, "codecs.c")
    if not os.path.exists(lib) or os.path.getmtime(lib) < os.path.getmtime(src):
        subprocess.check_call(["cc", "-O2", "-shared", "-fPIC", "-o", lib, src])
    return ctypes.CDLL(lib)


def _unpack(decode, blob, size):
    if size == 0:
        return b""
    out = ctypes.create_string_buffer(size)
    err = decode(bytes(blob), ctypes.c_size_t(len(blob)), out, ctypes.c_size_t(size))
    if err:
        raise ValueError(f"bitknit error {err}")
    return out.raw


class Gr2:
    def __init__(self, data):
        if data[:16] != MAGIC:
            raise ValueError("not a 64-bit little-endian gr2")
        (version, _size, _crc, table, nsec, rt_sec, rt_off, ro_sec, ro_off) = struct.unpack_from("<9I", data, 32)
        if version != 7:
            raise ValueError(f"gr2 version {version}")
        decode = None
        heads = [struct.unpack_from("<11I", data, 32 + table + 44 * i) for i in range(nsec)]
        base, parts, pos = [], [], 0
        for comp, off, clen, ulen, *_ in heads:
            if comp == 0:
                parts.append(data[off:off + ulen])
            elif comp == 4:
                decode = decode or codecs().bitknit2_decode
                parts.append(_unpack(decode, data[off:off + clen], ulen))
            else:
                raise ValueError(f"gr2 compression {comp} not supported")
            base.append(pos)
            pos += ulen
        self.mem = b"".join(parts)
        self.ptr = {}  # address of a pointer field -> address it points to
        for i, (comp, _o, _c, _u, _a, _s0, _s1, fix_off, nfix, *_r) in enumerate(heads):
            if comp == 4:
                clen = struct.unpack_from("<I", data, fix_off)[0]
                fix = _unpack(decode, data[fix_off + 4:fix_off + 4 + clen], nfix * 12)
            else:
                fix = data[fix_off:fix_off + nfix * 12]
            for at, sec, off in struct.iter_unpack("<III", fix):
                self.ptr[base[i] + at] = base[sec] + off
        self.types = {}
        self.objects = {}
        self.root = self.obj(base[ro_sec] + ro_off, base[rt_sec] + rt_off)

    def string(self, at):
        return self.mem[at:self.mem.index(b"\0", at)].decode("utf-8", "replace")

    def type(self, at):
        """Struct definition at `at` as a list of (kind, name, subtype address, count)."""
        if at not in self.types:
            fields = []
            self.types[at] = fields
            p = at
            while True:
                kind, _name, _ref, count = struct.unpack_from("<IQQI", self.mem, p)
                if kind == 0:
                    break
                fields.append((kind, self.string(self.ptr[p + 4]), self.ptr.get(p + 12), count))
                p += 44
        return self.types[at]

    def size(self, tdef):
        return sum(self.field_size(f) for f in self.type(tdef))

    def field_size(self, f):
        kind, _n, sub, count = f
        one = self.size(sub) if kind == 1 else SIZES[kind] if kind in SIZES else np.dtype(PLAIN[kind]).itemsize
        return one * max(count, 1)

    def dtype(self, tdef):
        """numpy dtype when the struct holds only plain values, else None."""
        out = []
        for kind, name, sub, count in self.type(tdef):
            if kind == 1:
                dt = self.dtype(sub)
            elif kind == 9:
                dt = TRANSFORM
            else:
                dt = PLAIN.get(kind)
            if dt is None:
                return None
            out.append((name, dt, count) if count else (name, dt))
        return np.dtype(out)

    def array(self, at, count, tdef):
        if not count or at is None or tdef is None:
            return []
        dt = self.dtype(tdef)
        if dt is not None:
            return np.frombuffer(self.mem, dt, count, at)
        step = self.size(tdef)
        return [self.obj(at + i * step, tdef) for i in range(count)]

    def obj(self, at, tdef):
        key = (at, tdef)
        if key in self.objects:
            return self.objects[key]
        out = {}
        self.objects[key] = out
        p = at
        for f in self.type(tdef):
            kind, name, sub, count = f
            vals = []
            for _ in range(max(count, 1)):
                vals.append(self.value(p, kind, sub))
                p += self.field_size((kind, name, sub, 0))
            out[name] = vals if count else vals[0]
        return out

    def value(self, p, kind, sub):
        mem, ptr = self.mem, self.ptr
        if kind == 1:
            return self.obj(p, sub)
        if kind == 2:
            return self.obj(ptr[p], sub) if p in ptr and sub is not None else None
        if kind == 3:
            return self.array(ptr.get(p + 4), struct.unpack_from("<I", mem, p)[0], sub)
        if kind == 4:
            n, arr = struct.unpack_from("<I", mem, p)[0], ptr.get(p + 4)
            return [self.obj(ptr[arr + 8 * i], sub) if arr + 8 * i in ptr else None for i in range(n)] if arr is not None else []
        if kind == 5:
            return self.obj(ptr[p + 8], ptr[p]) if p in ptr and p + 8 in ptr else None
        if kind == 7:
            return self.array(ptr.get(p + 12), struct.unpack_from("<I", mem, p + 8)[0], ptr.get(p))
        if kind == 8:
            return self.string(ptr[p]) if p in ptr else None
        if kind == 9:
            return np.frombuffer(mem, TRANSFORM, 1, p)[0]
        if kind == 22:
            return None
        return np.frombuffer(mem, PLAIN[kind], 1, p)[0].item()


def load(data):
    return Gr2(data).root


def dump(v, depth=0, seen=None):
    seen = set() if seen is None else seen
    pad = "  " * depth
    if isinstance(v, dict):
        if id(v) in seen:
            print(pad + "<seen>")
            return
        seen.add(id(v))
        for k, x in v.items():
            if isinstance(x, (dict, list)) and len(x):
                print(f"{pad}{k}:" + (f" [{len(x)}]" if isinstance(x, list) else ""))
                dump(x, depth + 1, seen)
            elif isinstance(x, np.ndarray):
                print(f"{pad}{k}: array[{len(x)}] {x.dtype.names or x.dtype}")
            else:
                print(f"{pad}{k}: {x!r}"[:160])
    elif isinstance(v, list):
        for i, x in enumerate(v[:3]):
            print(f"{pad}- #{i}")
            dump(x, depth + 1, seen)
        if len(v) > 3:
            print(f"{pad}... {len(v) - 3} more")
    else:
        print(pad + repr(v)[:160])


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] != "dump":
        sys.exit(__doc__)
    dump(load(open(sys.argv[2], "rb").read()))
