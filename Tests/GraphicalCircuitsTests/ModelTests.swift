import XCTest
import AppKit
@testable import GraphicalCircuits
final class ModelTests: XCTestCase {
    func testRotatedPadsAndPackages() throws {
        let board = try importBoard("""
        (kicad_pcb (footprint "R" (at 10 20 90)
          (property "Reference" "R1")
          (pad "1" thru_hole circle (at 0 0))
          (pad "2" thru_hole circle (at 2.54 0))))
        """, name: "Test")
        XCTAssertEqual(board.pins.count,2)
        XCTAssertEqual(board.boardDrawing?.packageCount,1)
        XCTAssertEqual(board.pins[0].point.x,board.pins[1].point.x,accuracy:0.001)
        XCTAssertEqual(board.pins[0].point.y-board.pins[1].point.y,17,accuracy:0.001)
        XCTAssertEqual(board.pins[0].name,"R1.1")
    }
    func testSurfaceMountPackagesAreNotWireTargets() throws {
        let board = try importBoard("""
        (kicad_pcb
          (footprint "QFN" (at 10 10) (pad "1" smd rect (at 0 0)) (pad "2" smd rect (at 1 0)))
          (footprint "Header" (at 20 10) (pad "1" thru_hole circle (at 0 0)))
          (footprint "Mount" (at 30 10) (pad "" np_thru_hole circle (at 0 0)))
          (footprint "Unpopulated" (attr dnp) (pad "1" thru_hole circle (at 0 0))))
        """, name: "Mixed")
        XCTAssertEqual(board.pins.count, 1)
        XCTAssertEqual(board.boardDrawing?.packageCount, 2)
    }
    func testMalformedInput() {
        XCTAssertThrowsError(try importBoard("(kicad_pcb",name:"Broken"))
        XCTAssertThrowsError(try importBoard("(kicad_pcb)",name:"Empty"))
        XCTAssertThrowsError(try SExpr.parse("(a) junk"))
    }
    func testWireTracksPartAndRoundTrip() throws {
        var d = Diagram(); d.add("LED"); d.add("Resistor")
        let a = Endpoint(part:d.parts[0].id,pin:0), b = Endpoint(part:d.parts[1].id,pin:1)
        d.wires.append(Wire(from:a,to:b,color:"#dc654c"))
        let old = d.point(a)!
        d.parts[0].position.x += 50
        XCTAssertEqual(d.point(a)!.x,old.x+50)
        let copy = try JSONDecoder().decode(Diagram.self,from:JSONEncoder().encode(d))
        XCTAssertEqual(copy.point(a),d.point(a))
        d.parts[0].label = "A&B <LED>"
        XCTAssertTrue(d.svg().contains("A&amp;B &lt;LED&gt;"))
        XCTAssertTrue(d.svg().contains("<path"))
    }
    func testWireBendPersistenceAndLegacyDecode() throws {
        var d = Diagram(); d.add("LED"); d.add("Resistor")
        let legacy = "{\"from\":{\"part\":\"\(d.parts[0].id)\",\"pin\":0},\"to\":{\"part\":\"\(d.parts[1].id)\",\"pin\":1},\"color\":\"#dc654c\"}"
        var wire = try JSONDecoder().decode(Wire.self,from:Data(legacy.utf8))
        XCTAssertNil(wire.bend)
        wire.bend = Point(x:420,y:330); d.wires = [wire]
        let route = d.route(wire)
        XCTAssertEqual(route[2],Point(x:420,y:330))
        for (a,b) in zip(route,route.dropFirst()) { XCTAssertTrue(a.x == b.x || a.y == b.y) }
        d.parts[0].position.y += 40
        XCTAssertEqual(d.route(wire).first,d.point(wire.from))
        let saved = try JSONDecoder().decode(Diagram.self,from:JSONEncoder().encode(d))
        XCTAssertEqual(saved.wires[0].bend,wire.bend)
        XCTAssertTrue(saved.svg().contains("L 420.0 330.0"))
    }
    func testBreadboardPowerRails() {
        var d = Diagram(); d.add("Breadboard")
        let p = d.parts[0]
        XCTAssertEqual(p.pins.count,420)
        XCTAssertEqual(p.pins[300].name,"Top + 1")
        XCTAssertEqual(p.pins[330].name,"Top − 1")
        XCTAssertEqual(p.pins[360].name,"Bottom + 1")
        XCTAssertTrue(p.pins.allSatisfy { $0.point.x < p.width && $0.point.y < p.height })
        XCTAssertTrue(d.svg().contains("#d6534b"))
        XCTAssertTrue(d.svg().contains("#4785b5"))
    }
    @MainActor func testWireHitAndUndoRedo() {
        let canvas = Canvas(frame:NSRect(x:0,y:0,width:1400,height:900))
        canvas.diagram.add("LED"); canvas.diagram.add("Resistor")
        canvas.diagram.wires = [Wire(from:Endpoint(part:canvas.diagram.parts[0].id,pin:0),to:Endpoint(part:canvas.diagram.parts[1].id,pin:1),color:"#dc654c",bend:Point(x:400,y:300))]
        XCTAssertEqual(canvas.hitWire(NSPoint(x:400,y:300)),0)
        XCTAssertNil(canvas.hitWire(NSPoint(x:800,y:800)))
        canvas.checkpoint(); canvas.diagram.wires[0].bend = Point(x:500,y:350)
        canvas.undoEdit(); XCTAssertEqual(canvas.diagram.wires[0].bend,Point(x:400,y:300))
        canvas.redoEdit(); XCTAssertEqual(canvas.diagram.wires[0].bend,Point(x:500,y:350))
    }

