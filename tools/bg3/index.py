#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["lz4", "zstandard"]
# ///
"""Build the lookup database of every BG3 resource (meshes, materials, textures, animations, sounds).

  index.py build              read the resource banks straight from the paks -> ~/.cache/tavernfall-bg3/index.db
  index.py find <text> [bank] list resources whose name contains text (bank: Visual, Material, Texture, Animation ...)
  index.py show <id-or-name>  print one resource as JSON

Table res(id, bank, name, source, body): body is the whole resource node as JSON (see lsf.py).
Table file(path, pak): every file in every pak, for finding which archive holds a path.
"""
import glob, json, os, sqlite3, sys
import lsf, lspk

GAME = os.environ.get("BG3_DATA", "/mnt/wdblack/Games/Baldur's Gate 3/Data")
CACHE = os.path.expanduser("~/.cache/tavernfall-bg3")
DB = os.path.join(CACHE, "index.db")


def db():
    return sqlite3.connect(DB)


def build():
    os.makedirs(CACHE, exist_ok=True)
    if os.path.exists(DB):
        os.remove(DB)
    con = db()
    con.execute("create table res(id text, bank text, name text, source text, body text)")
    con.execute("create table file(path text, pak text)")
    paks = [p for p in sorted(glob.glob(GAME + "/*.pak") + glob.glob(GAME + "/Localization/*.pak"))
            if not os.path.basename(p)[:-4].rsplit("_", 1)[-1].isdigit()]  # Textures_1.pak etc. are parts of Textures.pak
    for pak in paks:
        try:
            ents = list(lspk.entries(pak))
        except Exception as e:
            print("skip", os.path.basename(pak), e)
            continue
        con.executemany("insert into file values(?,?)", [(e[0].lower(), os.path.basename(pak)) for e in ents])
        n = 0
        for e in ents:
            low = e[0].lower()
            if "/content/" not in low or not low.endswith(".lsf"):
                continue
            try:
                top = lsf.load(lspk.read(pak, e))
            except Exception as err:
                print("bad lsf", e[0], err)
                continue
            rows = []
            for bank in top:  # top-level nodes are the banks (VisualBank, MaterialBank ...), their children the resources
                for r in bank["_children"]:
                    rows.append((r.get("ID"), bank["_id"].removesuffix("Bank"), r.get("Name"),
                                 r.get("SourceFile") or r.get("GTexFileName") or r.get("Template"), json.dumps(r)))
            con.executemany("insert into res values(?,?,?,?,?)", rows)
            n += len(rows)
        print(f"{os.path.basename(pak)}: {len(ents)} files, {n} resources")
        con.commit()
    con.execute("create index res_id on res(id)")
    con.execute("create index res_name on res(name collate nocase)")
    con.execute("create index file_path on file(path)")
    con.commit()


def get(con, key, bank=None):
    """A resource by id, or by name. Names repeat across banks (a Visual and its Material often share one), so pass bank for names."""
    q = "select body from res where (id=? or name=? collate nocase)" + (" and bank=?" if bank else "") + " limit 1"
    row = con.execute(q, (key, key, bank) if bank else (key, key)).fetchone()
    return json.loads(row[0]) if row else None


def kids(node, name):
    return [c for c in node["_children"] if c["_id"] == name]


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["build"]:
        build()
    elif a[:1] == ["find"] and len(a) >= 2:
        q = "select bank, name, id, source from res where name like ?" + (" and bank=?" if len(a) > 2 else "") + " order by bank, name"
        for row in db().execute(q, ["%" + a[1] + "%"] + a[2:3]):
            print("\t".join(str(x) for x in row))
    elif a[:1] == ["show"] and len(a) == 2:
        print(json.dumps(get(db(), a[1]), indent=1))
    else:
        sys.exit(__doc__)
