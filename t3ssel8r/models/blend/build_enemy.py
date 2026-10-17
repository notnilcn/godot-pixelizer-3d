"""Build the t3ssel8r ENEMY (quadruped walker mech) from an empty scene.

Run headless (Blender 5.2):
    blender --background --factory-startup --python build_enemy.py

Outputs (paths relative to t3ssel8r/models/):
    blend/enemy.blend, enemy.glb, renders/enemy_*.png, renders/enemy_compare.png

Spec: docs/references/t3ssel8r/refs/enemy/SPEC.md. Blender convention: metres,
+Z up, mech faces -Y (eye panel at -Y), mech's left = +X, origin on the floor
between the feet. glTF export (+Y up) puts the front on Godot +Z (MODEL_FRONT).
Deterministic: no randomness, every number is a constant below.
"""

import math
import os
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector
from bpy_extras.object_utils import world_to_camera_view

# --------------------------------------------------------------------------
# Paths
# --------------------------------------------------------------------------
HERE = os.path.dirname(os.path.abspath(__file__))
MODELS_DIR = os.path.dirname(HERE)
REPO_DIR = os.path.dirname(os.path.dirname(MODELS_DIR))
REFS_DIR = os.path.join(REPO_DIR, "docs", "references", "t3ssel8r", "refs", "enemy")
RENDER_DIR = os.path.join(MODELS_DIR, "renders")
BLEND_PATH = os.path.join(HERE, "enemy.blend")
GLB_PATH = os.path.join(MODELS_DIR, "enemy.glb")

# --------------------------------------------------------------------------
# Colours (sRGB hex, from SPEC section 3 / palette.png)
# --------------------------------------------------------------------------
COL_HULL = "#A9BAD2"
COL_TRIM = "#050508"      # eye bezel, vent bars, rear notch
COL_EYE = "#FF0000"
COL_CABLE = "#C02028"
COL_ANTENNA = "#D8DCE4"
EYE_EMISSION_STRENGTH = 8.0

# --------------------------------------------------------------------------
# Body boxes: (x_min, x_max, y_min, y_max, z_min, z_max), metres, Blender axes
# --------------------------------------------------------------------------
HULL_W, HULL_L = 0.48, 0.66
HULL_Z0, HULL_Z1 = 0.42, 0.84    # 0.02 taller than SPEC (refs read slightly stockier)
HULL_Y0 = -HULL_L / 2          # front face (-Y)
HULL_Y1 = HULL_L / 2
HX = HULL_W / 2

BODY_CENTRE = Vector((0.0, 0.0, (HULL_Z0 + HULL_Z1) / 2))

# Eye bezel + eye on the front face (lower half)
BEZEL_W, BEZEL_H, BEZEL_D = 0.26, 0.22, 0.015
BEZEL_ZC = 0.59
EYE_W, EYE_H, EYE_D = 0.18, 0.16, 0.02     # sticks 0.005 past the bezel face

# Vent bars: 2 per side, protruding past the front face like mandibles
VENT_T = 0.03                    # square section
VENT_PROUD = 0.01                # stand-off from the hull side
VENT_Z = (0.52, 0.59)            # bar centres
VENT_Y_BACK = -0.02              # rear end
VENT_Y_FRONT = -0.46             # front end (0.13 past the front face)

# Roof deck: raised block on the rear part of the top, with a notch at its
# front centre (two forward prongs -> the "castellated" top in the front view)
ROOF_W = 0.40
ROOF_Y0, ROOF_Y1 = -0.10, 0.29
ROOF_Z1 = 0.90
ROOF_NOTCH_W = 0.12
ROOF_NOTCH_D = 0.12
# Small step block on the deck (side-view stepped profile)
ROOF_STEP = (0.04, 0.18, 0.02, 0.16, ROOF_Z1, ROOF_Z1 + 0.035)

# Side pods (both flanks, rear half) + smaller forward lug
POD_PROUD = 0.14
POD_Y0, POD_Y1 = -0.02, 0.30
POD_Z0, POD_Z1 = 0.70, 0.86
POD_LUG = (0.08, -0.14, -0.02, 0.60, 0.71)   # (proud, y0, y1, z0, z1)

