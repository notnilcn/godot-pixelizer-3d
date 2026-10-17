"""Build the t3ssel8r player character (white-haired elf swordsman) from scratch.

Spec: docs/references/t3ssel8r/refs/player/SPEC.md

Run (headless, deterministic, from any cwd):
    blender --background --factory-startup --python build_player.py

Produces (paths relative to this file's folder `models/blend/`):
    player.blend                  the built scene (rest pose)
    ../player.glb                 glTF 2.0 binary, +Y up, armature + skin + materials
    ../renders/player_*.png       review renders + player_compare.png

Conventions: metres, soles on Z = 0, origin centred between the feet, facing
Blender -Y (exports to glTF/Godot +Z = Vector3.MODEL_FRONT), character's left = +X.
"""

import json
import math
import os
import struct
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Quaternion, Vector

# --------------------------------------------------------------------------
# Paths
# --------------------------------------------------------------------------
HERE = os.path.dirname(os.path.abspath(__file__))
MODELS_DIR = os.path.dirname(HERE)
RENDER_DIR = os.path.join(MODELS_DIR, "renders")
REPO_DIR = os.path.normpath(os.path.join(MODELS_DIR, "..", ".."))   # <repo>/t3ssel8r/models
REF_DIR = os.path.join(REPO_DIR, "docs", "references", "t3ssel8r", "refs", "player")
BLEND_PATH = os.path.join(HERE, "player.blend")
GLB_PATH = os.path.join(MODELS_DIR, "player.glb")

# --------------------------------------------------------------------------
# Tuning constants (metres unless noted)
# --------------------------------------------------------------------------
# Colours (sRGB hex, SPEC section 5)
COL = {
    "hair": "#E8E8E8",
    "skin": "#D6A28C",
    "eyes": "#101012",
    "shirt": "#393A39",
    "collar": "#997967",
    "cape": "#592B0D",
    "shorts": "#784F36",
    "tights": "#141418",
    "boots": "#4E260F",   # a touch darker than the cape so legs/boots/cape separate
    "belt": "#1D120E",
    "blade": "#A8A8A8",
    "hilt": "#393A39",
}
# Set to "skin" to switch the legs to bare skin (SPEC uncertainty 1).
LEG_STYLE = "tights"

# Vertical landmarks
H_TOTAL = 1.50
Z_CHIN = 1.19
Z_EYES = 1.33
Z_FRINGE = 1.37
Z_SHOULDER = 1.165
Z_BELT = 0.77
Z_SHORTS_HEM = 0.58
Z_CROTCH = 0.63
Z_KNEE = 0.38
Z_BOOT_TOP = 0.355
Z_HIP = 0.70

# Head
HEAD_RINGS = [  # (z, half-width x, half-depth y, centre y)
    (Z_CHIN, 0.050, 0.045, -0.025),
    (1.235, 0.085, 0.080, -0.008),
    (1.300, 0.100, 0.095, 0.000),
    (1.420, 0.095, 0.095, 0.005),
    (1.455, 0.065, 0.070, 0.005),
]
EYE_W, EYE_H, EYE_SEP = 0.045, 0.025, 0.035
# Hair shell: ellipsoid cut by a height function of the angle around the head
HAIR_C = (0.0, 0.012, 1.372)
HAIR_R = (0.158, 0.152, 0.128)
HAIR_CUT_FRONT = Z_FRINGE   # straight fringe
HAIR_CUT_SIDE = 1.290
HAIR_CUT_BACK = 1.250
HAIR_COLS, HAIR_ROWS = 14, 5
BUN_C = (0.0, 0.080, 1.495)
BUN_R = (0.058, 0.056, 0.050)
BUN_TILT_DEG = 25.0
LOCK_TOP, LOCK_BOT = 1.345, 1.215
LOCK_X, LOCK_Y = 0.118, -0.066
LOCK_W_TOP, LOCK_W_BOT, LOCK_T = 0.055, 0.026, 0.020
EAR_ROOT = (0.094, 0.012, 1.335)
EAR_LEN, EAR_ROOT_H, EAR_ROOT_D = 0.125, 0.050, 0.030
EAR_UP_DEG, EAR_BACK_DEG = 15.0, 20.0

# Neck / collar
NECK_R, NECK_Z0, NECK_Z1 = 0.040, 1.13, 1.215
COLLAR_RX, COLLAR_RY, COLLAR_Z0, COLLAR_Z1 = 0.072, 0.066, 1.140, 1.200

# Torso (shirt) rings: (z, half x, half y)
SHIRT_RINGS = [
    (0.735, 0.108, 0.070),
    (0.860, 0.113, 0.072),
    (0.990, 0.122, 0.077),
    (1.100, 0.125, 0.075),
    (Z_SHOULDER, 0.085, 0.060),
]
BELT_Z0, BELT_Z1, BELT_RX, BELT_RY = 0.755, 0.787, 0.116, 0.077

# Shorts / tunic skirt: (z, half x, half y)
SHORTS_RINGS = [(0.790, 0.112, 0.076), (0.700, 0.150, 0.096), (Z_SHORTS_HEM, 0.190, 0.112)]
SHORTS_SPLIT_Z = 0.625     # front/back centre of the hem lifted to this height
SHORTS_SIDES = 12

# Legs
FOOT_X = 0.075             # feet 0.15 m apart centre to centre
LEG_RINGS = [(0.700, 0.058), (0.550, 0.054), (Z_KNEE, 0.046), (0.320, 0.043)]
BOOT_RINGS = [(0.060, 0.050), (0.300, 0.050), (0.335, 0.058), (Z_BOOT_TOP + 0.01, 0.061)]
# Foot sections along -Y: (y, z_bottom, z_top, half width)
FOOT_SECTIONS = [(0.055, 0.0, 0.090, 0.045), (-0.030, 0.0, 0.095, 0.050),
                 (-0.100, 0.0, 0.070, 0.050), (-0.150, 0.018, 0.052, 0.040)]

