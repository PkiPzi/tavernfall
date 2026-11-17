#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["lz4", "zstandard"]
# ///
"""Read Baldur's Gate 3 .pak archives (LSPK v18).

  lspk.py list  <pak>  [glob]            print "size<TAB>name"
  lspk.py extract <pak> <outdir> [glob]  write matching files under outdir

Glob is fnmatch on the full lower-cased path, e.g. '*/skills_png/*'.
"""
import fnmatch, os, struct, sys, zlib
import lz4.block, zstandard

ENTRY = struct.Struct("<256sIHBBII")  # name, offset low, offset high, part, flags, size on disk, real size


def entries(pak):
    with open(pak, "rb") as f:
        magic, version, list_off = struct.unpack("<4sIQ", f.read(16))
        assert magic == b"LSPK" and version == 18, f"unsupported pak {magic} v{version}"
        f.seek(list_off)
        count, packed = struct.unpack("<II", f.read(8))
        table = lz4.block.decompress(f.read(packed), uncompressed_size=count * ENTRY.size)
    for i in range(count):
        name, lo, hi, part, flags, disk, real = ENTRY.unpack_from(table, i * ENTRY.size)
        yield name.split(b"\0", 1)[0].decode(), lo | hi << 32, part, flags, disk, real


def part_path(pak, part):
    return pak if part == 0 else f"{pak[:-4]}_{part}.pak"


def read(pak, entry):
    name, off, part, flags, disk, real = entry
    with open(part_path(pak, part), "rb") as f:
        f.seek(off)
        data = f.read(disk)
    method = flags & 0x0F
    if method == 0 or real == 0:
        return data
    if method == 1:
        return zlib.decompress(data)
    if method == 2:
        return lz4.block.decompress(data, uncompressed_size=real)
    if method == 3:
        return zstandard.ZstdDecompressor().decompress(data, max_output_size=real)
    raise ValueError(f"{name}: unknown compression {method}")


def main():
    cmd, pak = sys.argv[1], sys.argv[2]
    if cmd == "list":
        pat = sys.argv[3].lower() if len(sys.argv) > 3 else "*"
        for e in entries(pak):
            if fnmatch.fnmatch(e[0].lower(), pat):
                print(f"{e[5] or e[4]}\t{e[0]}")
    elif cmd == "extract":
        out = sys.argv[3]
        pat = sys.argv[4].lower() if len(sys.argv) > 4 else "*"
        n = 0
        for e in entries(pak):
            if not fnmatch.fnmatch(e[0].lower(), pat):
                continue
            dest = os.path.realpath(os.path.join(out, e[0]))
            assert dest.startswith(os.path.realpath(out) + os.sep), f"bad path {e[0]}"
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, "wb") as f:
                f.write(read(pak, e))
            n += 1
        print(f"{n} files -> {out}")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
