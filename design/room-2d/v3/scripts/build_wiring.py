#!/usr/bin/env python3
"""Build unlit room wiring and intermittent travelling-light overlays.

The generated files intentionally contain room-background pixels only. Runtime
layer order is: v2 background -> off-base -> pulse frame -> furniture/effects.
This keeps CPU bulbs, fan rotors, monitors, and furniture indicators untouched.
"""

from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
V2 = ROOT.parent / "v2"
OUT = ROOT / "effects" / "wiring"
WIDTH, HEIGHT = 1672, 941
FRAME_COUNT = 24
FRAME_DURATION_MS = 100

COLORS = {
    "cyan": (72, 232, 255),
    "blue": (89, 151, 255),
    "lavender": (212, 126, 255),
}


# Coordinates follow the physical conduits already painted into the room.
# Black and white themes share camera geometry, so each view has one path set.
PATHS = {
    "horizontal": [
        {"id": "ceiling-left", "color": "blue", "points": [(319, 59), (511, 111), (696, 159), (834, 207)]},
        {"id": "ceiling-right", "color": "lavender", "points": [(836, 207), (1042, 151), (1244, 99), (1343, 71)]},
        {"id": "wall-rail-left", "color": "cyan", "points": [(102, 128), (303, 154), (505, 181), (755, 218)]},
        {"id": "wall-rail-right", "color": "blue", "points": [(865, 220), (1116, 180), (1362, 139), (1573, 105)]},
        {"id": "left-bus", "color": "cyan", "points": [(178, 168), (178, 322), (144, 365), (144, 512), (164, 548)]},
        {"id": "left-return", "color": "lavender", "points": [(114, 171), (114, 350), (132, 382), (132, 530)]},
        {"id": "center-left-bus", "color": "blue", "points": [(721, 267), (721, 410), (701, 451), (701, 546)]},
        {"id": "center-right-bus", "color": "lavender", "points": [(858, 306), (858, 417), (876, 454), (876, 548)]},
        {"id": "right-bus", "color": "cyan", "points": [(1448, 154), (1448, 323), (1474, 356), (1474, 542)]},
        {"id": "right-return", "color": "lavender", "points": [(1549, 170), (1549, 351), (1522, 391), (1522, 548)]},
        {"id": "floor-back-left", "color": "cyan", "points": [(83, 645), (317, 619), (550, 592), (789, 570)]},
        {"id": "floor-back-right", "color": "blue", "points": [(840, 570), (1064, 592), (1303, 620), (1552, 645)]},
        {"id": "floor-front-left", "color": "lavender", "points": [(96, 683), (270, 755), (191, 863), (314, 941)]},
        {"id": "floor-front-right", "color": "cyan", "points": [(1575, 684), (1487, 781), (1535, 850), (1481, 941)]},
    ],
    "overview": [
        {"id": "wall-cap-left", "color": "cyan", "points": [(204, 262), (413, 185), (619, 111), (806, 44)]},
        {"id": "wall-cap-right", "color": "blue", "points": [(867, 46), (1054, 123), (1264, 210), (1453, 288)]},
        {"id": "left-wall-bus", "color": "cyan", "points": [(336, 246), (336, 349), (315, 379), (315, 481)]},
        {"id": "left-wall-return", "color": "lavender", "points": [(271, 297), (271, 410), (286, 438), (286, 495)]},
        {"id": "corner-left-bus", "color": "cyan", "points": [(754, 94), (754, 224), (739, 251), (739, 283)]},
        {"id": "corner-right-bus", "color": "blue", "points": [(901, 91), (901, 221), (919, 251), (919, 287)]},
        {"id": "right-wall-bus", "color": "cyan", "points": [(1282, 241), (1282, 338), (1308, 370), (1308, 477)]},
        {"id": "right-wall-return", "color": "lavender", "points": [(1392, 294), (1392, 408), (1372, 438), (1372, 498)]},
        {"id": "rear-floor-rail", "color": "blue", "points": [(292, 510), (548, 406), (814, 279), (1110, 404), (1381, 510)]},
        {"id": "floor-left-outer", "color": "lavender", "points": [(287, 536), (341, 574), (337, 612), (449, 675), (573, 706)]},
        {"id": "floor-left-inner", "color": "cyan", "points": [(412, 524), (449, 554), (410, 589), (521, 656), (667, 668)]},
        {"id": "floor-right-inner", "color": "cyan", "points": [(1002, 659), (1110, 621), (1134, 575), (1260, 532)]},
        {"id": "floor-right-outer", "color": "lavender", "points": [(1090, 718), (1208, 684), (1281, 637), (1369, 607), (1394, 559)]},
        {"id": "front-rail-left", "color": "blue", "points": [(506, 735), (659, 809), (806, 895)]},
        {"id": "front-rail-right", "color": "cyan", "points": [(867, 896), (1024, 810), (1193, 719)]},
    ],
}