# Arms (A-pose)
SHOULDER_JOINT = (0.110, 0.0, 1.120)
ARM_DOWN_DEG = 40.0        # upper arm below horizontal
ELBOW_BEND_DEG = 10.0
UPPER_ARM_LEN, FOREARM_LEN, HAND_LEN = 0.22, 0.20, 0.085
ARM_R = (0.037, 0.035, 0.032, 0.029)   # shoulder, mid upper, elbow, wrist radii
HAND_HALF_W, HAND_HALF_T = 0.030, 0.016

# Cape rows: (z, half x, half y, half front opening at that row)
CAPE_ROWS = [
    (1.205, 0.088, 0.076, 0.045),
    (1.130, 0.205, 0.130, 0.050),
    (0.985, 0.285, 0.165, 0.065),
    (0.800, 0.320, 0.195, 0.095),
    (0.615, 0.360, 0.225, 0.140),
]
CAPE_COLS = 16
CAPE_FRONT_LIFT = 0.09    # front edges hang shorter than the sides/back (A-line read)
CAPE_THICK = 0.012
# Hood: teardrop flap on the upper back
HOOD_PTS = {
    "N": (0.000, 0.105, 1.230), "L": (0.120, 0.070, 1.205), "Lm": (0.135, 0.150, 1.110),
    "Lb": (0.080, 0.180, 1.010), "T": (0.000, 0.190, 0.930), "M": (0.000, 0.196, 1.100),
}

# Sword (SPEC: 0.60 blade, 0.02 guard, 0.13 grip, 0.03 pommel)
BLADE_LEN, BLADE_W, BLADE_T, BLADE_TIP = 0.60, 0.035, 0.015, 0.035
GUARD = (0.080, 0.020, 0.022)          # x (edge dir), y (blade dir), z (flat normal)
GRIP_LEN, GRIP_R, POMMEL = 0.13, 0.0125, 0.030
SWORD_DIR = (-0.30, -0.70, -0.62)      # rest: blade forward-down from the right hand

# Review renders
RENDER_H, RENDER_W = 800, 640
ORTHO_SCALE = 1.80
CAM_TARGET_Z = 0.77
BG_SRGB = "#8E959E"
AMBIENT, SUN_ENERGY = 0.72, 1.2

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_rgb(h, linear=True):
    h = h.lstrip("#")
    rgb = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return [srgb_to_lin(c) for c in rgb] if linear else rgb


OCT = [(0.6, -1.0), (1.0, -0.5), (1.0, 0.5), (0.6, 1.0),
       (-0.6, 1.0), (-1.0, 0.5), (-1.0, -0.5), (-0.6, -1.0)]  # front face is flat (y=-1)


def vring(z, rx, ry, cx=0.0, cy=0.0, n=8, offset=0.0, profile=None):
    """Horizontal ring; angle 0 = front (-Y), +90 deg = character's left (+X)."""
    if profile:
        return [Vector((cx + px * rx, cy + py * ry, z)) for px, py in profile]
    pts = []
    for k in range(n):
        a = offset + 2 * math.pi * k / n
        pts.append(Vector((cx + rx * math.sin(a), cy - ry * math.cos(a), z)))
    return pts


def aring(center, tangent, ref, ru, rv, n=6, offset=0.0):
    """Ring perpendicular to `tangent`; rv along `ref` (projected), ru across."""
    t = Vector(tangent).normalized()
    r = Vector(ref)
    v = (r - r.dot(t) * t).normalized()
    u = v.cross(t).normalized()
    c = Vector(center)
    return [c + u * (ru * math.cos(offset + 2 * math.pi * k / n))
            + v * (rv * math.sin(offset + 2 * math.pi * k / n)) for k in range(n)]


class MeshBuilder:
    def __init__(self):
        self.verts, self.weights, self.faces, self.fmats = [], [], [], []

    def v(self, co, w):
        self.verts.append(Vector(co))
        self.weights.append(dict(w))
        return len(self.verts) - 1

    def f(self, idx, mat):
        self.faces.append(list(idx))
        self.fmats.append(mat)

    def loft(self, rings, mat, cap0=True, cap1=True, cap0_pt=None, cap1_pt=None):
        """rings: [(points, weights)]; consecutive rings bridged with quads."""
        ids = [[self.v(p, w) for p in pts] for pts, w in rings]
        n = len(ids[0])
        for a, b in zip(ids[:-1], ids[1:]):
            for k in range(n):
                self.f([a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]], mat)
        for cap, ring, pt, w in ((cap0, ids[0], cap0_pt, rings[0][1]),
                                 (cap1, ids[-1], cap1_pt, rings[-1][1])):
            if not cap:
                continue
            if pt is None:
                self.f(ring, mat)
            else:
                c = self.v(pt, w)
                for k in range(n):
                    self.f([ring[k], ring[(k + 1) % n], c], mat)
        return ids

    def box(self, center, size, mat, w, rot=None):
        c, s = Vector(center), Vector(size) * 0.5
        m = rot if rot is not None else Matrix.Identity(3)
        corners = [Vector((x * s.x, y * s.y, z * s.z)) for z in (-1, 1) for y in (-1, 1) for x in (-1, 1)]
        ids = [self.v(c + m @ p, w) for p in corners]
        for q in ((0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)):
            self.f([ids[i] for i in q], mat)
        return ids


def blend_chain(x, joints, names, band):
    """joints ascending (len names + 1); returns {name: weight} with linear blends."""
    i = 0
    while i < len(names) - 1 and x > joints[i + 1]:
        i += 1
    w = {names[i]: 1.0}
    if i > 0 and x - joints[i] < band:
        t = 0.5 + (x - joints[i]) / (2 * band)
        w = {names[i]: t, names[i - 1]: 1 - t}
    elif i < len(names) - 1 and joints[i + 1] - x < band:
        t = 0.5 + (joints[i + 1] - x) / (2 * band)
        w = {names[i]: t, names[i + 1]: 1 - t}
    return w


SPINE_JOINTS = [0.0, 0.80, 0.90, 1.02, 1.15]
SPINE_NAMES = ["DEF-spine", "DEF-spine.001", "DEF-spine.002", "DEF-spine.003"]


def spine_w(z):
    return blend_chain(z, SPINE_JOINTS, SPINE_NAMES, 0.03)


def side(x):
    return "L" if x > 0 else "R"


# --------------------------------------------------------------------------
# Scene reset + materials
# --------------------------------------------------------------------------
print("Blender", bpy.app.version_string)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0

