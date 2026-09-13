#!/usr/bin/env python3
"""Export canvas-sized RGBA effect layers from the four room master images."""

from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ANNOTATIONS = ROOT / "effects-annotations.json"
OUTPUT = ROOT / "effects"
FRAME_COUNT = 12
FRAME_DURATION_MS = 100


def polygon_mask(size: tuple[int, int], points: list[list[int]]) -> np.ndarray:
    width, height = size
    mask = np.zeros((height, width), dtype=np.uint8)
    cv2.fillPoly(mask, [np.asarray(points, dtype=np.int32)], 255)
    return mask


def ellipse_mask(size: tuple[int, int], ellipse: dict) -> np.ndarray:
    width, height = size
    mask = np.zeros((height, width), dtype=np.uint8)
    center = (int(ellipse["cx"]), int(ellipse["cy"]))
    axes = (int(ellipse["rx"]), int(ellipse["ry"]))
    cv2.ellipse(mask, center, axes, float(ellipse.get("rotationDegrees", 0)), 0, 360, 255, -1, cv2.LINE_AA)
    return mask


def rgba_from_mask(bgr: np.ndarray, mask: np.ndarray) -> np.ndarray:
    rgba = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGBA)
    rgba[:, :, 3] = mask
    rgba[mask == 0, :3] = 0
    return rgba


def save_rgba(path: Path, rgba: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba, "RGBA").save(path, compress_level=6)


def solid_layer(size: tuple[int, int], mask: np.ndarray, rgb: tuple[int, int, int]) -> np.ndarray:
    width, height = size
    rgba = np.zeros((height, width, 4), dtype=np.uint8)
    rgba[:, :, :3] = rgb
    rgba[:, :, 3] = mask
    return rgba


def composite(base: np.ndarray, overlay: np.ndarray) -> np.ndarray:
    a = overlay[:, :, 3:4].astype(np.float32) / 255.0
    out = base.copy()
    out[:, :, :3] = np.clip(overlay[:, :, :3] * a + base[:, :, :3] * (1.0 - a), 0, 255).astype(np.uint8)
    out[:, :, 3] = np.maximum(base[:, :, 3], overlay[:, :, 3])
    return out


def extract_compute_components(bgr: np.ndarray, roi_mask: np.ndarray) -> list[dict]:
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    value = hsv[:, :, 2]
    saturation = hsv[:, :, 1]
    blue = bgr[:, :, 0]
    green = bgr[:, :, 1]
    red = bgr[:, :, 2]
    bright = ((value >= 172) & (blue >= 160) & (green >= 135) & ((saturation >= 20) | (value >= 225)))
    binary = (bright.astype(np.uint8) * 255)
    binary = cv2.bitwise_and(binary, roi_mask)
    binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, np.ones((2, 2), np.uint8))
    count, labels, stats, centroids = cv2.connectedComponentsWithStats(binary, 8)
    components = []
    for index in range(1, count):
        x, y, width, height, area = [int(v) for v in stats[index]]
        aspect = width / max(height, 1)
        if area < 3 or area > 180 or width > 12 or height > 14 or not 0.5 <= aspect <= 1.8:
            continue
        component = np.zeros_like(binary)
        component[labels == index] = 255
        component = cv2.dilate(component, np.ones((3, 3), np.uint8), iterations=1)
        components.append({
            "center": [round(float(centroids[index][0]), 1), round(float(centroids[index][1]), 1)],
            "bbox": [x, y, x + width, y + height],
            "mask": component,
        })
    return components


def make_compute_layers(
    bgr: np.ndarray,
    roi_mask: np.ndarray,
    components: list[dict],
    theme: str,
    seed: int,
) -> tuple[np.ndarray, np.ndarray, list[np.ndarray]]:
    height, width = bgr.shape[:2]
    on = np.zeros((height, width, 4), dtype=np.uint8)
    off = np.zeros_like(on)
    source_rgba = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGBA)
    off_rgb = (19, 32, 40) if theme == "black" else (51, 67, 77)
    all_mask = np.zeros((height, width), dtype=np.uint8)
    for component in components:
        all_mask = cv2.bitwise_or(all_mask, component["mask"])
    all_soft = cv2.max(all_mask, cv2.GaussianBlur(all_mask, (0, 0), 1.2))
    on = source_rgba.copy()
    on[:, :, 3] = all_soft
    on[all_soft == 0, :3] = 0
    off = solid_layer((width, height), all_soft, off_rgb)

    rng = np.random.default_rng(seed)
    frames = []
    for frame_index in range(FRAME_COUNT):
        frame = off.copy()
        if components:
            selection = rng.random(len(components)) < (0.35 + 0.18 * ((frame_index % 3) / 2))
            if not selection.any():
                selection[rng.integers(0, len(components))] = True
            selected_mask = np.zeros((height, width), dtype=np.uint8)
            for enabled, component in zip(selection, components):
                if enabled:
                    selected_mask = cv2.bitwise_or(selected_mask, component["mask"])
            selected_soft = cv2.max(selected_mask, cv2.GaussianBlur(selected_mask, (0, 0), 1.2))
            component_rgba = source_rgba.copy()
            component_rgba[:, :, 3] = selected_soft
            component_rgba[selected_soft == 0, :3] = 0
            frame = composite(frame, component_rgba)
        frames.append(frame)
    return off, on, frames


