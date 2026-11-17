#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["lz4", "zstandard", "numpy"]
# ///
"""Pull one texture out of Baldur's Gate 3's virtual textures (Granite .gts/.gtp) as PNG files.

  vtex.py <GTexFileName> <out_prefix> [level]

GTexFileName is the 32-hex name a VirtualTexture resource carries (see index.py).
Writes <out_prefix>_albedo.png, _normal.png and _physical.png. level 0 is full size,
each level up halves it (default 1, plenty for a tabletop camera).
Needs ImageMagick (`magick`) to turn the DDS it assembles into PNG.
"""
import ctypes, os, struct, subprocess, sys
import numpy as np
import gr2, index, lspk

VT_PAK = os.path.join(index.GAME, "VirtualTextures.pak")
LAYERS = ["albedo", "normal", "physical"]
_pak = None


def pak_read(name):
    global _pak
    if _pak is None:
        _pak = {e[0].rsplit("/", 1)[-1].lower(): e for e in lspk.entries(VT_PAK)}
    return lspk.read(VT_PAK, _pak[name.lower()])


def gdex(buf, pos, end):
    """Granite's metadata tree -> list of (tag, payload-or-children)."""
    out = []
    while pos < end:
        tag, kind, flag, n = struct.unpack_from("<4sBBH", buf, pos)
        head = 8
        if flag & 1:
            n |= struct.unpack_from("<I", buf, pos + 8)[0] << 16
            head = 12
        body = pos + head
        out.append((tag.decode(), gdex(buf, body, body + n) if kind == 1 else buf[body:body + n]))
        pos = body + ((n + 3) & ~3)
    return out


class TileSet:
    def __init__(self, gtex):
        self.name = f"Albedo_Normal_Physical_{gtex[0]}"
        cache = os.path.join(index.CACHE, self.name + ".gts")
        if not os.path.exists(cache):
            os.makedirs(index.CACHE, exist_ok=True)
            open(cache, "wb").write(pak_read(self.name + ".gts"))
        d = self.d = np.memmap(cache, np.uint8, "r")
        u32 = lambda o: int(d[o:o + 4].view("<u4")[0])
        u64 = lambda o: int(d[o:o + 8].view("<u8")[0])
        self.nlayers, self.nlevels, levels = u32(0x1C), u32(0x28), u64(0x2C)
        self.tile, self.border = u32(0x34), u32(0x3C)
        self.flat = d[u64(0x48):u64(0x48) + u32(0x44) * 12].view("<u2").reshape(-1, 6)
        pf, npf = u64(0x88), u32(0x84)
        self.pagefiles = [bytes(d[pf + 536 * i:pf + 536 * i + 512]).decode("utf-16-le").split("\0")[0] for i in range(npf)]
        self.levels = []
        for i in range(self.nlevels):
            w, h, off = u32(levels + 16 * i), u32(levels + 16 * i + 4), u64(levels + 16 * i + 8)
            self.levels.append(d[off:off + w * h * self.nlayers * 4].view("<u4").reshape(h, w, self.nlayers))
        g = bytes(d[u64(0x94):u64(0x94) + u32(0x90)])
        self.textures = {}
        find = lambda items, tag: next(v for t, v in items if t == tag)
        for t, tex in find(find(find(gdex(g, 0, len(g)), "META"), "ATLS"), "TXTS"):
            f = dict(tex)
            self.textures[f["NAME"].decode("utf-16-le").strip("\0")] = tuple(
                struct.unpack("<I", f[k][:4])[0] for k in ("XXXX", "YYYY", "WDTH", "HGHT"))
        self.pages = {}

    def chunk(self, pagefile, page, chunk):
        """One tile's BC3 blocks, shape (blocks, blocks, 16)."""
        key = (pagefile, page)
        if key not in self.pages:
            if pagefile not in self.pages:
                self.pages[pagefile] = pak_read(self.pagefiles[pagefile])
            self.pages[key] = self.pages[pagefile][page * 0x100000:(page + 1) * 0x100000]
        buf = self.pages[key]
        base = 24 if page == 0 else 0  # the file header sits in front of the first page's chunk table
        off = struct.unpack_from("<I", buf, base + 4 + 4 * chunk)[0]
        codec, _param, size = struct.unpack_from("<III", buf, off)
        n = self.tile // 4
        if codec != 9:
            raise ValueError(f"tile codec {codec} not handled (only BC)")
        want = n * n * 16
        out = ctypes.create_string_buffer(want * 2)  # some tiles carry a half-size copy after the full one
        got = gr2.codecs().fastlz_decode(buf[off + 12:off + 12 + size], ctypes.c_size_t(size), out, ctypes.c_size_t(len(out)))
        if got < want:
            raise ValueError(f"tile decoded to {got} bytes, expected {want}")
        return np.frombuffer(out.raw[:want], np.uint8).reshape(n, n, 16)

    def export(self, gtex, prefix, level=1):
        x, y, w, h = self.textures[gtex]
        inner, edge = self.tile - 2 * self.border, self.border // 4
        ib = inner // 4  # blocks per tile without the border
        scale = inner << level
        tx0, ty0, tx1, ty1 = x // scale, y // scale, -(-(x + w) // scale), -(-(y + h) // scale)
        table = self.levels[level]
        written = []
        for layer in range(self.nlayers):
            blocks = np.zeros(((ty1 - ty0) * ib, (tx1 - tx0) * ib, 16), np.uint8)
            used = False
            for ty in range(ty0, ty1):
                for tx in range(tx0, tx1):
                    idx = int(table[ty, tx, layer])
                    if idx == 0xFFFFFFFF:
                        continue
                    pagefile, page, chunk = (int(v) for v in self.flat[idx][:3])
                    t = self.chunk(pagefile, page, chunk)
                    blocks[(ty - ty0) * ib:(ty - ty0 + 1) * ib, (tx - tx0) * ib:(tx - tx0 + 1) * ib] = t[edge:edge + ib, edge:edge + ib]
                    used = True
            if not used:
                continue
            # cut to the texture's own rectangle (it rarely starts on a tile corner at higher levels)
            px0, py0 = (x >> level) - tx0 * inner, (y >> level) - ty0 * inner
            dds = prefix + f"_{LAYERS[layer]}.dds"
            hh, ww = blocks.shape[0] * 4, blocks.shape[1] * 4
            head = struct.pack("<4s7I44x", b"DDS ", 124, 0x81007, hh, ww, blocks.size, 0, 1)
            head += struct.pack("<II4s5I", 32, 4, b"DXT5", 0, 0, 0, 0, 0) + struct.pack("<5I", 0x1000, 0, 0, 0, 0)
            open(dds, "wb").write(head + blocks.tobytes())
            png = prefix + f"_{LAYERS[layer]}.png"
            subprocess.check_call(["magick", dds, "-crop", f"{w >> level}x{h >> level}+{px0}+{py0}", "+repage", png])
            os.remove(dds)
            written.append(png)
        return written


_sets = {}


def export(gtex, prefix, level=1):
    ts = _sets.get(gtex[0]) or _sets.setdefault(gtex[0], TileSet(gtex))
    return ts.export(gtex, prefix, level)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    print("\n".join(export(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 1)))