# Rear parts
REAR_BLOCK = (-0.20, 0.20, HULL_Y1, HULL_Y1 + 0.10, 0.46, 0.79)
REAR_SLAB_W = 0.08                 # rear corner slabs (x thickness)
REAR_SLAB_Y0, REAR_SLAB_Y1 = 0.24, 0.40
REAR_SLAB_Z0, REAR_SLAB_Z1 = 0.44, 0.88
REAR_SLAB_PROUD = 0.04             # beyond the hull side
REAR_NOTCH_SIZE = 0.07             # black wedge between slab and roof

# Belly hub (8-sided cylinder)
HUB_RADIUS, HUB_Z0, HUB_Z1, HUB_SIDES = 0.10, HULL_Z0 - 0.06, HULL_Z0, 8

# Antenna (6-sided cylinder)
ANTENNA_BASE = Vector((-0.10, 0.15, ROOF_Z1))
ANTENNA_TIP_Z = 1.30
ANTENNA_RADIUS, ANTENNA_SIDES = 0.006, 6

# Cables: drooping loops from each side pod to the rear hip
CABLE_T = 0.014
CABLE_SEGMENTS = 4
CABLE_DROOP = 0.14
CABLE_END_ALONG_THIGH = 0.5     # where the cable plugs into the rear thigh

# --------------------------------------------------------------------------
# Legs (FL joints; others mirrored). SPEC section 2 joint table.
# --------------------------------------------------------------------------
HIP_FL = Vector((0.22, -0.20, 0.46))
KNEE_FL = Vector((0.53, -0.47, 0.31))
ANKLE_FL = Vector((0.59, -0.53, 0.05))

THIGH_WIDTH = 0.19          # broad plate, horizontal across the leg plane
THIGH_THICK = 0.08          # along the plate normal ("up" in the leg plane)
THIGH_EXT_HIP = 0.04        # extra length behind the hip
THIGH_EXT_KNEE = 0.05       # overlap past the knee
THIGH2_LEN, THIGH2_WIDTH, THIGH2_THICK = 0.30, 0.10, 0.05    # second (top) plate
THIGH2_SHIFT = 0.02         # shift of the top plate toward the knee
SHIN_W = 0.13
SHIN_EXT_KNEE = 0.05
FOOT_SIZE = (0.16, 0.16, 0.10)    # (along leg, across, height)
FOOT_OUTWARD = 0.02
HIP_CUBE = 0.10
HIP_BONE_LEN = 0.06

LEGS = {
    "FL": (1, -1),   # (x sign, y sign)
    "FR": (-1, -1),
    "BL": (1, 1),
    "BR": (-1, 1),
}

POLE_OUT = 0.35             # IK pole: outward from the knee
POLE_UP = 0.30

# Weapon / arm mount where the reference's white box sits (front underside)
MUZZLE_POS = Vector((0.0, -0.34, HULL_Z0 - 0.04))

# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------
RENDER_SIZE = 800
BG_GREY = 0.30                    # linear
AMBIENT_STRENGTH = 1.6            # world light (grey) -> soft fill
SUN_ENERGY = 2.2
SUN_ROT_DEG = (35.0, 0.0, 30.0)   # sun from above / front-left
CAM_TARGET = Vector((0.0, 0.0, 0.45))
CAM_DISTANCE = 3.3
CAM_LENS = 50.0
CAM_ELEV_REF = 40.0               # degrees down, like the refs
# name -> (azimuth deg of the camera position around +Z from -Y (front),
#          positive toward +X; elevation deg)
VIEWS = {
    "enemy_front": (0.0, 15.0),
    "enemy_back": (180.0, 15.0),
    "enemy_side_left": (90.0, 15.0),
    "enemy_34_front_left": (45.0, 25.0),
    "enemy_34_front_right": (-45.0, 25.0),
    "enemy_34_rear_left": (135.0, 25.0),
    "enemy_topdown_high": (30.0, 40.0),
}
# Compare panels: (ref file, mirror ref?, ref crop y0..y1 fraction [roof..feet],
#                  render azimuth, render elevation)
COMPARE = [
    ("view_front.png", False, (0.18, 0.955), 0.0, 42.0),
    ("view_side_right.png", False, (0.21, 0.94), 90.0, 38.0),
    ("view_rear_34_left.png", True, (0.16, 0.85), 135.0, 38.0),
    ("view_34_front_left.png", False, (0.19, 0.74), 45.0, 42.0),
    ("view_34_front_right_high.png", False, (0.10, 0.77), -50.0, 45.0),
]
COMPARE_PANEL_H = 420
COMPARE_LENS = 28.0               # Unity scene-view-like wide FOV, close camera
COMPARE_DISTANCE = 2.0

