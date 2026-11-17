#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["lz4", "zstandard", "numpy"]
# ///
"""Build one textured, animated .glb from a Baldur's Gate 3 resource name.

  creature.py <out.glb> <name> [more visual names ...] [--anims all|none|regex] [--level N] [--list]

<name> is a CharacterVisual (a whole dressed character: body, head, gear) or a Visual
(one mesh file: a monster, weapon, prop, piece of scenery). Find names with
`index.py find <text> CharacterVisual` or `index.py find <text> Visual`.
Extra names are added to the same skeleton (e.g. a body plus a helmet).

--anims   which animations of that skeleton to include. Default is a small standard set
          (idle, walk, run, attack, shoot, cast, hit, die). `all` takes everything
          (hundreds), a regex takes the ones whose name matches, `none` skips them.
--rig     also take animations whose name starts with this (e.g. GOB_M_Rig). Some bodies have few
          animations of their own and borrow another rig's; bones are matched by name.
--level   texture size step: 0 full, 1 half (default), 2 quarter.
--list    only print the animations available for this skeleton.

Needs index.py build to have been run once.
"""
import json, os, re, subprocess, sys
import numpy as np
import gr2, gr2gltf, index, lspk, vtex

TEX = os.path.join(index.CACHE, "tex")
# our name -> patterns tried in order against the game's animation names
STANDARD = {
    "idle": [r"_DFLT_IDLE_Still_Combat_01$", r"_IDLE_Still_Combat_01$", r"_IDLE_Still_Peace_01$", r"_IDLE_.*Still", r"_IDLE_"],
    "calm": [r"_DFLT_IDLE_Still_Peace_01$", r"_1HS_IDLE_Still_Peace_01$", r"_IDLE_Still_Peace_01$"],  # a relaxed stance for conversations
    "talk": [r"_CINE_GestureRight_RHand_StandL_01$", r"_CINE_GestureLeft_LHand_StandL$"],  # speaking with the hands (the CROWD_ talk clips are for another skeleton: stretched necks)
    "greet": [r"_CINE_Greet_RaiseHand_01$", r"_CINE_Wave_Afar_01$"],
    "walk": [r"_DFLT_LOCO_Walk_F_Peace_01$", r"_LOCO_Walk_F_.*01$", r"_LOCO_Walk_F"],
    "run": [r"_DFLT_LOCO_Run_F_Combat_01$", r"_DFLT_LOCO_Run_F_Peace_01$", r"_LOCO_Run_F_.*01$", r"_LOCO_Run_F"],
    "attack": [r"_DFLT_CMBT_Melee_RHand_01_Attack$", r"_CMBT_Melee_.*01_Attack$", r"_CMBT_.*Attack"],
    "shoot": [r"_BOW_CMBT_Ranged_RHand_01_Attack$", r"_CMBT_Ranged_.*Attack$"],
    "cast": [r"_DFLT_SPL_Somatic_Projectile_01_Cast$", r"_SPL_.*_Cast$"],
    "hit": [r"_DFLT_REAC_Hit_F_Combat_01$", r"_REAC_Hit_F", r"_REAC_Hit"],
    "die": [r"_DFLT_DIE_Physical_.*01$", r"_DIE_Physical", r"_DIE_"],
}
BASECOLOR = ("basecolor", "basemap", "BaseColor_NonSkin", "Body_color_texture", "MainTexture", "baseMaps_RGB")
CUTOUT = ("AlphaTest", "Feather", "Fur", "Hair", "AlphaBlend")  # material types whose colour texture carries see-through parts
SKIP_MATERIALS = ("Tearline", "LashesShadow", "LashShadow", "Engine_Default", "Helper_Invisible", "InvisibleMat")  # see-through overlays and placeholders