def rgba_composite(base: np.ndarray, over: np.ndarray) -> np.ndarray:
    alpha = over[..., 3:4].astype(np.float32) / 255.0
    rgb = over[..., :3].astype(np.float32) * alpha + base[..., :3].astype(np.float32) * (1.0 - alpha)
    return np.dstack((np.clip(rgb, 0, 255).astype(np.uint8), np.full((HEIGHT, WIDTH), 255, np.uint8)))


def make_off_base(source: np.ndarray, theme: str, view: str) -> tuple[np.ndarray, dict]:
    # Neutral material/grooves rebuilt with imagegen; avoids residual emission and corridor bands.
    path = ROOT / 'repairs' / f'{theme}-{view}-background-off.png'
    off = np.array(Image.open(path).convert('RGBA'))
    assert off.shape == (HEIGHT, WIDTH, 4)
    # Explicit unlit inset conductors align exactly with the animated pulse paths.
    for pathdef in PATHS[view]:
        points = np.asarray(pathdef['points'], np.int32).reshape((-1, 1, 2))
        cv2.polylines(off, [points + np.array([0, 1])], False,
                      (77, 80, 84, 255) if theme == 'black' else (241, 242, 243, 255), 2, cv2.LINE_AA)
        cv2.polylines(off, [points], False,
                      (24, 28, 33, 255) if theme == 'black' else (154, 159, 166, 255), 2, cv2.LINE_AA)
    return off, {'method': 'Built-in imagegen unlit background replacement',
                 'source': str(path.relative_to(ROOT)), 'coverage': 'entire room background',
                 'opaqueReplacement': True}


def polyline_samples(points: list[tuple[int, int]]) -> tuple[np.ndarray, float]:
    pts = np.asarray(points, dtype=np.float32)
    pieces = pts[1:] - pts[:-1]
    lengths = np.sqrt((pieces * pieces).sum(axis=1))
    cumulative = np.concatenate(([0.0], np.cumsum(lengths)))
    total = float(cumulative[-1])
    distances = np.arange(0, max(1, int(total)) + 1, dtype=np.float32)
    result = []
    for d in distances:
        seg = min(int(np.searchsorted(cumulative, d, side="right") - 1), len(pieces) - 1)
        ratio = 0.0 if lengths[seg] == 0 else (d - cumulative[seg]) / lengths[seg]
        result.append(pts[seg] + pieces[seg] * ratio)
    return np.asarray(result, dtype=np.float32), total