MAT_ORDER = ["hair", "skin", "eyes", "shirt", "collar", "belt", "shorts", "tights", "boots",
             "cape", "blade", "hilt"]
MATS = {}
for name in MAT_ORDER:
    m = bpy.data.materials.new("mat_" + name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    lin = hex_rgb(COL[name])
    m.diffuse_color = (*lin, 1.0)        # viewport / Workbench colour
    m.roughness = 0.9
    m.use_backface_culling = False
    bsdf = m.node_tree.nodes.get("Principled BSDF") if m.node_tree else None
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.9
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = 0.0
    MATS[name] = m
LEG_MAT = "tights"   # slot name; colour switched by LEG_STYLE below
if LEG_STYLE == "skin":
    lin = hex_rgb(COL["skin"])
    MATS["tights"].diffuse_color = (*lin, 1.0)
    MATS["tights"].node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*lin, 1.0)

# --------------------------------------------------------------------------
# Derived skeleton positions
# --------------------------------------------------------------------------
def arm_points(sx):
    s = Vector((sx * SHOULDER_JOINT[0], SHOULDER_JOINT[1], SHOULDER_JOINT[2]))
    a1 = math.radians(ARM_DOWN_DEG)
    a2 = math.radians(ARM_DOWN_DEG + ELBOW_BEND_DEG)
    d1 = Vector((sx * math.cos(a1), 0.0, -math.sin(a1)))
    d2 = Vector((sx * math.cos(a2), 0.0, -math.sin(a2)))
    e = s + d1 * UPPER_ARM_LEN
    w = e + d2 * FOREARM_LEN
    h = w + d2 * HAND_LEN
    return s, e, w, h, d1, d2


ARMS = {"L": arm_points(1.0), "R": arm_points(-1.0)}


def cape_dims(z):
    rows = CAPE_ROWS
    for (z0, rx0, ry0, g0), (z1, rx1, ry1, g1) in zip(rows[:-1], rows[1:]):
        if z1 <= z <= z0:
            t = (z0 - z) / (z0 - z1)
            return rx0 + (rx1 - rx0) * t, ry0 + (ry1 - ry0) * t
    return (rows[0][1], rows[0][2]) if z > rows[0][0] else (rows[-1][1], rows[-1][2])


def cape_point(phi, z, out=0.0):
    rx, ry = cape_dims(z)
    return Vector(((rx + out) * math.sin(phi), -(ry + out) * math.cos(phi), z))


CAPE_STRIPS = [  # (phi centre, chain base name, bone count)
    (0.55, "DEF-cape_front.L", 2), (1.45, "DEF-cape_side.L", 2), (2.35, "DEF-cape_back.L", 3),
    (math.pi, "DEF-cape_back", 3),
    (2 * math.pi - 2.35, "DEF-cape_back.R", 3), (2 * math.pi - 1.45, "DEF-cape_side.R", 2),
    (2 * math.pi - 0.55, "DEF-cape_front.R", 2),
]
CAPE_TOP, CAPE_BOT = 1.15, CAPE_ROWS[-1][0]


def chain_joints(count):
    return [CAPE_TOP - (CAPE_TOP - CAPE_BOT) * i / count for i in range(count + 1)]


# --------------------------------------------------------------------------
# Armature
# --------------------------------------------------------------------------
arm_data = bpy.data.armatures.new("player_rig")
arm_obj = bpy.data.objects.new("player_rig", arm_data)
scene.collection.objects.link(arm_obj)
bpy.context.view_layer.objects.active = arm_obj
arm_obj.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
EB = arm_data.edit_bones


def bone(name, head, tail, parent=None, connect=False, deform=True, roll=0.0):
    b = EB.new(name)
    b.head, b.tail, b.roll = Vector(head), Vector(tail), roll
    if parent:
        b.parent = EB[parent]
        b.use_connect = connect
    b.use_deform = deform
    return b


bone("root", (0, 0, 0), (0, -0.25, 0), deform=False)
bone("DEF-spine", (0, 0, Z_HIP), (0, 0, 0.80), "root")
bone("DEF-spine.001", (0, 0, 0.80), (0, 0, 0.90), "DEF-spine", True)
bone("DEF-spine.002", (0, 0, 0.90), (0, 0, 1.02), "DEF-spine.001", True)
bone("DEF-spine.003", (0, 0, 1.02), (0, 0, 1.15), "DEF-spine.002", True)
bone("DEF-spine.004", (0, 0, 1.15), (0, 0, 1.17), "DEF-spine.003", True)
bone("DEF-spine.005", (0, 0, 1.17), (0, 0, Z_CHIN), "DEF-spine.004", True)
bone("DEF-spine.006", (0, 0, Z_CHIN), (0, 0, H_TOTAL), "DEF-spine.005", True)
bone("DEF-hair_bun", (0, 0.045, 1.46), (0, 0.085, 1.535), "DEF-spine.006")
for s, sx in (("L", 1), ("R", -1)):
    er = Vector((sx * EAR_ROOT[0], EAR_ROOT[1], EAR_ROOT[2]))
    bone(f"DEF-ear.{s}", er, er + Vector((sx * 0.10, 0.036, 0.027)), "DEF-spine.006")
    sh, el, wr, ha, d1, d2 = ARMS[s]
    bone(f"DEF-shoulder.{s}", (sx * 0.02, 0, 1.15), sh, "DEF-spine.003")
    bone(f"DEF-upper_arm.{s}", sh, el, f"DEF-shoulder.{s}", True)
    bone(f"DEF-forearm.{s}", el, wr, f"DEF-upper_arm.{s}", True)
    bone(f"DEF-hand.{s}", wr, ha, f"DEF-forearm.{s}", True)
    fx = sx * FOOT_X
    bone(f"DEF-thigh.{s}", (fx, 0, Z_HIP), (fx, -0.012, Z_KNEE), "DEF-spine")
    bone(f"DEF-shin.{s}", (fx, -0.012, Z_KNEE), (fx, 0, 0.075), f"DEF-thigh.{s}", True)
    bone(f"DEF-foot.{s}", (fx, 0, 0.075), (fx, -0.10, 0.025), f"DEF-shin.{s}", True)
    bone(f"DEF-toe.{s}", (fx, -0.10, 0.025), (fx, -0.155, 0.025), f"DEF-foot.{s}", True)
