# CondensedContext

## Context Freshness
Last Verified Commit: aa72bd81618e4d89f53c1daf79824713e60eefc6
Current HEAD: aa72bd81618e4d89f53c1daf79824713e60eefc6
Status: partial; implementation uncommitted, verified 2026-10-25.

## Current Focus
Native macOS wiring illustration editor for Kavrous blog posts.

## Stable Facts and Decisions
Swift 6 / AppKit / Swift Package Manager; macOS 14+, no external dependencies.
KiCad S-expression import uses Edge.Cuts closed contours, real pads/drills, front silkscreen geometry (including KiBuzzard polygons) and package silhouettes from F.Fab plus family-specific illustrative LED, button, JST, and USB details. Missing outlines use package dimensions, silk extents, or rotated pad bounds; IC silk corners keep leads exposed. BoardDrawing optional field preserves old JSON compatibility.
User requires uncluttered package representations and only physically appropriate wiring targets.
Plated thru_hole pads plus explicit JST mating-contact socket dots are clickable; raw SMD pads remain visual only. Socket dots preserve pin numbers and rotation, append after physical header pins, and are excluded from breadboard snapping. DNP bodies are omitted (pads remain visual); NPTH holes render as cutouts. Mounting-hole footprints are excluded as wire targets even when plated. No inferred castellation/test-point classification yet.
Shared physical pitch: CircuitScale.pointsPerMillimeter = 17 / 2.54; use for all imported geometry. JSON editable projects; fixed 1400 × 900 SVG output. Visual breadboard placement, no electrical checking.

## File Map
- Package.swift: executable and tests.
- Sources/GraphicalCircuits/Model.swift: document, endpoints, SVG, S-expression parser.
- Sources/GraphicalCircuits/SilkscreenText.swift: CoreText glyph paths with source justification, rotation, mirror, font size/aspect/style; system-font substitute for KiCad stroke font, shared canvas/SVG paths.
- Sources/GraphicalCircuits/PackageRendering.swift: footprint-local package family recognition, physical envelopes, LED lenses, switch caps, JST contacts/cavities, USB shells.
- Sources/GraphicalCircuits/BoardGeometry.swift: KiCad geometry import, contour joining, finely sampled arcs, front silkscreen and F.Fab bodies, pads/drill cutouts.
- docs/previews/bma530.png and .svg, feather.png and .svg: generated AppKit/SVG previews using actual board geometry.
- Tests/GraphicalCircuitsTests/Fixtures/BMA530.kicad_pcb and RPGA-Feather.kicad_pcb: extracted local board geometry, no unrelated project metadata.
- Sources/GraphicalCircuits/main.swift: AppKit canvas/editor, file panels, controls.
- Tests/GraphicalCircuitsTests/ModelTests.swift: parser, rotation, connection eligibility, persistence/SVG tests.
- scripts/build-app.sh: release build and locally signed app bundle.
- README.md: run instructions, supported workflow and limitations.

## Validation Memory
`swift test`: 18 tests passed; JST-PH front direction, numbered socket dots, nearest-pin picking, wire persistence, silk left/bottom anchors at 0/90 degrees, filled yes polygons, text aspect and escape decoding; actual Feather checks four LED lenses, two button actuators, two JST housings, USB shell, four SH contacts, correct 0603 size/rotation, value-derived green lens, USB shield target exclusion, QFN leads and persistence; board/module footprints with Edge.Cuts retain outline, silk and headers while suppressing both F.Fab and pad-bounds package bodies; shared pitch and all-seven-header alignment, saved-project normalization without repeated scaling/wire loss; real BMA530 fixture verifies 33.85 × 23.02 mm outline, four mounting + seven header drills, seven wire targets, ten bodies, polygon silk, persisted geometry; separate cutout/rotated artwork test. `scripts/build-app.sh`: release build and ad-hoc signing passed.
Sandbox denied compiler cache writes; Swift commands needed escalation.
Live GUI interaction has not been validated. AppKit board rendering was rendered offscreen and visually inspected in docs/previews/bma530.png and feather.png; header pad occlusion and hidden QFN leads were corrected.

