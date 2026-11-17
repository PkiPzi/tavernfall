#!/usr/bin/env -S uv run --script
# /// script
# dependencies = ["numpy"]
# ///
"""Turn Baldur's Gate 3 .gr2 files into one .glb that Godot imports.

  gr2gltf.py out.glb part1.gr2 [part2.gr2 ...] [--anim name=file.gr2 ...]

This is the plain converter (grey, untextured). creature.py wraps it and adds the right
parts, textures and animations for a named BG3 creature or object.

All parts must share a skeleton (body, head, armour pieces of one creature). The skeleton
comes from the first file that has one; meshes are bound to it by bone name.
LOD copies (mesh names ending _LOD1.. ) are skipped.
"""
import os, subprocess, json, os, struct, sys
import numpy as np
import gr2
import gr2anim


class Glb:
    def __init__(self):
        self.bin = bytearray()
        self.j = {"asset": {"version": "2.0", "generator": "tavernfall gr2gltf"}, "scene": 0, "scenes": [{"nodes": []}],
                  "nodes": [], "meshes": [], "accessors": [], "bufferViews": [], "materials": []}

    def accessor(self, arr, kind, target=None, minmax=False, normalized=False):
        arr = np.ascontiguousarray(arr)
        while len(self.bin) % 4:
            self.bin.append(0)
        view = {"buffer": 0, "byteOffset": len(self.bin), "byteLength": arr.nbytes}
        if target:
            view["target"] = target
        self.bin += arr.tobytes()
        self.j["bufferViews"].append(view)
        comp = {"float32": 5126, "uint16": 5123, "uint32": 5125, "uint8": 5121}[arr.dtype.name]
        acc = {"bufferView": len(self.j["bufferViews"]) - 1, "componentType": comp, "count": len(arr), "type": kind}
        if normalized:
            acc["normalized"] = True
        if minmax:
            acc["min"], acc["max"] = np.atleast_1d(arr.min(0)).tolist(), np.atleast_1d(arr.max(0)).tolist()
        self.j["accessors"].append(acc)
        return len(self.j["accessors"]) - 1

    def image(self, path, jpeg=False, q=88):
        """Embed a PNG; jpeg=True stores it as a JPEG a fifth of the size (colour and surface maps without see-through parts)."""
        seen = self.__dict__.setdefault("_seen", {})
        if (path, jpeg, q) in seen:  # the same texture used by several meshes is stored once
            return seen[(path, jpeg, q)]
        mime = "image/png"
        key = (path, jpeg, q)
        if jpeg and os.environ.get("GLB_JPEG", "1") != "0":
            jpg = path[:-4] + f".q{q}.jpg"
            if not os.path.exists(jpg):
                subprocess.run(["magick", path, "-alpha", "off", "-sampling-factor", "4:4:4", "-quality", str(q), jpg], check=True)
            path, mime = jpg, "image/jpeg"
        data = open(path, "rb").read()
        while len(self.bin) % 4:
            self.bin.append(0)
        self.j["bufferViews"].append({"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(data)})
        self.bin += data
        self.j.setdefault("images", []).append({"bufferView": len(self.j["bufferViews"]) - 1, "mimeType": mime})
        self.j.setdefault("textures", []).append({"source": len(self.j["images"]) - 1})
        seen[key] = len(self.j["textures"]) - 1
        return seen[key]

    def save(self, path):
        while len(self.bin) % 4:
            self.bin.append(0)
        self.j["buffers"] = [{"byteLength": len(self.bin)}]
        self.j = {k: v for k, v in self.j.items() if v != []}
        text = json.dumps(self.j, separators=(",", ":")).encode()
        text += b" " * (-len(text) % 4)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, 28 + len(text) + len(self.bin)))
            f.write(struct.pack("<II", len(text), 0x4E4F534A) + text)
            f.write(struct.pack("<II", len(self.bin), 0x004E4942) + self.bin)


def normals(qt):
    """QTangent (int16 quaternion of the tangent frame) -> unit normals."""
    q = qt.astype(np.float32) / 32767.0
    x, y, z, w = q.T
    n = np.stack([2 * (x * z + w * y), 2 * (y * z - w * x), 1 - 2 * (x * x + y * y)], 1)
    return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-8)