for phi, base, count in CAPE_STRIPS:
    js = chain_joints(count)
    parent = "DEF-spine.003"
    for i in range(count):
        nm = f"{base}.{i + 1:03d}"
        bone(nm, cape_point(phi, js[i], 0.005), cape_point(phi, js[i + 1], 0.005), parent, i > 0)
        parent = nm
hp = {k: Vector(v) for k, v in HOOD_PTS.items()}
bone("DEF-hood.001", hp["N"] + Vector((0, 0.01, -0.02)), hp["M"], "DEF-spine.003")
bone("DEF-hood.002", hp["M"], hp["T"], "DEF-hood.001", True)
# Sword prop bone: head at the grip centre, tail along the blade
SH, SE, SW, SHA, SD1, SD2 = ARMS["R"]
GRIP_CENTER = SW + SD2 * (HAND_LEN * 0.5)
BLADE_DIR = Vector(SWORD_DIR).normalized()
bone("prop.sword", GRIP_CENTER, GRIP_CENTER + BLADE_DIR * 0.25, "DEF-hand.R", deform=False)
bpy.ops.object.mode_set(mode="OBJECT")
BONE_NAMES = [b.name for b in arm_data.bones]

# --------------------------------------------------------------------------
# Body mesh
# --------------------------------------------------------------------------
mb = MeshBuilder()

# Head (skull/face)
head_w = {"DEF-spine.006": 1.0}
mb.loft([(vring(z, rx, ry, cy=cy, profile=OCT), head_w) for z, rx, ry, cy in HEAD_RINGS], "skin")
# Eyes: thin black boxes on the flat face front (front face of the 1.30 ring)
z_a, rx_a, ry_a, cy_a = HEAD_RINGS[1]
z_b, rx_b, ry_b, cy_b = HEAD_RINGS[2]
t = (Z_EYES - z_a) / (z_b - z_a)
face_y = (cy_a - ry_a) + ((cy_b - ry_b) - (cy_a - ry_a)) * t
for sx in (1, -1):
    mb.box((sx * EYE_SEP, face_y - 0.002, Z_EYES), (EYE_W, 0.006, EYE_H), "eyes", head_w)
# Neck + collar band
mb.loft([(vring(NECK_Z0, NECK_R, NECK_R, n=8), {"DEF-spine.004": 1.0}),
         (vring(NECK_Z1, NECK_R, NECK_R, n=8), {"DEF-spine.005": 0.5, "DEF-spine.006": 0.5})], "skin")
mb.loft([(vring(COLLAR_Z0, COLLAR_RX, COLLAR_RY, n=8, offset=math.pi / 8), {"DEF-spine.003": 1.0}),
         (vring(COLLAR_Z1, COLLAR_RX * 0.92, COLLAR_RY * 0.92, n=8, offset=math.pi / 8),
          {"DEF-spine.004": 1.0})], "collar")

# Hair shell
hx, hy, hz = HAIR_C
HRx, HRy, HRz = HAIR_R


def hair_cut(phi):
    a = abs((phi + math.pi) % (2 * math.pi) - math.pi)  # 0 front .. pi back
    if a <= 0.85:
        return HAIR_CUT_FRONT
    if a <= math.pi / 2:
        t = (a - 0.85) / (math.pi / 2 - 0.85)
        return HAIR_CUT_FRONT + (HAIR_CUT_SIDE - HAIR_CUT_FRONT) * t
    t = (a - math.pi / 2) / (math.pi / 2)
    return HAIR_CUT_SIDE + (HAIR_CUT_BACK - HAIR_CUT_SIDE) * t


hair_rings = []
for i in range(1, HAIR_ROWS + 1):
    pts = []
    for k in range(HAIR_COLS):
        phi = 2 * math.pi * k / HAIR_COLS
        cmax = max(-0.98, min(1.0, (hair_cut(phi) - hz) / HRz))
        th = math.acos(cmax) * i / HAIR_ROWS
        pts.append(Vector((hx + HRx * math.sin(th) * math.sin(phi),
                           hy - HRy * math.sin(th) * math.cos(phi),
                           hz + HRz * math.cos(th))))
    hair_rings.append((pts, head_w))
mb.loft(hair_rings, "hair", cap0_pt=(hx, hy, hz + HRz), cap1_pt=(0.0, 0.02, 1.30))
# Top-knot bun: icosphere, tilted back
bm = bmesh.new()
bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
tilt = Matrix.Rotation(math.radians(BUN_TILT_DEG), 3, "X")
ids = [mb.v(Vector(BUN_C) + tilt @ Vector((v.co.x * BUN_R[0], v.co.y * BUN_R[1], v.co.z * BUN_R[2])),
            {"DEF-hair_bun": 1.0}) for v in bm.verts]
for f in bm.faces:
    mb.f([ids[v.index] for v in f.verts], "hair")
bm.free()
# Side locks (flat tapered slabs in front of the ears, angled slightly forward)
for sx in (1, -1):
    rings = []
    for z, wdt, fwd in ((LOCK_TOP, LOCK_W_TOP, 0.0), (1.28, (LOCK_W_TOP + LOCK_W_BOT) / 2, -0.008),
                        (LOCK_BOT, LOCK_W_BOT, -0.022)):
        c = Vector((sx * (LOCK_X - (LOCK_TOP - z) * 0.08), LOCK_Y + fwd, z))
        rings.append(([c + Vector((sx * dx * LOCK_T / 2, dy * wdt / 2, 0))
                       for dx, dy in ((-1, -1), (1, -1), (1, 1), (-1, 1))], head_w))
    mb.loft(rings, "hair")