## Handoff
Built app: dist/Graphical Circuits.app (ignored generated output).
Next: validate live native UI and additional KiCad boards. Old geometry-based board imports scale automatically on opening; older pad-envelope imports still need reimport for detailed board graphics.
Save is explicit; no unsaved-change recovery. Cmd+S updates current projectURL; Cmd+O opens; Cmd+Z/Y undo/redo via native menus. Cmd+E edits selected component labels/values and LED preset colors. No zoom or object rotation.

## Changes
2026-10-25: Corrected PH side-entry opening opposite solder tails; JST socket wire targets (side-entry outside mouth, top-entry within well), nearest-pin picking and socket persistence. Fixed ignored text justification and filled-yes silk polygons; shared glyph paths now preserve source anchors/angles/aspect/mirror/style and variable references, with system-font approximation. Standard string escapes decoded. Reimport old board artwork. Updated Feather/BMA previews visually inspected. Uncommitted.
2026-10-25: Inspected local RPGA Feather file. Added family-aware LED/switch/JST/USB vector packages, distinguishing diode symbols from body outlines; no-Fab 0603 LEDs use actual body size and value-derived color, SOF-232 switches use silk envelope + metal plate/round actuator, custom JST PH uses manufacturer-sized housing, SH retains F.Fab contact loops, USB gets shell/front opening with shield tabs excluded from wire targets. Added sanitized Feather fixture, rendering regression and previews. Reimport board to refresh artwork. Uncommitted.
2026-10-25: Footprints with Edge.Cuts geometry (case-insensitive layer check) skip physical-package silhouette generation, retaining their board outline, artwork, pad graphics and wire targets. Regression covers F.Fab and fallback cases alongside a normal component. Reimport old board imports to apply suppression. Uncommitted.
2026-10-25: Corrected shared physical scale to 17 points / 2.54 mm (CircuitScale), breadboard row pitch 15→17 and matching center channel. Board placement snaps near breadboard holes (7-point radius), favoring most aligned pins. Decoder upgrades old board geometry from 6 points/mm and normalizes breadboard pin positions without changing IDs/indices or double-scaling. Preview docs/previews/breadboard-spacing.png visually checked. Uncommitted.
2026-10-25: Rebuilt board rendering using local BMA530 PCB. Shared canvas/SVG BoardDrawing; Edge.Cuts outline/cutouts, sized pad rings/drill holes, rotated F.Fab package silhouettes, front silk polygons and visible text. Hidden fabrication labels omitted; filename no longer drawn over board. Mounting holes visual only; SMD pads never wire targets. Added fixture tests and previews. Uncommitted.
2026-10-25: Resistors, LEDs, capacitors, headers snap top-left positions to shared CanvasGrid.spacing (17 points) on creation and drag. Existing saved coordinates preserved until dragged. Boards/breadboards and wire bends retain free movement. Existing 10 tests pass. Uncommitted.
2026-10-25: Component editor (toolbar and Cmd+E), seven LED lens colors via optional persisted LEDColor (legacy defaults red), editable resistor values with value-derived four-band codes, non-polarized ceramic capacitor with editable value and two wire endpoints. Shared canvas/SVG artwork; undoable edits. Uncommitted.
2026-10-25: Added draggable X/Y wire bend (Wire mode off), selected wire deletion, native Cmd+Z/Y/S/O menus, same-file saving, shared vector resistor/LED artwork and connectable +/- breadboard rails. Wire bend is optional for legacy JSON compatibility; old breadboards retain original pins to preserve wire endpoints. Uncommitted.
2026-10-25: Initial native app, import, breadboard/parts, attached wires, undo/redo, labels, JSON save/open, SVG export. Uncommitted.

## Open Threads
Custom pad geometry, exact oval slots, legacy arc encodings, back-side mirroring, external 3D models, optional connector exceptions, improved editing ergonomics, live UI validation. Board colors and system-font glyph shapes remain illustrative (source text alignment/geometry styles preserved); curves are finely sampled vectors.