def render_pulse_frame(paths: list[dict], frame_index: int) -> tuple[np.ndarray, int]:
    core_rgb = np.zeros((HEIGHT, WIDTH, 3), np.uint8)
    core_alpha = np.zeros((HEIGHT, WIDTH), np.uint8)
    glow_rgb = np.zeros((HEIGHT, WIDTH, 3), np.float32)
    glow_alpha = np.zeros((HEIGHT, WIDTH), np.float32)
    active_count = 0

    for path_index, path in enumerate(paths):
        # Different quiet windows prevent every conduit from flashing in unison.
        cycle = (frame_index + path_index * 3) % FRAME_COUNT
        active_span = 13 + (path_index % 3)
        if cycle >= active_span:
            continue
        samples, total = polyline_samples(path["points"])
        if total < 2:
            continue
        segment_length = min(116 + (path_index % 4) * 16, max(32, int(total * 0.34)))
        head = int((cycle / max(1, active_span - 1)) * (len(samples) + segment_length))
        start = max(0, head - segment_length)
        end = min(len(samples), head)
        if end - start < 2:
            continue
        segment = np.rint(samples[start:end]).astype(np.int32).reshape((-1, 1, 2))
        color = COLORS[path["color"]]
        mask = np.zeros((HEIGHT, WIDTH), np.uint8)
        cv2.polylines(mask, [segment], False, 255, 11, cv2.LINE_AA)
        blurred = cv2.GaussianBlur(mask, (0, 0), 7.0).astype(np.float32) / 255.0
        weight = blurred * 0.58
        color_array = np.asarray(color, np.float32)
        glow_rgb += color_array[None, None, :] * weight[..., None]
        glow_alpha += weight
        cv2.polylines(core_rgb, [segment], False, color, 4, cv2.LINE_AA)
        cv2.polylines(core_alpha, [segment], False, 238, 4, cv2.LINE_AA)
        cv2.polylines(core_rgb, [segment], False, (221, 250, 255), 1, cv2.LINE_AA)
        cv2.polylines(core_alpha, [segment], False, 252, 1, cv2.LINE_AA)
        active_count += 1

    core = np.dstack((core_rgb, core_alpha))
    glow = np.zeros_like(core)
    safe_alpha = np.clip(glow_alpha, 0, 1)
    glow[..., :3] = np.clip(glow_rgb / np.maximum(glow_alpha[..., None], 1e-6), 0, 255).astype(np.uint8)
    glow[..., 3] = np.clip(safe_alpha * 148, 0, 148).astype(np.uint8)
    result = rgba_composite(glow, core)
    # rgba_composite assumes an opaque destination; restore true combined alpha.
    a0 = glow[..., 3].astype(np.float32) / 255.0
    a1 = core[..., 3].astype(np.float32) / 255.0
    result[..., 3] = np.clip((a1 + a0 * (1 - a1)) * 255, 0, 255).astype(np.uint8)
    return result, active_count


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    scene_records = []
    for theme in ("black", "white"):
        for view in ("overview", "horizontal"):
            scene_id = f"{theme}-{view}"
            source_path = V2 / "scenes" / scene_id / "background.png"
            source = np.asarray(Image.open(source_path).convert("RGBA"))
            destination = OUT / scene_id
            destination.mkdir(parents=True, exist_ok=True)

            off_base, neutralization = make_off_base(source, theme, view)
            off_path = destination / "off-base.png"
            Image.fromarray(off_base, "RGBA").save(off_path, optimize=True)

            frame_paths = []
            active_counts = []
            for index in range(FRAME_COUNT):
                frame, active_count = render_pulse_frame(PATHS[view], index)
                path = destination / f"pulse-{index:02d}.png"
                Image.fromarray(frame, "RGBA").save(path, optimize=True)
                frame_paths.append(str(path.relative_to(ROOT)))
                active_counts.append(active_count)

            scene_records.append({
                "id": scene_id,
                "inputBackground": str(Path("..") / source_path.relative_to(V2)),
                "layering": [
                    "v2 background",
                    "wiring offBase",
                    "wiring pulse frame",
                    "all furniture/component layers",
                    "component-local animated effects",
                ],
                "offBase": str(off_path.relative_to(ROOT)),
                "frames": frame_paths,
                "activePathCounts": active_counts,
                "paths": PATHS[view],
                "neutralization": neutralization,
            })

    revision = {
        "version": 3,
        "feature": "intermittent-room-wiring-pulses",
        "canvas": {"width": WIDTH, "height": HEIGHT},
        "frameCount": FRAME_COUNT,
        "frameDurationMs": FRAME_DURATION_MS,
        "loopDurationMs": FRAME_COUNT * FRAME_DURATION_MS,
        "pulseLengthPx": {"minimum": 32, "nominal": [116, 164], "maximumPathFraction": 0.34},
        "palette": COLORS,
        "baseState": "All room wiring off: imagegen rebuilt unlit metallic grooves; no emissive background traces",
        "scope": "room background circuitry only; furniture, CPU bulbs, fans, display, and component indicators are excluded by construction",
        "integration": {
            "blend": "source-over",
            "offBaseRequired": True,
            "pulseFrameRequired": True,
            "runtimeFrameIndex": "floor(elapsedMs / 100) % 24",
        },
        "scenes": scene_records,
    }
    (ROOT / "wiring-revision.json").write_text(json.dumps(revision, ensure_ascii=False, indent=2) + "\n")
    print(f"Created {len(scene_records)} off-base overlays and {len(scene_records) * FRAME_COUNT} pulse frames")


if __name__ == "__main__":
    main()
