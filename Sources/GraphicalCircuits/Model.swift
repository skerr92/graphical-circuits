import Foundation

struct Point: Codable, Equatable { var x: Double; var y: Double }
enum CanvasGrid {
    static let spacing = 17
    static func snap(_ value: Double) -> Double {
        max(0,(value / Double(spacing)).rounded() * Double(spacing))
    }
}
enum CircuitScale {
    static let headerPitchMM = 2.54
    static let pointsPerMillimeter = Double(CanvasGrid.spacing) / headerPitchMM
}
enum PinConnection: String, Codable { case socket }
struct Pin: Codable { var connection: PinConnection? = nil; var name: String; var point: Point }
struct PackageBody: Codable { var x: Double; var y: Double; var width: Double; var height: Double }
enum LEDColor: String, Codable, CaseIterable {
    case red = "Red", green = "Green", blue = "Blue", yellow = "Yellow", amber = "Amber", white = "White", purple = "Purple"
    var hex: String {
        switch self {
        case .red: return "#eb5148"
        case .green: return "#39b66c"
        case .blue: return "#4284ee"
        case .yellow: return "#ead34b"
        case .amber: return "#f0a02f"
        case .white: return "#e6edf4"
        case .purple: return "#a96be3"
        }
    }
    func shade(_ amount: Double) -> String {
        let n = UInt64(hex.dropFirst(),radix:16)!
        let channels = [16,8,0].map { shift -> Int in
            let c = Double((n >> shift) & 255)
            return Int((amount >= 0 ? c+(255-c)*amount : c*(1+amount)).rounded())
        }
        return String(format:"#%02x%02x%02x",channels[0],channels[1],channels[2])
    }
}
struct Part: Codable, Identifiable {
    var ledColor: LEDColor? = nil
    var boardDrawing: BoardDrawing? = nil
    var pointsPerMillimeter: Double? = nil
    var packages: [PackageBody] = []
    var id = UUID()
    var kind: String
    var label: String
    var position: Point
    var width: Double
    var height: Double
    var pins: [Pin]
}
struct Endpoint: Codable { var part: UUID; var pin: Int }
struct Wire: Codable {
    var from: Endpoint; var to: Endpoint; var color: String
    var bend: Point? = nil
}
struct Artwork {
    var rect: CGRect
    var fill: String
    var ellipse = false
    var radius: Double = 0
    func svg() -> String {
        if ellipse { return "<ellipse cx=\"\(rect.midX)\" cy=\"\(rect.midY)\" rx=\"\(rect.width/2)\" ry=\"\(rect.height/2)\" fill=\"\(fill)\"/>" }
        return "<rect x=\"\(rect.minX)\" y=\"\(rect.minY)\" width=\"\(rect.width)\" height=\"\(rect.height)\" rx=\"\(radius)\" fill=\"\(fill)\"/>"
    }
}
extension Part {
    var snapsToGrid: Bool { ["Resistor","LED","Capacitor","Header"].contains(kind) }
    func placement(at point: Point) -> Point {
        if snapsToGrid { return Point(x:CanvasGrid.snap(point.x),y:CanvasGrid.snap(point.y)) }
        return Point(x:max(0,point.x.rounded()),y:max(0,point.y.rounded()))
    }
    // Four-band codes are shown only when the label is representable by two digits.
    var resistorBandColors: [String]? {
        var text = label.trimmingCharacters(in:.whitespacesAndNewlines)
            .replacingOccurrences(of:"Ω",with:"")
            .replacingOccurrences(of:"ohms",with:"",options:.caseInsensitive)
            .replacingOccurrences(of:"ohm",with:"",options:.caseInsensitive)
            .replacingOccurrences(of:" ",with:"")
        var multiplier = 1.0
        if let suffix = text.last {
            switch suffix {
            case "k", "K": multiplier = 1_000; text.removeLast()
            case "M": multiplier = 1_000_000; text.removeLast()
            case "G": multiplier = 1_000_000_000; text.removeLast()
            case "m": multiplier = 0.001; text.removeLast()
            default: break
            }
        }
        guard let number = Double(text), number.isFinite, number > 0 else { return nil }
        let resistance = number*multiplier
        guard resistance.isFinite, resistance > 0 else { return nil }
        let exponent = Int(floor(log10(resistance)))-1
        guard (-2...9).contains(exponent) else { return nil }
        let digits = resistance / pow(10,Double(exponent))
        guard abs(digits-digits.rounded()) < 0.000001 else { return nil }
        let code = Int(digits.rounded())
        guard (10...99).contains(code) else { return nil }
        let colors = ["#242424","#6b4430","#bb3433","#ed862f","#e8cf42","#3a9359","#3f70be","#8f56b0","#888888","#eeeeee"]
        let scale = exponent == -2 ? "#b4b9bd" : exponent == -1 ? "#bf963d" : colors[exponent]
        return [colors[code/10],colors[code%10],scale,"#bf963d"]
    }
    var artwork: [Artwork] {
        if boardDrawing != nil { return [] }
        func box(_ x: Double,_ y: Double,_ w: Double,_ h: Double,_ color: String,_ radius: Double = 0) -> Artwork { Artwork(rect: CGRect(x:x,y:y,width:w,height:h),fill:color,radius:radius) }
        if kind == "Resistor" {
            var a = [box(0,20,90,4,"#9ca5aa"),box(20,11,50,22,"#b99b63",8),box(22,12,46,19,"#dfc38c",7)]
            if let bands = resistorBandColors {
                for (x,color) in zip([29.0,38,47,60],bands) { a.append(box(x,12,x == 60 ? 3 : 5,20,color)) }
            }
            a.append(box(25,14,38,3,"#f4dfb5",1))
            return a
        }
        if kind == "LED" {
            let color = ledColor ?? .red
            return [box(0,20,33,4,"#9ca5aa"),box(57,20,33,4,"#9ca5aa"),box(28,5,34,34,color.shade(-0.3),16),box(31,6,28,30,color.hex,14),box(27,30,36,8,color.shade(-0.2),3),Artwork(rect:CGRect(x:35,y:10,width:9,height:16),fill:color.shade(0.6),ellipse:true),box(52,12,3,16,color.shade(-0.15),1)]
        }
        if kind == "Capacitor" {
            return [box(0,20,90,4,"#9ca5aa"),Artwork(rect:CGRect(x:27,y:3,width:36,height:38),fill:"#9b572d",ellipse:true),Artwork(rect:CGRect(x:29,y:4,width:32,height:34),fill:"#c78a4c",ellipse:true),Artwork(rect:CGRect(x:33,y:8,width:10,height:18),fill:"#e2b77f",ellipse:true)]
        }
        var a = [box(0,0,width,height,kind == "Board" ? "#236b55" : "#ecebe5",8)]
        if kind == "Breadboard" {
            a.append(box(16,(65+4.5*Double(CanvasGrid.spacing)+11)-7,width-32,14,"#cecec6",4))
            if pins.contains(where: { $0.name.hasPrefix("Top +") }) {
                for y in [12.0,height-51] {
                    a.append(box(18,y,width-36,2,"#d6534b"))
                    a.append(box(18,y+37,width-36,2,"#4785b5"))
                }
            }
        }
        return a
    }
}

