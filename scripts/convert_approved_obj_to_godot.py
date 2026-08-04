"""Convert the visually approved, transform-baked DAO OBJ into Godot GLB."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy


def main() -> int:
    args = sys.argv[sys.argv.index("--") + 1 :]
    if len(args) != 2:
        raise SystemExit("expected: <approved.obj> <output.glb>")
    source, output = map(Path, args)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.obj_import(
        filepath=str(source),
        forward_axis="NEGATIVE_Z",
        up_axis="Y",
        use_split_objects=True,
        use_split_groups=True,
        validate_meshes=True,
    )
    # OBJ's declared Y-up conversion arrives as a +90-degree object root. Bake
    # it into vertex data so Godot receives identity roots and cannot apply the
    # interchange-axis correction a second time.
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        use_visible=True,
        export_animations=False,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_apply=True,
    )
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    print("DAO_APPROVED_GLTF " + json.dumps({"output": str(output), "meshes": len(meshes)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