def rotate_fan_frames(bgr: np.ndarray, ellipse: dict) -> list[np.ndarray]:
    height, width = bgr.shape[:2]
    cx, cy = int(ellipse["cx"]), int(ellipse["cy"])
    rx, ry = int(ellipse["rx"]), int(ellipse["ry"])
    rotation = float(ellipse.get("rotationDegrees", 0))
    margin = 3
    radius = max(rx, ry) + margin
    x1, y1, x2, y2 = cx - radius, cy - radius, cx + radius + 1, cy + radius + 1
    crop = cv2.cvtColor(bgr[y1:y2, x1:x2], cv2.COLOR_BGR2RGBA)
    local_center = (radius, radius)

    local_mask = np.zeros(crop.shape[:2], dtype=np.uint8)
    cv2.ellipse(local_mask, local_center, (rx, ry), rotation, 0, 360, 255, -1, cv2.LINE_AA)
    crop[:, :, 3] = local_mask
    crop[local_mask == 0, :3] = 0
    hub_mask = np.zeros(crop.shape[:2], dtype=np.uint8)
    cv2.circle(hub_mask, local_center, max(5, round(min(rx, ry) * 0.24)), 255, -1, cv2.LINE_AA)

    # Undo perspective ellipse, rotate as a circle, then restore the source ellipse.
    unrot = cv2.warpAffine(crop, cv2.getRotationMatrix2D(local_center, rotation, 1.0), crop.shape[1::-1], flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_CONSTANT)
    square_size = max(rx, ry) * 2 + 1
    normalized = cv2.resize(unrot[radius - ry:radius + ry + 1, radius - rx:radius + rx + 1], (square_size, square_size), interpolation=cv2.INTER_CUBIC)
    norm_center = ((square_size - 1) / 2, (square_size - 1) / 2)

    frames = []
    for index in range(FRAME_COUNT):
        angle = index * (360.0 / FRAME_COUNT)
        spun = cv2.warpAffine(normalized, cv2.getRotationMatrix2D(norm_center, angle, 1.0), (square_size, square_size), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_CONSTANT)
        restored = cv2.resize(spun, (rx * 2 + 1, ry * 2 + 1), interpolation=cv2.INTER_CUBIC)
        local = np.zeros_like(crop)
        local[radius - ry:radius + ry + 1, radius - rx:radius + rx + 1] = restored
        local = cv2.warpAffine(local, cv2.getRotationMatrix2D(local_center, -rotation, 1.0), crop.shape[1::-1], flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_CONSTANT)
        local[:, :, 3] = cv2.bitwise_and(local[:, :, 3], local_mask)
        local[hub_mask > 0] = crop[hub_mask > 0]
        canvas = np.zeros((height, width, 4), dtype=np.uint8)
        canvas[y1:y2, x1:x2] = local
        frames.append(canvas)
    return frames


def clock_hand_masks(size: tuple[int, int], scene_id: str, clock: dict) -> tuple[np.ndarray, dict[str, list[int]], dict[str, np.ndarray]]:
    width, height = size
    center = tuple(int(v) for v in clock["center"])
    endpoints_by_view = {
        "overview": {"hour": [654, 151], "minute": [679, 141]},
        "horizontal": {"hour": [693, 311], "minute": [650, 309]},
    }
    view = "overview" if scene_id.endswith("overview") else "horizontal"
    endpoints = endpoints_by_view[view]
    face_mask = polygon_mask(size, clock["polygon"])
    individual = {}
    for role, endpoint in endpoints.items():
        hand = np.zeros((height, width), dtype=np.uint8)
        cv2.line(hand, center, tuple(endpoint), 255, 4, cv2.LINE_AA)
        cv2.circle(hand, center, 5, 255, -1, cv2.LINE_AA)
        individual[role] = cv2.bitwise_and(hand, face_mask)
    combined = cv2.bitwise_or(individual["hour"], individual["minute"])
    return combined, endpoints, individual