struct Diagram: Codable {
    var parts: [Part] = []
    var wires: [Wire] = []
    init(parts: [Part] = [], wires: [Wire] = []) { self.parts = parts; self.wires = wires }
    enum CodingKeys: String, CodingKey { case parts, wires }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        parts = try c.decode([Part].self,forKey:.parts)
        wires = try c.decode([Wire].self,forKey:.wires)
        normalizePhysicalSpacing()
    }
    /// Upgrade previous saved projects without replacing pin IDs or array indices.
    mutating func normalizePhysicalSpacing() {
        var template = Diagram(); template.add("Breadboard")
        let breadboard = template.parts[0]
        let holes = Dictionary(uniqueKeysWithValues:breadboard.pins.map { ($0.name,$0.point) })
        for i in parts.indices {
            if parts[i].kind == "Breadboard" {
                for j in parts[i].pins.indices {
                    if let p = holes[parts[i].pins[j].name] { parts[i].pins[j].point = p }
                }
                parts[i].width = breadboard.width; parts[i].height = breadboard.height
            } else if parts[i].kind == "Board" {
                let previous = parts[i].pointsPerMillimeter ?? 6
                guard previous > 0, previous.isFinite else { continue }
                let ratio = CircuitScale.pointsPerMillimeter / previous
                func scaled(_ p: Point) -> Point { Point(x:p.x*ratio,y:p.y*ratio) }
                parts[i].width *= ratio; parts[i].height *= ratio
                for j in parts[i].pins.indices { parts[i].pins[j].point = scaled(parts[i].pins[j].point) }
                for j in parts[i].packages.indices {
                    parts[i].packages[j].x *= ratio; parts[i].packages[j].y *= ratio
                    parts[i].packages[j].width *= ratio; parts[i].packages[j].height *= ratio
                }
                if var drawing = parts[i].boardDrawing {
                    drawing.substrate.contours = drawing.substrate.contours.map { $0.map(scaled) }; drawing.substrate.lineWidth *= ratio
                    for j in drawing.graphics.indices {
                        drawing.graphics[j].contours = drawing.graphics[j].contours.map { $0.map(scaled) }; drawing.graphics[j].lineWidth *= ratio
                    }
                    for j in drawing.texts.indices { drawing.texts[j].point = scaled(drawing.texts[j].point); drawing.texts[j].size *= ratio; if let width = drawing.texts[j].fontWidth { drawing.texts[j].fontWidth = width*ratio } }
                    parts[i].boardDrawing = drawing
                }
                parts[i].pointsPerMillimeter = CircuitScale.pointsPerMillimeter
            }
        }
    }
    func placement(of index: Int, at point: Point) -> Point {
        let part = parts[index]
        guard part.kind == "Board", !part.pins.isEmpty else { return part.placement(at:point) }
        let holes = parts.filter { $0.kind == "Breadboard" }.flatMap { board in board.pins.map { Point(x:board.position.x+$0.point.x,y:board.position.y+$0.point.y) } }
        let proposed = part.pins.filter { $0.connection != .socket }.map { Point(x:point.x+$0.point.x,y:point.y+$0.point.y) }
        var best: (point:Point,matches:Int,distance:Double)?
        for pin in proposed { for hole in holes {
            let dx = hole.x-pin.x, dy = hole.y-pin.y, distance = hypot(dx,dy)
            guard distance <= 7 else { continue }
            let candidate = Point(x:point.x+dx,y:point.y+dy)
            guard candidate.x >= 0, candidate.y >= 0 else { continue }
            let matches = proposed.filter { pin in holes.contains { hypot(pin.x+dx-$0.x,pin.y+dy-$0.y) < 0.05 } }.count
            if best == nil || matches > best!.matches || (matches == best!.matches && distance < best!.distance) { best = (candidate,matches,distance) }
        } }
        return best?.point ?? part.placement(at:point)
    }
    func point(_ endpoint: Endpoint) -> Point? {
        guard let p = parts.first(where: { $0.id == endpoint.part }), p.pins.indices.contains(endpoint.pin) else { return nil }
        let a = p.pins[endpoint.pin].point
        return Point(x: p.position.x + a.x, y: p.position.y + a.y)
    }
    mutating func add(_ kind: String) {
        let offset = Double(parts.count % 8) * 20
        var p = Part(kind: kind, label: kind == "Resistor" ? "220 Ω" : kind == "Capacitor" ? "100 nF" : kind, position: Point(x: 120 + offset, y: 120 + offset), width: 90, height: 44, pins: [Pin(name: "1", point: Point(x: 0, y: 22)), Pin(name: "2", point: Point(x: 90, y: 22))])
        if kind == "Breadboard" {
            p.width = 540; p.height = 300; p.pins = []
            for row in 0..<10 { for col in 0..<30 {
                p.pins.append(Pin(name: "\(Array("abcdefghij")[row])\(col+1)", point: Point(x: 24 + Double(col)*Double(CanvasGrid.spacing), y: 65 + Double(row)*Double(CanvasGrid.spacing) + (row >= 5 ? 22 : 0))))
            } }
            for (side, base) in [("Top",24.0),("Bottom",261.0)] {
                for row in 0..<2 { for col in 0..<30 {
                    p.pins.append(Pin(name: "\(side) \(row == 0 ? "+" : "−") \(col+1)", point: Point(x:24+Double(col)*Double(CanvasGrid.spacing),y:base+Double(row)*Double(CanvasGrid.spacing))))
                } }
            }
        }
        p.position = p.placement(at:p.position)
        parts.append(p)
    }
    func route(_ wire: Wire) -> [Point] {
        guard let a = point(wire.from), let b = point(wire.to) else { return [] }
        let bend = wire.bend ?? Point(x:(a.x+b.x)/2,y:(a.y+b.y)/2)
        return [a,Point(x:bend.x,y:a.y),bend,Point(x:b.x,y:bend.y),b]
    }
    func svg() -> String {
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;") }
        var out = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1400\" height=\"900\" viewBox=\"0 0 1400 900\"><rect width=\"1400\" height=\"900\" fill=\"#faf9f6\"/>"
        for p in parts {
            out += "<g transform=\"translate(\(p.position.x) \(p.position.y))\">"
            if let board = p.boardDrawing {
                out += board.substrate.svg() + board.graphics.map { $0.svg() }.joined()
                for text in board.texts { out += text.vectorGraphic().svg() }
            }
            out += p.artwork.map { $0.svg() }.joined()
            let labelY = (["LED","Resistor","Capacitor"].contains(p.kind) || p.boardDrawing != nil) ? p.height + 13 : p.kind == "Breadboard" ? p.height/2+5 : p.height/2+5
            if p.boardDrawing == nil { out += "<text x=\"\(p.width/2)\" y=\"\(labelY)\" text-anchor=\"middle\" font-family=\"Helvetica\" font-size=\"13\" fill=\"\(p.kind == "Board" && p.boardDrawing == nil ? "white" : "#333333")\">\(esc(p.label))</text>" }
            if p.kind == "Breadboard", p.pins.contains(where: { $0.name.hasPrefix("Top +") }) {
                for (text,y) in [("+",27.0),("−",44.0),("+",264.0),("−",281.0)] { out += "<text x=\"5\" y=\"\(y)\" font-family=\"Helvetica\" font-size=\"12\" fill=\"\(text == "+" ? "#d6534b" : "#4785b5")\">\(text)</text>" }
            }
            for body in p.packages { out += "<rect x=\"\(body.x)\" y=\"\(body.y)\" width=\"\(body.width)\" height=\"\(body.height)\" rx=\"2\" fill=\"#303936\" stroke=\"#8a9690\"/>" }
            for pin in p.boardDrawing == nil ? p.pins : [] { out += "<circle cx=\"\(pin.point.x)\" cy=\"\(pin.point.y)\" r=\"3\" fill=\"#454b49\" stroke=\"#c4ad70\"/>" }
            out += "</g>"
        }
        for w in wires {
            let points = route(w)
            guard let first = points.first else { continue }
            let path = "M \(first.x) \(first.y) " + points.dropFirst().map { "L \($0.x) \($0.y)" }.joined(separator:" ")
            out += "<path d=\"\(path)\" fill=\"none\" stroke=\"\(esc(w.color))\" stroke-width=\"4\" stroke-linejoin=\"round\"/>"
        }
        return out + "</svg>"
    }
}

indirect enum SExpr {
    case atom(String), list([SExpr])
    var atom: String { if case .atom(let a) = self { return a }; return "" }
    var items: [SExpr] { if case .list(let a) = self { return a }; return [] }
    func children(_ name: String) -> [SExpr] { items.filter { $0.items.first?.atom == name } }
    func child(_ name: String) -> [SExpr] { children(name).first?.items ?? [] }
    func number(_ i: Int) -> Double { items.indices.contains(i) ? Double(items[i].atom) ?? 0 : 0 }
    static func parse(_ input: String) throws -> SExpr {
        let chars = Array(input); var i = 0
        func read() throws -> SExpr {
            while i < chars.count && chars[i].isWhitespace { i += 1 }
            guard i < chars.count else { throw ImportError.invalid }
            if chars[i] == "(" {
                i += 1; var values: [SExpr] = []
                while true {
                    while i < chars.count && chars[i].isWhitespace { i += 1 }
                    guard i < chars.count else { throw ImportError.invalid }
                    if chars[i] == ")" { i += 1; return .list(values) }
                    values.append(try read())
                }
            }
            if chars[i] == "\"" {
                i += 1; var s = ""
                while i < chars.count && chars[i] != "\"" {
                    if chars[i] == "\\" {
                        i += 1; guard i < chars.count else { throw ImportError.invalid }
                        switch chars[i] { case "n": s.append("\n"); case "r": s.append("\r"); case "t": s.append("\t"); default: s.append(chars[i]) }
                    } else { s.append(chars[i]) }
                    i += 1
                }
                guard i < chars.count else { throw ImportError.invalid }; i += 1; return .atom(s)
            }
            let start = i
            while i < chars.count && !chars[i].isWhitespace && chars[i] != ")" && chars[i] != "(" { i += 1 }
            guard i > start else { throw ImportError.invalid }
            return .atom(String(chars[start..<i]))
        }
        let result = try read()
        while i < chars.count && chars[i].isWhitespace { i += 1 }
        guard i == chars.count else { throw ImportError.invalid }; return result
    }
}
enum ImportError: Error, LocalizedError {
    case invalid, noPads
    var errorDescription: String? { self == .invalid ? "This is not a valid modern KiCad PCB file." : "No usable pads found in this board." }
}