# Elf ears: 4-sided pyramid from a root quad to the tip
for sx in (1, -1):
    root = Vector((sx * EAR_ROOT[0], EAR_ROOT[1], EAR_ROOT[2]))
    d = Vector((sx, math.tan(math.radians(EAR_BACK_DEG)), math.tan(math.radians(EAR_UP_DEG)))).normalized()
    tip = root + d * EAR_LEN
    w = {f"DEF-ear.{side(sx)}": 1.0}
    q = [mb.v(root + Vector((0, dy * EAR_ROOT_D / 2, dz * EAR_ROOT_H / 2)), w)
         for dy, dz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    # the upper edge sits a bit further out so the ear reads as a leaf, not a cone
    q_mid = mb.v(root + d * (EAR_LEN * 0.45) + Vector((0, 0.004, 0.018)), w)
    tp = mb.v(tip, w)
    mb.f(q[::-1], "skin")
    mb.f([q[0], q[1], tp], "skin")
    mb.f([q[1], q[2], q_mid, tp], "skin")
    mb.f([q[2], q[3], q_mid], "skin")
    mb.f([q[3], q[0], tp, q_mid], "skin")

# Torso / shirt
mb.loft([(vring(z, rx, ry, profile=OCT), spine_w(z)) for z, rx, ry in SHIRT_RINGS], "shirt")
# Belt + buckle
mb.loft([(vring(BELT_Z0, BELT_RX, BELT_RY, profile=OCT), {"DEF-spine": 1.0}),
         (vring(BELT_Z1, BELT_RX, BELT_RY, profile=OCT), {"DEF-spine": 1.0})], "belt")
mb.box((0, -BELT_RY - 0.003, (BELT_Z0 + BELT_Z1) / 2), (0.026, 0.006, 0.024), "eyes", {"DEF-spine": 1.0})

# Shorts / tunic skirt
srings = []
for i, (z, rx, ry) in enumerate(SHORTS_RINGS):
    pts = vring(z, rx, ry, n=SHORTS_SIDES)
    ws = []
    for p in pts:
        if i == len(SHORTS_RINGS) - 1 and abs(p.x) < 1e-6:
            p.z = SHORTS_SPLIT_Z   # shallow split front/back between the legs
        ws.append(p)
    srings.append(pts)
sids = []
for i, pts in enumerate(srings):
    row = []
    for p in pts:
        if i == len(srings) - 1 and abs(p.x) > 0.03:
            w = {"DEF-spine": 0.4, f"DEF-thigh.{side(p.x)}": 0.6}
        else:
            w = {"DEF-spine": 1.0}
        row.append(mb.v(p, w))
    sids.append(row)
n = SHORTS_SIDES
for a, b in zip(sids[:-1], sids[1:]):
    for k in range(n):
        mb.f([b[k], b[(k + 1) % n], a[(k + 1) % n], a[k]], "shorts")
mb.f(sids[0], "shorts")
crotch = mb.v((0, 0, Z_CROTCH - 0.005), {"DEF-spine": 1.0})
for k in range(n):
    mb.f([sids[-1][k], sids[-1][(k + 1) % n], crotch], "shorts")

# Legs (tights) + boots
for sx in (1, -1):
    s = side(sx)
    fx = sx * FOOT_X
    leg_w = [{f"DEF-thigh.{s}": 1.0}, {f"DEF-thigh.{s}": 1.0},
             {f"DEF-thigh.{s}": 0.5, f"DEF-shin.{s}": 0.5}, {f"DEF-shin.{s}": 1.0}]
    mb.loft([(vring(z, r, r, cx=fx, n=6, offset=math.pi / 6), w) for (z, r), w in zip(LEG_RINGS, leg_w)],
            LEG_MAT)
    mb.loft([(vring(z, r, r * 1.05, cx=fx, n=8, offset=math.pi / 8), {f"DEF-shin.{s}": 1.0})
             for z, r in BOOT_RINGS], "boots")
    frings = []
    for y, z0, z1, hw in FOOT_SECTIONS:
        w = {f"DEF-toe.{s}": 1.0} if y < -0.12 else {f"DEF-foot.{s}": 1.0}
        frings.append(([Vector((fx - hw, y, z0)), Vector((fx + hw, y, z0)),
                        Vector((fx + hw, y, z1)), Vector((fx - hw, y, z1))], w))
    mb.loft(frings, "boots")

# Arms (sleeves) + mitten hands
for sx in (1, -1):
    s = side(sx)
    sh, el, wr, ha, d1, d2 = ARMS[s]
    y_ref = Vector((0, 1, 0))
    rings = [
        (aring(sh - d1 * 0.025, d1, y_ref, ARM_R[0], ARM_R[0]), {f"DEF-shoulder.{s}": 0.5, f"DEF-upper_arm.{s}": 0.5}),
        (aring(sh + d1 * 0.11, d1, y_ref, ARM_R[1], ARM_R[1]), {f"DEF-upper_arm.{s}": 1.0}),
        (aring(el, (d1 + d2) * 0.5, y_ref, ARM_R[2], ARM_R[2]), {f"DEF-upper_arm.{s}": 0.5, f"DEF-forearm.{s}": 0.5}),
        (aring(wr, d2, y_ref, ARM_R[3], ARM_R[3]), {f"DEF-forearm.{s}": 1.0}),
    ]
    mb.loft(rings, "shirt")
    hw = {f"DEF-hand.{s}": 1.0}
    mb.loft([(aring(wr - d2 * 0.012, d2, y_ref, HAND_HALF_T * 0.9, HAND_HALF_W * 0.85, n=4, offset=math.pi / 4), hw),
             (aring(wr + d2 * 0.045, d2, y_ref, HAND_HALF_T * 1.1, HAND_HALF_W, n=4, offset=math.pi / 4), hw),
             (aring(ha, d2, y_ref, HAND_HALF_T * 0.8, HAND_HALF_W * 0.8, n=4, offset=math.pi / 4), hw)], "skin")


def build_object(name, builder, mat_names):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in builder.verts], [], builder.faces)
    for mn in mat_names:
        me.materials.append(MATS[mn])
    idx = {mn: i for i, mn in enumerate(mat_names)}
    for poly, mn in zip(me.polygons, builder.fmats):
        poly.material_index = idx[mn]
        poly.use_smooth = False
    me.validate()
    me.update()
    ob = bpy.data.objects.new(name, me)
    scene.collection.objects.link(ob)
    groups = {}
    for vi, wd in enumerate(builder.weights):
        tot = sum(wd.values())
        for g, w in wd.items():
            if g not in groups:
                groups[g] = ob.vertex_groups.new(name=g)
            groups[g].add([vi], w / tot, "REPLACE")
    # consistent outward normals (every island is closed)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    return ob