def export_scene(scene: dict, theme: str, view: str, source_path: Path) -> dict:
    bgr = cv2.imread(str(source_path), cv2.IMREAD_COLOR)
    if bgr is None:
        raise FileNotFoundError(source_path)
    height, width = bgr.shape[:2]
    size = (width, height)
    out = OUTPUT / theme / view
    out.mkdir(parents=True, exist_ok=True)

    monitor_mask = polygon_mask(size, scene["monitorScreen"]["quad"])
    save_rgba(out / "display-screen.png", rgba_from_mask(bgr, monitor_mask))
    blank_rgb = (6, 18, 26) if theme == "black" else (21, 36, 45)
    blank = solid_layer(size, monitor_mask, blank_rgb)
    save_rgba(out / "display-blank.png", blank)

    battery_mask = polygon_mask(size, scene["batteryIndicator"]["polygon"])
    save_rgba(out / "battery-indicator.png", rgba_from_mask(bgr, battery_mask))

    compute_polygons = scene["computeLights"].get("polygons", [scene["computeLights"]["polygon"]])
    compute_mask = np.zeros((height, width), dtype=np.uint8)
    for points in compute_polygons:
        compute_mask = cv2.bitwise_or(compute_mask, polygon_mask(size, points))
    components = extract_compute_components(bgr, compute_mask)
    seed = 4817 + (100 if theme == "white" else 0) + (10 if view == "horizontal" else 0)
    compute_off, compute_on, compute_frames = make_compute_layers(bgr, compute_mask, components, theme, seed)
    save_rgba(out / "compute-off.png", compute_off)
    save_rgba(out / "compute-on.png", compute_on)
    for index, frame in enumerate(compute_frames):
        save_rgba(out / "compute" / f"frame-{index:02d}.png", frame)

    fan_entries = []
    for fan in scene["fans"]:
        frames = rotate_fan_frames(bgr, fan["ellipse"])
        for index, frame in enumerate(frames):
            save_rgba(out / fan["id"] / f"frame-{index:02d}.png", frame)
        fan_entries.append({
            "id": fan["id"],
            "center": fan["center"],
            "ellipse": fan["ellipse"],
            "frames": [f"{theme}/{view}/{fan['id']}/frame-{index:02d}.png" for index in range(FRAME_COUNT)],
            "frameDurationMs": FRAME_DURATION_MS,
            "blend": "source-over",
        })

    clock_polygon_mask = polygon_mask(size, scene["clock"]["polygon"])
    hand_mask, hand_endpoints, individual_hands = clock_hand_masks(size, scene["id"], scene["clock"])
    save_rgba(out / "clock-face.png", rgba_from_mask(bgr, clock_polygon_mask))
    inpaint_mask = cv2.dilate(hand_mask, np.ones((3, 3), np.uint8), iterations=1)
    inpainted = cv2.inpaint(bgr, inpaint_mask, 4, cv2.INPAINT_TELEA)
    save_rgba(out / "clock-face-blank.png", rgba_from_mask(inpainted, clock_polygon_mask))
    save_rgba(out / "clock-hands.png", rgba_from_mask(bgr, hand_mask))
    save_rgba(out / "clock-hour-hand.png", rgba_from_mask(bgr, individual_hands["hour"]))
    save_rgba(out / "clock-minute-hand.png", rgba_from_mask(bgr, individual_hands["minute"]))

    prefix = f"{theme}/{view}"
    return {
        "id": f"{theme}-{view}",
        "source": str(source_path.relative_to(ROOT)),
        "display": {
            "quad": scene["monitorScreen"]["quad"],
            "screen": f"{prefix}/display-screen.png",
            "blank": f"{prefix}/display-blank.png",
            "blend": "source-over",
        },
        "battery": {
            "polygon": scene["batteryIndicator"]["polygon"],
            "indicator": f"{prefix}/battery-indicator.png",
            "blend": "source-over",
        },
        "compute": {
            "roiPolygon": scene["computeLights"]["polygon"],
            "roiPolygons": compute_polygons,
            "detectedLightCount": len(components),
            "centers": [component["center"] for component in components],
            "off": f"{prefix}/compute-off.png",
            "on": f"{prefix}/compute-on.png",
            "frames": [f"{prefix}/compute/frame-{index:02d}.png" for index in range(FRAME_COUNT)],
            "frameDurationMs": FRAME_DURATION_MS,
            "blend": "source-over",
            "seed": seed,
        },
        "fans": fan_entries,
        "clock": {
            "center": scene["clock"]["center"],
            "ellipse": scene["clock"]["ellipse"],
            "face": f"{prefix}/clock-face.png",
            "blankFace": f"{prefix}/clock-face-blank.png",
            "hands": f"{prefix}/clock-hands.png",
            "hourHand": f"{prefix}/clock-hour-hand.png",
            "minuteHand": f"{prefix}/clock-minute-hand.png",
            "handEndpoints": hand_endpoints,
            "blend": "source-over",
        },
    }


def main() -> None:
    data = json.loads(ANNOTATIONS.read_text(encoding="utf-8"))
    base_scenes = {scene["id"].removeprefix("black-"): scene for scene in data["scenes"]}
    exported = []
    for theme in ("black", "white"):
        for view in ("overview", "horizontal"):
            source_path = ROOT / "sources" / f"{theme}-{view}-master.png"
            exported.append(export_scene(base_scenes[view], theme, view, source_path))

    manifest = {
        "version": 1,
        "canvas": data["canvas"],
        "coordinateSpace": data.get("coordinateSpace", "source-image-pixels"),
        "frameDurationMs": FRAME_DURATION_MS,
        "frameCount": FRAME_COUNT,
        "scenes": exported,
    }
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for scene in exported:
        print(f"{scene['id']}: {scene['compute']['detectedLightCount']} compute lights")


if __name__ == "__main__":
    main()
