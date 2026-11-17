#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["lz4", "zstandard"]
# ///
"""Find and export Baldur's Gate 3 sounds by event name.

  audio.py find <text>              list sound events whose name contains text (name, bank, seconds)
  audio.py export <event> <outdir>  write every recording that event can play

The game stores audio as numbered Wwise .wem files; a soundbank (.bnk) says which numbers
an event plays. Export follows that chain and writes <event>_<n>.ogg, converting with
`vgmstream-cli` (not installed by default: `yay -S vgmstream-git`). Without it the raw .wem
files are written instead, which Godot cannot play.
"""
import os, shutil, struct, subprocess, sys
import index, lspk

con = None
_paks = {}


def fetch(path):
    row = con.execute("select pak from file where path=?", (path.lower(),)).fetchone()
    if not row:
        return None
    full = os.path.join(index.GAME, row[0])
    if full not in _paks:
        _paks[full] = {e[0].lower(): e for e in lspk.entries(full)}
    return lspk.read(full, _paks[full][path.lower()])


def objects(bnk):
    """HIRC chunk of a soundbank -> {id: (type, data)}."""
    pos, out = 0, {}
    while pos + 8 <= len(bnk):
        tag, size = struct.unpack_from("<4sI", bnk, pos)
        if tag == b"HIRC":
            p = pos + 12
            for _ in range(struct.unpack_from("<I", bnk, pos + 8)[0]):
                kind, n, oid = struct.unpack_from("<BII", bnk, p)
                out[oid] = (kind, bnk[p + 9:p + 5 + n])
                p += 5 + n
        pos += 8 + size
    return out


def children(objs, kind, data):
    """Ids this object points down to. Layouts differ between Wwise versions, so instead of fixed
    offsets this looks for the shapes that hold: an action's target id, and counted id lists."""
    if kind == 3:  # action: u16 type, then the id it acts on
        return [struct.unpack_from("<I", data, 2)[0]] if len(data) >= 6 else []
    if kind == 2:  # a sound is a leaf
        return []
    found = []
    for width in (1, 4):  # an event's count is one byte in newer banks, lists elsewhere use four
        for p in range(0, len(data) - 4):
            n = data[p] if width == 1 else struct.unpack_from("<I", data, p)[0]
            if not 0 < n <= 2000 or p + width + 4 * n > len(data):
                continue
            ids = struct.unpack_from(f"<{n}I", data, p + width)
            if all(i in objs for i in ids):
                found += ids
        if found:
            break
    return found


_all = None
_wem = None
_media = {}  # recording id -> (bank path, offset, size) for sounds stored inside a bank (most UI sounds)


def embedded(bank_path, bnk):
    """DIDX lists the recordings inside a bank, DATA holds them."""
    pos, didx, data_at = 0, b"", 0
    while pos + 8 <= len(bnk):
        tag, size = struct.unpack_from("<4sI", bnk, pos)
        if tag == b"DIDX":
            didx = bnk[pos + 8:pos + 8 + size]
        elif tag == b"DATA":
            data_at = pos + 8
        pos += 8 + size
    for i in range(0, len(didx) - 11, 12):
        wid, off, n = struct.unpack_from("<III", didx, i)
        _media[str(wid)] = (bank_path, data_at + off, n)


def everything():
    """Objects of every soundbank merged, and wem id -> path. An event's container often points at sounds that
    live in another bank, so the walk has to see them all."""
    global _all, _wem
    if _all is None:
        _all = {}
        for (path,) in con.execute("select path from file where path like '%.bnk'"):
            try:
                bnk = fetch(path) or b""
                _all.update(objects(bnk))
                embedded(path, bnk)
            except (OSError, KeyError):  # a bank listed in a pak this install does not have
                pass
        _wem = {}
        for (path,) in con.execute("select path from file where path like '%.wem'"):
            _wem.setdefault(path.rsplit("/", 1)[1][:-4], path)
    return _all, _wem


def wems(event_id, bank_path, folder):
    objs, wemfiles = everything()
    objs = {**objs, **objects(fetch(bank_path) or b"")}  # the event's own bank wins on a clash
    seen, stack, out = set(), [event_id], []
    while stack:
        oid = stack.pop()
        if oid in seen or oid not in objs:
            continue
        seen.add(oid)
        kind, data = objs[oid]
        if kind in (2, 11):  # sound, music track: hold the numbers of the recordings
            for p in range(0, min(len(data), 64) - 3 if kind == 2 else len(data) - 3):
                wid = str(struct.unpack_from('<I', data, p)[0])
                path = wemfiles.get(wid) or _media.get(wid)
                if path and path not in out:
                    out.append(path)
        stack += children(objs, kind, data)
    return out


def export(event, outdir):
    row = con.execute("select body from res where bank='Sound' and name=? collate nocase", (event,)).fetchone()
    if not row:
        sys.exit(f"no sound event called {event}")
    import json
    r = json.loads(row[0])
    files = wems(r["SoundEventID"], r["SourceFile"], r["SourceFile"].rsplit("/", 1)[0])
    files = files[::max(1, len(files) // 8)][:8]  # switch containers list every variant (hundreds): an even sample of eight is plenty
    os.makedirs(outdir, exist_ok=True)
    tool = shutil.which("vgmstream-cli")
    for i, path in enumerate(files):
        base = os.path.join(outdir, f"{event}_{i}")
        if isinstance(path, tuple):  # inside a bank
            bank, off, n = path
            open(base + ".wem", "wb").write(fetch(bank)[off:off + n])
        else:
            open(base + ".wem", "wb").write(fetch(path))
        if tool:
            subprocess.check_call([tool, "-o", base + ".wav", base + ".wem"], stdout=subprocess.DEVNULL)
            subprocess.check_call(["ffmpeg", "-loglevel", "error", "-y", "-i", base + ".wav", "-af", "loudnorm=I=-20:TP=-1.5:LRA=9", "-ac", "2", "-ar", "44100", "-q:a", "5", base + ".ogg"])
            os.remove(base + ".wav")
            os.remove(base + ".wem")
    print(f"{event}: {len(files)} recordings -> {outdir}" + ("" if tool else "  (raw .wem: install vgmstream-cli to get .ogg)"))


if __name__ == "__main__":
    a = sys.argv[1:]
    con = index.db()
    if a[:1] == ["find"] and len(a) == 2:
        for name, body in con.execute("select name, body from res where bank='Sound' and name like ? order by name", (f"%{a[1]}%",)):
            import json
            r = json.loads(body)
            print(f"{name}\t{r.get('SoundBank')}\t{r.get('Duration', -1):.1f}")
    elif a[:1] == ["export"] and len(a) == 3:
        export(a[1], a[2])
    else:
        sys.exit(__doc__)