body = build_object("player_body", mb,
                    ["hair", "skin", "eyes", "shirt", "collar", "belt", "shorts", "tights", "boots"])

# --------------------------------------------------------------------------
# Cape + hood (separate skinned mesh, solidified)
# --------------------------------------------------------------------------
cb = MeshBuilder()


def cape_weights(phi, z):
    phis = [c[0] for c in CAPE_STRIPS]
    if phi <= phis[0]:
        strip_w = {0: 1.0}
    elif phi >= phis[-1]:
        strip_w = {len(phis) - 1: 1.0}
    else:
        j = max(i for i in range(len(phis)) if phis[i] <= phi)
        t = (phi - phis[j]) / (phis[j + 1] - phis[j])
        strip_w = {j: 1 - t, j + 1: t}
    w = {}
    if z >= CAPE_ROWS[0][0] - 1e-6:
        return {"DEF-spine.003": 1.0}
    for j, sw in strip_w.items():
        _, base, count = CAPE_STRIPS[j]
        js = chain_joints(count)[::-1]            # ascending z
        names = [f"{base}.{count - i:03d}" for i in range(count)]
        cw = blend_chain(z, js, names, 0.06)
        arm_share = 0.0
        if "side" in base and z > 0.95:
            arm_share = 0.4
        for nm, v in cw.items():
            w[nm] = w.get(nm, 0) + v * sw * (1 - arm_share)
        if arm_share:
            ab = "DEF-upper_arm." + base[-1]
            w[ab] = w.get(ab, 0) + sw * arm_share
        if z > 1.08:   # top band follows the chest
            for k in list(w):
                w[k] *= 0.6
            w["DEF-spine.003"] = w.get("DEF-spine.003", 0) + 0.4 * sw
    return w


cape_ids = []
for z, rx, ry, gap in CAPE_ROWS:
    g = math.asin(min(0.95, gap / rx))
    row = []
    for j in range(CAPE_COLS + 1):
        phi = g + (2 * math.pi - 2 * g) * j / CAPE_COLS
        zz = z
        if z < 1.0:   # lift the lower rows toward the front opening
            f = max(0.0, math.cos(phi)) ** 2 * (1.0 - z) / (1.0 - CAPE_ROWS[-1][0])
            zz = z + CAPE_FRONT_LIFT * f
        p = Vector((rx * math.sin(phi), -ry * math.cos(phi), zz))
        row.append(cb.v(p, cape_weights(phi, zz)))
    cape_ids.append(row)
for a, b in zip(cape_ids[:-1], cape_ids[1:]):
    for j in range(CAPE_COLS):
        cb.f([a[j], b[j], b[j + 1], a[j + 1]], "cape")
# Hood flap
H = {}
for k, p in HOOD_PTS.items():
    p = Vector(p)
    for nm, sx in ((k, 1), (k.replace("L", "R"), -1)):
        if nm in H:
            continue
        q = Vector((sx * p.x, p.y, p.z))
        if q.z > 1.15:
            w = {"DEF-spine.003": 0.5, "DEF-hood.001": 0.5}
        elif q.z > 1.03:
            w = {"DEF-hood.001": 1.0}
        else:
            w = {"DEF-hood.002": 1.0}
        H[nm] = cb.v(q, w)
cb.f([H["N"], H["L"], H["Lm"], H["M"]], "cape")
cb.f([H["M"], H["Lm"], H["Lb"], H["T"]], "cape")
cb.f([H["N"], H["M"], H["Rm"], H["R"]], "cape")
cb.f([H["M"], H["T"], H["Rb"], H["Rm"]], "cape")
cape = build_object("player_cape", cb, ["cape"])
mod = cape.modifiers.new("solidify", "SOLIDIFY")
mod.thickness = CAPE_THICK
mod.offset = -1.0
mod.use_even_offset = True
with bpy.context.temp_override(object=cape, active_object=cape, selected_objects=[cape]):
    bpy.ops.object.modifier_apply(modifier=mod.name)
bm = bmesh.new()
bm.from_mesh(cape.data)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.to_mesh(cape.data)
bm.free()
for p in cape.data.polygons:
    p.use_smooth = False

# Skin body + cape to the armature
for ob in (body, cape):
    ob.parent = arm_obj
    am = ob.modifiers.new("Armature", "ARMATURE")
    am.object = arm_obj
    am.use_vertex_groups = True
    missing = [g.name for g in ob.vertex_groups if g.name not in BONE_NAMES]
    assert not missing, f"vertex groups without bones: {missing}"

# --------------------------------------------------------------------------
# Sword (separate object, origin at grip centre)
#   Blender local: blade along -Y, cutting edge +X, blade flat normal +Z
#   -> glTF/Godot local: +Z toward the tip, +X cutting edge, +Y flat normal
# --------------------------------------------------------------------------
sb = MeshBuilder()
sw = {}
y0 = -GRIP_LEN / 2 - GUARD[1]                     # blade base
diamond = lambda y, s=1.0: [Vector((BLADE_W / 2 * s, y, 0)), Vector((0, y, BLADE_T / 2 * s)),
                            Vector((-BLADE_W / 2 * s, y, 0)), Vector((0, y, -BLADE_T / 2 * s))]
sb.loft([(diamond(y0 + 0.005), sw), (diamond(y0 - BLADE_LEN + BLADE_TIP), sw),
         (diamond(y0 - BLADE_LEN, 0.35), sw)], "blade")
sb.box((0, -GRIP_LEN / 2 - GUARD[1] / 2, 0), GUARD, "blade", sw)
sb.loft([(aring((0, GRIP_LEN / 2, 0), (0, -1, 0), (0, 0, 1), GRIP_R, GRIP_R, n=6), sw),
         (aring((0, -GRIP_LEN / 2, 0), (0, -1, 0), (0, 0, 1), GRIP_R, GRIP_R, n=6), sw)], "hilt")
sb.box((0, GRIP_LEN / 2 + POMMEL / 2, 0), (POMMEL, POMMEL, POMMEL), "hilt", sw)
sword = build_object("player_sword", sb, ["blade", "hilt"])

