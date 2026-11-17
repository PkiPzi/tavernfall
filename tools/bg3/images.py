#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["lz4", "zstandard"]
# ///
"""Copy images out of a BG3 pak as PNG (icons, interface art, portraits), or fonts as they are.

  images.py <pak name> <glob> <outdir> [max_size]

  images.py Game.pak '*/controlleruiicons/skills_png/*' assets/bg3/icons/skills
  images.py Game.pak '*/gui/assets/fonts/*.ttf' assets/bg3/fonts

glob is matched on the lower-cased path inside the pak. Files land flat in outdir with their
own names (lower-cased); .dds becomes .png, shrunk to max_size pixels on the long side if given.
Existing files are kept, so re-running is cheap. Needs ImageMagick.
"""
import fnmatch, os, subprocess, sys, tempfile
import index, lspk


def export(pak, glob, outdir, max_size=0):
    pak = os.path.join(index.GAME, pak)
    os.makedirs(outdir, exist_ok=True)
    done = 0
    with tempfile.TemporaryDirectory() as tmp:
        for e in lspk.entries(pak):
            low = e[0].lower()
            if not fnmatch.fnmatch(low, glob.lower()):
                continue
            name = os.path.basename(low)
            if not name.endswith(".dds"):
                dest = os.path.join(outdir, name)
                if not os.path.exists(dest):
                    open(dest, "wb").write(lspk.read(pak, e))
                done += 1
            elif not os.path.exists(os.path.join(outdir, name[:-4] + ".png")):
                open(os.path.join(tmp, name), "wb").write(lspk.read(pak, e))
                done += 1
        dds = sorted(f for f in os.listdir(tmp))
        for i in range(0, len(dds), 200):  # in batches: one magick start per file is slow, one for thousands eats memory
            resize = ["-resize", f"{max_size}x{max_size}>"] if max_size else []
            subprocess.check_call(["magick", "mogrify", "-format", "png", "-path", os.path.abspath(outdir), *resize, *dds[i:i + 200]], cwd=tmp)
    print(f"{outdir}: {done} files")


if __name__ == "__main__":
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    export(sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else 0)
