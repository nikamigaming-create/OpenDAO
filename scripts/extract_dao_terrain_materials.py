"""Extract DAO terrain blend masks and shader metadata from sector RIMs."""

from __future__ import annotations

import json
import re
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image


def read_erf_v20(path: Path) -> dict[str, bytes]:
    data = path.read_bytes()
    if data[:16].decode("utf-16le", "ignore").rstrip("\0") != "ERF V2.0":
        return {}
    count = struct.unpack_from("<I", data, 16)[0]
    result: dict[str, bytes] = {}
    for index in range(count):
        base = 32 + index * 72
        name = data[base : base + 64].decode("utf-16le").split("\0", 1)[0]
        offset, size = struct.unpack_from("<II", data, base + 64)
        result[name.lower()] = data[offset : offset + size]
    return result


def decode_rgba4444(dds: bytes) -> Image.Image:
    if dds[:4] != b"DDS ":
        raise ValueError("not DDS")
    height, width = struct.unpack_from("<II", dds, 12)
    bits, rmask, gmask, bmask, amask = struct.unpack_from("<IIIII", dds, 88)
    if bits != 16 or (rmask, gmask, bmask) != (0x0F00, 0x00F0, 0x000F):
        raise ValueError(f"unsupported terrain mask DDS layout: {bits=} {rmask=:x}")
    pixels = bytearray(width * height * 4)
    source = memoryview(dds)[128:]
    for index in range(width * height):
        value = source[index * 2] | (source[index * 2 + 1] << 8)
        pixels[index * 4 + 0] = ((value >> 8) & 15) * 17
        pixels[index * 4 + 1] = ((value >> 4) & 15) * 17
        pixels[index * 4 + 2] = (value & 15) * 17
        pixels[index * 4 + 3] = ((value >> 12) & 15) * 17 if amask == 0xF000 else 255
    return Image.frombytes("RGBA", (width, height), bytes(pixels))


def values(root: ET.Element, name: str) -> list[float]:
    node = root.find(f".//*[@Name='{name}']")
    if node is None:
        return []
    return [float(value) for value in node.attrib.get("value", "").split()]


def texture(root: ET.Element, name: str) -> str:
    for node in root.findall(".//Texture"):
        if node.attrib.get("Name", "").lower() == name.lower():
            return node.attrib.get("ResName", "").lower()
    return ""


def main() -> int:
    args = sys.argv[1:]
    if len(args) != 2:
        raise SystemExit("expected: <DAO area env directory> <output directory>")
    area_dir, output_dir = map(Path, args)
    output_dir.mkdir(parents=True, exist_ok=True)
    descriptors: dict[str, dict[str, object]] = {}

    for rim_path in area_dir.glob("*.rim"):
        if rim_path.name.lower().endswith(".gpu.rim"):
            continue
        entries = read_erf_v20(rim_path)
        gpu_path = rim_path.with_name(rim_path.stem + ".gpu.rim")
        if not gpu_path.exists():
            continue
        gpu = read_erf_v20(gpu_path)
        for name, payload in entries.items():
            if not name.endswith(".mao") or b"terrain.mat" not in payload:
                continue
            root = ET.fromstring(payload.decode("utf-8"))
            mask_v_name = texture(root, "MaskV")
            mask_a_name = texture(root, "MaskA")
            mask_a2_name = texture(root, "MaskA2")
            if not mask_v_name or not mask_a_name or mask_v_name not in gpu or mask_a_name not in gpu:
                continue
            mask_v = decode_rgba4444(gpu[mask_v_name])
            mask_a = decode_rgba4444(gpu[mask_a_name])
            mask_a2 = decode_rgba4444(gpu[mask_a2_name]) if mask_a2_name in gpu else Image.new("RGBA", mask_a.size)

            # MaskV stores the three active palette indices. MaskA/A2 store
            # fixed palette weights; remove stale channels while preserving
            # the A4R4G4B4 alpha nibble (layer 3/7).
            pv, pa, pa2 = mask_v.load(), mask_a.load(), mask_a2.load()
            for y in range(mask_a.height):
                for x in range(mask_a.width):
                    active = {max(0, min(7, round(channel / 255.0 * 7.5))) for channel in pv[x, y][:3]}
                    a = list(pa[x, y])
                    b = list(pa2[x, y])
                    for channel in range(4):
                        if channel not in active:
                            a[channel] = 0
                        if channel + 4 not in active:
                            b[channel] = 0
                    pa[x, y], pa2[x, y] = tuple(a), tuple(b)

            stem = re.sub(r"[^a-z0-9_.-]+", "_", name.lower())
            mask_a_path = output_dir / f"{stem}_maska.png"
            mask_a2_path = output_dir / f"{stem}_maska2.png"
            mask_a.save(mask_a_path)
            mask_a2.save(mask_a2_path)
            pal_dim = values(root, "mml_vPalette_dimensions")
            pal_param = values(root, "mml_vPalette_parameters")
            uv_scales = values(root, "mml_mUVScaleValues")[:8]
            descriptors[name.lower()] = {
                "palDim": pal_dim,
                "palParam": pal_param,
                "uvScales": uv_scales,
                "maskA": str(mask_a_path).replace("\\", "/"),
                "maskA2": str(mask_a2_path).replace("\\", "/"),
            }

    manifest = output_dir / "terrain-materials.json"
    manifest.write_text(json.dumps(descriptors, indent=2), encoding="utf-8")
    print(f"DAO_TERRAIN_MATERIALS count={len(descriptors)} manifest={manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
