# Graphical Circuits

A native macOS wiring illustration editor for Kavrous blog posts. Requires macOS 14+ and Xcode command-line tools to build; no third-party dependencies.

## Run

```sh
scripts/build-app.sh
open 'dist/Graphical Circuits.app'
```

The generated app can be copied to Applications. It is locally ad-hoc signed, not notarized for distribution. For development use `swift run`; run tests with `swift test`.

## Use

- Import a modern `.kicad_pcb` file. The board becomes a movable illustration built from Edge.Cuts, front silkscreen graphics, real pad/drill sizes, and simplified physical packages derived from F.Fab geometry. Through-hole pads and displayed JST mating-contact dots accept wires.
- Add breadboards with red + / blue − power rails, banded axial resistors, domed LEDs, ceramic capacitors, and headers. Drag components into place, including onto breadboards. Resistors, LEDs, capacitors, and headers snap their top-left position to the 17-point canvas grid when added or dragged. Existing saved positions are preserved until moved; breadboards move freely. Imported boards snap nearby through-hole pads onto breadboard holes when dragged (within 7 points), preferring the alignment that matches the most pins. The component artwork stays vector-sharp in SVG exports. New breadboards include 120 connectable rail holes in addition to the 300 terminal holes.
- Enable Wire mode, choose a color, and click a start and end pin. Wires follow components as they move. Escape cancels a pending connection.
- Turn Wire mode off, then click and drag a wire to move its routing bend in both X and Y. Endpoints stay attached; the white handle marks the selected bend. Press Delete to remove a selected wire.
- Select a component and press Cmd+E (or click Edit) to change its label/value. LED colors: red, green, blue, yellow, amber, white, and purple. Resistor values such as `220 Ω`, `4.7 kΩ`, or `1 MΩ` update the color bands when representable as a four-band code (gold tolerance); other labels display without bands. Capacitors are non-polarized ceramic parts, initially `100 nF`, with editable capacitance labels.
- Press Delete to remove a selected component and its wires. Cmd+Z undoes; Cmd+Y redoes. Component edits participate in undo/redo and are retained in saved projects and SVG exports.
- Cmd+S saves editable JSON projects; after the first save it updates the same file. Cmd+O opens a saved project. Export SVG for publication at 1400 × 900. Save explicitly before closing. Old project files remain readable; add a new breadboard to get the new power rails.

## KiCad import policy

The importer follows KiCad's [S-expression board format](https://dev-docs.kicad.org/en/file-formats/sexpr-pcb/). Closed Edge.Cuts lines, arcs, rectangles, circles, and polygons define the substrate and internal cutouts. Arcs/circles use fine vector sampling shared by the canvas and SVG exporter. When no closed outline is available, pad bounds provide a fallback.

Front silkscreen polygons (including KiBuzzard labels), lines, circles, rectangles, arcs, and visible text are preserved. Hidden text, courtyards, fabrication labels, tracks, and copper zones are omitted. Component bodies use F.Fab geometry when present. Package recognition adds LED lenses, tactile-switch actuators, JST cavities/contacts, and USB metal shells. Names, values, silkscreen extents, and common package dimensions handle custom footprints lacking body outlines; diode glyphs are not treated as LED bodies. Generic fallback bounds include pad dimensions and rotation; leaded ICs with only silkscreen corners use those corners to keep their leads exposed. Footprints containing Edge.Cuts geometry are treated as board/module outlines: their package body is suppressed while outline geometry, silkscreen, pads, and header wire targets remain intact. Reimport previously saved boards to apply this rule. Back-side package bodies are omitted in this top view. Package details and colors are illustrative; they are not reconstructed 3D models. The legacy JST PH housing uses the [manufacturer drawing](https://www.jst.com/wp-content/uploads/2021/08/ePH-new.pdf). External STEP/VRML models are not loaded. USB shield mounting tabs are visual only and excluded from jumper targets. SVG and AppKit share the same imported vector geometry; ordinary text uses a system font substitute rather than KiCad's stroke font, with preserved justification, rotation, mirroring, width/height, and bold/italic styling. Text is converted to shared vector paths, so the canvas and exported SVG use identical glyph geometry. Filled `yes`/`solid` silk polygons are retained, including KiBuzzard labels.

Pad sizes and drill holes are preserved, including transparent mounting holes. Plated `thru_hole` pads become wire targets; mounting-hole footprints are excluded even when plated. JST connectors additionally expose their numbered mating contacts as copper-colored socket dots: side-entry connectors place them just outside the opening, and top-entry connectors place them in the socket well. Pad order and footprint rotation are preserved, mounting tabs are excluded, and close dots use nearest-pin picking. Socket targets do not participate in breadboard mounting alignment. SMD pads (including QFN/TQFP and exposed center pads) are visual geometry only. DNP bodies are omitted and their pads remain visible without wire targets. Castellations, SMD test points, and edge contacts are not yet automatically classified. Less common custom pad shapes, oval slots, legacy arc encodings, and back-side mirroring are not fully reproduced.

Imported boards use a shared physical scale of 17 canvas points per 2.54 mm (about 6.693 points/mm), matching the breadboard’s 17-point pitch in both axes. Saved projects from earlier versions are upgraded on open: board geometry and breadboard hole positions are corrected while part IDs and wire pin indices are preserved. Existing placements may need to be dragged into alignment afterward. This is an illustration tool, not a circuit simulator or electrical-rule checker. Breadboard placement is visual; connectivity within its strips is not inferred. Older saved imports retain their original rendering; reimport the PCB to use the improved geometry.

The additional `RPGA-Feather.kicad_pcb` fixture checks the actual custom LEDs, buttons, JST and USB connectors, preserved QFN leads, rotations, and saved vector geometry. Previews are in `docs/previews/feather.png` and `feather.svg`. Reimport existing board objects to regenerate package artwork.

The regression fixture in `Tests/GraphicalCircuitsTests/Fixtures/BMA530.kicad_pcb` contains geometry extracted from the local BMA530 Stemma board, with unrelated project metadata removed. Tests check its 33.85 × 23.02 mm outline, four mounting holes, seven header holes/targets, package silhouettes, and silkscreen artwork.

## Current scope

This first version supports movable parts, orthogonal pin-to-pin wires, five wire colors, undo/redo, labels, project files, and SVG export. It does not yet support zoom, rotation of placed objects, automatic breadboard alignment, or automatic save recovery. Keep content within the fixed 1400 × 900 canvas for export.
