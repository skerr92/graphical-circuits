import Foundation

/// One vector shape may contain multiple contours (including transparent cutouts).
struct BoardGraphic: Codable {
    var contours: [[Point]]
    var fill: String?
    var stroke: String? = nil
    var lineWidth: Double = 0
    var closed = true
    var feature: String? = nil
    var sourceReference: String? = nil
    func svg() -> String {
        let path = contours.filter { !$0.isEmpty }.map { points in
            "M \(points[0].x) \(points[0].y) " + points.dropFirst().map { "L \($0.x) \($0.y)" }.joined(separator:" ") + (closed ? " Z" : "")
        }.joined(separator:" ")
        return "<path d=\"\(path)\" fill=\"\(fill ?? "none")\" fill-rule=\"evenodd\" stroke=\"\(stroke ?? "none")\" stroke-width=\"\(lineWidth)\" stroke-linejoin=\"round\"/>"
    }
}
struct BoardText: Codable {
    var text: String
    var point: Point
    var size: Double
    var angle: Double
    var horizontal: String? = nil
    var vertical: String? = nil
    var fontWidth: Double? = nil
    var mirrored: Bool? = nil
    var bold: Bool? = nil
    var italic: Bool? = nil
    var fontFace: String? = nil
}
struct BoardDrawing: Codable {
    var substrate: BoardGraphic
    var graphics: [BoardGraphic]
    var texts: [BoardText]
    var packageCount: Int
}

private func distance(_ a: Point,_ b: Point) -> Double { hypot(a.x-b.x,a.y-b.y) }
private func circle(_ center: Point,_ rx: Double,_ ry: Double) -> [Point] {
    (0..<96).map { i in let a = Double(i)*2 * .pi/96; return Point(x:center.x+rx*cos(a),y:center.y+ry*sin(a)) }
}
private func contains(_ point: Point,in polygon: [Point]) -> Bool {
    guard polygon.count > 2 else { return false }
    var inside = false
    for (a,b) in zip(polygon,Array(polygon.dropFirst())+[polygon[0]]) {
        if (a.y > point.y) != (b.y > point.y), point.x < (b.x-a.x)*(point.y-a.y)/(b.y-a.y)+a.x { inside.toggle() }
    }
    return inside
}
private func unique(_ contours: [[Point]]) -> [[Point]] {
    var result: [[Point]] = []
    for p in contours where !result.contains(where: { $0.count == p.count && distance($0[0],p[0]) < 0.001 && distance($0[$0.count/2],p[p.count/2]) < 0.001 }) { result.append(p) }
    return result
}
private func area(_ points: [Point]) -> Double {
    guard points.count >= 3 else { return 0 }
    return abs(zip(points,Array(points.dropFirst())+[points[0]]).reduce(0) { $0 + $1.0.x*$1.1.y-$1.1.x*$1.0.y })/2
}
/// Joins unordered/reversed outline segments; disconnected closed contours become cutouts.
func joinContours(_ segments: [[Point]]) -> (closed: [[Point]], open: [[Point]]) {
    var remaining = segments.filter { $0.count >= 2 }, closed: [[Point]] = [], open: [[Point]] = []
    while !remaining.isEmpty {
        var chain = remaining.removeFirst()
        while distance(chain[0],chain.last!) > 0.001 {
            guard let i = remaining.firstIndex(where: { distance(chain.last!,$0[0]) < 0.001 || distance(chain.last!,$0.last!) < 0.001 }) else { break }
            var next = remaining.remove(at:i)
            if distance(chain.last!,next[0]) >= 0.001 { next.reverse() }
            chain.append(contentsOf:next.dropFirst())
        }
        if distance(chain[0],chain.last!) <= 0.001 { closed.append(chain) } else { open.append(chain) }
    }
    return (closed,open)
}
extension SExpr {
    func xy(_ key: String) -> Point {
        let v = SExpr.list(child(key)); return Point(x:v.number(1),y:v.number(2))
    }
    var layer: String { child("layer").dropFirst().first?.atom ?? "" }
    var hidden: Bool {
        items.contains { $0.atom == "hide" } || child("hide").dropFirst().first?.atom == "yes" || child("effects").contains { $0.atom == "hide" }
    }
    var strokeWidth: Double {
        let stroke = SExpr.list(child("stroke")); return SExpr.list(stroke.child("width")).number(1)
    }
    /// Native KiCad geometry in its local coordinate system. Arcs are sampled finely for both renderers.
    var geometry: [Point] {
        let type = items.first?.atom ?? ""
        if type.hasSuffix("_line") { return [xy("start"),xy("end")] }
        if type.hasSuffix("_rect") {
            let a = xy("start"), b = xy("end")
            return [a,Point(x:b.x,y:a.y),b,Point(x:a.x,y:b.y),a]
        }
        if type.hasSuffix("_poly") { let p = SExpr.list(child("pts")).children("xy").map { Point(x:$0.number(1),y:$0.number(2)) }; return p.isEmpty ? [] : p+[p[0]] }
        if type.hasSuffix("_circle") { let c = xy("center"), r = distance(c,xy("end")); let p = circle(c,r,r); return p+[p[0]] }
        if type.hasSuffix("_arc"), !child("mid").isEmpty {
            let a = xy("start"), m = xy("mid"), b = xy("end")
            let d = 2*(a.x*(m.y-b.y)+m.x*(b.y-a.y)+b.x*(a.y-m.y))
            guard abs(d) > 1e-10 else { return [a,b] }
            let aa = a.x*a.x+a.y*a.y, mm = m.x*m.x+m.y*m.y, bb = b.x*b.x+b.y*b.y
            let c = Point(x:(aa*(m.y-b.y)+mm*(b.y-a.y)+bb*(a.y-m.y))/d,y:(aa*(b.x-m.x)+mm*(a.x-b.x)+bb*(m.x-a.x))/d)
            let start = atan2(a.y-c.y,a.x-c.x), mid = atan2(m.y-c.y,m.x-c.x), end = atan2(b.y-c.y,b.x-c.x)
            func positive(_ angle: Double) -> Double { let p = angle.truncatingRemainder(dividingBy:2 * .pi); return p < 0 ? p+2 * .pi : p }
            let ccw = positive(end-start)
            let sweep = positive(mid-start) <= ccw+1e-8 ? ccw : ccw-2 * .pi
            let steps = max(8,Int(ceil(abs(sweep)/(.pi/96))))
            let radius = distance(a,c)
            var result = (0...steps).map { i -> Point in let angle = start+sweep*Double(i)/Double(steps); return Point(x:c.x+radius*cos(angle),y:c.y+radius*sin(angle)) }
            result[0] = a; result[steps] = b; return result
        }
        return []
    }
}