# Pose test
POSE_LIFT_LEG = "FL"
POSE_LIFT = Vector((0.06, -0.12, 0.25))
POSE_CROUCH = -0.10
POSE_CAM = (70.0, 15.0)          # azimuth, elevation


# ==========================================================================
# Helpers
# ==========================================================================
def hex_lin(h):
    h = h.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*out, 1.0)


def make_material(name, hexcol, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    col = hex_lin(hexcol)
    mat.diffuse_color = col
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = 0.8
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.2
    if emission > 0:
        bsdf.inputs["Emission Color"].default_value = col
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


class MeshBuilder:
    """Accumulates boxes into one bmesh; tracks material + bone per face set."""

    def __init__(self):
        self.bm = bmesh.new()
        self.deform = self.bm.verts.layers.deform.verify()
        self.materials = []
        self.bones = []

    def _mat_index(self, mat):
        if mat not in self.materials:
            self.materials.append(mat)
        return self.materials.index(mat)

    def _bone_index(self, bone):
        if bone not in self.bones:
            self.bones.append(bone)
        return self.bones.index(bone)

    def add_prism(self, ring_bottom, ring_top, mat, bone):
        """Closed prism from two vertex rings (same count, CCW seen from top)."""
        mi = self._mat_index(mat)
        bi = self._bone_index(bone)
        vb = [self.bm.verts.new(p) for p in ring_bottom]
        vt = [self.bm.verts.new(p) for p in ring_top]
        for v in vb + vt:
            v[self.deform][bi] = 1.0
        n = len(vb)
        faces = [self.bm.faces.new(list(reversed(vb))), self.bm.faces.new(vt)]
        for i in range(n):
            j = (i + 1) % n
            faces.append(self.bm.faces.new((vb[i], vb[j], vt[j], vt[i])))
        for f in faces:
            f.material_index = mi
            f.smooth = False
        return faces

    def add_box(self, x0, x1, y0, y1, z0, z1, mat, bone):
        b = [Vector((x0, y0, z0)), Vector((x1, y0, z0)), Vector((x1, y1, z0)), Vector((x0, y1, z0))]
        t = [v + Vector((0, 0, z1 - z0)) for v in b]
        self.add_prism(b, t, mat, bone)

    def add_oriented_box(self, centre, ax, ay, az, sx, sy, sz, mat, bone):
        """Box centred at `centre` with unit axes ax/ay/az and full sizes sx/sy/sz."""
        hx, hy, hz = ax * (sx / 2), ay * (sy / 2), az * (sz / 2)
        b = [centre - hx - hy - hz, centre + hx - hy - hz, centre + hx + hy - hz, centre - hx + hy - hz]
        t = [p + 2 * hz for p in b]
        # keep the winding outward whatever the handedness of (ax, ay, az)
        if ax.cross(ay).dot(az) < 0:
            b.reverse()
            t.reverse()
        self.add_prism(b, t, mat, bone)

    def add_cylinder(self, base, top_z, radius, sides, mat, bone, phase=0.0):
        ring = [Vector((base.x + radius * math.cos(phase + 2 * math.pi * i / sides),
                        base.y + radius * math.sin(phase + 2 * math.pi * i / sides),
                        base.z)) for i in range(sides)]
        top = [Vector((p.x, p.y, top_z)) for p in ring]
        self.add_prism(ring, top, mat, bone)

    def add_wedge_x(self, x0, x1, pts_yz, mat, bone):
        """Triangular prism along X from a CCW triangle in the YZ plane."""
        b = [Vector((x0, y, z)) for y, z in pts_yz]
        t = [Vector((x1, y, z)) for y, z in pts_yz]
        self.add_prism(b, t, mat, bone)   # normals fixed by recalc in finish()

    def finish(self, name):
        me = bpy.data.meshes.new(name)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.materials:
            me.materials.append(m)
        obj = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(obj)
        for b in self.bones:
            obj.vertex_groups.new(name=b)
        return obj


def leg_joints(tag):
    sx, sy = LEGS[tag]
    m = Vector((sx, -sy, 1.0))   # FL has x+ y-; flip signs per leg
    hip = Vector((HIP_FL.x * m.x, HIP_FL.y * m.y, HIP_FL.z))
    knee = Vector((KNEE_FL.x * m.x, KNEE_FL.y * m.y, KNEE_FL.z))
    ankle = Vector((ANKLE_FL.x * m.x, ANKLE_FL.y * m.y, ANKLE_FL.z))
    return hip, knee, ankle


def leg_frame(a, b):
    """Axes for a segment a->b: d along it, side horizontal, up in leg plane."""
    d = (b - a).normalized()
    side = d.cross(Vector((0, 0, 1)))
    if side.length < 1e-6:
        side = Vector((1, 0, 0))
    side.normalize()
    up = side.cross(d).normalized()
    return d, side, up


# ==========================================================================
# Build
# ==========================================================================
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    return scene


def build_mesh(mats):
    mb = MeshBuilder()
    hull, trim, eye, cable, ant = (mats[k] for k in ("hull", "trim", "eye", "cable", "antenna"))
    B = "DEF-body"

    # 1 Hull
    mb.add_box(-HX, HX, HULL_Y0, HULL_Y1, HULL_Z0, HULL_Z1, hull, B)
    # 2-3 Bezel + eye
    mb.add_box(-BEZEL_W / 2, BEZEL_W / 2, HULL_Y0 - BEZEL_D, HULL_Y0 + 0.005,
               BEZEL_ZC - BEZEL_H / 2, BEZEL_ZC + BEZEL_H / 2, trim, B)
    mb.add_box(-EYE_W / 2, EYE_W / 2, HULL_Y0 - EYE_D, HULL_Y0 - BEZEL_D + 0.004,
               BEZEL_ZC - EYE_H / 2, BEZEL_ZC + EYE_H / 2, eye, "DEF-eye")
    # 4 Vent bars
    for s in (1, -1):
        x_in = HX + VENT_PROUD - 0.005
        x_out = HX + VENT_PROUD + VENT_T
        x0, x1 = (x_in, x_out) if s > 0 else (-x_out, -x_in)
        for zc in VENT_Z:
            mb.add_box(x0, x1, VENT_Y_FRONT, VENT_Y_BACK, zc - VENT_T / 2, zc + VENT_T / 2, trim, B)
        # stand-off block hiding the gap to the hull
        xs0, xs1 = (HX - 0.005, x_in + 0.005) if s > 0 else (-x_in - 0.005, -HX + 0.005)
        mb.add_box(xs0, xs1, VENT_Y_BACK - 0.06, VENT_Y_BACK, VENT_Z[0] - VENT_T / 2,
                   VENT_Z[1] + VENT_T / 2, trim, B)
    # 5 Roof deck with front notch: rear part + two prongs
    rx = ROOF_W / 2
    ny = ROOF_Y0 + ROOF_NOTCH_D
    mb.add_box(-rx, rx, ny, ROOF_Y1, HULL_Z1 - 0.005, ROOF_Z1, hull, B)
    for s in (1, -1):
        xa, xb = ROOF_NOTCH_W / 2, rx
        x0, x1 = (xa, xb) if s > 0 else (-xb, -xa)
        mb.add_box(x0, x1, ROOF_Y0, ny + 0.005, HULL_Z1 - 0.005, ROOF_Z1, hull, B)
    # 6 Roof step
    mb.add_box(*ROOF_STEP[:4], ROOF_STEP[4] - 0.005, ROOF_STEP[5], hull, B)
    # 7 Side pods + forward lugs
    for s in (1, -1):
        xo = HX + POD_PROUD
        x0, x1 = (HX - 0.01, xo) if s > 0 else (-xo, -HX + 0.01)
        mb.add_box(x0, x1, POD_Y0, POD_Y1, POD_Z0, POD_Z1, hull, B)
        lp, ly0, ly1, lz0, lz1 = POD_LUG
        xo2 = HX + lp
        x0, x1 = (HX - 0.01, xo2) if s > 0 else (-xo2, -HX + 0.01)
        mb.add_box(x0, x1, ly0, ly1 + 0.005, lz0, lz1, hull, B)
    # 8 Rear block
    mb.add_box(*REAR_BLOCK[:2], REAR_BLOCK[2] - 0.005, REAR_BLOCK[3], *REAR_BLOCK[4:], hull, B)
    # 9 Rear corner slabs + black notch wedge (left rear)
    for s in (1, -1):
        xo = HX + REAR_SLAB_PROUD
        x0, x1 = (xo - REAR_SLAB_W, xo) if s > 0 else (-xo, -xo + REAR_SLAB_W)
        mb.add_box(x0, x1, REAR_SLAB_Y0, REAR_SLAB_Y1, REAR_SLAB_Z0, REAR_SLAB_Z1, hull, B)
    xo = HX + REAR_SLAB_PROUD - REAR_SLAB_W
    n = REAR_NOTCH_SIZE
    mb.add_wedge_x(xo - 0.05, xo + 0.002,
                   [(REAR_SLAB_Y0 + 0.001, HULL_Z1), (REAR_SLAB_Y0 + 0.001, HULL_Z1 + n),
                    (REAR_SLAB_Y0 - n, HULL_Z1)], trim, B)
    # 10 Belly hub
    mb.add_cylinder(Vector((0, 0, HUB_Z0)), HUB_Z1 + 0.005, HUB_RADIUS, HUB_SIDES, hull, B,
                    phase=math.pi / HUB_SIDES)
    # 11 Antenna
    mb.add_cylinder(ANTENNA_BASE + Vector((0, 0, -0.005)), ANTENNA_TIP_Z, ANTENNA_RADIUS,
                    ANTENNA_SIDES, ant, "DEF-antenna")

    # Legs
    for tag in LEGS:
        hip, knee, ankle = leg_joints(tag)
        sx, sy = LEGS[tag]
        # hip cube (yaw bone)
        c = hip
        mb.add_box(c.x - HIP_CUBE / 2, c.x + HIP_CUBE / 2, c.y - HIP_CUBE / 2, c.y + HIP_CUBE / 2,
                   c.z - HIP_CUBE / 2, c.z + HIP_CUBE / 2, hull, f"DEF-leg_hip.{tag}")
        # thigh: broad plate + narrower top plate
        d, side, up = leg_frame(hip, knee)
        a = hip - d * THIGH_EXT_HIP
        b = knee + d * THIGH_EXT_KNEE
        L = (b - a).length
        mb.add_oriented_box((a + b) / 2, d, side, up, L, THIGH_WIDTH, THIGH_THICK, hull,
                            f"DEF-leg_upper.{tag}")
        c2 = (a + b) / 2 + d * THIGH2_SHIFT + up * (THIGH_THICK / 2 + THIGH2_THICK / 2 - 0.004)
        mb.add_oriented_box(c2, d, side, up, THIGH2_LEN, THIGH2_WIDTH, THIGH2_THICK, hull,
                            f"DEF-leg_upper.{tag}")
        # shin
        d2, side2, up2 = leg_frame(knee, ankle)
        a = knee - d2 * SHIN_EXT_KNEE
        b = ankle
        mb.add_oriented_box((a + b) / 2, d2, side2, up2, (b - a).length, SHIN_W, SHIN_W, hull,
                            f"DEF-leg_lower.{tag}")
        # foot: axis-aligned with the leg's yaw, flat on the floor
        out = Vector((ankle.x, ankle.y, 0)).normalized()
        perp = Vector((0, 0, 1)).cross(out).normalized()
        fl, fw, fh = FOOT_SIZE
        fc = Vector((ankle.x, ankle.y, fh / 2)) + out * FOOT_OUTWARD
        mb.add_oriented_box(fc, out, perp, Vector((0, 0, 1)), fl, fw, fh, hull, f"DEF-leg_foot.{tag}")

    # Cables: pod underside (rear) -> rear hip, drooping, 4 segments
    for tag in ("BL", "BR"):
        sx = LEGS[tag][0]
        hip, knee, _ = leg_joints(tag)
        p0 = Vector((sx * (HX + POD_PROUD * 0.5), POD_Y1 - 0.06, POD_Z0))
        p1 = hip + (knee - hip) * CABLE_END_ALONG_THIGH + Vector((0, 0, 0.04))
        pts = []
        for i in range(CABLE_SEGMENTS + 1):
            t = i / CABLE_SEGMENTS
            p = p0.lerp(p1, t)
            p.z -= CABLE_DROOP * math.sin(math.pi * t)
            pts.append(p)
        for i in range(CABLE_SEGMENTS):
            a, b = pts[i], pts[i + 1]
            d, side, up = leg_frame(a, b)
            bone = B if i < CABLE_SEGMENTS // 2 else f"DEF-leg_upper.{tag}"
            mb.add_oriented_box((a + b) / 2, d, side, up, (b - a).length + CABLE_T, CABLE_T, CABLE_T,
                                cable, bone)

    return mb.finish("enemy_mesh")


def build_armature():
    arm_data = bpy.data.armatures.new("enemy_rig")
    arm = bpy.data.objects.new("enemy_rig", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    def bone(name, head, tail, parent=None, connect=False, deform=True, roll=0.0):
        b = eb.new(name)
        b.head, b.tail = Vector(head), Vector(tail)
        b.roll = roll
        b.use_deform = deform
        if parent:
            b.parent = eb[parent]
            b.use_connect = connect
        return b

    bone("root", (0, 0, 0), (0, 0.25, 0))
    bone("DEF-body", BODY_CENTRE, BODY_CENTRE + Vector((0, 0, 0.2)), "root")
    bone("DEF-eye", (0, HULL_Y0, BEZEL_ZC), (0, HULL_Y0 - 0.08, BEZEL_ZC), "DEF-body")
    bone("DEF-antenna", ANTENNA_BASE, Vector((ANTENNA_BASE.x, ANTENNA_BASE.y, ANTENNA_TIP_Z)), "DEF-body")
    bone("DEF-muzzle", MUZZLE_POS, MUZZLE_POS + Vector((0, -0.10, 0)), "DEF-body")

    poles = {}
    for tag in LEGS:
        hip, knee, ankle = leg_joints(tag)
        out = Vector((ankle.x, ankle.y, 0)).normalized()
        bone(f"DEF-leg_hip.{tag}", hip, hip + Vector((0, 0, HIP_BONE_LEN)), "DEF-body")
        up_b = bone(f"DEF-leg_upper.{tag}", hip, knee, f"DEF-leg_hip.{tag}")
        lo_b = bone(f"DEF-leg_lower.{tag}", knee, ankle, f"DEF-leg_upper.{tag}", connect=True)
        bone(f"DEF-leg_foot.{tag}", ankle, ankle + out * 0.10, f"DEF-leg_lower.{tag}", connect=True)
        bone(f"IK-foot.{tag}", ankle, ankle + out * 0.12,
             "root", deform=False)
        pole = knee + out * POLE_OUT + Vector((0, 0, POLE_UP))
        bone(f"IK-pole.{tag}", pole, pole + Vector((0, 0, 0.06)), "root", deform=False)
        # pole angle so the IK solution matches the rest pose
        base, ikb = up_b, lo_b
        pole_normal = (ikb.tail - base.head).cross(pole - base.head)
        proj = pole_normal.cross(base.tail - base.head)
        x_axis = base.x_axis
        ang = x_axis.angle(proj)
        if x_axis.cross(proj).dot(base.tail - base.head) > 0:
            ang = -ang
        poles[tag] = ang

    bpy.ops.object.mode_set(mode="POSE")
    pb = arm.pose.bones
    for tag in LEGS:
        ik = pb[f"DEF-leg_lower.{tag}"].constraints.new("IK")
        ik.target = arm
        ik.subtarget = f"IK-foot.{tag}"
        ik.pole_target = arm
        ik.pole_subtarget = f"IK-pole.{tag}"
        ik.pole_angle = poles[tag]
        ik.chain_count = 2
        cr = pb[f"DEF-leg_foot.{tag}"].constraints.new("COPY_ROTATION")
        cr.target = arm
        cr.subtarget = f"IK-foot.{tag}"
        hip_pb = pb[f"DEF-leg_hip.{tag}"]
        hip_pb.lock_rotation = (True, False, True)    # local Y = world Z (yaw only)
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def build_muzzle_empty(arm):
    emp = bpy.data.objects.new("muzzle", None)
    emp.empty_display_type = "SINGLE_ARROW"
    emp.empty_display_size = 0.15
    bpy.context.scene.collection.objects.link(emp)
    emp.parent = arm
    emp.parent_type = "BONE"
    emp.parent_bone = "DEF-muzzle"
    # place at the bone head, arrow (local Z) pointing forward (-Y)
    emp.matrix_world = Matrix.Translation(MUZZLE_POS) @ Matrix.Rotation(math.radians(90), 4, "X")
    return emp


# ==========================================================================
# Render helpers
# ==========================================================================
def setup_render(scene):
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = RENDER_SIZE
    scene.render.resolution_y = RENDER_SIZE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    if hasattr(scene, "eevee"):
        scene.eevee.taa_render_samples = 16
    world = bpy.data.worlds.new("bg")
    world.use_nodes = True
    bgn = world.node_tree.nodes["Background"]
    bgn.inputs["Color"].default_value = (BG_GREY, BG_GREY, BG_GREY, 1)
    bgn.inputs["Strength"].default_value = AMBIENT_STRENGTH
    scene.world = world
    sun_data = bpy.data.lights.new("review_sun", "SUN")
    sun_data.energy = SUN_ENERGY
    sun_data.use_shadow = False
    sun = bpy.data.objects.new("review_sun", sun_data)
    sun.rotation_euler = tuple(math.radians(a) for a in SUN_ROT_DEG)
    scene.collection.objects.link(sun)
    cam_data = bpy.data.cameras.new("review_cam")
    cam_data.lens = CAM_LENS
    cam = bpy.data.objects.new("review_cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def place_camera(cam, azim, elev, target=CAM_TARGET, dist=CAM_DISTANCE):
    a, e = math.radians(azim), math.radians(elev)
    direction = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
    cam.location = target + direction * dist
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    bpy.context.view_layer.update()


def render_to(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def projected_bbox(scene, cam, mesh_obj, skip_group="DEF-antenna"):
    """Normalised image bbox (x0, y0, x1, y1; y from the top) of the posed mesh."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = mesh_obj.evaluated_get(dg)
    me = ev.to_mesh()
    gi = mesh_obj.vertex_groups[skip_group].index
    src = mesh_obj.data
    xs, ys = [], []
    for v, sv in zip(me.vertices, src.vertices):
        if any(g.group == gi for g in sv.groups):
            continue
        co = world_to_camera_view(scene, cam, mesh_obj.matrix_world @ v.co)
        xs.append(co.x)
        ys.append(1.0 - co.y)
    ev.to_mesh_clear()
    return min(xs), min(ys), max(xs), max(ys)


def load_rgba(path):
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    arr = px.reshape(h, w, 4)[::-1].copy()   # top row first
    bpy.data.images.remove(img)
    return arr


def resize_nn(arr, new_h):
    h, w = arr.shape[:2]
    f = int(h // new_h)
    if f >= 2:   # box-filter first so a big shrink does not alias
        hh, ww = (h // f) * f, (w // f) * f
        arr = arr[:hh, :ww].reshape(hh // f, f, ww // f, f, 4).mean(axis=(1, 3))
        h, w = arr.shape[:2]
    new_w = max(1, int(round(w * new_h / h)))
    yi = np.clip((np.arange(new_h) * h / new_h).astype(int), 0, h - 1)
    xi = np.clip((np.arange(new_w) * w / new_w).astype(int), 0, w - 1)
    return arr[yi][:, xi]


def save_rgba(arr, path):
    h, w = arr.shape[:2]
    img = bpy.data.images.new("compare_out", w, h, alpha=True)
    img.pixels.foreach_set(arr[::-1].astype(np.float32).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def crop_frac(arr, y0, y1, pad=0.06):
    h = arr.shape[0]
    span = y1 - y0
    a = max(0, int((y0 - span * pad) * h))
    b = min(h, int((y1 + span * pad) * h))
    return arr[a:b]


def build_compare(scene, cam, mesh_obj):
    """Reference crops (top row) over matching renders (bottom row), mech height equalised."""
    panels_top, panels_bot = [], []
    tmp = os.path.join(RENDER_DIR, "_compare_tmp.png")
    for ref_name, mirror, (fy0, fy1), azim, elev in COMPARE:
        ref = load_rgba(os.path.join(REFS_DIR, ref_name))
        if mirror:
            ref = ref[:, ::-1]
        ref = crop_frac(ref, fy0, fy1)
        cam.data.lens = COMPARE_LENS
        place_camera(cam, azim, elev, dist=COMPARE_DISTANCE)
        render_to(tmp)
        mine = load_rgba(tmp)
        bx0, by0, bx1, by1 = projected_bbox(scene, cam, mesh_obj)
        cam.data.lens = CAM_LENS
        print("BBOX", ref_name, round(bx0,3), round(by0,3), round(bx1,3), round(by1,3), mine.shape)
        mine = crop_frac(mine, by0, by1)
        # crop width around the mech centre to the ref's aspect
        H = COMPARE_PANEL_H
        ref_r = resize_nn(ref, H)
        mine_r = resize_nn(mine, H)
        cx = int((bx0 + bx1) / 2 * mine_r.shape[1])
        half = ref_r.shape[1] // 2
        pad = np.zeros((H, half * 2 + mine_r.shape[1], 4), dtype=np.float32)
        pad[:, :, :3] = BG_GREY ** (1 / 2.2)
        pad[:, :, 3] = 1
        pad[:, half:half + mine_r.shape[1]] = mine_r
        mine_c = pad[:, cx:cx + half * 2]
        panels_top.append(ref_r[:, :half * 2])
        panels_bot.append(mine_c)
    os.remove(tmp)
    gap = 8
    total_w = sum(p.shape[1] for p in panels_top) + gap * (len(panels_top) + 1)
    out = np.ones((COMPARE_PANEL_H * 2 + gap * 3, total_w, 4), dtype=np.float32) * 0.1
    out[:, :, 3] = 1
    x = gap
    for t, b in zip(panels_top, panels_bot):
        w = t.shape[1]
        out[gap:gap + COMPARE_PANEL_H, x:x + w] = t
        out[gap * 2 + COMPARE_PANEL_H:gap * 2 + COMPARE_PANEL_H * 2, x:x + w] = b
        x += w + gap
    save_rgba(out, os.path.join(RENDER_DIR, "enemy_compare.png"))


# ==========================================================================
# Main
# ==========================================================================
def main():
    print("Blender", bpy.app.version_string)
    os.makedirs(RENDER_DIR, exist_ok=True)
    scene = reset_scene()
    mats = {
        "hull": make_material("mat_hull", COL_HULL),
        "trim": make_material("mat_trim", COL_TRIM),
        "eye": make_material("mat_eye", COL_EYE, EYE_EMISSION_STRENGTH),
        "cable": make_material("mat_cable", COL_CABLE),
        "antenna": make_material("mat_antenna", COL_ANTENNA),
    }
    mesh = build_mesh(mats)
    arm = build_armature()
    mesh.parent = arm
    mod = mesh.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    muzzle = build_muzzle_empty(arm)

    # vertex groups must exist for every deform bone (empty ones are fine)
    for b in arm.data.bones:
        if b.use_deform and b.name not in mesh.vertex_groups:
            mesh.vertex_groups.new(name=b.name)

    tris = sum(len(p.vertices) - 2 for p in mesh.data.polygons)
    print(f"ENEMY_TRIS {tris}")
    print("ENEMY_BONES", [b.name for b in arm.data.bones])

    # apply transforms (all identity by construction, but enforce it)
    for o in (arm, mesh):
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # --- glTF export ---
    bpy.ops.object.select_all(action="DESELECT")
    for o in (arm, mesh, muzzle):
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=GLB_PATH,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_skins=True,
        export_def_bones=True,
        export_animations=False,
        export_materials="EXPORT",
        export_extras=False,
    )

    # --- review renders ---
    cam = setup_render(scene)
    for name, (azim, elev) in VIEWS.items():
        place_camera(cam, azim, elev)
        render_to(os.path.join(RENDER_DIR, name + ".png"))
    build_compare(scene, cam, mesh)

    # --- pose test (lift one leg, crouch the body), then restore rest ---
    pb = arm.pose.bones
    ik = pb[f"IK-foot.{POSE_LIFT_LEG}"]
    ik.location = Vector((0, 0, 0))
    # pose-bone location is in bone-local space; convert the world offset
    rest = arm.data.bones[ik.name].matrix_local.to_3x3()
    ik.location = rest.inverted() @ POSE_LIFT
    body = pb["DEF-body"]
    body_rest = arm.data.bones["DEF-body"].matrix_local.to_3x3()
    body.location = body_rest.inverted() @ Vector((0, 0, POSE_CROUCH))
    body.rotation_mode = "XYZ"
    body.rotation_euler = (math.radians(-8), 0, 0)
    bpy.context.view_layer.update()
    for tag in LEGS:
        fh = arm.matrix_world @ pb[f"DEF-leg_foot.{tag}"].head
        kh = arm.matrix_world @ pb[f"DEF-leg_lower.{tag}"].head
        print("POSE", tag, "knee", tuple(round(c, 3) for c in kh), "ankle", tuple(round(c, 3) for c in fh))
    place_camera(cam, *POSE_CAM)
    render_to(os.path.join(RENDER_DIR, "enemy_posetest.png"))
    for p in pb:
        p.location = (0, 0, 0)
        p.rotation_quaternion = (1, 0, 0, 0)
        p.rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()

    bpy.context.preferences.filepaths.save_version = 0   # no enemy.blend1 backups
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print("ENEMY_DONE")


if __name__ == "__main__":
    main()
