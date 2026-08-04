# OpenDAO Redcliffe POC

OpenDAO is an experimental compatibility runtime for loading a legitimate
Dragon Age: Origins installation into a modern open-source renderer. The
current vertical slice boots into Redcliffe Village with authored terrain,
setpieces, water, sky, lights, portals, and active UTC actors.

No BioWare assets are stored in this repository. Import and generated caches
remain local and are excluded by `.gitignore`.

## What works

- DAO ERF/RIM/GFF/UTC/ARE extraction through a patched Haven Tools CLI.
- Redcliffe terrain and placed environment geometry.
- DAO palette/mask terrain materials and DXT5NM normal-map handling.
- Authored sun, ambient colour, point lights, cloud sky, volumetric fog, and
  water in the Godot reference runtime.
- Twelve active actors assembled from their real UTC/MOR/equipment data with
  default animation loops.
- First-person movement, sprint, jump/swim, collision, doors, and streamed
  Redcliffe interiors.
- Boot movie, lightweight DAO-style menu, Level-1 human warrior start, mobile
  controls, deterministic short-video capture, and Meta XR simulator capture.
- An experimental OpenMW/OpenSceneGraph compatibility path. Native GLB/PBR
  ingestion is under active development; Godot is presently the golden visual
  reference.

## Requirements

- Windows 10/11 and PowerShell 7 (`pwsh`).
- A legally installed Dragon Age: Origins Ultimate Edition.
- Git, CMake, Visual Studio 2022 C++ tools, Python 3.11+, FFmpeg.
- Godot 4.6.3 (standard and console executables).
- Blender 5.2 LTS for offline composition/baking jobs.

The scripts accept explicit paths, so installs do not need to live on `D:`.

## One-command setup

After downloading a GitHub release or cloning the repository, run:

```powershell
pwsh -File scripts/Setup-OpenDAO.ps1 `
  -GameRoot 'C:\Program Files (x86)\Steam\steamapps\common\Dragon Age Ultimate Edition' `
  -CacheRoot 'C:\OpenDAO-cache'
```

This clones and patches the tested Haven Tools revision, builds it, imports
Redcliffe from the user's owned DAO installation, and writes the local Godot
profile. No BioWare content is downloaded or distributed by OpenDAO.

## Bootstrap the patched exporter

```powershell
pwsh -File scripts/Bootstrap-OpenDAO.ps1
```

This clones Haven Tools at the tested revision and applies
`patches/haven-tools-opendao.patch`. To use a different checkout directory:

```powershell
pwsh -File scripts/Bootstrap-OpenDAO.ps1 -HavenRoot C:\src\Haven-Tools
```

## Import owned DAO data

```powershell
pwsh -File scripts/Import-DAO.ps1 `
  -GameRoot 'D:\SteamLibrary\steamapps\common\Dragon Age Ultimate Edition' `
  -CacheRoot 'D:\OpenDAO-cache'
```

Source-only checks, including verification that the exporter patch applies to
the pinned upstream revision, run on GitHub Actions and can be run locally:

```powershell
pwsh -File scripts/Test-OpenDAOSource.ps1 -ValidateHavenPatch
```

The importer configures/builds patched Haven Tools, extracts `lak100d`, and
writes `godot/profiles/local.json`. Reuse an existing exporter build with
`-SkipBuild`.

For the higher-fidelity reference scene, run the Python composition helpers in
`scripts/` after import. They consume only the generated `.havenarea`, GLBs,
and terrain manifests in your local cache.

## Run the POC

```powershell
pwsh -File scripts/Start-OpenDAO.ps1 `
  -Godot C:\Tools\Godot_v4.6.3-stable_win64_console.exe
```

Controls: WASD move, mouse look, Shift sprint, Space jump/swim, Esc releases
the mouse. Door portals stream the corresponding Redcliffe interior and return
to the exterior.

Mobile profile:

```powershell
pwsh -File scripts/Start-OpenDAO-Mobile.ps1
```

## Deterministic CLI video captures

```powershell
pwsh -File scripts/Capture-OpenDAO-Short.ps1 -Short town
pwsh -File scripts/Capture-OpenDAO-Short.ps1 -Short water
pwsh -File scripts/Capture-OpenDAO-Short.ps1 -Short door
```

Each command uses Godot fixed-FPS movie output and FFmpeg to create a
shareable 720p MP4 under `artifacts/shorts/`. It does not require UI clicks.

Meta XR simulator capture:

```powershell
pwsh -File scripts/Capture-OpenDAO-XRSimulatorShort.ps1
```

## OpenMW compatibility lab

The OpenMW path requires a world-viewer-enabled OpenMW build. See
`docs/dao-openmw-poc.md` and invoke:

```powershell
pwsh -File scripts/Invoke-DAOOpenMWPoc.ps1 `
  -OpenMWBinary C:\OpenMW-lab\openmw.exe `
  -OpenMWConfig C:\OpenMW-lab\config `
  -OpenMWResources C:\OpenMW-lab\resources
```

OpenMW work is experimental; do not treat a launch alone as visual proof.
Inspect its retained logs, decoded MP4, and contact sheet.

## Repository map

- `godot/` — runtime, shaders, UI, controls, and scene adapters.
- `scripts/` — importer, composition, launch, capture, and preview tools.
- `patches/` — reproducible Haven Tools changes.
- `docs/compatibility-layer.md` — architecture and compatibility boundary.
- `docs/dao-openmw-poc.md` — OpenMW/OpenSceneGraph lab notes.

## Known limitations

- Quest/combat/NCS coverage is not complete.
- OpenMW parity still needs native glTF/PBR, DAO terrain shader equivalence,
  actor animation integration, and authored atmosphere parity.
- Generated caches are large and machine-local by design.