bpy.context.view_layer.update()
y_axis = -BLADE_DIR                                  # local +Y = toward the pommel
down = Vector((0, 0, -1))
x_axis = (down - down.dot(y_axis) * y_axis).normalized()   # cutting edge faces the ground
z_axis = x_axis.cross(y_axis)
rot = Matrix((x_axis, y_axis, z_axis)).transposed()
sword_world = Matrix.Translation(GRIP_CENTER) @ rot.to_4x4()
sword.parent = arm_obj
sword.parent_type = "BONE"
sword.parent_bone = "prop.sword"
bpy.context.view_layer.update()
sword.matrix_world = sword_world
bpy.context.view_layer.update()

# --------------------------------------------------------------------------
# Stats
# --------------------------------------------------------------------------
tri_total = 0
for ob in (body, cape, sword):
    ob.data.calc_loop_triangles()
    nt = len(ob.data.loop_triangles)
    tri_total += nt
    print(f"TRIS {ob.name}: {nt}")
print("TRIS total:", tri_total)
print("BONES:", len(BONE_NAMES), BONE_NAMES)

# --------------------------------------------------------------------------
# Rest action (optional) + export + save
# --------------------------------------------------------------------------
bpy.ops.object.select_all(action="DESELECT")
for ob in (arm_obj, body, cape, sword):
    ob.select_set(True)
bpy.context.view_layer.objects.active = arm_obj
gltf_kwargs = dict(filepath=GLB_PATH, export_format="GLB", use_selection=True, export_yup=True,
                   export_skins=True, export_materials="EXPORT", export_animations=False,
                   export_apply=False)
try:
    bpy.ops.export_scene.gltf(**gltf_kwargs)
except TypeError as e:
    print("gltf export kwarg issue, retrying minimal:", e)
    bpy.ops.export_scene.gltf(filepath=GLB_PATH, export_format="GLB", use_selection=True)


def verify_glb(path):
    """Check the exported sword: local +Z must run grip -> tip."""
    with open(path, "rb") as fh:
        data = fh.read()
    jlen = struct.unpack_from("<I", data, 12)[0]
    gj = json.loads(data[20:20 + jlen])
    nodes = gj["nodes"]
    parent = {}
    for i, nd in enumerate(nodes):
        for c in nd.get("children", []):
            parent[c] = i

    def local(nd):
        if "matrix" in nd:
            return Matrix([nd["matrix"][i::4] for i in range(4)])
        t = Vector(nd.get("translation", (0, 0, 0)))
        q = nd.get("rotation", (0, 0, 0, 1))
        s = nd.get("scale", (1, 1, 1))
        return (Matrix.Translation(t) @ Quaternion((q[3], q[0], q[1], q[2])).to_matrix().to_4x4()
                @ Matrix.Diagonal((*s, 1)))

    si = next(i for i, nd in enumerate(nodes) if nd.get("name") == "player_sword")
    m = Matrix.Identity(4)
    i = si
    while i is not None:
        m = local(nodes[i]) @ m
        i = parent.get(i)
    acc = gj["accessors"][gj["meshes"][nodes[si]["mesh"]]["primitives"][0]["attributes"]["POSITION"]]
    z_world = (m.to_3x3() @ Vector((0, 0, 1))).normalized()
    x_world = (m.to_3x3() @ Vector((1, 0, 0))).normalized()
    expect = Vector((BLADE_DIR.x, BLADE_DIR.z, -BLADE_DIR.y))
    print("GLB sword parent chain:", [nodes[j].get("name") for j in [si] + [parent.get(si)] if j is not None])
    print("GLB sword blade-primitive POSITION min/max:", acc.get("min"), acc.get("max"))
    print("GLB sword world basis.z:", tuple(round(c, 3) for c in z_world),
          " expected blade dir (glTF):", tuple(round(c, 3) for c in expect), " dot=%.4f" % z_world.dot(expect))
    print("GLB sword world basis.x (edge):", tuple(round(c, 3) for c in x_world))
    print("GLB sword origin (glTF):", tuple(round(c, 3) for c in m.to_translation()),
          " expected", tuple(round(c, 3) for c in (GRIP_CENTER.x, GRIP_CENTER.z, -GRIP_CENTER.y)))
    print("GLB skins:", len(gj.get("skins", [])), " joints:", len(gj["skins"][0]["joints"]) if gj.get("skins") else 0,
          " materials:", [mt["name"] for mt in gj.get("materials", [])])


verify_glb(GLB_PATH)
arm_obj.data.display_type = "STICK"
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)

# --------------------------------------------------------------------------
# Review renders
# --------------------------------------------------------------------------
os.makedirs(RENDER_DIR, exist_ok=True)
for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
    try:
        scene.render.engine = eng
        break
    except TypeError:
        continue
scene.render.resolution_x, scene.render.resolution_y = RENDER_W, RENDER_H
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.film_transparent = True     # composited onto the flat grey afterwards
try:
    scene.view_settings.view_transform = "Standard"
except Exception:
    pass
# Flat-ish lighting: white ambient + one soft key sun, no shadows
world = bpy.data.worlds.new("ambient")
world.use_nodes = True
bgn = world.node_tree.nodes.get("Background")
bgn.inputs["Color"].default_value = (1, 1, 1, 1)
bgn.inputs["Strength"].default_value = AMBIENT
scene.world = world
sun_data = bpy.data.lights.new("key", "SUN")
sun_data.energy = SUN_ENERGY
sun_data.use_shadow = False
sun = bpy.data.objects.new("key", sun_data)
sun.rotation_euler = Euler((math.radians(40), 0, math.radians(-35)), "XYZ")
scene.collection.objects.link(sun)
arm_obj.hide_render = True

cam_data = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam


