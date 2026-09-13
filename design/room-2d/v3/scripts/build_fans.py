#!/usr/bin/env python3
"""Build fan assets with a fixed housing/hub and blade-only animation frames.

The v2 animation rotated the entire fan ellipse, including the inner rim and hub.
This exporter reconstructs the rotor well as a fixed component and emits twelve
transparent frames whose non-zero alpha is restricted to the blade swept area.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
V2 = ROOT / "v2"
V3 = ROOT / "v3"
EFFECTS_OUT = V3 / "effects"
FRAME_COUNT = 12
FRAME_DURATION_MS = 100
CANVAS = (1672, 941)
SUPERSAMPLE = 4


def ellipse_mask(shape: tuple[int, int], ellipse: dict, inset: float = 0.0) -> np.ndarray:
    height, width = shape
    mask = np.zeros((height, width), dtype=np.uint8)
    axes = (
        max(1, int(round(float(ellipse["rx"]) - inset))),
        max(1, int(round(float(ellipse["ry"]) - inset))),
    )
    cv2.ellipse(
        mask,
        (int(ellipse["cx"]), int(ellipse["cy"])),
        axes,
        float(ellipse.get("rotationDegrees", 0)),
        0,
        360,
        255,
        -1,
        cv2.LINE_AA,
    )
    return mask


def polar_point(center: float, radius: float, angle_degrees: float) -> tuple[int, int]:
    angle = math.radians(angle_degrees)
    return (
        int(round(center + radius * math.cos(angle))),
        int(round(center + radius * math.sin(angle))),
    )


def blade_disc(theme: str, angle_offset: float, blade_count: int) -> np.ndarray:
    size = 256 * SUPERSAMPLE
    center = (size - 1) / 2.0
    outer = size * 0.47
    image = np.zeros((size, size, 4), dtype=np.uint8)

    if theme == "black":
        base = (58, 76, 84, 242)
        edge = (55, 224, 255, 255)
        highlight = (145, 244, 255, 225)
    else:
        base = (96, 112, 120, 235)
        edge = (48, 205, 247, 255)
        highlight = (181, 244, 255, 235)

    step = 360.0 / blade_count
    for blade_index in range(blade_count):
        a = angle_offset + blade_index * step
        blade = [
            polar_point(center, outer * 0.27, a + 10),
            polar_point(center, outer * 0.43, a + 7),
            polar_point(center, outer * 0.67, a - 3),
            polar_point(center, outer * 0.88, a - 18),
            polar_point(center, outer * 0.91, a - 4),
            polar_point(center, outer * 0.75, a + 13),
            polar_point(center, outer * 0.51, a + 21),
            polar_point(center, outer * 0.31, a + 18),
        ]
        cv2.fillPoly(image, [np.asarray(blade, dtype=np.int32)], base, cv2.LINE_AA)

        cyan_edge = [
            polar_point(center, outer * 0.35, a + 12),
            polar_point(center, outer * 0.55, a + 10),
            polar_point(center, outer * 0.78, a - 2),
            polar_point(center, outer * 0.84, a - 10),
            polar_point(center, outer * 0.72, a + 5),
            polar_point(center, outer * 0.51, a + 17),
        ]
        cv2.polylines(image, [np.asarray(cyan_edge, dtype=np.int32)], False, edge, 7 * SUPERSAMPLE, cv2.LINE_AA)
        cv2.polylines(image, [np.asarray(cyan_edge, dtype=np.int32)], False, highlight, 2 * SUPERSAMPLE, cv2.LINE_AA)

    # The hub owns the center, so blade frames never paint it.
    cv2.circle(image, (round(center), round(center)), round(outer * 0.36), (0, 0, 0, 0), -1, cv2.LINE_AA)
    return cv2.resize(image, (256, 256), interpolation=cv2.INTER_AREA)


def project_disc(disc: np.ndarray, ellipse: dict) -> np.ndarray:
    width, height = CANVAS
    cx, cy = int(ellipse["cx"]), int(ellipse["cy"])
    rx, ry = int(ellipse["rx"]), int(ellipse["ry"])
    rotation = float(ellipse.get("rotationDegrees", 0))
    radius = max(rx, ry) + 6
    patch_size = radius * 2 + 1
    local = np.zeros((patch_size, patch_size, 4), dtype=np.uint8)
    resized = cv2.resize(disc, (rx * 2 + 1, ry * 2 + 1), interpolation=cv2.INTER_AREA)
    local[radius - ry : radius + ry + 1, radius - rx : radius + rx + 1] = resized
    if rotation:
        matrix = cv2.getRotationMatrix2D((radius, radius), -rotation, 1.0)
        local = cv2.warpAffine(
            local,
            matrix,
            (patch_size, patch_size),
            flags=cv2.INTER_CUBIC,
            borderMode=cv2.BORDER_CONSTANT,
        )

    canvas = np.zeros((height, width, 4), dtype=np.uint8)
    x1, y1 = cx - radius, cy - radius
    canvas[y1 : y1 + patch_size, x1 : x1 + patch_size] = local
    swept = ellipse_mask((height, width), ellipse, inset=max(3.0, min(rx, ry) * 0.08))
    canvas[:, :, 3] = cv2.bitwise_and(canvas[:, :, 3], swept)
    canvas[canvas[:, :, 3] == 0, :3] = 0
    return canvas


def clean_fixed_housing(source: np.ndarray, ellipse: dict, theme: str, view: str) -> np.ndarray:
    height, width = source.shape[:2]
    fixed = source.copy()
    inset = max(2.5, min(float(ellipse["rx"]), float(ellipse["ry"])) * 0.08)
    well_mask = ellipse_mask((height, width), ellipse, inset=inset)
    cx, cy = int(ellipse["cx"]), int(ellipse["cy"])
    rx, ry = int(ellipse["rx"]), int(ellipse["ry"])
    angle = float(ellipse.get("rotationDegrees", 0))

    well_color = np.array((9, 17, 23, 255) if theme == "black" else (29, 39, 45, 255), dtype=np.uint8)
    fixed[well_mask > 0] = well_color

    # Keep the circular inner rim fixed. Horizontal view also retains its protective grille.
    ring_color = (67, 86, 94, 255) if theme == "black" else (132, 145, 150, 255)
    ring_glint = (105, 135, 145, 220) if theme == "black" else (205, 216, 220, 230)
    cv2.ellipse(fixed, (cx, cy), (max(1, rx - 2), max(1, ry - 2)), angle, 0, 360, ring_color, 2, cv2.LINE_AA)
    cv2.ellipse(fixed, (cx, cy), (max(1, rx - 4), max(1, ry - 4)), angle, 195, 340, ring_glint, 1, cv2.LINE_AA)

    return fixed


def fixed_hub(ellipse: dict, theme: str, view: str) -> np.ndarray:
    width, height = CANVAS
    hub = np.zeros((height, width, 4), dtype=np.uint8)
    cx, cy = int(ellipse["cx"]), int(ellipse["cy"])
    rx, ry = int(ellipse["rx"]), int(ellipse["ry"])
    radius = max(5, round(min(rx, ry) * (0.25 if view == "horizontal" else 0.22)))
    outer = (29, 43, 49, 255) if theme == "black" else (101, 111, 116, 255)
    inner = (55, 65, 69, 255) if theme == "black" else (146, 154, 157, 255)
    cyan = (52, 223, 255, 255)
    cv2.circle(hub, (cx, cy), radius + 2, outer, -1, cv2.LINE_AA)
    cv2.circle(hub, (cx, cy), radius, cyan, 2, cv2.LINE_AA)
    cv2.circle(hub, (cx, cy), max(2, radius - 3), inner, -1, cv2.LINE_AA)
    cv2.circle(hub, (cx - max(1, radius // 4), cy - max(1, radius // 4)), max(1, radius // 5), (190, 236, 244, 170), -1, cv2.LINE_AA)
    return hub


def fixed_grille(ellipse: dict, theme: str, view: str) -> np.ndarray:
    width, height = CANVAS
    grille = np.zeros((height, width, 4), dtype=np.uint8)
    cx, cy = int(ellipse["cx"]), int(ellipse["cy"])
    rx, ry = int(ellipse["rx"]), int(ellipse["ry"])
    angle = float(ellipse.get("rotationDegrees", 0))
    hub_radius = max(5, round(min(rx, ry) * 0.25))
    spoke_color = (64, 76, 82, 235) if theme == "black" else (116, 126, 130, 230)
    cv2.ellipse(grille, (cx, cy), (max(1, rx - 3), max(1, ry - 3)), angle, 0, 360, spoke_color, 1, cv2.LINE_AA)
    if view != "horizontal":
        return grille
    for spoke_angle in (18, 108, 198, 288):
        theta = math.radians(spoke_angle)
        inner_point = (round(cx + math.cos(theta) * hub_radius), round(cy + math.sin(theta) * hub_radius))
        outer_point = (round(cx + math.cos(theta) * (rx - 3)), round(cy + math.sin(theta) * (ry - 3)))
        cv2.line(grille, inner_point, outer_point, spoke_color, 2, cv2.LINE_AA)
    return grille


def save_rgba(path: Path, rgba: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba, "RGBA").save(path, optimize=True)


def alpha_bbox(alpha: np.ndarray) -> list[int] | None:
    ys, xs = np.where(alpha > 0)
    if not len(xs):
        return None
    return [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1]


def main() -> None:
    effects_manifest = json.loads((V2 / "effects" / "manifest.json").read_text())
    scene_map = {scene["id"]: scene for scene in effects_manifest["scenes"]}
    revision = {
        "version": 3,
        "sourceVersion": 2,
        "frameCount": FRAME_COUNT,
        "frameDurationMs": FRAME_DURATION_MS,
        "contract": {
            "compositionOrder": ["fixedHousing", "bladeFrame", "fixedGrille", "fixedHub"],
            "rotatingPixels": "bladeFrame alpha only",
            "fixedPixels": "housing, inner rim, grille/supports, and hub",
        },
        "scenes": [],
        "qa": {},
    }

    unique_frame_hashes: set[bytes] = set()
    outside_swept_alpha = 0
    separation_overlap = 0
    outer_housing_changed_pixels = 0
    composite_variation_outside_blades = 0
    output_count = 0

    for scene_id in ("black-overview", "black-horizontal", "white-overview", "white-horizontal"):
        theme, view = scene_id.split("-")
        v2_scene = scene_map[scene_id]
        scene_record = {"id": scene_id, "fans": []}
        for fan in v2_scene["fans"]:
            fan_id = fan["id"]
            ellipse = fan["ellipse"]
            source_path = V2 / "scenes" / scene_id / f"{fan_id}.png"
            source = np.asarray(Image.open(source_path).convert("RGBA"))
            fixed = clean_fixed_housing(source, ellipse, theme, view)
            hub = fixed_hub(ellipse, theme, view)
            grille = fixed_grille(ellipse, theme, view)
            fan_dir = EFFECTS_OUT / theme / view / fan_id
            fan_dir.mkdir(parents=True, exist_ok=True)
            for index in range(FRAME_COUNT):
                legacy_frame = fan_dir / f"frame-{index:02d}.png"
                if legacy_frame.exists():
                    legacy_frame.unlink()

            rotor_envelope = ellipse_mask((CANVAS[1], CANVAS[0]), ellipse)
            changed = np.any(fixed != source, axis=2)
            outer_housing_changed_pixels += int(np.count_nonzero(changed & (rotor_envelope == 0)))

            fixed_path = fan_dir / "fixed-housing.png"
            grille_path = fan_dir / "fixed-grille.png"
            hub_path = fan_dir / "fixed-hub.png"
            save_rgba(fixed_path, fixed)
            save_rgba(grille_path, grille)
            save_rgba(hub_path, hub)
            output_count += 3

            frame_paths = []
            frames = []
            blade_count = 11 if view == "horizontal" else 7
            hub_exclusion = cv2.dilate((hub[:, :, 3] > 0).astype(np.uint8), np.ones((3, 3), np.uint8), iterations=1) > 0
            fan_frame_hashes: set[bytes] = set()
            for index in range(FRAME_COUNT):
                angle = index * (360.0 / FRAME_COUNT)
                disc = blade_disc(theme, angle, blade_count)
                frame = project_disc(disc, ellipse)
                frame[hub_exclusion] = 0
                frame_path = fan_dir / f"blades-frame-{index:02d}.png"
                save_rgba(frame_path, frame)
                frame_paths.append(str(frame_path.relative_to(EFFECTS_OUT)))
                frames.append(frame)
                unique_frame_hashes.add(frame.tobytes())
                fan_frame_hashes.add(frame.tobytes())
                output_count += 1

                swept = ellipse_mask((CANVAS[1], CANVAS[0]), ellipse, inset=max(3.0, min(ellipse["rx"], ellipse["ry"]) * 0.08))
                outside_swept_alpha += int(np.count_nonzero((frame[:, :, 3] > 0) & (swept == 0)))
                hub_mask = hub[:, :, 3] > 0
                separation_overlap += int(np.count_nonzero((frame[:, :, 3] > 0) & hub_mask))

            static_path = fan_dir / "blades-static.png"
            save_rgba(static_path, frames[0])
            output_count += 1
            composite_static = Image.fromarray(fixed, "RGBA")
            for layer in (frames[0], grille, hub):
                composite_static = Image.alpha_composite(composite_static, Image.fromarray(layer, "RGBA"))
            composite_path = fan_dir / "composite-static.png"
            composite_static.save(composite_path, optimize=True)
            output_count += 1

            blade_union = np.logical_or.reduce([frame[:, :, 3] > 0 for frame in frames])
            reference_composite = np.asarray(composite_static)
            for frame in frames[1:]:
                composite = Image.fromarray(fixed, "RGBA")
                for layer in (frame, grille, hub):
                    composite = Image.alpha_composite(composite, Image.fromarray(layer, "RGBA"))
                changed = np.any(np.asarray(composite) != reference_composite, axis=2)
                composite_variation_outside_blades += int(np.count_nonzero(changed & ~blade_union))
            scene_record["fans"].append(
                {
                    "id": fan_id,
                    "center": fan["center"],
                    "ellipse": ellipse,
                    "bladeCount": blade_count,
                    "fixedHousing": str(fixed_path.relative_to(EFFECTS_OUT)),
                    "fixedGrille": str(grille_path.relative_to(EFFECTS_OUT)),
                    "fixedHub": str(hub_path.relative_to(EFFECTS_OUT)),
                    "bladesStatic": str(static_path.relative_to(EFFECTS_OUT)),
                    "compositeStatic": str(composite_path.relative_to(EFFECTS_OUT)),
                    "bladeFrames": frame_paths,
                    "frameDurationMs": FRAME_DURATION_MS,
                    "blend": "source-over",
                    "bladeAlphaBBox": alpha_bbox(frames[0][:, :, 3]),
                    "uniqueBladeFrameCount": len(fan_frame_hashes),
                }
            )
        revision["scenes"].append(scene_record)

    revision["qa"] = {
        "fanCount": 8,
        "outputPngCount": output_count,
        "expectedOutputPngCount": 8 * (3 + FRAME_COUNT + 2),
        "uniqueBladeFramesAcrossAllFans": len(unique_frame_hashes),
        "outsideSweptAreaAlphaPixels": outside_swept_alpha,
        "bladeHubAlphaOverlapPixels": separation_overlap,
        "fixedHousingChangedPixelsOutsideRotorEllipse": outer_housing_changed_pixels,
        "compositeVariationOutsideBladeUnionPixels": composite_variation_outside_blades,
        "passed": (
            outside_swept_alpha == 0
            and separation_overlap == 0
            and outer_housing_changed_pixels == 0
            and composite_variation_outside_blades == 0
            and output_count == 136
        ),
    }
    (V3 / "fan-revision.json").write_text(json.dumps(revision, indent=2) + "\n")
    print(json.dumps(revision["qa"], indent=2))


if __name__ == "__main__":
    main()