func importBoard(_ source: String, name: String) throws -> Part {
    let root = try SExpr.parse(source)
    guard root.items.first?.atom == "kicad_pcb" else { throw ImportError.invalid }
    let scale = CircuitScale.pointsPerMillimeter
    let footprints = root.children("footprint") + root.children("module")
    func transform(_ p: Point,at: SExpr) -> Point {
        let a = SExpr.list(at.child("at")), angle = a.number(3) * .pi/180
        return Point(x:a.number(1)+p.x*cos(angle)+p.y*sin(angle),y:a.number(2)-p.x*sin(angle)+p.y*cos(angle))
    }
    var edges = root.items.filter { $0.layer == "Edge.Cuts" }.map(\.geometry).filter { !$0.isEmpty }
    for fp in footprints { edges += fp.items.filter { $0.layer == "Edge.Cuts" }.map { $0.geometry.map { transform($0,at:fp) } }.filter { !$0.isEmpty } }
    var outlines = joinContours(edges).closed
    // Pad bounds are only a fallback for files with no closed Edge.Cuts geometry.
    let padPoints = footprints.flatMap { fp in fp.children("pad").map { transform($0.xy("at"),at:fp) } }
    guard !outlines.isEmpty || !padPoints.isEmpty else { throw ImportError.noPads }
    let boundary = outlines.isEmpty ? padPoints : outlines.flatMap { $0 }
    let margin = outlines.isEmpty ? 3.0 : 0
    let minX = boundary.map(\.x).min()!-margin, minY = boundary.map(\.y).min()!-margin
    let maxX = boundary.map(\.x).max()!+margin, maxY = boundary.map(\.y).max()!+margin
    if outlines.isEmpty { outlines = [[Point(x:minX,y:minY),Point(x:maxX,y:minY),Point(x:maxX,y:maxY),Point(x:minX,y:maxY)]] }
    func local(_ p: Point) -> Point { Point(x:(p.x-minX)*scale,y:(p.y-minY)*scale) }
    var graphics: [BoardGraphic] = [], texts: [BoardText] = [], drills: [[Point]] = [], pins: [Pin] = []
    var packageCount = 0
    var topPads: [BoardGraphic] = []
    var connectorPins: [Pin] = []
    func silk(_ node: SExpr,fp: SExpr?) {
        guard node.layer == "F.SilkS", !node.hidden else { return }
        func convert(_ p: Point) -> Point { local(fp.map { transform(p,at:$0) } ?? p) }
        let type = node.items.first?.atom ?? ""
        if type == "property" || type.hasSuffix("_text") {
            let index = type == "gr_text" ? 1 : 2
            guard node.items.indices.contains(index) else { return }
            var text = node.items[index].atom
            if let fp {
                for property in fp.children("property") where property.items.count > 2 {
                    text = text.replacingOccurrences(of:"${\(property.items[1].atom.uppercased())}",with:property.items[2].atom)
                }
            }
            guard !text.contains("${"), !text.isEmpty else { return }
            let size = SExpr.list(SExpr.list(SExpr.list(node.child("effects")).child("font")).child("size")).number(1)
            let angle = SExpr.list(node.child("at")).number(3)
            let effects = SExpr.list(node.child("effects")), font = SExpr.list(effects.child("font"))
            let justify = effects.child("justify").map(\.atom)
            let width = SExpr.list(font.child("size")).number(2)
            texts.append(BoardText(text:text,point:convert(node.xy("at")),size:max(0.01,size*scale),angle:angle,horizontal:justify.contains("left") ? "left" : justify.contains("right") ? "right" : nil,vertical:justify.contains("top") ? "top" : justify.contains("bottom") ? "bottom" : nil,fontWidth:width > 0 ? width*scale : nil,mirrored:justify.contains("mirror"),bold:font.items.contains { $0.atom == "bold" },italic:font.items.contains { $0.atom == "italic" },fontFace:font.child("face").dropFirst().first?.atom))
        } else {
            let points = node.geometry.map(convert)
            guard points.count > 1 else { return }
            let filled = ["solid","yes"].contains(node.child("fill").dropFirst().first?.atom ?? "")
            graphics.append(BoardGraphic(contours:[points],fill:filled ? "#f0eee2" : nil,stroke:node.strokeWidth > 0 ? "#f0eee2" : nil,lineWidth:node.strokeWidth*scale,closed:filled || distance(points[0],points.last!) < 0.01))
        }
    }
    // Silkscreen art is preserved, including KiBuzzard polygons and visible pin labels.
    for item in root.items { silk(item,fp:nil) }
    for fp in footprints { for item in fp.items { silk(item,fp:fp) } }
    for fp in footprints {
        let identifier = fp.items.dropFirst().first?.atom ?? ""
        let back = fp.layer == "B.Cu"
        let dnp = fp.child("attr").contains { $0.atom == "dnp" }
        let mounting = identifier.lowercased().contains("mountinghole")
        let family = PackageSketch.family(of:fp)
        let reference = fp.children("property").first { $0.items.count > 2 && $0.items[1].atom == "Reference" }?.items[2].atom ?? fp.children("fp_text").first { $0.items.count > 2 && $0.items[1].atom == "reference" }?.items[2].atom ?? "Pad"
        func convert(_ p: Point) -> Point { local(transform(p,at:fp)) }
        var footprintDrills: [[Point]] = []
        for pad in fp.children("pad") {
            guard pad.items.count > 3 else { continue }
            let padName = pad.items[1].atom.uppercased()
            let shellNumber = padName.hasPrefix("S") && !padName.dropFirst().isEmpty && padName.dropFirst().allSatisfy(\.isNumber)
            let mechanical = family == .usb && (shellNumber || padName == "SH" || padName.hasPrefix("SHIELD") || padName.isEmpty)
            let type = pad.items[2].atom, shape = pad.items[3].atom, pos = pad.xy("at"), size = pad.xy("size")
            let padAngle = SExpr.list(pad.child("at")).number(3)
            let fpAngle = SExpr.list(fp.child("at")).number(3)
            // Pad angle in a board file is absolute; shape geometry is converted back into footprint space.
            let angle = (padAngle-fpAngle) * .pi/180
            func padPoint(_ p: Point) -> Point { convert(Point(x:pos.x+p.x*cos(angle)+p.y*sin(angle),y:pos.y-p.x*sin(angle)+p.y*cos(angle))) }
            var holes: [[Point]] = []
            let matchingDrill = fp.children("pad").first { distance($0.xy("at"),pos) < 0.001 && !$0.child("drill").isEmpty }
            let drill = pad.child("drill").isEmpty ? (matchingDrill?.child("drill") ?? []) : pad.child("drill")
            if drill.count > 1 {
                let oval = drill[1].atom == "oval"
                let dx = Double(drill[oval ? 2 : 1].atom) ?? 0
                let dy = oval && drill.count > 3 ? Double(drill[3].atom) ?? dx : dx
                let offset = SExpr.list(drill).xy("offset")
                if dx > 0 { holes = [circle(offset,dx/2,dy/2).map(padPoint)]; drills += holes; footprintDrills += holes }
            }
            if !back || type == "thru_hole" || type == "np_thru_hole" {
                let layers = pad.child("layers").map(\.atom)
                if type != "np_thru_hole", size.x > 0, size.y > 0, layers.contains("F.Cu") || layers.contains("*.Cu") || layers.count <= 1 {
                    let contour: [Point]
                    if shape == "circle" || shape == "oval" { contour = circle(Point(x:0,y:0),size.x/2,size.y/2) }
                    else { contour = [Point(x:-size.x/2,y:-size.y/2),Point(x:size.x/2,y:-size.y/2),Point(x:size.x/2,y:size.y/2),Point(x:-size.x/2,y:size.y/2)] }
                    let graphic = BoardGraphic(contours:[contour.map(padPoint)]+holes,fill:type == "smd" || mechanical ? "#b9beb9" : "#c6ad67")
                    if type == "smd" || mechanical { graphics.append(graphic) } else { topPads.append(graphic) }
                }
            }
            // Mounting hardware is visible but never treated as a jumper connection.
            if type == "thru_hole", !mounting, !dnp, !mechanical {
                pins.append(Pin(name:"\(reference).\(pad.items[1].atom)",point:convert(pos)))
            }
        }
        // Board/module footprints may carry both the PCB outline and its headers.
        // Their fabrication envelope is the board itself, not a physical package body.
        let containsBoardOutline = fp.items.contains { $0.layer.caseInsensitiveCompare("Edge.Cuts") == .orderedSame }
        guard !containsBoardOutline, !back, !dnp, !mounting, fp.children("pad").contains(where: { $0.items.count > 2 && $0.items[2].atom != "np_thru_hole" }) else { continue }
        if let sketch = packageSketch(fp) {
            for port in sketch.ports { connectorPins.append(Pin(connection:.socket,name:"\(reference).\(port.name)",point:convert(port.point))) }
            for var graphic in sketch.graphics {
                graphic.contours = graphic.contours.map { $0.map(convert) }
                graphic.lineWidth *= scale
                graphic.sourceReference = reference
                // Generic pin headers remain open through their drilled pins. Installed connector shells,
                // LED lenses and switch caps cover their locating holes, as the physical packages do.
                if sketch.family == .generic, let contour = graphic.contours.first {
                    let holes = unique(footprintDrills).filter { $0.allSatisfy { contains($0,in:contour) } }
                    graphic.contours += holes
                }
                graphics.append(graphic)
            }
            packageCount += 1
        }
    }
    // Duplicate drill contours (stacked pads) would cancel out with even-odd filling.
    let uniqueDrills = unique(drills)
    graphics += topPads
    pins += connectorPins
    let drawing = BoardDrawing(substrate:BoardGraphic(contours:outlines.map { $0.map(local) }+uniqueDrills,fill:"#236b55",stroke:"#194e3f",lineWidth:0.6),graphics:graphics,texts:texts,packageCount:packageCount)
    // Legacy package data remains empty; the new drawing owns geometry and presentation.
    var part = Part(kind:"Board",label:name,position:Point(x:100,y:100),width:(maxX-minX)*scale,height:(maxY-minY)*scale,pins:pins)
    part.boardDrawing = drawing
    part.pointsPerMillimeter = scale
    return part
}
