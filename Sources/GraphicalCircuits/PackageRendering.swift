import Foundation

/// Geometry is in footprint-local millimeters, before board rotation/translation.
struct PackageSketch {
    enum Family: String { case generic, led, button, jst, usb }
    var family: Family
    var graphics: [BoardGraphic]
    var ports: [Pin] = []
    static func family(of fp: SExpr) -> Family {
        let name = fp.items.dropFirst().first?.atom.lowercased() ?? ""
        let value = fp.children("property").first { $0.items.count > 2 && $0.items[1].atom == "Value" }?.items[2].atom.lowercased() ?? ""
        let description = fp.child("descr").dropFirst().first?.atom.lowercased() ?? ""
        if name.contains("usb") { return .usb }
        if name.contains("jst") { return .jst }
        if name.contains("led") { return .led }
        if name.contains("sw_push") || name.contains("switch") || description.contains("tactile") || value.contains("sof-232") { return .button }
        return .generic
    }
}
private func bounds(_ points: [Point]) -> CGRect? {
    guard let x = points.map(\.x).min(), let y = points.map(\.y).min(), let r = points.map(\.x).max(), let b = points.map(\.y).max() else { return nil }
    return CGRect(x:x,y:y,width:r-x,height:b-y)
}
private func polygonArea(_ points: [Point]) -> Double {
    guard let first = points.first else { return 0 }
    return abs(zip(points,Array(points.dropFirst())+[first]).reduce(0) { $0+$1.0.x*$1.1.y-$1.1.x*$1.0.y })/2
}
private func rectangle(_ r: CGRect) -> [Point] {
    [Point(x:r.minX,y:r.minY),Point(x:r.maxX,y:r.minY),Point(x:r.maxX,y:r.maxY),Point(x:r.minX,y:r.maxY)]
}
private func rounded(_ r: CGRect,radius: Double) -> [Point] {
    let radius = max(0,min(radius,min(r.width,r.height)/2))
    return [(r.maxX-radius,r.minY+radius,-Double.pi/2),(r.maxX-radius,r.maxY-radius,0.0),(r.minX+radius,r.maxY-radius,Double.pi/2),(r.minX+radius,r.minY+radius,Double.pi)].flatMap { x,y,start in
        (0...16).map { i in let a = start+Double(i) * .pi/32; return Point(x:x+radius*cos(a),y:y+radius*sin(a)) }
    }
}
private func ellipse(_ r: CGRect) -> [Point] {
    (0..<64).map { i in let a = Double(i)*2 * .pi/64; return Point(x:r.midX+r.width/2*cos(a),y:r.midY+r.height/2*sin(a)) }
}
/// Unlike the old center-only fallback this includes pad width, height and rotation.
private func padCorners(_ fp: SExpr) -> [Point] {
    let fpAngle = SExpr.list(fp.child("at")).number(3)
    return fp.children("pad").filter { $0.items.count > 3 && $0.items[2].atom != "np_thru_hole" }.flatMap { pad -> [Point] in
        let p = pad.xy("at"), size = pad.xy("size")
        let angle = (SExpr.list(pad.child("at")).number(3)-fpAngle) * .pi/180
        return rectangle(CGRect(x:-max(0.5,size.x)/2,y:-max(0.5,size.y)/2,width:max(0.5,size.x),height:max(0.5,size.y))).map { Point(x:p.x+$0.x*cos(angle)+$0.y*sin(angle),y:p.y-$0.x*sin(angle)+$0.y*cos(angle)) }
    }
}
func packageSketch(_ fp: SExpr) -> PackageSketch? {
    let family = PackageSketch.family(of:fp)
    let name = fp.items.dropFirst().first?.atom.lowercased() ?? ""
    let value = fp.children("property").first { $0.items.count > 2 && $0.items[1].atom == "Value" }?.items[2].atom ?? ""
    let fab = fp.items.filter { $0.layer == "F.Fab" }.map(\.geometry).filter { !$0.isEmpty }
    let loops = joinContours(fab).closed
    let largest = loops.max { polygonArea($0) < polygonArea($1) }
    let silk = fp.items.filter { $0.layer == "F.SilkS" && $0.items.first?.atom != "fp_text" }.flatMap(\.geometry)
    let silkBounds = bounds(silk)
    let padBounds = bounds(padCorners(fp))
    var body: [Point]? = largest
    // A closed polarity symbol is not a package envelope.
    if let p = body, polygonArea(p) < 0.1 { body = nil }
    guard var rect = body.flatMap(bounds) ?? padBounds ?? silkBounds else { return nil }
    var graphics: [BoardGraphic] = []
    var ports: [Pin] = []
    func shape(_ points: [Point],_ fill: String,role: String,stroke: String? = nil) {
        graphics.append(BoardGraphic(contours:[points],fill:fill,stroke:stroke,lineWidth:stroke == nil ? 0 : 0.06,feature:role))
    }
    switch family {
    case .led:
        // Common imperial package codes supply physical body size even when F.Fab contains only a diode glyph.
        if body == nil {
            let size: (Double,Double)? = name.contains("0603") ? (1.6,0.8) : name.contains("0402") ? (1,0.5) : name.contains("0805") ? (2,1.25) : name.contains("1206") ? (3.2,1.6) : nil
            if let size { rect = CGRect(x:rect.midX-size.0/2,y:rect.midY-size.1/2,width:size.0,height:size.1) }
            body = rounded(rect,radius:min(rect.width,rect.height)*0.12)
        }
        shape(body!,"#e9e6d2",role:"led-body",stroke:"#9c9b83")
        let color = LEDColor.allCases.first { value.localizedCaseInsensitiveContains($0.rawValue) }
        let lens = rect.insetBy(dx:rect.width*0.22,dy:rect.height*0.14)
        shape(rounded(lens,radius:min(lens.width,lens.height)*0.2),color?.hex ?? "#f3d987",role:"led-lens")
        let shine = CGRect(x:lens.minX+lens.width*0.08,y:lens.minY+lens.height*0.10,width:lens.width*0.7,height:lens.height*0.2)
        shape(rounded(shine,radius:shine.height/2),color?.shade(0.65) ?? "#fff6d5",role:"led-highlight")
    case .button:
        // Imported Eagle-style footprints often describe only the metal rim on silkscreen.
        if body == nil, let silkBounds { rect = silkBounds; body = rounded(rect,radius:0.12) }
        shape(body ?? rounded(rect,radius:0.12),"#b9c1c3",role:"button-body",stroke:"#707a7d")
        let rim = rect.insetBy(dx:rect.width*0.1,dy:rect.height*0.1)
        shape(rounded(rim,radius:0.15),"#e2e6e5",role:"button-plate")
        let diameter = min(rect.width,rect.height)*0.57
        let actuator = CGRect(x:rect.midX-diameter/2,y:rect.midY-diameter/2,width:diameter,height:diameter)
        shape(ellipse(actuator),"#343c40",role:"button-actuator")
        shape(ellipse(actuator.insetBy(dx:diameter*0.16,dy:diameter*0.16)),"#525d61",role:"button-highlight")
    case .usb:
        shape(body ?? rounded(rect,radius:0.4),"#aab5bb",role:"usb-shell",stroke:"#626f76")
        shape(rounded(rect.insetBy(dx:0.25,dy:0.25),radius:0.3),"#d7dfe1",role:"usb-top")
        // Cable entry is opposite the signal-pad row (mechanical shield tabs are ignored).
        let signal = fp.children("pad").filter { $0.items.count > 2 && $0.items[2].atom == "smd" }.map { $0.xy("at") }
        let meanY = signal.isEmpty ? rect.minY : signal.map(\.y).reduce(0,+)/Double(signal.count)
        let frontAtMaxY = meanY < rect.midY
        let opening = CGRect(x:rect.minX+rect.width*0.1,y:frontAtMaxY ? rect.maxY-0.8 : rect.minY+0.15,width:rect.width*0.8,height:min(0.65,rect.height*0.2))
        shape(rounded(opening,radius:opening.height/2),"#303c43",role:"usb-opening")
        shape(rounded(opening.insetBy(dx:opening.width*0.16,dy:opening.height*0.32),radius:0.05),"#7e8a91",role:"usb-tongue")
        let seam = CGRect(x:rect.minX+rect.width*0.13,y:rect.midY,width:rect.width*0.74,height:0.06)
        shape(rectangle(seam),"#8d9ba2",role:"usb-seam")
    case .jst:
        if body == nil {
            if name.contains("jst-2-smd") {
                // JST PH side-entry 2-pin housing (7.9 × 6 mm), local origin as used by this legacy footprint.
                rect = CGRect(x:-3.95,y:-3,width:7.9,height:6)
            } else if let silkBounds { rect = silkBounds }
            body = rounded(rect,radius:0.1)
        }
        shape(body!,"#e8e4d5",role:"jst-housing",stroke:"#aaa796")
        let signalPads = fp.children("pad").filter { $0.items.count > 2 && Int($0.items[1].atom) != nil }
        let signals = signalPads.map { $0.xy("at") }
        let meanY = signals.isEmpty ? rect.maxY : signals.map(\.y).reduce(0,+)/Double(signals.count)
        let meanX = signals.isEmpty ? rect.midX : signals.map(\.x).reduce(0,+)/Double(signals.count)
        let rowX = (signals.map(\.x).max() ?? 0)-(signals.map(\.x).min() ?? 0)
        let rowY = (signals.map(\.y).max() ?? 0)-(signals.map(\.y).min() ?? 0)
        let horizontalRow = rowX >= rowY
        let frontAtMin = horizontalRow ? meanY >= rect.midY : meanX >= rect.midX
        let topEntry = name.contains("vertical") || name.contains("bm04b") || name.contains("topentry")
        let cavity: CGRect
        if topEntry {
            cavity = rect.insetBy(dx:max(0.25,rect.width*0.13),dy:max(0.25,rect.height*0.18))
        } else if horizontalRow {
            cavity = CGRect(x:rect.minX+rect.width*0.12,y:frontAtMin ? rect.minY+0.08 : rect.maxY-0.78,width:rect.width*0.76,height:0.7)
        } else {
            cavity = CGRect(x:frontAtMin ? rect.minX+0.08 : rect.maxX-0.78,y:rect.minY+rect.height*0.12,width:0.7,height:rect.height*0.76)
        }
        shape(rounded(cavity,radius:0.12),"#555b52",role:topEntry ? "jst-cavity" : "jst-mouth")
        let contacts = loops.filter { polygonArea($0) < polygonArea(body!)*0.1 && polygonArea($0) > 0.015 }
        if topEntry && !contacts.isEmpty {
            for contact in contacts { shape(contact,"#ceb678",role:"jst-contact") }
        } else {
            for pin in signals {
                let contact = horizontalRow ? CGRect(x:pin.x-0.1,y:cavity.minY+0.1,width:0.2,height:max(0.2,cavity.height-0.2)) : CGRect(x:cavity.minX+0.1,y:pin.y-0.1,width:max(0.2,cavity.width-0.2),height:0.2)
                shape(rectangle(contact),"#ceb678",role:"jst-contact")
            }
        }
        // Side-entry contacts project outside the mouth; top-entry contacts sit in the accessible well.
        // Pin numbers come from signal pads; mounting tabs are excluded.
        for pad in signalPads {
            let pin = pad.xy("at")
            let offset = topEntry ? -min(rect.width,rect.height)*0.25 : 1.1
            let point = horizontalRow ? Point(x:pin.x,y:frontAtMin ? rect.minY-offset : rect.maxY+offset) : Point(x:frontAtMin ? rect.minX-offset : rect.maxX+offset,y:pin.y)
            let edge = horizontalRow ? Point(x:point.x,y:frontAtMin ? rect.minY : rect.maxY) : Point(x:frontAtMin ? rect.minX : rect.maxX,y:point.y)
            if !topEntry { graphics.append(BoardGraphic(contours:[[edge,point]],fill:nil,stroke:"#ceb678",lineWidth:0.1,closed:false,feature:"jst-port-lead")) }
            shape(ellipse(CGRect(x:point.x-0.36,y:point.y-0.36,width:0.72,height:0.72)),"#d5b76c",role:"jst-port")
            shape(ellipse(CGRect(x:point.x-0.12,y:point.y-0.12,width:0.24,height:0.24)),"#454b49",role:"jst-port-center")
            ports.append(Pin(connection:.socket,name:pad.items[1].atom,point:point))
        }
    case .generic:
        // For leaded ICs with missing fabrication data, broken silk corner marks describe
        // the case; the complete solder-pad envelope includes the leads outside that case.
        let ic = ["qfn","qfp","bga","dfn","soic","sot"].contains { name.contains($0) }
        if body == nil, ic, let silkBounds, silkBounds.width > 0.5, silkBounds.height > 0.5 {
            rect = silkBounds.insetBy(dx:0.1,dy:0.1)
        }
        let fill = name.contains("capacitor") ? "#bc9868" : "#303936"
        shape(body ?? rectangle(rect),fill,role:"body",stroke:"#626c64")
    }
    return PackageSketch(family:family,graphics:graphics,ports:ports)
}
