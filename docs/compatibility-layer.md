# DA Open compatibility layer

The target user flow is: select a legitimate Dragon Age: Origins install, run the importer, and play through DA Open. Original game assets remain in the user's installation or a generated local cache.

## Layers

1. **VFS and formats** — xoreos/xoreos-tools plus the modified Haven Tools reader index ERF/RIM/GFF/UTC/ARE resources and create a reproducible local rendering cache.
2. **Script compatibility** — xoreos's Dragon Age `ScriptContainer`, NCS VM, event model, object model, and implemented engine-function tables are the starting point. DA Open adds Godot-facing adapters for spawn, transforms, animation actions, movement, variables, events, and save state. Unsupported quest/combat functions report telemetry and safely no-op during the vertical slice.
3. **Runtime** — Godot streams individual glTF resources from the generated profile, maps DAO Z-up transforms into Godot Y-up space, renders the area, provides collision/navigation, and hosts UI/input/audio.
4. **Game profile** — the importer writes a local profile pointing at the owned DAO installation and cache. No proprietary assets are committed to the open-source runtime.

The first vertical slice supports boot movie, menu, New Game/Continue, a deterministic Level-1 human warrior save, Redcliffe area streaming, active UTC actors, and their exported default animation loops.
