"""Compose a Haven Tools .havenarea export and write one OpenMW-readable OBJ.

Run with Blender, not CPython:
  blender --background --python compose_dao_havenarea.py -- <importer.py> <area> <out.obj>
"""

from __future__ import annotations

import importlib.util
import json
import re
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def main() -> int:
    args = sys.argv[sys.argv.index("--") + 1 :]
    if len(args) != 3:
        raise SystemExit("expected: <havenarea_importer.py> <area.havenarea> <output.obj>")

    importer_path, area_path, output_path = map(Path, args)
    spec = importlib.util.spec_from_file_location("havenarea_importer", importer_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load Haven importer: {importer_path}")
    haven = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(haven)

    area = json.loads(area_path.read_text(encoding="utf-8"))
    haven.import_havenarea(bpy.context, str(area_path), True, True, True)

    # Bake a real DAO idle pose into the static OpenMW interchange scene. The
    # GLBs carry Haven's exported armature/action and OBJ export evaluates the
    # armature modifiers at this frame, avoiding bind/T-pose actors.
    bpy.context.scene.frame_set(12)

    # Haven's current SpeedTree flattening is not yet trustworthy (some branch
    # buffers become long spikes). Keep authored architecture/setpieces and omit
    # only that broken conversion from the playable proof.
    trees_collection = bpy.data.collections.get("Trees")
    tree_objects = set(trees_collection.all_objects) if trees_collection else set()

    # Match render_dao_havenarea_preview.py exactly: export the coherent authored
    # Redcliffe encounter neighborhood that was visually approved, not the full
    # kilometre-scale cell with unfinished terrain/backdrop/SpeedTree layers.
    cluster = Vector((260.0, 301.0, 1.2))
    remove_objects = []
    for obj in list(bpy.context.scene.objects):
        if obj in tree_objects or obj.hide_render or obj.hide_get():
            remove_objects.append(obj)
            continue
        if obj.type == "MESH":
            center = obj.matrix_world.translation
            if Vector((center.x - cluster.x, center.y - cluster.y)).length > 85.0:
                remove_objects.append(obj)
    for obj in remove_objects:
        bpy.data.objects.remove(obj, do_unlink=True)
    for _ in range(3):
        bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)

    mesh_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    visible_meshes = [obj for obj in mesh_objects if not obj.hide_render]
    if not visible_meshes:
        raise RuntimeError("Haven import produced no visible mesh objects")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.suffix.lower() != ".obj":
        raise RuntimeError("Blender 5.2 POC output must use .obj")

    # GLB images are packed in Blender. OBJ/MTL cannot reference packed data, so
    # material maps must be written beside the interchange scene and rebound to
    # real relative paths before export.
    texture_dir = output_path.parent / f"{output_path.stem}-textures"
    texture_dir.mkdir(parents=True, exist_ok=True)
    used_names: set[str] = set()
    saved_images = 0
    for index, image in enumerate(bpy.data.images):
        if image.name in {"Render Result", "Viewer Node"}:
            continue
        stem = re.sub(r"[^A-Za-z0-9_.-]+", "_", image.name).strip("._") or f"image_{index}"
        candidate = f"{stem}.png"
        suffix = 1
        while candidate.lower() in used_names:
            candidate = f"{stem}_{suffix}.png"
            suffix += 1
        used_names.add(candidate.lower())
        image.filepath_raw = str(texture_dir / candidate)
        image.file_format = "PNG"
        try:
            # Accessing pixels forces lazy GLB image payloads to decode.
            _ = image.pixels[0]
            image.save()
            saved_images += 1
        except (RuntimeError, IndexError) as exc:
            print(f"DAO_OPENMW_IMAGE_SKIP name={image.name!r} source={image.source} error={exc}")
    print(f"DAO_OPENMW_IMAGES saved={saved_images} total={len(bpy.data.images)} dir={texture_dir}")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in visible_meshes:
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = visible_meshes[0]
    bpy.ops.wm.obj_export(
        filepath=str(output_path),
        check_existing=False,
        apply_modifiers=True,
        apply_transform=True,
        export_selected_objects=True,
        export_uv=True,
        export_normals=True,
        export_materials=True,
        export_pbr_extensions=False,
        path_mode="RELATIVE",
        export_triangulated_mesh=True,
        export_object_groups=True,
        export_material_groups=True,
    )

    # Blender 5.2's Windows OBJ exporter can serialize packed-image names as
    # synthetic C:/Image_*.png paths even after the images have been saved.
    # Point those MTL references at the real portable texture directory.
    mtl_path = output_path.with_suffix(".mtl")
    if mtl_path.exists():
        mtl_text = mtl_path.read_text(encoding="utf-8")
        mtl_text = re.sub(
            r"C:/([^/\s]+\.png)",
            lambda match: f"{texture_dir.name}/{match.group(1)}",
            mtl_text,
        )
        # OSG's OBJ reader used by OpenMW does not consume the optional -bm
        # argument and otherwise folds it into the texture filename.
        mtl_text = re.sub(r"(?m)^(map_Bump)\s+-bm\s+\S+\s+", r"\1 ", mtl_text)
        mtl_path.write_text(mtl_text, encoding="utf-8", newline="\n")

    summary = {
        "source": str(area_path),
        "output": str(output_path),
        "meshObjects": len(mesh_objects),
        "visibleMeshObjects": len(visible_meshes),
        "terrainKinds": len(area.get("terrain", {}).get("patches", {})),
        "propKinds": len(area.get("props", {})),
        "treeKinds": len(area.get("trees", {})),
        "actors": len(area.get("actors", [])),
        "activeActors": sum(bool(actor.get("active")) for actor in area.get("actors", [])),
    }
    print("DAO_OPENMW_COMPOSE " + json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
