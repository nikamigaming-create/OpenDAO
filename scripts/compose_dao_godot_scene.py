"""Build a Godot-ready Redcliffe GLB from a Haven .havenarea.

Blender is the coordinate-system authority here: Haven's importer composes the
DAO placement with each model's exporter-root correction, then Blender's glTF
exporter converts that coherent Z-up scene to glTF/Godot coordinates once.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def main() -> int:
    args = sys.argv[sys.argv.index("--") + 1 :]
    if len(args) != 3:
        raise SystemExit("expected: <havenarea_importer.py> <area.havenarea> <output.glb>")
    importer_path, area_path, output_path = map(Path, args)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    spec = importlib.util.spec_from_file_location("havenarea_importer", importer_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load Haven importer: {importer_path}")
    haven = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(haven)
    area = json.loads(area_path.read_text(encoding="utf-8"))
    haven.import_havenarea(bpy.context, str(area_path), True, True, True)

    cluster = Vector((260.0, 301.0, 1.2))
    trees = bpy.data.collections.get("Trees")
    tree_objects = set(trees.all_objects) if trees else set()
    for obj in list(bpy.context.scene.objects):
        remove = obj in tree_objects or obj.hide_render or obj.hide_get()
        if obj.type == "MESH":
            center = obj.matrix_world.translation
            remove = remove or Vector((center.x - cluster.x, center.y - cluster.y)).length > 85.0
        if remove:
            bpy.data.objects.remove(obj, do_unlink=True)

    for _ in range(3):
        bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)

    bpy.context.scene.frame_set(12)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        export_format="GLB",
        use_visible=True,
        export_animations=True,
        export_animation_mode="ACTIVE_ACTIONS",
        export_force_sampling=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_apply=False,
    )
    actors = bpy.data.collections.get("Actors")
    active_actors = sum(bool(actor.get("active")) for actor in area.get("actors", []))
    actor_roots = [obj for obj in actors.all_objects if obj.name.startswith("Actor_")] if actors else []
    print(
        "DAO_GODOT_COMPOSE "
        + json.dumps(
            {
                "output": str(output_path),
                "objects": len(bpy.context.scene.objects),
                "actorRoots": len(actor_roots),
                "activeActors": active_actors,
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
