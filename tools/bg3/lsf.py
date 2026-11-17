#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["lz4"]
# ///
"""Read Baldur's Gate 3 binary resource files (.lsf, "LSOF" v5-v7).

load(data) -> list of top-level nodes. A node is a dict: "_id" is the node name,
"_children" its child nodes, every other key an attribute.

  lsf.py dump <file.lsf>      print as JSON
"""
import json, struct, sys, uuid
import lz4.block, lz4.frame

# value type -> struct format, for the fixed-size ones
FIXED = {1: "B", 2: "h", 3: "H", 4: "i", 5: "I", 6: "f", 7: "d", 8: "2i", 9: "3i", 10: "4i", 11: "2f", 12: "3f", 13: "4f",
         14: "4f", 15: "9f", 16: "12f", 17: "12f", 18: "16f", 19: "?", 24: "Q", 26: "q", 27: "b", 32: "q"}
TEXT = {20, 21, 22, 23, 29, 30}


def _section(data, pos, real, packed, chunked):
    if real == 0:
        return b"", pos
    if packed == 0:
        return data[pos:pos + real], pos + real
    blob = data[pos:pos + packed]
    out = lz4.frame.decompress(blob) if chunked else lz4.block.decompress(blob, uncompressed_size=real)
    return out, pos + packed


def _guid(b):
    b = bytes(b)
    tail = bytes(b[8 + (i ^ 1)] for i in range(8))  # the last 8 bytes are stored with each pair swapped
    return str(uuid.UUID(bytes_le=b[:8] + tail))


def _value(kind, raw):
    if kind in FIXED:
        v = struct.unpack("<" + FIXED[kind], raw[:struct.calcsize("<" + FIXED[kind])])
        return v[0] if len(v) == 1 else list(v)
    if kind in TEXT:
        return raw.split(b"\0", 1)[0].decode("utf-8", "replace")
    if kind == 31:
        return _guid(raw)
    if kind in (28, 33):  # translated string: version u16, then handle length i32 + handle
        n = struct.unpack_from("<i", raw, 2)[0]
        return raw[6:6 + n].split(b"\0", 1)[0].decode("utf-8", "replace")
    return raw.hex()


def load(data):
    magic, version = struct.unpack_from("<4sI", data, 0)
    if magic != b"LSOF" or not 5 <= version <= 7:
        raise ValueError(f"unsupported lsf {magic} v{version}")
    pos = 16
    if version >= 6:
        s_real, s_pack, _k_real, _k_pack, n_real, n_pack, a_real, a_pack, v_real, v_pack = struct.unpack_from("<10I", data, pos)
        pos += 40
    else:
        s_real, s_pack, n_real, n_pack, a_real, a_pack, v_real, v_pack = struct.unpack_from("<8I", data, pos)
        pos += 32
    comp, _u2, _u3, flags = struct.unpack_from("<BBHI", data, pos)
    pos += 8
    chunked = (comp & 0x0F) == 2 and version >= 2
    strings, pos = _section(data, pos, s_real, s_pack, False)
    nodes, pos = _section(data, pos, n_real, n_pack, chunked)
    attrs, pos = _section(data, pos, a_real, a_pack, chunked)
    values, pos = _section(data, pos, v_real, v_pack, chunked)

    names, p = [], 4
    for _ in range(struct.unpack_from("<I", strings, 0)[0]):
        bucket = []
        (count,) = struct.unpack_from("<H", strings, p)
        p += 2
        for _ in range(count):
            (n,) = struct.unpack_from("<H", strings, p)
            bucket.append(strings[p + 2:p + 2 + n].decode("utf-8", "replace"))
            p += 2 + n
        names.append(bucket)
    name = lambda ref: names[ref >> 16][ref & 0xFFFF]

    wide = flags & 1  # nodes and attributes carry "next" links
    out, built = [], []
    if wide:
        attr_at = lambda i: struct.unpack_from("<IIiI", attrs, i * 16)
        for i in range(len(nodes) // 16):
            nm, parent, _next, first = struct.unpack_from("<Iiii", nodes, i * 16)
            node = {"_id": name(nm)}
            while first != -1:
                anm, tl, first, off = attr_at(first)
                node[name(anm)] = _value(tl & 0x3F, values[off:off + (tl >> 6)])
            node["_children"] = []
            built.append(node)
            (out if parent == -1 else built[parent]["_children"]).append(node)
    else:
        owners, off = {}, 0
        for i in range(len(attrs) // 12):
            anm, tl, owner = struct.unpack_from("<IIi", attrs, i * 12)
            owners.setdefault(owner, []).append((anm, tl & 0x3F, off, tl >> 6))
            off += tl >> 6
        for i in range(len(nodes) // 12):
            nm, _first, parent = struct.unpack_from("<Iii", nodes, i * 12)
            node = {"_id": name(nm)}
            for anm, kind, o, n in owners.get(i, ()):
                node[name(anm)] = _value(kind, values[o:o + n])
            node["_children"] = []
            built.append(node)
            (out if parent == -1 else built[parent]["_children"]).append(node)
    return out


def walk(nodes, node_id):
    """Yield every node named node_id at any depth."""
    for n in nodes:
        if n["_id"] == node_id:
            yield n
        yield from walk(n["_children"], node_id)


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] != "dump":
        sys.exit(__doc__)
    json.dump(load(open(sys.argv[2], "rb").read()), sys.stdout, indent=1)