def flatten_bg(path):
    """Alpha-composite a transparent render onto the flat grey background."""
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    a = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    a = a.reshape(h, w, 4)
    bg = np.array(hex_rgb(BG_SRGB, linear=False), dtype=np.float32)
    al = a[:, :, 3:4]
    a[:, :, :3] = a[:, :, :3] * al + bg[None, None, :] * (1 - al)
    a[:, :, 3] = 1.0
    img.pixels.foreach_set(a.ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def shoot(name, yaw_deg, pitch_deg, ortho=True, target_z=CAM_TARGET_Z, scale=ORTHO_SCALE):
    """yaw 0 = camera in front of the character (at -Y) looking +Y; +yaw moves it to the character's left."""
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    look = Vector((-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), -math.sin(pitch)))
    target = Vector((0, 0, target_z))
    cam.location = target - look * 8.0
    cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
    cam_data.type = "ORTHO" if ortho else "PERSP"
    cam_data.ortho_scale = scale
    cam_data.clip_end = 50
    scene.render.filepath = os.path.join(RENDER_DIR, name + ".png")
    bpy.ops.render.render(write_still=True)
    flatten_bg(scene.render.filepath)
    return scene.render.filepath


VIEWS = {
    "player_front": (0, 0), "player_back": (180, 0), "player_side_left": (90, 0),
    "player_34_left": (45, 25), "player_34_right": (-45, 25), "player_topdown_high": (180, 40),
}
for nm, (yw, pt) in VIEWS.items():
    shoot(nm, yw, pt)

# Pose test (not saved into the .blend)
pb = arm_obj.pose.bones


def rot(name, axis, deg):
    """Rotate a pose bone by `deg` about a WORLD axis (through its head)."""
    m = arm_obj.data.bones[name].matrix_local.to_3x3()
    r = Matrix.Rotation(math.radians(deg), 3, axis)
    pb[name].rotation_mode = "QUATERNION"
    pb[name].rotation_quaternion = (m.inverted() @ r @ m).to_quaternion()


rot("DEF-upper_arm.R", "Y", 95)       # raise the sword arm above the shoulder
rot("DEF-forearm.R", "Z", 35)
rot("DEF-thigh.L", "X", -70)          # lift the left knee forward
rot("DEF-shin.L", "X", 85)            # and bend it back
rot("DEF-spine.002", "Z", -15)
rot("DEF-spine.006", "Z", 15)
for base in ("DEF-cape_back", "DEF-cape_back.L", "DEF-cape_back.R"):
    rot(base + ".001", "X", -35)      # flare the cape backward
    rot(base + ".002", "X", -15)
rot("DEF-hood.001", "X", -15)
bpy.context.view_layer.update()
shoot("player_posetest", 35, 20)
for b in pb:
    b.rotation_mode = "QUATERNION"
    b.rotation_quaternion = (1, 0, 0, 0)

# --------------------------------------------------------------------------
# Compare sheet: my renders next to the matching references at one subject height
# --------------------------------------------------------------------------
def load_rgba(path):
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    a = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    bpy.data.images.remove(img)
    return a.reshape(h, w, 4)[::-1]          # top row first


def subject_rows(a, bg):
    diff = np.abs(a[:, :, :3] - np.array(bg)[None, None, :]).max(axis=2) > 0.04
    rows = np.where(diff.any(axis=1))[0]
    cols = np.where(diff.any(axis=0))[0]
    return rows[0], rows[-1], cols[0], cols[-1]


def scaled(a, top, bot, target_h, margin=30):
    s = target_h / float(bot - top + 1)
    h, w = a.shape[:2]
    nh, nw = int(round(h * s)), int(round(w * s))
    yi = np.clip((np.arange(nh) / s).astype(int), 0, h - 1)
    xi = np.clip((np.arange(nw) / s).astype(int), 0, w - 1)
    out = a[yi][:, xi]
    t = int(round(top * s)) - margin
    return out, t


COMPARE = [  # (my render, reference file, ref subject top row, ref sole row)
    ("player_front", "view_front_apose.png", 20, 735),
    ("player_34_left", "view_34_front_left_idle.png", 15, 728),
    ("player_34_right", "view_34_front_right_idle.png", 15, 730),
    ("player_side_left", "game_side_facing_left_bright.png", 30, 725),
    ("player_back", "game_back_walk_bright.png", 30, 730),
    ("player_topdown_high", "view_back_high_topdown.png", 15, 735),
]
SUBJ_H, PANEL_H = 660, 720
bg_rgb = hex_rgb(BG_SRGB, linear=False)
panels = []
for mine, ref, rt, rb in COMPARE:
    for path, top_bot in ((os.path.join(RENDER_DIR, mine + ".png"), None),
                          (os.path.join(REF_DIR, ref), (rt, rb))):
        if not os.path.exists(path):
            continue
        a = load_rgba(path)
        if top_bot is None:
            t, b, c0, c1 = subject_rows(a, bg_rgb)
            pad = 25
            a = a[:, max(0, c0 - pad):c1 + pad]
            top_bot = (t, b)
        img, t = scaled(a, top_bot[0], top_bot[1], SUBJ_H)
        canvas = np.ones((PANEL_H, img.shape[1], 4), dtype=np.float32)
        canvas[:, :, :3] = bg_rgb
        src0 = max(0, t)
        dst0 = max(0, -t)
        hgt = min(img.shape[0] - src0, PANEL_H - dst0)
        canvas[dst0:dst0 + hgt] = img[src0:src0 + hgt]
        panels.append(canvas)
rows = [panels[i:i + 6] for i in range(0, len(panels), 6)]
sep = 12
row_imgs = []
for r in rows:
    parts = []
    for k, p in enumerate(r):
        parts.append(p)
        gap = np.zeros((PANEL_H, sep if k % 2 == 0 else sep * 4, 4), dtype=np.float32)
        gap[:, :, 3] = 1.0
        gap[:, :, :3] = 0.15 if k % 2 == 1 else 0.3
        parts.append(gap)
    row_imgs.append(np.concatenate(parts, axis=1))
W = max(r.shape[1] for r in row_imgs)
sheet = np.zeros((PANEL_H * len(row_imgs) + sep * (len(row_imgs) - 1), W, 4), dtype=np.float32)
sheet[:, :, 3] = 1.0
y = 0
for r in row_imgs:
    sheet[y:y + PANEL_H, :r.shape[1]] = r
    y += PANEL_H + sep
out = bpy.data.images.new("compare", sheet.shape[1], sheet.shape[0], alpha=True)
out.pixels.foreach_set(sheet[::-1].ravel())
out.filepath_raw = os.path.join(RENDER_DIR, "player_compare.png")
out.file_format = "PNG"
out.save()
print("DONE")