    func testLEDColorPersistenceAndLegacyDefault() throws {
        var d = Diagram(); d.add("LED")
        let legacyData = try JSONEncoder().encode(d)
        XCTAssertNil(try JSONDecoder().decode(Diagram.self,from:legacyData).parts[0].ledColor)
        XCTAssertTrue(d.svg().contains(LEDColor.red.hex))
        for color in LEDColor.allCases {
            d.parts[0].ledColor = color
            let copy = try JSONDecoder().decode(Diagram.self,from:JSONEncoder().encode(d))
            XCTAssertEqual(copy.parts[0].ledColor,color)
            XCTAssertTrue(copy.svg().contains(color.hex))
            XCTAssertTrue(copy.svg().contains(color.shade(0.6)))
        }
    }
    func testResistorBandsFollowValue() {
        var d = Diagram(); d.add("Resistor")
        XCTAssertEqual(d.parts[0].resistorBandColors, ["#bb3433","#bb3433","#6b4430","#bf963d"])
        d.parts[0].label = "4.7 kΩ"
        XCTAssertEqual(d.parts[0].resistorBandColors, ["#e8cf42","#8f56b0","#bb3433","#bf963d"])
        XCTAssertTrue(d.svg().contains("4.7 kΩ"))
        XCTAssertTrue(d.svg().contains("#8f56b0"))
        for text in ["custom", "NaN", "inf", "-5 Ω", "4.99 kΩ"] {
            d.parts[0].label = text
            XCTAssertNil(d.parts[0].resistorBandColors)
        }
    }
    @MainActor func testComponentEditsUndoAndCapacitorConnections() throws {
        let canvas = Canvas(frame:NSRect(x:0,y:0,width:1400,height:900))
        canvas.diagram.add("LED"); canvas.diagram.add("Capacitor")
        canvas.selected = canvas.diagram.parts[0].id
        canvas.editSelectedPart(label:"Status",ledColor:.green)
        XCTAssertEqual(canvas.diagram.parts[0].ledColor,.green)
        canvas.undoEdit(); XCTAssertNil(canvas.diagram.parts[0].ledColor)
        canvas.redoEdit(); XCTAssertEqual(canvas.diagram.parts[0].ledColor,.green)
        canvas.selected = canvas.diagram.parts[1].id
        canvas.editSelectedPart(label:"  10 µF  ",ledColor:nil)
        XCTAssertEqual(canvas.diagram.parts[1].label,"10 µF")
        let count = canvas.history.count
        canvas.editSelectedPart(label:"  ",ledColor:nil)
        XCTAssertEqual(canvas.history.count,count)
        XCTAssertEqual(canvas.diagram.parts[1].pins.count,2)
        let from = Endpoint(part:canvas.diagram.parts[0].id,pin:0)
        let to = Endpoint(part:canvas.diagram.parts[1].id,pin:1)
        canvas.diagram.wires.append(Wire(from:from,to:to,color:"#303938"))
        let d = try JSONDecoder().decode(Diagram.self,from:JSONEncoder().encode(canvas.diagram))
        XCTAssertEqual(d.parts[1].label,"10 µF")
        XCTAssertEqual(d.point(to),canvas.diagram.point(to))
        XCTAssertTrue(d.svg().contains("10 µF"))
        XCTAssertTrue(d.svg().contains("#c78a4c"))
        canvas.undoEdit(); XCTAssertEqual(canvas.diagram.parts[1].label,"100 nF")
    }