# The game's data is left-handed (characters face -Z with their right side at -X). Everything
# is mirrored along Z on the way out, so models are right-handed and face +Z like other glTF.
FLIP_V = np.array([1, 1, -1], np.float32)
FLIP_Q = np.array([-1, -1, 1, 1], np.float32)
FLIP_M = np.array([[-1 if (r == 2) != (c == 2) else 1 for r in range(4)] for c in range(4)], np.float32).reshape(16)


def trs(node, tr):
    if tr["flags"] & 1:
        node["translation"] = [float(x) for x in tr["t"] * FLIP_V]
    if tr["flags"] & 2:
        node["rotation"] = [float(x) for x in tr["r"] * FLIP_Q]
    if tr["flags"] & 4:
        node["scale"] = [float(tr["s"][i][i]) for i in range(3)]


def _bytes(x):
    return x if isinstance(x, bytes) else open(x, "rb").read()


def convert(out, parts, anims=(), materials=None):
    """parts: .gr2 paths or bytes. anims: (name, path-or-bytes) pairs.
    materials: {mesh name: None to drop the mesh, or {"albedo": png, "normal": png, "color": [r,g,b,a],
    "alpha": bool}}; meshes not listed get plain grey."""
    g = Glb()
    materials = materials or {}
    roots = [gr2.load(_bytes(p)) for p in parts]
    # One skeleton for everything: the first file's bones, plus any extra bones later parts bring
    # (a head carries face bones the body rig lacks), hung under their parent by name.
    bones, index = [], {}
    for r in roots:
        for sk in r["Skeletons"]:
            for b in sk["Bones"]:
                if b["Name"] in index:
                    continue
                parent = sk["Bones"][b["ParentIndex"]]["Name"] if b["ParentIndex"] >= 0 else None
                index[b["Name"]] = len(bones)
                bones.append((b, index.get(parent, -1) if parent else -1))
    skin = None
    if bones:
        for i, (b, parent) in enumerate(bones):
            node = {"name": b["Name"]}
            trs(node, b["Transform"])
            g.j["nodes"].append(node)
            if parent >= 0:
                g.j["nodes"][parent].setdefault("children", []).append(i)
            else:
                g.j["scenes"][0]["nodes"].append(i)
        ibm = np.array([b["InverseWorldTransform"] for b, _ in bones], np.float32) * FLIP_M
        g.j["skins"] = [{"joints": list(range(len(bones))), "inverseBindMatrices": g.accessor(ibm, "MAT4")}]
        skin = 0
        base_ibm = ibm

    for root in roots:
        # A hair piece or helmet made for another body (a taller rig) carries that rig's bind pose. Left alone it hangs where
        # the other rig's head was, so its vertices are moved to where this body's bones put them (rest pose only).
        retarget = None
        if skin is not None and root is not roots[0]:
            own = base_ibm.copy()
            for sk in root["Skeletons"]:
                for b in sk["Bones"]:
                    if b["Name"] in index:
                        own[index[b["Name"]]] = np.array(b["InverseWorldTransform"], np.float32) * FLIP_M
            if not np.allclose(own, base_ibm, atol=1e-4):
                # glTF reads the 16 floats column-major, so the matrix in use is the transpose of the stored 4x4
                ob = base_ibm.reshape(-1, 4, 4).transpose(0, 2, 1).astype(np.float64)
                oh = own.reshape(-1, 4, 4).transpose(0, 2, 1).astype(np.float64)
                retarget = np.einsum("nij,njk->nik", np.linalg.inv(ob), oh).astype(np.float32)
        for mesh in root["Meshes"]:
            name = mesh["Name"]
            if "_LOD" in name.upper() or (name in materials and materials[name] is None):
                continue
            v = mesh["PrimaryVertexData"]["Vertices"]
            topo = mesh["PrimaryTopology"]
            idx = topo["Indices"] if len(topo["Indices"]) else topo["Indices16"]
            if not len(v) or not len(idx):
                continue
            idx = np.frombuffer(idx.tobytes(), "<i4" if len(topo["Indices"]) else "<u2").astype(np.uint32)
            idx = idx[:len(idx) // 3 * 3]  # the Z mirror below already turns the triangles round; reversing them again made every mesh inside out
            names = v.dtype.names
            pos = v["Position"].astype(np.float32) * FLIP_V
            nrm = None
            attr = {}
            if "QTangent" in names:
                nrm = -normals(v["QTangent"]) * FLIP_V  # the decoded frame's Z points into the surface in these meshes
            elif "Normal" in names:
                nrm = v["Normal"].astype(np.float32) * FLIP_V
            if "NKD_Body" in name and "DiffuseColor0" in names:  # the body's vertex colour (G) numbers its regions: outfits hide the ones they cover
                attr["COLOR_0"] = g.accessor(v["DiffuseColor0"].astype(np.float32) / 255, "VEC4", 34962)
            if "TextureCoordinates0" in names:
                attr["TEXCOORD_0"] = g.accessor(v["TextureCoordinates0"].astype(np.float32), "VEC2", 34962)
            skinned = skin is not None and len(mesh["BoneBindings"]) > 0
            if skinned:
                remap = np.array([index.get(b["BoneName"], 0) for b in mesh["BoneBindings"]], np.uint16)
                if "BoneIndices" in names:
                    w = v["BoneWeights"].astype(np.float32)
                    w /= np.maximum(w.sum(1, keepdims=True), 1e-8)
                    joints = remap[np.minimum(v["BoneIndices"], len(remap) - 1)]
                    joints[w == 0] = 0
                else:  # a rigid piece (helmet, ears): the whole mesh rides on its one bone
                    w = np.tile(np.array([1, 0, 0, 0], np.float32), (len(v), 1))
                    joints = np.tile(np.array([remap[0], 0, 0, 0], np.uint16), (len(v), 1))
                if retarget is not None:
                    mv = np.einsum("nk,nkij->nij", w, retarget[joints.astype(int)])
                    pos = np.einsum("nij,nj->ni", mv, np.concatenate([pos, np.ones((len(pos), 1), np.float32)], 1))[:, :3].astype(np.float32)
                    if nrm is not None:
                        nrm = np.einsum("nij,nj->ni", mv[:, :3, :3], nrm).astype(np.float32)
                attr["JOINTS_0"] = g.accessor(joints, "VEC4", 34962)
                attr["WEIGHTS_0"] = g.accessor(w, "VEC4", 34962)
            if materials.get(name, {}) and materials[name].get("scalp") and nrm is not None:
                pos = pos + nrm * 0.0025  # the crown hair sits a hair's breadth above the skin so the two do not flicker
            attr["POSITION"] = g.accessor(pos, "VEC3", 34962, minmax=True)
            if nrm is not None:
                attr["NORMAL"] = g.accessor(nrm, "VEC3", 34962)
            m = materials.get(name, {})
            pbr = {"metallicFactor": 0.0, "roughnessFactor": 0.8}
            mat = {"name": name, "pbrMetallicRoughness": pbr, "doubleSided": True}
            if m.get("color"):
                pbr["baseColorFactor"] = m["color"]
            if m.get("albedo"):
                pbr["baseColorTexture"] = {"index": g.image(m["albedo"], jpeg=not m.get("alpha"))}
            if m.get("normal"):
                mat["normalTexture"] = {"index": g.image(m["normal"], jpeg=True, q=93)}
            if m.get("rough") is not None:
                pbr["roughnessFactor"] = m["rough"]
            if m.get("orm"):  # occlusion in R, roughness in G, metal in B
                i = g.image(m["orm"], jpeg=True)
                pbr["metallicRoughnessTexture"] = {"index": i}
                pbr["metallicFactor"], pbr["roughnessFactor"] = 1.0, 1.0
                mat["occlusionTexture"] = {"index": i}
            if m.get("alpha"):
                mat["alphaMode"], mat["alphaCutoff"] = "MASK", 0.5
            g.j["materials"].append(mat)
            g.j["meshes"].append({"name": name, "primitives": [
                {"attributes": attr, "indices": g.accessor(idx, "SCALAR", 34963), "material": len(g.j["materials"]) - 1}]})
            node = {"name": name, "mesh": len(g.j["meshes"]) - 1}
            if skinned:
                node["skin"] = skin
            g.j["nodes"].append(node)
            g.j["scenes"][0]["nodes"].append(len(g.j["nodes"]) - 1)

    for name, path in anims:
        gr2anim.add(g, index, name, gr2.load(_bytes(path)))
    g.save(out)
    print(f"{out}: {len(g.j.get('meshes', []))} meshes, {len(bones)} bones, {len(g.j.get('animations', []))} animations")


if __name__ == "__main__":
    args = sys.argv[1:]
    if len(args) < 2:
        sys.exit(__doc__)
    out, parts, anims = args[0], [], []
    it = iter(args[1:])
    for a in it:
        if a == "--anim":
            anims.append(next(it).split("=", 1))
        else:
            parts.append(a)
    convert(out, parts, anims)