# Armour colour mask (MSKColor texture): each channel is 0, 127 or 255 and the triple names the dye slot.
# Nine triples are read off the game's own Engine_Default_<slot>_MSKcloth textures; the three marked
# "inferred" follow the same pattern (primary / secondary / tertiary) and match what real armour uses.
DYE = {(2, 1, 0): "Cloth_Primary", (2, 0, 0): "Cloth_Secondary", (2, 1, 1): "Cloth_Tertiary",  # secondary inferred
       (1, 0, 2): "Leather_Primary", (0, 0, 2): "Leather_Secondary", (1, 1, 2): "Leather_Tertiary",  # last two inferred
       (0, 2, 1): "Metal_Primary", (0, 2, 0): "Metal_Secondary", (1, 2, 1): "Metal_Tertiary",
       (2, 0, 1): "Accent_Color", (0, 1, 2): "Custom_1", (1, 2, 0): "Custom_2"}

con = None
_paks = {}


def fetch(path):
    """Bytes of a game file, wherever it is packed."""
    row = con.execute("select pak from file where path=?", (path.lower(),)).fetchone()
    if not row:
        return None
    full = os.path.join(index.GAME, "Localization" if row[0].startswith(("English", "Voice")) else "", row[0])
    if full not in _paks:
        _paks[full] = {e[0].lower(): e for e in lspk.entries(full)}
    return lspk.read(full, _paks[full][path.lower()])


def dds_png(path, level, extra=()):
    """A loose .dds from the paks as a cached PNG path."""
    out = os.path.join(TEX, os.path.basename(path).rsplit(".", 1)[0] + f"_l{level}.png")
    if not os.path.exists(out):
        data = fetch(path)
        if data is None:
            return None
        tmp = out[:-4] + ".dds"
        open(tmp, "wb").write(data)
        subprocess.check_call(["magick", tmp + "[0]", "-resize", f"{100 >> level}%", *extra, out])
        os.remove(tmp)
    return out


def vt_png(gtex, level):
    prefix = os.path.join(TEX, gtex)
    albedo, normal = prefix + "_albedo.png", prefix + f"_normal_gl.png"
    if not os.path.exists(albedo):
        vtex.export(gtex, prefix, level)
        if os.path.exists(prefix + "_normal.png"):
            # the game stores normals the DirectX way (green down); glTF wants green up
            subprocess.check_call(["magick", prefix + "_normal.png", "-channel", "G", "-negate", "+channel", normal])
    phys, orm = prefix + "_physical.png", prefix + "_orm.png"
    if not os.path.exists(orm) and os.path.exists(phys):
        # the game's physical map is R metal, G roughness, B occlusion; glTF wants R occlusion, G roughness, B metal. Half size is plenty.
        subprocess.check_call(["magick", phys, "-resize", "50%", "-separate", "-swap", "0,2", "-combine", "-channel", "B", "-evaluate", "multiply", "0.85", "+channel", orm])
    return (albedo if os.path.exists(albedo) else None), (normal if os.path.exists(normal) else None), (orm if os.path.exists(orm) else None)


def overrides(cv):
    """Colour and amount settings a CharacterVisual lays over its materials (skin tone, eye colour ...)."""
    vec, num = {}, {}

    def take(node):
        for p in index.kids(node, "Vector3Parameters"):
            vec[p["Parameter"]] = p["Value"]
        for p in index.kids(node, "ScalarParameters"):
            num[p["Parameter"]] = p["Value"]

    for mo in index.kids(cv, "MaterialOverrides"):
        for group in index.kids(mo, "MaterialPresets"):
            for o in group["_children"]:
                preset = index.get(con, o.get("MaterialPresetResource", ""))
                for pr in index.kids(preset, "Presets") if preset else ():
                    take(pr)
        take(mo)
    return vec, num