    @MainActor func testActualBMA530BoardGeometryAndPreview() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"BMA530",withExtension:"kicad_pcb",subdirectory:"Fixtures"))
        let board = try importBoard(String(contentsOf:url,encoding:.utf8),name:"BMA530 Breakout")
        let drawing = try XCTUnwrap(board.boardDrawing)
        XCTAssertEqual(board.width,33.85*CircuitScale.pointsPerMillimeter,accuracy:0.001)
        XCTAssertEqual(board.height,23.02*CircuitScale.pointsPerMillimeter,accuracy:0.001)
        XCTAssertEqual(board.pins.filter { $0.connection != .socket }.count,7)
        XCTAssertTrue(board.pins.allSatisfy { $0.name.hasPrefix("J") })
        XCTAssertEqual(drawing.substrate.contours.count,12) // outline + four mounting and seven header drills
        XCTAssertEqual(drawing.packageCount,10)
        XCTAssertTrue(drawing.graphics.contains { $0.fill == "#303936" && $0.contours.count == 8 }) // header housing retains seven drill cutouts
        XCTAssertGreaterThan(drawing.graphics.filter { $0.fill == "#f0eee2" }.count,15) // KiBuzzard glyphs
        XCTAssertTrue(drawing.substrate.contours[0].count > 100) // rounded Edge.Cuts corners
        var d = Diagram(); d.parts = [board]
        let svg = d.svg()
        XCTAssertTrue(svg.contains("fill-rule=\"evenodd\""))
        XCTAssertFalse(svg.contains("G***"))
        let saved = try JSONDecoder().decode(Diagram.self,from:JSONEncoder().encode(d))
        XCTAssertEqual(saved.parts[0].boardDrawing?.substrate.contours.count,12)
        try svg.write(toFile:"/private/tmp/graphical-circuits-bma530.svg",atomically:true,encoding:.utf8)
        // Render the same AppKit paths used by the editor, enlarged for visual inspection.
        let canvas = Canvas(frame:NSRect(x:0,y:0,width:260,height:210))
        var previewBoard = board; previewBoard.position = Point(x:25,y:25)
        canvas.diagram.parts = [previewBoard]
        let image = NSImage(size:NSSize(width:1040,height:840),flipped:true) { _ in
            let t = NSAffineTransform(); t.scale(by:4); t.concat()
            canvas.draw(canvas.bounds)
            return true
        }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data:try XCTUnwrap(image.tiffRepresentation)))
        try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:"/private/tmp/graphical-circuits-bma530.png"))
    }

    func testEdgeCutsCutoutAndMechanicalHoleWithoutElectricalTargets() throws {
        let board = try importBoard("""
        (kicad_pcb
          (gr_rect (start 0 0) (end 20 10) (layer "Edge.Cuts"))
          (gr_circle (center 10 5) (end 11 5) (layer "Edge.Cuts"))
          (footprint "MountingHole:MountingHole_2mm" (at 2 2)
            (pad "" np_thru_hole circle (at 0 0) (size 2 2) (drill 2)))
          (footprint "Art" (at 4 4 90)
            (fp_poly (pts (xy 0 0) (xy 1 0) (xy 1 1)) (fill solid) (layer "F.SilkS"))
            (property "Reference" "HIDDEN" (at 0 0) (layer "F.SilkS") (hide yes))))
        """,name:"Mechanical")
        XCTAssertEqual(board.width,20*CircuitScale.pointsPerMillimeter)
        XCTAssertEqual(board.height,10*CircuitScale.pointsPerMillimeter)
        XCTAssertTrue(board.pins.isEmpty)
        XCTAssertEqual(board.boardDrawing?.substrate.contours.count,3)
        XCTAssertEqual(board.boardDrawing?.packageCount,0)
        XCTAssertFalse(Diagram(parts:[board]).svg().contains("HIDDEN"))
        let art = try XCTUnwrap(board.boardDrawing?.graphics.first?.contours.first)
        XCTAssertEqual(art[1].x,4*CircuitScale.pointsPerMillimeter,accuracy:0.001)
        XCTAssertEqual(art[1].y,3*CircuitScale.pointsPerMillimeter,accuracy:0.001)
    }

    @MainActor func testBMA530HeaderMatchesBreadboardAndSnapsAsARow() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"BMA530",withExtension:"kicad_pcb",subdirectory:"Fixtures"))
        let board = try importBoard(String(contentsOf:url,encoding:.utf8),name:"BMA530")
        var d = Diagram(); d.add("Breadboard"); d.parts[0].position = Point(x:300,y:300); d.parts.append(board)
        let breadboard = d.parts[0]
        XCTAssertEqual(breadboard.pins[1].point.x-breadboard.pins[0].point.x,17)
        XCTAssertEqual(breadboard.pins[30].point.y-breadboard.pins[0].point.y,17)
        XCTAssertEqual(abs(board.pins[1].point.x-board.pins[0].point.x),17,accuracy:0.001)
        let target = breadboard.pins[15].point
        let aligned = Point(x:300+target.x-board.pins[0].point.x,y:300+target.y-board.pins[0].point.y)
        let snapped = d.placement(of:1,at:Point(x:aligned.x+2,y:aligned.y-3))
        XCTAssertEqual(snapped.x,aligned.x,accuracy:0.001)
        XCTAssertEqual(snapped.y,aligned.y,accuracy:0.001)
        d.parts[1].position = snapped
        for pin in board.pins where pin.connection != .socket {
            XCTAssertTrue(breadboard.pins.contains { hypot(300+$0.point.x-snapped.x-pin.point.x,300+$0.point.y-snapped.y-pin.point.y) < 0.001 })
        }
        let canvas = Canvas(frame:NSRect(x:0,y:0,width:900,height:650)); canvas.diagram = d
        let image = NSImage(size:NSSize(width:900,height:650),flipped:true) { _ in canvas.draw(canvas.bounds); return true }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data:try XCTUnwrap(image.tiffRepresentation)))
        try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:"/private/tmp/graphical-circuits-spacing.png"))
    }
    func testOldProjectSpacingUpgradeKeepsWireEndpointsAndDoesNotRepeat() throws {
        var d = Diagram(); d.add("Breadboard")
        d.parts[0].pins[30].point.y = 80 // previous 15-point row pitch
        var board = Part(kind:"Board",label:"Legacy",position:Point(x:80,y:90),width:60,height:30,pins:[Pin(name:"J1.1",point:Point(x:15.24,y:12))])
        board.boardDrawing = BoardDrawing(substrate:BoardGraphic(contours:[[Point(x:0,y:0),Point(x:60,y:0),Point(x:60,y:30)]],fill:"#236b55"),graphics:[],texts:[],packageCount:0)
        d.parts.append(board)
        let endpoint = Endpoint(part:board.id,pin:0)
        d.wires = [Wire(from:endpoint,to:Endpoint(part:d.parts[0].id,pin:30),color:"#dc654c")]
        let loaded = try JSONDecoder().decode(Diagram.self,from:JSONEncoder().encode(d))
        XCTAssertEqual(loaded.parts[1].pins[0].point.x,17,accuracy:0.001)
        XCTAssertEqual(loaded.parts[1].width,10*CircuitScale.pointsPerMillimeter,accuracy:0.001)
        XCTAssertEqual(loaded.parts[1].boardDrawing?.substrate.contours[0][1].x,loaded.parts[1].width)
        XCTAssertEqual(loaded.parts[0].pins[30].point.y,82)
        XCTAssertEqual(loaded.wires[0].from.part,board.id)
        XCTAssertEqual(loaded.point(endpoint)!.x,97,accuracy:0.001)
        let twice = try JSONDecoder().decode(Diagram.self,from:JSONEncoder().encode(loaded))
        XCTAssertEqual(twice.parts[1].width,loaded.parts[1].width)
        XCTAssertEqual(twice.point(endpoint),loaded.point(endpoint))
    }

    func testBoardOutlineFootprintKeepsHeadersAndSilkWithoutPackageBox() throws {
        for fabrication in ["", "(fp_rect (start 0 0) (end 30 15) (layer \"F.Fab\"))"] {
            let board = try importBoard("""
            (kicad_pcb
              (footprint "Module:BoardWithHeaders" (at 40 50)
                (property "Reference" "MOD1")
                (fp_rect (start 0 0) (end 30 15) (layer "Edge.Cuts"))
                \(fabrication)
                (fp_poly (pts (xy 1 1) (xy 2 1) (xy 2 2)) (fill solid) (layer "F.SilkS"))
                (pad "1" thru_hole circle (at 2 2) (size 1.8 1.8) (drill 1) (layers "*.Cu" "*.Mask"))
                (pad "2" thru_hole circle (at 4.54 2) (size 1.8 1.8) (drill 1) (layers "*.Cu" "*.Mask")))
              (footprint "Resistor_SMD:R_0603" (at 50 55)
                (fp_rect (start -0.8 -0.4) (end 0.8 0.4) (layer "F.Fab"))
                (pad "1" smd rect (at -0.8 0) (size 0.8 0.8) (layers "F.Cu"))))
            """,name:"Module board")
            let drawing = try XCTUnwrap(board.boardDrawing)
            XCTAssertEqual(board.width,30*CircuitScale.pointsPerMillimeter,accuracy:0.001)
            XCTAssertEqual(board.height,15*CircuitScale.pointsPerMillimeter,accuracy:0.001)
            XCTAssertEqual(board.pins.map(\.name),["MOD1.1","MOD1.2"])
            XCTAssertEqual(drawing.substrate.contours.count,3)
            XCTAssertEqual(drawing.packageCount,1) // only the resistor gets a package body
            XCTAssertEqual(drawing.graphics.filter { $0.fill == "#303936" }.count,1)
            XCTAssertEqual(drawing.graphics.filter { $0.fill == "#c6ad67" }.count,2)
            XCTAssertTrue(Diagram(parts:[board]).svg().contains("#f0eee2"))
        }
    }

    @MainActor func testFeatherPackageRecognitionAndPreview() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"RPGA-Feather",withExtension:"kicad_pcb",subdirectory:"Fixtures"))
        let source = try String(contentsOf:url,encoding:.utf8)
        let board = try importBoard(source,name:"RPGA Feather")
        let drawing = try XCTUnwrap(board.boardDrawing)
        XCTAssertEqual(drawing.graphics.filter { $0.feature == "led-lens" }.count,4)
        XCTAssertEqual(drawing.graphics.filter { $0.feature == "button-actuator" }.count,2)
        XCTAssertEqual(drawing.graphics.filter { $0.feature == "jst-housing" }.count,2)
        XCTAssertEqual(drawing.graphics.filter { $0.feature == "usb-shell" }.count,1)
        XCTAssertEqual(drawing.graphics.filter { $0.feature == "jst-contact" && $0.sourceReference == "J3" }.count,4)
        XCTAssertFalse(board.pins.contains { $0.name.hasPrefix("J1.S") }) // USB shield tabs are not jumper targets
        let root = try SExpr.parse(source)
        let qfn = try XCTUnwrap(root.children("footprint").first { $0.items[1].atom == "RPGA Feather:QFN-56" })
        let qfnBody = try XCTUnwrap(packageSketch(qfn)?.graphics.first?.contours.first)
        XCTAssertLessThan(qfnBody.map(\.x).max()!-qfnBody.map(\.x).min()!,7) // case excludes solder leads
        let greenLens = try XCTUnwrap(drawing.graphics.first { $0.feature == "led-lens" && $0.sourceReference == "CDONE0" })
        XCTAssertEqual(greenLens.fill,LEDColor.green.hex)
        let led = try XCTUnwrap(drawing.graphics.first { $0.feature == "led-body" && $0.sourceReference == "CDONE0" }?.contours.first)
        let w = led.map(\.x).max()!-led.map(\.x).min()!, h = led.map(\.y).max()!-led.map(\.y).min()!
        XCTAssertEqual(min(w,h),0.8*CircuitScale.pointsPerMillimeter,accuracy:0.001)
        XCTAssertEqual(max(w,h),1.6*CircuitScale.pointsPerMillimeter,accuracy:0.001)
        let saved = try JSONDecoder().decode(Diagram.self,from:JSONEncoder().encode(Diagram(parts:[board])))
        XCTAssertEqual(saved.parts[0].boardDrawing?.graphics.filter { $0.feature == "usb-opening" }.count,1)
        let svg = Diagram(parts:[board]).svg()
        XCTAssertTrue(svg.contains("#d7dfe1"))
        XCTAssertTrue(svg.contains("#e8e4d5"))
        try svg.write(toFile:"/private/tmp/graphical-circuits-feather.svg",atomically:true,encoding:.utf8)
        let canvas = Canvas(frame:NSRect(x:0,y:0,width:board.width+80,height:board.height+80))
        var preview = board; preview.position = Point(x:40,y:40); canvas.diagram.parts = [preview]
        let image = NSImage(size:NSSize(width:canvas.bounds.width*3,height:canvas.bounds.height*3),flipped:true) { _ in
            let t = NSAffineTransform(); t.scale(by:3); t.concat(); canvas.draw(canvas.bounds); return true
        }
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data:try XCTUnwrap(image.tiffRepresentation)))
        try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:"/private/tmp/graphical-circuits-feather.png"))
    }

    @MainActor func testJSTOrientationSocketDotsAndClosestPinHit() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"RPGA-Feather",withExtension:"kicad_pcb",subdirectory:"Fixtures"))
        let source = try String(contentsOf:url,encoding:.utf8)
        let fp = try XCTUnwrap(SExpr.parse(source).children("footprint").first { $0.items[1].atom == "RPGA Feather:JST-2-SMD" })
        let sketch = try XCTUnwrap(packageSketch(fp))
        let housing = try XCTUnwrap(sketch.graphics.first { $0.feature == "jst-housing" }?.contours.first)
        let mouth = try XCTUnwrap(sketch.graphics.first { $0.feature == "jst-mouth" }?.contours.first)
        XCTAssertLessThan(mouth.map(\.y).max()!,0) // opening at negative Y, opposite the solder tails
        XCTAssertEqual(sketch.ports.map(\.name),["1","2"])
        XCTAssertEqual(sketch.ports[0].point.x,-1)
        XCTAssertEqual(sketch.ports[1].point.x,1)
        XCTAssertLessThan(sketch.ports[0].point.y,housing.map(\.y).min()!)
        let board = try importBoard(source,name:"Feather")
        XCTAssertEqual(board.pins.filter { $0.connection == .socket }.map(\.name).sorted(),["J2.1","J2.2","J3.1","J3.2","J3.3","J3.4"])
        let canvas = Canvas(frame:NSRect(x:0,y:0,width:900,height:650)); canvas.diagram.parts = [board]
        for (i,pin) in board.pins.enumerated() where pin.connection == .socket {
            let hit = try XCTUnwrap(canvas.nearestPin(to:NSPoint(x:board.position.x+pin.point.x,y:board.position.y+pin.point.y)))
            XCTAssertEqual(hit.endpoint.pin,i)
        }
        let socket = try XCTUnwrap(board.pins.firstIndex { $0.name == "J3.3" && $0.connection == .socket })
        canvas.diagram.wires = [Wire(from:Endpoint(part:board.id,pin:socket),to:Endpoint(part:board.id,pin:0),color:"#dc654c")]
        let copy = try JSONDecoder().decode(Diagram.self,from:JSONEncoder().encode(canvas.diagram))
        XCTAssertEqual(copy.parts[0].pins[socket].connection,.socket)
        XCTAssertEqual(copy.point(copy.wires[0].from),canvas.diagram.point(canvas.diagram.wires[0].from))
    }
    func testSilkscreenAnchorsRotationAndFilledPolygons() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource:"RPGA-Feather",withExtension:"kicad_pcb",subdirectory:"Fixtures"))
        let source = try String(contentsOf:url,encoding:.utf8)
        let board = try importBoard(source,name:"Feather")
        let drawing = try XCTUnwrap(board.boardDrawing)
        for label in ["rst","F13"] {
            let text = try XCTUnwrap(drawing.texts.first { $0.text == label })
            XCTAssertEqual(text.horizontal,"left"); XCTAssertEqual(text.vertical,"bottom")
            let points = text.vectorGraphic().contours.flatMap { $0 }
            if label == "rst" { XCTAssertEqual(points.map(\.x).min()!,text.point.x,accuracy:0.001) }
            else { XCTAssertEqual(points.map(\.x).max()!,text.point.x,accuracy:0.001) }
            XCTAssertEqual(points.map(\.y).max()!,text.point.y,accuracy:0.001)
        }
        let root = try SExpr.parse(source)
        let nodes = root.items + root.children("footprint").flatMap(\.items)
        let filled = nodes.filter { $0.layer == "F.SilkS" && ["yes","solid"].contains($0.child("fill").dropFirst().first?.atom ?? "") && $0.geometry.count > 1 }
        XCTAssertGreaterThan(filled.count,20)
        XCTAssertEqual(drawing.graphics.filter { $0.fill == "#f0eee2" }.count,filled.count)
        XCTAssertFalse(Diagram(parts:[board]).svg().contains("<text")) // identical path geometry in SVG and canvas
        var wide = BoardText(text:"ABC",point:Point(x:10,y:20),size:10,angle:0,horizontal:"left",vertical:"bottom")
        let normal = wide.vectorGraphic().contours.flatMap { $0 }
        wide.fontWidth = 20
        let stretched = wide.vectorGraphic().contours.flatMap { $0 }
        XCTAssertEqual(stretched.map(\.x).max()!-10,2*(normal.map(\.x).max()!-10),accuracy:0.001)
        let escaped = try SExpr.parse("(text \"first\\nsecond\")")
        XCTAssertEqual(escaped.items[1].atom,"first\nsecond")
    }

}
