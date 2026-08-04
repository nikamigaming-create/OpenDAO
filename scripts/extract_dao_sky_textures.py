"""Extract the authored DAO sky textures used by Redcliffe's sb_day rig."""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

from extract_dao_terrain_materials import read_erf_v20


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("expected: <DAO game root> <output directory>")
    game_root = Path(sys.argv[1])
    output = Path(sys.argv[2])
    output.mkdir(parents=True, exist_ok=True)
    textures = read_erf_v20(game_root / "packages/core/data/textures.erf")
    for name in ("sb03_bcloud.dds", "defaultsun.dds"):
        payload = textures.get(name)
        if payload is None:
            raise FileNotFoundError(name)
        dds_path = output / name
        dds_path.write_bytes(payload)
        with Image.open(dds_path) as image:
            image.convert("RGBA").save(output / f"{Path(name).stem}.png")
        print(f"DAO_SKY_TEXTURE name={name} bytes={len(payload)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