def skin_png(mat, level, over):
    """BG3 skin has no colour texture: the shader mixes pigments by the HMVY map (hemoglobin, melanin, vein, yellowing).
    This bakes that at full size, then adds what the shader gets from its other maps: cavity shading around the eyes, nose
    and mouth (Shading map), lips and eyebrows (CLEA map). Without them a face is a smooth pale mask."""
    params = index.kids(mat, "Texture2DParameters")
    tex = {p.get("ParameterName"): index.get(con, p["ID"]) for p in params}
    hmvy = tex.get("HMVY")
    src = hmvy and dds_png(hmvy["SourceFile"], 0)
    if not src:
        return None

    def find(word):
        for p in params:
            t = index.get(con, p["ID"])
            if t and word in t.get("SourceFile", "") and p.get("Enabled"):
                return dds_png(t["SourceFile"], 0)
        return None
    shading, clea = find("Shading_MSKA"), find("_CLEA")
    colour = {p["ParameterName"]: p["Value"] for p in index.kids(mat, "Vector3Parameters")} | over[0]
    amount = {p["ParameterName"]: p["Value"] for p in index.kids(mat, "ScalarParameters")} | over[1]
    pre = "sc_" if any(k.startswith("sc_") for k in colour) else ""  # dragonborn: sc_ pigments colour the scales, sk_ the soft skin
    colour = {k[len(pre):] if pre and k.startswith(pre) else k: v for k, v in colour.items()}
    amount = {k[len(pre):] if pre and k.startswith(pre) else k: v for k, v in amount.items()}
    tone = [colour.get(n + "Color") for n in ("Melanin", "Hemoglobin", "Yellowing", "Vein")] + [amount.get("MelaninAmount"), pre, colour.get("Eyebrow_Color"), colour.get("Lips_Makeup_Color"), "v3"]
    out = os.path.join(TEX, f"{mat['ID']}_{__import__('zlib').crc32(json.dumps(tone).encode())}_skin.png")
    if os.path.exists(out):
        return out
    raw = subprocess.check_output(["magick", src, "-depth", "8", "rgba:-"])
    w, h = (int(x) for x in subprocess.check_output(["magick", "identify", "-format", "%w %h", src]).split())
    px = np.frombuffer(raw, np.uint8).reshape(h, w, 4).astype(np.float32) / 255
    c = np.ones((h, w, 3), np.float32) * np.array([0.80, 0.58, 0.47], np.float32)  # unpigmented skin, linear-ish
    for ch, name, strength in ((1, "Melanin", 1.0), (0, "Hemoglobin", 0.55), (3, "Yellowing", 0.35), (2, "Vein", 0.35)):
        k = px[..., ch:ch + 1] * float(amount.get(name + "Amount", 0.5)) * strength
        c = c * (1 - k) + np.array(colour.get(name + "Color", [0.5, 0.3, 0.2]), np.float32) * k
    c = np.clip(c, 0, 1)
    if shading:  # the blue channel drops to zero in cavities: eye sockets, nostrils, the mouth line
        sh = pixels(shading, (w, h)).astype(np.float32) / 255
        c *= (1.0 - 0.6 * (1.0 - sh[..., 2:3]))
    if clea:  # magenta is the lips, the green channel is the eyebrows
        cl = pixels(clea, (w, h)).astype(np.float32) / 255
        lips = np.clip(cl[..., 2:3] * (1 - cl[..., 1:2]), 0, 1)
        lipc = np.array(colour.get("Lips_Makeup_Color") or [0.55, 0.2, 0.2], np.float32)
        lipc = np.maximum(lipc, 0.12) if lipc.max() > 0.05 else np.array([0.55, 0.2, 0.2], np.float32)
        c = c * (1 - 0.75 * lips) + lipc * 0.75 * lips
        brow = np.clip(cl[..., 1:2] * 1.2, 0, 1)
        browc = np.maximum(np.array(colour.get("Eyebrow_Color") or [0.08, 0.05, 0.03], np.float32), 0.05)
        c = c * (1 - 0.85 * brow) + browc * 0.85 * brow
    c = np.clip(c, 0, 1) ** (1 / 2.2)
    rng = np.random.default_rng(7)  # fine pores and mottling: skin is never one smooth tone
    coarse = np.kron(rng.normal(0, 1, (h // 16, w // 16)), np.ones((16, 16)))[..., None].astype(np.float32)
    c = c * (1 + 0.025 * rng.normal(0, 1, (h, w, 1)).astype(np.float32) + 0.03 * coarse)
    c = np.clip((c - 0.5) * 1.12 + 0.5, 0, 1)  # a little contrast: the shader's shading adds depth the bake lacks
    subprocess.run(["magick", "-size", f"{w}x{h}", "-depth", "8", "rgb:-", out], input=(c * 255).astype(np.uint8).tobytes(), check=True)
    return out


def eye_png(mat, level, over, tex):
    """The game draws an eye with a parallax shader from masks. Bake one flat picture instead: bloodshot-tinged sclera,
    a streaked iris in the character's eye colour with a dark limbal ring, a black pupil, and a catch of light."""
    region, parts = tex.get("RegionMask"), tex.get("ColorsMask")
    if not region:
        return None
    colour = {p["ParameterName"]: p["Value"] for p in index.kids(mat, "Vector3Parameters")} | over[0]
    iris = colour.get("Eyes_IrisColour") or [0.25, 0.15, 0.08]
    sec = colour.get("Eyes_IrisSecondaryColour") or iris
    out = os.path.join(TEX, f"eye_{__import__('zlib').crc32(json.dumps([iris, sec, 'v1']).encode())}.png")
    if os.path.exists(out):
        return out
    rp = dds_png(region["SourceFile"], 1)
    w, h = (int(x) for x in subprocess.check_output(["magick", "identify", "-format", "%w %h", rp]).split())
    r = pixels(rp).astype(np.float32) / 255
    strand = np.zeros((h, w, 1), np.float32)
    if parts:
        pp = dds_png(parts["SourceFile"], 1)
        strand = 1 - pixels(pp, (w, h)).astype(np.float32)[..., 2:3] / 255
    pupil = np.clip((r[..., 1:2] * (1 - r[..., 2:3]) - 0.3) * 4, 0, 1)
    irism = np.clip((1 - r[..., 1:2]) * 2.2, 0, 1) * (1 - pupil)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    # the iris is centred in the map; its limbal ring darkens toward the outer edge of the iris mask
    edge = np.clip(1 - np.abs(irism - 0.5) * 2, 0, 1) * (irism > 0.05)
    ic = np.array(iris, np.float32) ** (1 / 2.2)
    sc = np.array(sec, np.float32) ** (1 / 2.2)
    irisc = ic * (1 - strand * 0.8) + sc * strand * 0.8
    irisc = irisc * (0.7 + 0.5 * strand) * (1 - 0.45 * edge)
    irisc = np.clip(irisc * 0.9 + 0.02, 0, 1)
    sclera = np.array([0.90, 0.86, 0.82], np.float32)
    sclera = sclera * (1 - 0.18 * np.clip(1 - r[..., 0:1], 0, 1)) + np.array([0.7, 0.35, 0.3], np.float32) * 0.1 * (1 - irism)
    c = sclera * (1 - irism) + irisc * irism
    c = c * (1 - pupil) + np.array([0.02, 0.02, 0.025], np.float32) * pupil
    subprocess.run(["magick", "-size", f"{w}x{h}", "-depth", "8", "rgb:-", out], input=(np.clip(c, 0, 1) * 255).astype(np.uint8).tobytes(), check=True)
    return out


def hair_png(mask_png, colour, level):
    """Hair, beards and brows have no colour texture: the game tints a strand mask (ID, depth, root, alpha)
    with the character's hair colour. Bake that: colour varied per strand, darker deep in the mass, root to tip."""
    key = __import__("zlib").crc32(json.dumps(colour).encode())
    out = mask_png[:-4] + f"_hair{key}.png"
    if os.path.exists(out):
        return out
    w, h = (int(x) for x in subprocess.check_output(["magick", "identify", "-format", "%w %h", mask_png]).split())
    px = np.frombuffer(subprocess.check_output(["magick", mask_png, "-depth", "8", "rgba:-"]), np.uint8).reshape(h, w, 4).astype(np.float32) / 255
    base = np.clip(np.array(colour, np.float32), 0, 1) ** (1 / 2.2)
    base = np.maximum(base, 0.07)  # nobody has pure black hair under a lit scene
    shade = (0.65 + 0.7 * px[..., 0:1]) * (0.55 + 0.45 * px[..., 1:2]) * (1.0 - 0.25 * px[..., 2:3])
    rgb = np.clip(base * shade, 0, 1)
    img = np.concatenate([rgb, px[..., 3:4]], axis=2)
    subprocess.run(["magick", "-size", f"{w}x{h}", "-depth", "8", "rgba:-", out], input=(img * 255).astype(np.uint8).tobytes(), check=True)
    return out


def pixels(png, size=None):
    """PNG -> (h, w, 3) uint8 array, optionally resized without blending (for masks)."""
    cmd = ["magick", png] + (["-filter", "point", "-resize", f"{size[0]}x{size[1]}!"] if size else []) + ["-alpha", "off", "-depth", "8", "rgb:-"]
    if not size:
        size = [int(x) for x in subprocess.check_output(["magick", "identify", "-format", "%w %h", png]).split()]
    return np.frombuffer(subprocess.check_output(cmd), np.uint8).reshape(size[1], size[0], 3)


def dyed_png(mat, albedo, mask_path, level, over):
    """Multiply the (grey) armour albedo by the dye colour each pixel's mask slot asks for."""
    colours = {p["ParameterName"]: p["Value"] for p in index.kids(mat, "Vector3Parameters")} | over[0]
    key = __import__("zlib").crc32(json.dumps([colours.get(n) for n in DYE.values()]).encode())
    out = albedo[:-4] + f"_dye{key}.png"
    mask = dds_png(mask_path, level)
    if os.path.exists(out) or not mask:
        return out if os.path.exists(out) else albedo
    base = pixels(albedo).astype(np.float32) / 255
    h, w = base.shape[:2]
    code = np.round(pixels(mask, (w, h)) / 127.5).astype(np.int32)
    code = code[..., 0] * 9 + code[..., 1] * 3 + code[..., 2]
    tint = np.ones((27, 3), np.float32)
    for (r, g, b), slot in DYE.items():
        if slot in colours:
            tint[r * 9 + g * 3 + b] = np.clip(np.array(colours[slot], np.float32), 0, 1) ** (1 / 2.2)
    px = (np.clip(base * tint[code], 0, 1) * 255).astype(np.uint8)
    subprocess.run(["magick", "-size", f"{w}x{h}", "-depth", "8", "rgb:-", albedo, "-compose", "CopyOpacity", "-composite", out],
                   input=px.tobytes(), check=True)  # colour from the bake, see-through parts from the original
    return out


def material(mid, level, over=({}, {})):
    """Resource id of a material -> entry for gr2gltf (None = leave the mesh out)."""
    mat = index.get(con, mid)
    if not mat:
        return {}
    src = mat.get("SourceFile", "")
    if any(s in src or s in mat.get("Name", "") for s in SKIP_MATERIALS):
        return None
    out = {}
    if "CHAR_Skin_Body" in src:  # the body's own texture is the underwear; build() gives it the head's skin tone
        return {"skin_body": True}
    for p in index.kids(mat, "VirtualTextureParameters"):
        vt = p.get("Enabled") and index.get(con, p["ID"])
        if vt and vt.get("GTexFileName"):
            out["albedo"], out["normal"], out["orm"] = vt_png(vt["GTexFileName"], level)
            out["alpha"] = any(k in src for k in CUTOUT)
            mask = next((index.get(con, t["ID"]) for t in index.kids(mat, "Texture2DParameters")
                         if t.get("ParameterName") == "MSKColor" and t.get("Enabled")), None)
            if mask and out["albedo"]:
                out["albedo"] = dyed_png(mat, out["albedo"], mask["SourceFile"], level, over)
            return out
    tex = {p.get("ParameterName"): index.get(con, p["ID"]) for p in index.kids(mat, "Texture2DParameters") if p.get("Enabled")}
    if "CHAR_Hair" in src and tex.get("ID_Depth_Root_Alpha_MSKA"):
        name = mat.get("Name", "")
        key = "Beard_Color" if "Beard" in name else "Eyebrow_Color" if "Brow" in name else "Hair_Color"
        colour = over[0].get(key) or over[0].get("Hair_Color") or [0.1, 0.05, 0.02]
        mask = dds_png(tex["ID_Depth_Root_Alpha_MSKA"]["SourceFile"], level)
        if mask:
            return {"albedo": hair_png(mask, colour, level), "alpha": True}
    if "HMVY" in tex:
        out["albedo"] = skin_png(mat, level, over)
    else:
        for name in BASECOLOR:
            if tex.get(name):
                out["albedo"] = dds_png(tex[name]["SourceFile"], level)
                out["alpha"] = any(k in src for k in CUTOUT)
                break
    if "Feather" in src and tex.get("basecolor") and tex.get("Body_color_texture"):
        # feather cards are grey; the shader colours them from the body texture. Use that texture's average.
        body = dds_png(tex["Body_color_texture"]["SourceFile"], level)
        if body:
            mean = pixels(body).reshape(-1, 3).mean(0) / 255
            out["color"] = [*(float(x) ** 2.2 for x in mean), 1.0]
    nm = tex.get("normalmap") or tex.get("NormalMap") or tex.get("Fur_normalmap")
    if nm:
        out["normal"] = dds_png(nm["SourceFile"], level, ("-channel", "G", "-negate", "+channel"))
    if "Eye" in src:
        baked = eye_png(mat, level, over, tex)
        if baked:
            out["albedo"] = baked
            out["rough"] = 0.1  # glossy
        else:
            iris = over[0].get("Eyes_IrisColour") or next(
                (p["Value"] for p in index.kids(mat, "Vector3Parameters") if "Iris" in p.get("ParameterName", "")),
                [0.75, 0.4, 0.05] if "DGB" in mat.get("Name", "") else [0.25, 0.15, 0.08])  # dragonborn flame eyes: amber
            out["color"] = [*iris, 1.0]
    return out


SCALPS = [  # (hair name words, scalp texture): the strand pattern the game paints on the crown of the head under a hairstyle
    ("F", "AFRO", "SHORT", "HAIR_HUM_F_Afro_Short_A"), ("F", "AFRO", "", "HAIR_HUM_F_Afro_Long_A"),
    ("F", "CURLY", "", "HUM_F_NKD_Hair_FemCurly_Short_A"), ("F", "BRAIDS", "SHORT", "HUM_F_NKD_Hair_FemBraids_Short_B"),
    ("F", "BRAIDS", "", "HUM_F_NKD_Hair_FemBraids_Long_A_Spring"), ("F", "DREADS", "", "HUM_F_NKD_Hair_FemDreads_Long_A_Spring"),
    ("F", "GNOMECUT", "", "HUM_F_NKD_Hair_GnomeFemCut_Long_C"), ("F", "GITHYANKICUT", "", "HUM_F_NKD_Hair_GithyankiFemCut_Long_A"),
    ("F", "ORCCUT", "", "HAIR_HUM_F_OrcCut_Long_A"), ("F", "", "SHORT", "HUM_F_NKD_Hair_FemStraight_Short_A"),
    ("F", "", "", "HUM_F_NKD_Hair_FemStraight_Long_A"),
    ("M", "AFRO", "", "HUM_M_NKD_Hair_MenAfro_Short_B"), ("M", "CURLY", "", "HUM_F_NKD_Hair_MenCurly_Short_B"),
    ("M", "DREADS", "", "HUM_M_NKD_Hair_MenDreads_Short_A"), ("M", "WAVY", "LONG", "HUM_M_NKD_Hair_MenWavy_Long_B"),
    ("M", "WAVY", "", "HUM_M_NKD_Hair_MenWavy_Short_C"), ("M", "", "LONG", "HUM_M_NKD_Hair_MenStraight_Long_A"),
    ("M", "", "", "HUM_M_NKD_Hair_MenStraight_Short_C"),
]


def scalp_png(hair_name, colour, level):
    """The hair on top of the head. The hair mesh holds only the locks that hang or stand off the scalp; the crown is
    painted on the head's scalp mesh from a strand map picked by hairstyle (the game stores a ScalpIndex per style).
    Returns a baked strand-colour PNG or None."""
    n = hair_name.upper()
    sex = "M" if ("_M_" in n or "_MS_" in n) else "F"
    for s_, style, length, tex in SCALPS:
        if s_ == sex and (not style or style in n) and (not length or length in n):
            row = con.execute("select source from res where bank='Texture' and source like ? escape '\\' limit 1", (f"%/{tex}\\_Scalp.DDS",)).fetchone()
            if row:
                mask = dds_png(row[0], level)
                return hair_png(mask, colour, level) if mask else None
    return None


FAMILY_SEX = re.compile(r"^([A-Z]{3})_(F|M)(S?)_")


def _swap_sex(vname, sex):
    """HUM_F_ARM_Robe_A_Body -> HUM_M_ARM_Robe_A_Body: armour names are parallel across the two sexes."""
    m = FAMILY_SEX.match(vname)
    return vname if not m or not sex else f"HUM_{sex}_" + vname[m.end():]  # every outfit is cut for the medium human body of that sex


def visuals(name, mode="", sex=""):
    """-> (list of Visual resources, skeleton resource id or '', material overrides).
    mode "bare": the body and head of a character without its clothes, hair or beard (underwear stays);
    mode "dress": only the clothes and armour of a character, for fitting onto any body at run time (sex F or M swaps the names)."""
    row = con.execute("select body from res where bank='CharacterVisual' and (id=? or name=? collate nocase or name like ? escape '\\' or name like ? escape '\\') limit 1",
                      (name, name, name + "\\_%", name.replace("_", "\\_") + "-%")).fetchone()
    if not row:
        v = index.get(con, name, "Visual")
        if not v or "SourceFile" not in v:
            sys.exit(f"no Visual or CharacterVisual called {name}")
        return [v], v.get("SkeletonResource", ""), ({}, {})
    cv = json.loads(row[0])
    chosen = [] if mode == "dress" else [index.get(con, cv.get("BodySetVisual"))]
    for sl in index.kids(cv, "Slots"):
        v = index.get(con, sl["VisualResource"]) if sl.get("VisualResource") else None
        n = (v or {}).get("Name", "").upper()
        worn = "_ARM_" in n or "_CLT_" in n or n.startswith("HAIR_") or n.startswith("BEARD_") or "_HAIR_" in n
        if mode == "bare" and ((worn and sl["Slot"] != "Underwear") or sl["Slot"] in ("Private Parts", "ModestyLeaf", "NakedBody", "Body", "Unassigned")):
            continue
        if mode == "dress":
            if not worn or n.startswith("HAIR_") or n.startswith("BEARD_") or "_HAIR_" in n or sl["Slot"] == "Underwear":
                continue
            if "HEADWEAR" in n or "HELMET" in n or "HOOD" in n:  # heads stay bare: hair, horns and faces are what the player designed
                continue
            if sex:
                v = index.get(con, _swap_sex(v["Name"], sex), "Visual")
        chosen.append(v)
    out = [v for v in chosen if v and str(v.get("SourceFile", "")).lower().endswith(".gr2")]
    base = index.get(con, cv.get("BaseVisual", "")) or {}
    skel = base.get("SkeletonResource") or next((v.get("SkeletonResource") for v in out if v.get("SkeletonResource")), "")
    return out, skel, overrides(cv)


def animations(skel):
    """All animations bound to a skeleton resource: {name: source path}."""
    if not skel:
        return {}
    rows = con.execute("select name, source from res where bank='Animation' and body like ?", (f'%"SkeletonResource": "{skel}"%',))
    return {n: s for n, s in rows if s}


def pick(avail, want):
    if want == "none":
        return {}
    if want == "all":
        return avail
    if want != "standard":
        return {n: s for n, s in avail.items() if re.search(want, n, re.I)}
    out = {}
    names = [n for n in sorted(avail) if not re.search(r"_(LIE|SIT|CROUCH|KNEEL)_", n)]  # a lying or sitting clip is never an idle stance
    for ours, patterns in STANDARD.items():
        hit = next((n for p in patterns for n in names if re.search(p, n, re.I)), None)
        if hit:
            out[ours] = avail[hit]
    return out


def build(out, names, anims="standard", level=1, list_only=False, rig="", skel_name="", mode="", sex="", white_hair=False):
    global con
    con = index.db()
    os.makedirs(TEX, exist_ok=True)
    vis, skel, over = [], "", ({}, {})
    for i, n in enumerate(names):
        v, s, o = visuals(n, mode if i == 0 else "", sex)
        vis += v
        skel = skel or s
        over = (over[0] | o[0], over[1] | o[1])
    if skel_name:  # a part (hair, outfit) built to be fitted onto a body at run time still needs that body's rig for its skin
        sk0 = index.get(con, skel_name, "Skeleton")
        skel = sk0["ID"] if sk0 else sys.exit(f"no Skeleton called {skel_name}")
    if white_hair:  # hair for run-time tinting: baked neutral, the game multiplies by the chosen colour
        over = ({**over[0], "Hair_Color": [1, 1, 1], "Beard_Color": [1, 1, 1]}, over[1])
    avail = animations(skel)
    if rig:
        avail |= {n: s for n, s in con.execute("select name, source from res where bank='Animation' and name like ?", (rig + "%",)) if s}
    if list_only:
        print("\n".join(sorted(avail)))
        return
    parts, mats = [], {}
    sk = index.get(con, skel) if skel else None
    if sk and sk.get("SourceFile"):  # the skeleton file first, so every part binds to the full rig
        data = fetch(sk["SourceFile"])
        if data:
            parts.append(data)
    for v in vis:
        data = fetch(v["SourceFile"])
        if data is None:
            print("missing file", v["SourceFile"])
            continue
        parts.append(data)
        for o in index.kids(v, "Objects"):
            mesh = o["ObjectID"].split(".")[1]
            if o.get("LOD", 0) == 0 and mesh not in mats:
                mats[mesh] = material(o["MaterialID"], level, over)
    if mode == "bare":  # the crown hair is chosen later: keep the scalp mesh, the game paints it
        for mesh in [k for k in mats if k.endswith("_Scalp_Mesh")]:
            mats[mesh] = {"alpha": True, "scalp": True}
    for v in vis:  # hair on the crown: the head's scalp mesh gets the strand map of the chosen hairstyle
        hn = v.get("Name", "")
        if hn.upper().startswith("HAIR_") and "BEARD" not in hn.upper():
            png = scalp_png(hn, over[0].get("Hair_Color") or [0.1, 0.05, 0.02], level)
            for mesh in [k for k in mats if k.endswith("_Scalp_Mesh")]:
                if png:
                    mats[mesh] = {"albedo": png, "alpha": True, "scalp": True}
            break
    heads = [m["albedo"] for m in mats.values() if m and m.get("albedo", "").endswith("_skin.png")]
    tone = [0.6, 0.4, 0.3, 1.0]  # no head to copy: a plain mid skin tone
    if heads:
        tone = [*(float(x) ** 2.2 for x in pixels(heads[0]).reshape(-1, 3).mean(0) / 255), 1.0]
    for m in mats.values():
        if m and m.pop("skin_body", False):
            m["color"] = tone
    if mode == "dress":  # which body regions the clothes cover (the body's vertex colour numbers them), for the game to hide
        hide = sorted({c["Object"] for v in vis for c in v.get("_children", []) if c["_id"] == "VertexColorMaskSlots"})
        open(out + ".hide.txt", "w").write(" ".join(h.replace(" ", "_") for h in hide))
    chosen = [(n, d) for n, d in ((n, fetch(s)) for n, s in pick(avail, anims).items()) if d]
    gr2gltf.convert(out, parts, chosen, mats)


if __name__ == "__main__":
    a = sys.argv[1:]
    opt = {"--anims": "standard", "--level": "1", "--rig": "", "--skel": "", "--sex": ""}
    for k in list(opt):
        if k in a:
            i = a.index(k)
            opt[k] = a[i + 1]
            del a[i:i + 2]
    list_only = "--list" in a
    mode = "bare" if "--bare" in a else "dress" if "--dress" in a else ""
    white = "--white-hair" in a
    a = [x for x in a if x not in ("--list", "--bare", "--dress", "--white-hair")]
    if len(a) < 2:
        sys.exit(__doc__)
    build(a[0], a[1:], opt["--anims"], int(opt["--level"]), list_only, opt["--rig"], opt["--skel"], mode, opt["--sex"], white)
